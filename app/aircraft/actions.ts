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
