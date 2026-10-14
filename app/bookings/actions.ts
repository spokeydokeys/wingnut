"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireMember } from "@/lib/dal";
import { getAircraft } from "@/lib/flights";
import { createClient } from "@/lib/supabase/server";
import { formatClock, formatDayShort, fromInputValue } from "@/lib/time";

/**
 * Server Actions for the booking calendar.
 *
 * The no-double-booking rule is not re-implemented here. `booking_no_overlap`
 * is an exclusion constraint, so the database refuses the clash under
 * concurrency in a way an application check cannot: two owners tapping Book at
 * the same moment both read a free calendar and both pass. What this file does
 * is turn that refusal into a sentence worth reading, by going back and asking
 * who actually holds the slot.
 */

type Failed = { error: string };

const UUID = /^[0-9a-f-]{36}$/i;

/** Postgres `exclusion_violation` -- for us, always booking_no_overlap. */
const EXCLUSION_VIOLATION = "23P01";

function revalidateBookings() {
  revalidatePath("/", "layout");
}

/**
 * Who is already in the slot, so the refusal can name them.
 *
 * Read after the insert failed rather than before it, which is deliberate: a
 * read before would be the application check the constraint exists to replace,
 * and two of them would disagree the day the rule changed. The only job here is
 * wording.
 */
async function describeClash(
  aircraftId: string,
  startIso: string,
  endIso: string,
): Promise<string> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("booking")
    .select("start_at, end_at, pilot:member!booking_pilot_member_id_fkey(full_name)")
    .eq("aircraft_id", aircraftId)
    // The same half-open overlap the constraint tests: starts before ours ends
    // and ends after ours starts. A booking that merely touches ours at either
    // end is not a clash and must not be named as one.
    .lt("start_at", endIso)
    .gt("end_at", startIso)
    .order("start_at")
    .limit(1);

  const clash = (data ?? [])[0] as
    | { start_at: string; end_at: string; pilot: { full_name: string } | null }
    | undefined;

  if (!clash) {
    // The clash was there a moment ago and is not now, so somebody gave the
    // slot up in between. Saying so is more use than naming nobody.
    return "Somebody else has that slot. Have another look at the calendar.";
  }

  return `${clash.pilot?.full_name ?? "Another owner"} has it ${formatDayShort(
    clash.start_at,
  )}, ${formatClock(clash.start_at)}–${formatClock(clash.end_at)}.`;
}

/**
 * Holds the aeroplane for a slot.
 *
 * An admin may book on another owner's behalf -- the phone call that says "put
 * me down for Saturday" -- which is what `booking_insert_own` already allows.
 * For everyone else the pilot is themselves and the field is not rendered.
 */
export async function createBooking(
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | never> {
  const member = await requireMember();
  const aircraft = await getAircraft();
  if (!aircraft) return { error: "No aircraft has been set up yet." };

  const start = fromInputValue(String(form.get("start_at") ?? ""));
  const end = fromInputValue(String(form.get("end_at") ?? ""));
  if (!start || !end) return { error: "Set a start and an end." };
  if (end.valueOf() <= start.valueOf()) {
    return { error: "The end has to be after the start." };
  }

  let pilot = member.id;
  if (member.role === "admin") {
    const asked = String(form.get("pilot_member_id") ?? "");
    if (asked !== "") {
      if (!UUID.test(asked)) return { error: "That person could not be read." };
      pilot = asked;
    }
  }

  const startIso = start.toISOString();
  const endIso = end.toISOString();

  const supabase = await createClient();
  const { error } = await supabase.from("booking").insert({
    aircraft_id: aircraft.id,
    pilot_member_id: pilot,
    start_at: startIso,
    end_at: endIso,
    note: String(form.get("note") ?? "").trim() || null,
  });

  if (error) {
    if (error.code === EXCLUSION_VIOLATION) {
      return { error: await describeClash(aircraft.id, startIso, endIso) };
    }
    return { error: error.message };
  }

  revalidateBookings();
  redirect("/bookings");
}

/**
 * Gives a slot up.
 *
 * Deleted, not cancelled: the schema has no cancelled status on purpose -- a
 * booking somebody gave up is the absence of a fact about the aeroplane, and a
 * tombstone would have to be filtered out of both the calendar and the overlap
 * rule. RLS keeps this to the pilot holding it, or an admin.
 */
export async function releaseBooking(bookingId: string) {
  await requireMember();

  const supabase = await createClient();
  const { error } = await supabase.from("booking").delete().eq("id", bookingId);
  if (error) throw error;

  revalidateBookings();
  redirect("/bookings");
}
