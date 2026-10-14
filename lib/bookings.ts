import "server-only";

import { createClient } from "./supabase/server";
import { toAircraftDate, toDateInputValue, toInputValue } from "./time";
import type { Database } from "./database.types";

export type Booking = Database["public"]["Tables"]["booking"]["Row"] & {
  pilot: { full_name: string } | null;
};

/**
 * Reads for the booking calendar.
 *
 * Every owner sees every booking -- SPEC.md 4.5 asks for "the other pilot's
 * bookings visible" and `booking_select_members` grants exactly that -- so
 * nothing here filters by caller. Whose booking a row is matters only to the
 * screen, which decides whether to offer a way to give the slot up.
 *
 * The pilot's name is embedded rather than looked up per row, because a
 * calendar is mostly a list of names and the alternative is one query per
 * booking. It is nullable: `member` is cascaded on delete, so in practice the
 * join always lands, but the generated types do not know that.
 */
const BOOKING_SELECT = "*, pilot:member!booking_pilot_member_id_fkey(full_name)";

/**
 * What is still to come, soonest first.
 *
 * `end_at` rather than `start_at` is what "still to come" is measured against,
 * so the slot somebody is in the middle of using stays at the top of the list
 * instead of vanishing the moment they take off. That booking is the single
 * most useful row on the screen: it is the answer to "where is the aeroplane".
 *
 * A horizon rather than everything, because a booking made for next summer
 * should not push next weekend's off the bottom of a phone. Anything beyond it
 * is reachable from the month view.
 */
export async function getUpcomingBookings(
  aircraftId: string,
  horizonDays = 60,
): Promise<Booking[]> {
  const now = new Date();
  const horizon = new Date(now.valueOf() + horizonDays * 86_400_000);

  const supabase = await createClient();
  const { data } = await supabase
    .from("booking")
    .select(BOOKING_SELECT)
    .eq("aircraft_id", aircraftId)
    .gte("end_at", now.toISOString())
    .lt("start_at", horizon.toISOString())
    .order("start_at");

  return (data as Booking[] | null) ?? [];
}

export type BookingDay = {
  /** `2026-10-19`, where the aeroplane lives. */
  date: string;
  /** "Today" or "Tomorrow", or null to let the screen name the date. */
  label: string | null;
  bookings: Booking[];
};

/**
 * The same bookings, split into the days they fall on.
 *
 * Grouped by the aeroplane's calendar date, not the viewer's: `toAircraftDate`
 * is what decides which day a 23:30 slot belongs to, and slicing the ISO string
 * would file it under tomorrow for everyone west of Greenwich.
 *
 * A booking that spans midnight appears under the day it starts and nowhere
 * else. Two owners who fly a float plane do not book overnight, and repeating a
 * row under both days would make the agenda read as two bookings.
 */
export function groupByDay(bookings: Booking[]): BookingDay[] {
  const today = toDateInputValue();
  // Tomorrow by calendar arithmetic rather than by adding 86,400,000ms, which
  // lands on the wrong date twice a year when the clocks move.
  const [y, m, d] = today.split("-").map(Number);
  const tomorrow = new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10);

  const days: BookingDay[] = [];

  for (const booking of bookings) {
    const date = toAircraftDate(booking.start_at);
    const last = days[days.length - 1];
    if (last && last.date === date) {
      last.bookings.push(booking);
      continue;
    }
    days.push({
      date,
      label: date === today ? "Today" : date === tomorrow ? "Tomorrow" : null,
      bookings: [booking],
    });
  }

  return days;
}

/**
 * What the Book form opens on: the next whole hour, and three hours of it.
 *
 * Here rather than in the page because reading the clock in a component is
 * impure, and because "what is a normal booking" is a fact about the aeroplane
 * rather than about the form.
 *
 * Rounding the instant up to a whole hour rounds the local clock up to one too,
 * since the aircraft's zone is a whole number of hours off UTC.
 */
export function defaultSlot(): { start: string; end: string } {
  const start = new Date(Math.ceil(Date.now() / 3_600_000) * 3_600_000);
  return {
    start: toInputValue(start.toISOString()),
    end: toInputValue(new Date(start.valueOf() + 3 * 3_600_000).toISOString()),
  };
}

export async function getBooking(id: string): Promise<Booking | null> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("booking")
    .select(BOOKING_SELECT)
    .eq("id", id)
    .maybeSingle();
  return (data as Booking | null) ?? null;
}
