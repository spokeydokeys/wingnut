import "server-only";

import { createClient } from "./supabase/server";
import {
  fromInputValue,
  toAircraftDate,
  toDateInputValue,
  toInputValue,
} from "./time";
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
 * Everything starting inside a window of calendar days, for the month grid.
 *
 * The window is given as the aeroplane's own dates and turned into instants
 * here, by the same `fromInputValue` the booking form writes through -- so a
 * month that starts on the 1st starts at midnight in Victoria, not at 17:00 on
 * the 31st, which is what a bare date cast would have meant.
 *
 * Filtered on `start_at` rather than on an overlap, so that each booking lands
 * in exactly one cell: a grid that showed a slot in two squares would read as
 * two bookings, and the day something starts is the day people look for it.
 */
export async function getBookingsBetween(
  aircraftId: string,
  fromDate: string,
  /** Exclusive, like every other half-open range in this feature. */
  toDate: string,
): Promise<Booking[]> {
  const from = fromInputValue(`${fromDate}T00:00`);
  const to = fromInputValue(`${toDate}T00:00`);
  if (!from || !to) return [];

  const supabase = await createClient();
  const { data } = await supabase
    .from("booking")
    .select(BOOKING_SELECT)
    .eq("aircraft_id", aircraftId)
    .gte("start_at", from.toISOString())
    .lt("start_at", to.toISOString())
    .order("start_at");

  return (data as Booking[] | null) ?? [];
}

/** The bookings of each day, keyed by the aeroplane's calendar date. */
export function bookingsByDate(bookings: Booking[]): Map<string, Booking[]> {
  const days = new Map<string, Booking[]>();
  for (const booking of bookings) {
    const date = toAircraftDate(booking.start_at);
    const day = days.get(date);
    if (day) day.push(booking);
    else days.set(date, [booking]);
  }
  return days;
}

/**
 * `2026-10-19` plus or minus a number of days.
 *
 * Calendar arithmetic in UTC on a plain date, never 86,400,000ms added to an
 * instant: the two disagree on the mornings the clocks change, and a grid that
 * skipped or repeated a day would be a calendar nobody could trust.
 */
export function addDays(date: string, days: number): string {
  const [y, m, d] = date.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

/** `2026-10` plus or minus a number of months. */
export function addMonths(month: string, months: number): string {
  const [y, m] = month.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1 + months, 1)).toISOString().slice(0, 7);
}

/**
 * The squares of a month, Monday first, as whole weeks.
 *
 * Every cell is a real date, including the ones spilling out of the month at
 * either end: the aeroplane is just as bookable on the 1st of November as on
 * the 31st of October, and blanking those squares would hide a booking from
 * somebody looking at the week it falls in.
 *
 * Monday first to match the en-GB formatting used everywhere else, and because
 * it keeps Saturday and Sunday -- the two squares anybody is actually reading
 * this grid for -- side by side at the end of the row.
 */
export function monthGrid(month: string): string[][] {
  const [y, m] = month.split("-").map(Number);

  const firstOfMonth = new Date(Date.UTC(y, m - 1, 1));
  // getUTCDay is Sunday-based; shift it so Monday is 0.
  const lead = (firstOfMonth.getUTCDay() + 6) % 7;
  // Day 0 of the next month is the last day of this one, which saves knowing
  // anything about February.
  const length = new Date(Date.UTC(y, m, 0)).getUTCDate();

  const first = addDays(`${month}-01`, -lead);
  const weeks: string[][] = [];
  for (let cell = 0; cell < Math.ceil((lead + length) / 7) * 7; cell++) {
    if (cell % 7 === 0) weeks.push([]);
    weeks[weeks.length - 1].push(addDays(first, cell));
  }

  return weeks;
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

/**
 * The one booking worth a card on Home: your own next slot, or failing that
 * whoever has the aeroplane next.
 *
 * Your own first because Home is the screen you open to fly, and "Saturday,
 * 09:00" is the answer you came for. Falling back to somebody else's is not a
 * consolation prize -- "the other owner has it Saturday" is exactly as useful,
 * and it is the only way the card tells you the aeroplane is spoken for.
 *
 * A dozen rows is plenty to find your own in. Past that the card names whoever
 * is next instead, which is still true, and the calendar is one tap away.
 */
export async function getNextBooking(
  aircraftId: string,
  memberId: string,
): Promise<Booking | null> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("booking")
    .select(BOOKING_SELECT)
    .eq("aircraft_id", aircraftId)
    .gte("end_at", new Date().toISOString())
    .order("start_at")
    .limit(12);

  const rows = (data as Booking[] | null) ?? [];
  return rows.find((row) => row.pilot_member_id === memberId) ?? rows[0] ?? null;
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
