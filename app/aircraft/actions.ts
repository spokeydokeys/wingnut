"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getTachEstimate } from "@/lib/aircraft";
import { requireMember } from "@/lib/dal";
import { getAircraft } from "@/lib/flights";
import { createClient } from "@/lib/supabase/server";
import { fromInputValue } from "@/lib/time";

/**
 * Server Actions for the Aircraft tab.
 *
 * Each is a public POST endpoint, so each starts with requireMember(). Beyond
 * identity they lean on RLS: `snag_delete_own` and `maintenance_event_*` mean a
 * crafted id belonging to someone else matches no rows, so there is no
 * ownership test written out here to fall out of step with the policy.
 *
 * The one thing these do check by hand is the shape of what a human typed, and
 * each returns its complaint rather than throwing -- a mistyped tach reading is
 * a correction, not a crash. The leading unused argument is useActionState's
 * previous state, which these have no use for: the form is the whole input.
 */

type Failed = { error: string };

/** Readings and intervals are numeric(10,2); anything else is a typo. */
function readNumber(raw: FormDataEntryValue | null): number | null {
  const text = typeof raw === "string" ? raw.trim() : "";
  if (text === "") return null;
  const value = Number(text);
  return Number.isFinite(value) && value >= 0 ? value : null;
}

/** The three shapes of "come back to this", of which at most one is given. */
type Recheck = {
  recheck_item_id: string | null;
  recheck_tach_hours: number | null;
  recheck_on: string | null;
};

const NOTHING: Recheck = {
  recheck_item_id: null,
  recheck_tach_hours: null,
  recheck_on: null,
};

/**
 * Reads the re-check group off a snag form.
 *
 * One `<select>` decides, so the three columns can never disagree -- which is
 * also what `snag_recheck_one_way` enforces in the database, because this is
 * not the only thing that could ever write a snag.
 *
 * The hours are an interval, not a tach: `snag_stamp_recheck` measures it from
 * the tach at the moment of saving, so nothing here has to know what the
 * running estimate is.
 */
function readRecheck(form: FormData): Recheck | Failed {
  const choice = String(form.get("recheck") ?? "none");

  if (choice.startsWith("item:")) {
    const id = choice.slice("item:".length);
    if (!/^[0-9a-f-]{36}$/i.test(id)) {
      return { error: "That maintenance item could not be read." };
    }
    return { ...NOTHING, recheck_item_id: id };
  }

  if (choice === "tach") {
    const hours = readNumber(form.get("recheck_hours"));
    if (hours === null || hours <= 0) {
      return { error: "Say how many tach hours before it gets another look." };
    }
    return { ...NOTHING, recheck_tach_hours: hours };
  }

  if (choice === "date") {
    const on = String(form.get("recheck_on") ?? "");
    if (!/^\d{4}-\d{2}-\d{2}$/.test(on)) {
      return { error: "Give the date for the re-check." };
    }
    return { ...NOTHING, recheck_on: on };
  }

  return NOTHING;
}

export async function addSnag(_prev: Failed | null, form: FormData): Promise<Failed | never> {
  const member = await requireMember();
  const aircraft = await getAircraft();
  if (!aircraft) redirect("/no-access");

  const title = String(form.get("title") ?? "").trim();
  if (title === "") return { error: "Give the snag a title." };

  const status = String(form.get("status") ?? "open");
  if (status !== "open" && status !== "watch") {
    return { error: "A new snag is either open or one to watch." };
  }

  const recheck = readRecheck(form);
  if ("error" in recheck) return recheck;

  const supabase = await createClient();
  const { error } = await supabase.from("snag").insert({
    aircraft_id: aircraft.id,
    title,
    status,
    grounding: form.get("grounding") === "on",
    notes: String(form.get("notes") ?? "").trim() || null,
    reported_by: member.id,
    ...recheck,
  });

  if (error) return { error: error.message };

  revalidatePath("/aircraft", "layout");
  redirect("/aircraft");
}

/**
 * Re-grades a snag, including clearing it.
 *
 * Who cleared it and when are not passed in: `snag_stamp_cleared` sets them
 * from the status in the database, so a client cannot claim someone else fixed
 * the brake.
 */
export async function updateSnag(_prev: Failed | null, form: FormData): Promise<Failed | never> {
  await requireMember();

  const id = String(form.get("id") ?? "");
  const status = String(form.get("status") ?? "");
  if (status !== "open" && status !== "watch" && status !== "cleared") {
    return { error: "That is not a snag status." };
  }

  const recheck = readRecheck(form);
  if ("error" in recheck) return recheck;

  const supabase = await createClient();
  const { error } = await supabase
    .from("snag")
    .update({
      status,
      // A cleared snag cannot also be grounding the aeroplane.
      grounding: status !== "cleared" && form.get("grounding") === "on",
      notes: String(form.get("notes") ?? "").trim() || null,
      // Sent even when clearing, where `snag_stamp_recheck` discards it: a snag
      // that is sorted has nothing left to come back to.
      ...recheck,
    })
    .eq("id", id);

  if (error) return { error: error.message };

  revalidatePath("/aircraft", "layout");
  redirect("/aircraft");
}

/** For the snag that should never have been entered. */
export async function deleteSnag(snagId: string) {
  await requireMember();

  const supabase = await createClient();
  const { error } = await supabase.from("snag").delete().eq("id", snagId);
  if (error) throw error;

  revalidatePath("/aircraft", "layout");
  redirect("/aircraft");
}

/**
 * SPEC.md 4.4: any pilot can log an actual tach reading, and the app resets its
 * running estimate to match.
 *
 * There is no reset step -- `aircraft_tach_estimate` measures forward from the
 * newest reading, so inserting one IS the reset.
 */
export async function logTachReading(_prev: Failed | null, form: FormData): Promise<Failed | never> {
  const member = await requireMember();
  const aircraft = await getAircraft();
  if (!aircraft) redirect("/no-access");

  const reading = readNumber(form.get("reading"));
  if (reading === null) return { error: "The tach reading has to be a number." };

  const readOn = String(form.get("read_on") ?? "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(readOn)) {
    return { error: "That date could not be read." };
  }

  // Noon in the aeroplane's zone, not midnight: a reading dated today has to
  // sort after this morning's flight, and a date field cannot say when in the
  // day the meter was read.
  const readAt = fromInputValue(`${readOn}T12:00`);
  if (!readAt) return { error: "That date could not be read." };

  const supabase = await createClient();
  const { error } = await supabase.from("tach_reading").insert({
    aircraft_id: aircraft.id,
    reading,
    read_at: readAt.toISOString(),
    read_by: member.id,
    source: "manual",
    note: String(form.get("note") ?? "").trim() || null,
  });

  if (error) return { error: error.message };

  revalidatePath("/aircraft", "layout");
  redirect("/aircraft");
}

/**
 * A note in the running log: "added a qt of oil", "put air in the tires".
 *
 * The tach is optional and, when given, is mirrored into tach_reading by
 * `aircraft_note_sync_tach_reading` -- so this is one insert, and a number read
 * while topping up the oil moves the maintenance due-dates without the writer
 * having to go and log it a second time.
 */
export async function addAircraftNote(_prev: Failed | null, form: FormData): Promise<Failed | never> {
  const member = await requireMember();
  const aircraft = await getAircraft();
  if (!aircraft) redirect("/no-access");

  const body = String(form.get("body") ?? "").trim();
  if (body === "") return { error: "Say what you did." };

  const notedOn = String(form.get("noted_on") ?? "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(notedOn)) {
    return { error: "That date could not be read." };
  }

  // Sent as a plain date: the trigger stamps the mirrored reading at noon in
  // the aeroplane's zone, the same convention logTachReading uses by hand.
  const supabase = await createClient();
  const { error } = await supabase.from("aircraft_note").insert({
    aircraft_id: aircraft.id,
    body,
    noted_on: notedOn,
    noted_by: member.id,
    tach: readNumber(form.get("tach")),
  });

  if (error) return { error: error.message };

  revalidatePath("/aircraft", "layout");
  redirect("/aircraft");
}

/**
 * SPEC.md 4.4: "Marking a task done logs who, when and tach, and resets its
 * counter." The log is the counter, so this is one insert.
 *
 * The tach defaults to the running estimate rather than being required,
 * because the person who greased the hub is not necessarily standing in front
 * of the instrument panel when they remember to record it.
 */
export async function markMaintenanceDone(_prev: Failed | null, form: FormData): Promise<Failed | never> {
  const member = await requireMember();

  const itemId = String(form.get("item_id") ?? "");
  const doneOn = String(form.get("done_on") ?? "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(doneOn)) {
    return { error: "That date could not be read." };
  }

  const supabase = await createClient();

  // The item's own aircraft, not the one the screen happened to be showing.
  const { data: item } = await supabase
    .from("maintenance_item")
    .select("aircraft_id, basis")
    .eq("id", itemId)
    .maybeSingle();
  if (!item) return { error: "That maintenance item no longer exists." };

  let tach = readNumber(form.get("tach"));
  if (tach === null && item.basis === "tach") {
    tach = await getTachEstimate(item.aircraft_id);
    if (tach === null) {
      return {
        error:
          "This item is measured on the tach, so it needs a reading. Log one first.",
      };
    }
  }

  const { error } = await supabase.from("maintenance_event").insert({
    item_id: itemId,
    done_on: doneOn,
    tach,
    done_by: member.id,
    note: String(form.get("note") ?? "").trim() || null,
  });

  if (error) return { error: error.message };

  revalidatePath("/aircraft", "layout");
  redirect("/aircraft");
}

/**
 * Corrects what an item is: its name, its interval, how much warning it gives
 * and what the job is expected to cost.
 *
 * These numbers come off an airworthiness document, so until now they could
 * only be changed in SQL -- which made the one screen that shows them read as
 * though they were carved in. They are not: an interval changes at an annual, a
 * life limit moves on a service bulletin, and an estimate written at handover
 * is a guess somebody will want to correct.
 *
 * `maintenance_item_admin_write` is the rule, not a check written out here. RLS
 * refuses a pilot by matching no rows rather than by raising, so the update
 * asks for the id back and treats an empty result as the refusal it is.
 *
 * The basis is read from the row, never from the form: it decides which
 * interval columns mean anything, and a request claiming the wrong one would
 * write an interval the item can never come due on.
 */
export async function updateMaintenanceItem(
  itemId: string,
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | never> {
  await requireMember();

  const name = String(form.get("name") ?? "").trim();
  if (!name) return { error: "The item needs a name." };

  const supabase = await createClient();
  const { data: item } = await supabase
    .from("maintenance_item")
    .select("basis")
    .eq("id", itemId)
    .maybeSingle();
  if (!item) return { error: "That maintenance item no longer exists." };

  const patch: {
    name: string;
    est_cost: number | null;
    interval_hours?: number;
    lead_hours?: number | null;
    interval_months?: number | null;
    due_date?: string | null;
    lead_days?: number | null;
  } = {
    name,
    est_cost: readNumber(form.get("est_cost")),
  };

  if (item.basis === "tach") {
    const hours = readNumber(form.get("interval_hours"));
    if (hours === null || hours <= 0) {
      return { error: "Say how many tach hours there are between jobs." };
    }
    patch.interval_hours = hours;
    patch.lead_hours = readNumber(form.get("lead_hours"));
  } else {
    const months = readNumber(form.get("interval_months"));
    const dueOn = String(form.get("due_date") ?? "");
    const fixed = /^\d{4}-\d{2}-\d{2}$/.test(dueOn) ? dueOn : null;
    if ((months === null || months <= 0) && fixed === null) {
      return {
        error: "A calendar item needs either a number of months or a fixed date.",
      };
    }
    // Never both: the status view prefers the fixed date, so leaving an
    // interval behind it would have the screen saying one thing and the
    // countdown measuring another.
    patch.interval_months = fixed === null ? Math.round(months as number) : null;
    patch.due_date = fixed;
    const lead = readNumber(form.get("lead_days"));
    patch.lead_days = lead === null ? null : Math.round(lead);
  }

  const { data, error } = await supabase
    .from("maintenance_item")
    .update(patch)
    .eq("id", itemId)
    .select("id");

  if (error) return { error: error.message };
  if (!data || data.length === 0) {
    return {
      error:
        "Only an admin can change what an item is. Ask one of them to make the change.",
    };
  }

  revalidatePath("/aircraft", "layout");
  redirect(`/aircraft/maintenance/${itemId}`);
}
