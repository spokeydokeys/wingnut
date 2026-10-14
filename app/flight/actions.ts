"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireMember } from "@/lib/dal";
import { getAircraft, getRunningFlight } from "@/lib/flights";
import { createClient } from "@/lib/supabase/server";

/**
 * Server Actions for the flight timer.
 *
 * Every one of these is a public POST endpoint, so each starts with
 * requireMember() -- being reachable only from a page that already checked is
 * not a check. Beyond identity they lean on RLS: `flight_update_own` and
 * `flight_delete_own` mean a crafted flight id belonging to someone else
 * simply matches no rows, so there is no ownership test written out here that
 * could fall out of step with the policy.
 */

export type Fix = {
  lat: number;
  lon: number;
  accuracy: number | null;
};

/**
 * A fix arrives from `navigator.geolocation` in the browser, so it is input
 * and gets checked. Nonsense is dropped rather than rejected: a flight with no
 * fix is a supported flight, and refusing to start the timer because the phone
 * reported a silly latitude would be the wrong trade.
 */
function cleanFix(fix: Fix | null) {
  if (!fix) return null;
  const { lat, lon, accuracy } = fix;
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
  return {
    lat,
    lon,
    accuracy_m:
      accuracy !== null && Number.isFinite(accuracy) && accuracy >= 0 ? accuracy : null,
  };
}

// Unique violation. On `flight_one_open_per_aircraft` it means a second Start
// raced the first -- a double tap, or two phones. Both callers wanted a running
// flight and there is one, so that is a success.
const UNIQUE_VIOLATION = "23505";

export async function startFlight(fix: Fix | null) {
  const member = await requireMember();
  const aircraft = await getAircraft();
  if (!aircraft) redirect("/no-access");

  const clean = cleanFix(fix);
  const supabase = await createClient();

  const { data: flight, error } = await supabase
    .from("flight")
    // start_at is left out on purpose: the column defaults to now(), so the
    // moment of departure comes from the database's clock.
    .insert({
      aircraft_id: aircraft.id,
      pilot_member_id: member.id,
      tach_factor_used: aircraft.tach_factor,
      start_fix_at: clean ? new Date().toISOString() : null,
      start_fix_accuracy_m: clean?.accuracy_m ?? null,
    })
    .select("id")
    .single();

  if (error) {
    if (error.code !== UNIQUE_VIOLATION) throw error;
  } else if (clean) {
    // A failed fix must not undo a started flight, so this is not awaited into
    // the same failure path: the flight row already carries the accuracy, and
    // the fix table is the raw copy that Confirm may later discard.
    await supabase.from("flight_fix").insert({
      flight_id: flight.id,
      which: "start",
      lat: clean.lat,
      lon: clean.lon,
      accuracy_m: clean.accuracy_m,
      source: "gps",
    });
  }

  revalidatePath("/", "layout");
  redirect("/flight");
}

export async function stopFlight(fix: Fix | null) {
  await requireMember();

  const running = await getRunningFlight();
  if (!running) redirect("/");

  const clean = cleanFix(fix);
  const stoppedAt = new Date().toISOString();
  const supabase = await createClient();

  const { data: stopped, error } = await supabase
    .from("flight")
    .update({
      end_at: stoppedAt,
      end_fix_at: clean ? stoppedAt : null,
      end_fix_accuracy_m: clean?.accuracy_m ?? null,
    })
    .eq("id", running.id)
    .is("end_at", null)
    .select("id")
    .maybeSingle();

  if (error) throw error;

  // No row means the flight was stopped between the read and the write, or it
  // is another pilot's and RLS hid it from the update. Either way the timer is
  // no longer this caller's to stop.
  if (!stopped) redirect("/");

  if (clean) {
    await supabase.from("flight_fix").upsert(
      {
        flight_id: stopped.id,
        which: "end",
        lat: clean.lat,
        lon: clean.lon,
        accuracy_m: clean.accuracy_m,
        source: "gps",
      },
      { onConflict: "flight_id,which" },
    );
  }

  revalidatePath("/", "layout");
  redirect(`/flight/${stopped.id}/confirm`);
}

/**
 * Throws the flight away rather than recording a zero-length one.
 *
 * This is for the Start that should never have happened -- a pocket tap, the
 * wrong aeroplane. A flight that really did happen and lasted two minutes
 * should be stopped and saved, not cancelled.
 */
export async function cancelFlight(flightId: string) {
  await requireMember();

  const supabase = await createClient();
  const { error } = await supabase
    .from("flight")
    .delete()
    .eq("id", flightId)
    .eq("status", "draft");

  if (error) throw error;

  revalidatePath("/", "layout");
  redirect("/");
}

/**
 * "Already flown? Log a past flight."
 *
 * Creates a finished draft -- an hour long, ending now -- and hands it to the
 * Confirm screen. There is no separate past-flight form because Confirm
 * already edits every field on a flight, and a second form would be a second
 * set of rules to keep in step with this one.
 */
export async function logPastFlight() {
  const member = await requireMember();
  const aircraft = await getAircraft();
  if (!aircraft) redirect("/no-access");

  const endAt = new Date();
  const startAt = new Date(endAt.valueOf() - 60 * 60 * 1000);

  const supabase = await createClient();
  const { data: flight, error } = await supabase
    .from("flight")
    .insert({
      aircraft_id: aircraft.id,
      pilot_member_id: member.id,
      tach_factor_used: aircraft.tach_factor,
      start_at: startAt.toISOString(),
      end_at: endAt.toISOString(),
    })
    .select("id")
    .single();

  if (error) throw error;

  revalidatePath("/", "layout");
  redirect(`/flight/${flight.id}/confirm`);
}

export type ConfirmInput = {
  flightId: string;
  /**
   * Both as ISO strings with an offset, built in the browser from its own
   * time zone. The server cannot parse "2026-10-12T08:14" correctly because it
   * does not know where the pilot is standing.
   */
  startAt: string;
  endAt: string;
  pilotMemberId: string;
  actualTachHours: string;
  notes: string;
  /**
   * SPEC.md 4.2's journey log line. Blank is meaningful rather than missing:
   * `flight_set_journey` fills a blank with "Origin → Destination", so clearing
   * the field is how a pilot asks for the derived sentence back.
   */
  journeyText: string;
  /**
   * Whether the pilot ticked "I bought fuel on this flight". Asked here rather
   * than offered as a link beside the Save button because tapping a link would
   * throw away everything typed into this form; answered as a tick, it costs
   * nothing and only changes where saving lands.
   */
  boughtFuel: boolean;
};

/**
 * Confirms a draft flight. SPEC.md 4.1 is explicit that hand-editing is a
 * requirement, so every field here is editable and the saved times are
 * whatever the pilot says they are -- the GPS fixes stay on the record as the
 * evidence of what the phone thought at the time.
 *
 * Hours are not in the update. `flight_compute_hours` recalculates billed and
 * estimated tach from the times on the way through, so there is no way for a
 * client to post a cheaper flight than it flew.
 */
export async function saveFlight(
  input: ConfirmInput,
): Promise<{ error: string } | never> {
  const member = await requireMember();

  // Naming someone else as the pilot moves the cost of the flight onto their
  // bill, so only an admin may do it. `flight_update_own` already refuses, but
  // it refuses by matching no rows, and "no rows" is not an explanation.
  if (input.pilotMemberId !== member.id && member.role !== "admin") {
    return { error: "Only an admin can log a flight against another pilot." };
  }

  const startAt = new Date(input.startAt);
  const endAt = new Date(input.endAt);
  if (Number.isNaN(startAt.valueOf()) || Number.isNaN(endAt.valueOf())) {
    return { error: "Those times could not be read." };
  }
  if (endAt <= startAt) {
    return { error: "The end time has to be after the start time." };
  }

  let actualTachHours: number | null = null;
  if (input.actualTachHours.trim() !== "") {
    actualTachHours = Number(input.actualTachHours);
    if (!Number.isFinite(actualTachHours) || actualTachHours < 0) {
      return { error: "The tach reading has to be a number." };
    }
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("flight")
    .update({
      status: "confirmed",
      start_at: startAt.toISOString(),
      end_at: endAt.toISOString(),
      pilot_member_id: input.pilotMemberId,
      actual_tach_hours: actualTachHours,
      notes: input.notes.trim() || null,
      journey_text: input.journeyText.trim() || null,
    })
    .eq("id", input.flightId)
    .eq("status", "draft")
    .select("id")
    .maybeSingle();

  if (error) return { error: error.message };
  if (!data) return { error: "That flight is no longer a draft." };

  revalidatePath("/", "layout");

  // Straight on to the camera while the pilot is still standing by the pump,
  // with the flight named so the receipt files itself against it. SPEC.md 4.7
  // makes the flight link optional, and this is the one moment it is free.
  if (input.boughtFuel) redirect(`/receipts/new?flight=${data.id}`);
  redirect("/");
}
