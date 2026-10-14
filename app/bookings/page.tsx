import Link from "next/link";
import { redirect } from "next/navigation";

import { BookingMonth } from "@/components/booking-month";
import { BookingRow } from "@/components/booking-row";
import {
  BookingViewSwitcher,
  type BookingView,
} from "@/components/booking-view-switcher";
import { TabBar } from "@/components/tab-bar";
import {
  addDays,
  bookingsByDate,
  getBookingsBetween,
  getUpcomingBookings,
  groupByDay,
  monthGrid,
} from "@/lib/bookings";
import { requireMember } from "@/lib/dal";
import { getAircraft } from "@/lib/flights";
import { formatCalendarDay, toDateInputValue } from "@/lib/time";

// Both views are anchored to today, which moves on its own.
export const dynamic = "force-dynamic";

/**
 * The calendar, in whichever of its two shapes was asked for.
 *
 * SPEC.md 4.5 asks for a calendar with the other pilot's bookings visible, and
 * the two views are two questions, not two decorations:
 *
 *   agenda  what is booked, soonest first -- the usual one
 *   month   which weekend in March, and is anyone on it
 *
 * Both read the same rows and both send you to the same booking screen. The
 * view lives in the URL so the calendar can be sent, reloaded, and come back to
 * from a booking without snapping to a shape nobody chose.
 *
 * A tab, not a door behind More, which is where SPEC.md 3 put it: claiming the
 * aeroplane happens for roughly every flight, a few days ahead of it. The spec
 * was sorting screens by when they are used, and this one is used as often as
 * the Aircraft tab beside it.
 */
export default async function Bookings({ searchParams }: PageProps<"/bookings">) {
  const member = await requireMember();

  const aircraft = await getAircraft();
  if (!aircraft) redirect("/no-access");

  const query = await searchParams;
  const asked = String(query.view ?? "");
  const view: BookingView = asked === "month" ? "month" : "agenda";

  const today = toDateInputValue();

  return (
    <>
      <header className="flex flex-none items-center justify-between px-4 pt-4 pb-1">
        <h1 className="text-[26px] font-semibold">Bookings</h1>
        <Link
          href="/bookings/new"
          className="flex h-11 items-center rounded-[10px] border-[1.5px] border-ink bg-surface px-4 text-[15px] font-semibold"
        >
          + Book
        </Link>
      </header>

      <main className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto px-4 pt-3 pb-4">
        <BookingViewSwitcher current={view} />

        {view === "agenda" ? (
          <Agenda aircraftId={aircraft.id} memberId={member.id} />
        ) : (
          <Month
            aircraftId={aircraft.id}
            memberId={member.id}
            today={today}
            month={String(query.month ?? "").match(/^\d{4}-\d{2}$/)?.[0] ?? today.slice(0, 7)}
            day={String(query.day ?? "").match(/^\d{4}-\d{2}-\d{2}$/)?.[0] ?? null}
          />
        )}
      </main>

      <TabBar />
    </>
  );
}

/** What is booked, soonest first, grouped into the days it falls on. */
async function Agenda({
  aircraftId,
  memberId,
}: {
  aircraftId: string;
  memberId: string;
}) {
  const days = groupByDay(await getUpcomingBookings(aircraftId));

  if (days.length === 0) {
    return (
      <p className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3 text-[15px] text-muted">
        Nothing booked. The aeroplane is free as far ahead as this list looks.
      </p>
    );
  }

  return days.map((day) => (
    <div key={day.date} className="flex-none">
      <h2 className="field-label mb-1.5 px-0.5">
        {day.label ?? formatCalendarDay(day.date)}
      </h2>
      <div className="divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
        {day.bookings.map((booking) => (
          <BookingRow key={booking.id} booking={booking} memberId={memberId} />
        ))}
      </div>
    </div>
  ));
}

/** A month of squares, and the day picked out of it. */
async function Month({
  aircraftId,
  memberId,
  today,
  month,
  day,
}: {
  aircraftId: string;
  memberId: string;
  today: string;
  month: string;
  day: string | null;
}) {
  const weeks = monthGrid(month);
  const cells = weeks.flat();

  // The grid's own range, not the month's: the squares either side belong to
  // the weeks on show and their bookings have to be read too.
  const byDate = bookingsByDate(
    await getBookingsBetween(aircraftId, cells[0], addDays(cells[cells.length - 1], 1)),
  );

  // Today, when it is on screen, so the view opens on something rather than on
  // a grid with nothing chosen.
  const selected = day ?? (today.startsWith(month) ? today : null);

  return (
    <BookingMonth
      month={month}
      weeks={weeks}
      bookings={byDate}
      selected={selected}
      today={today}
      memberId={memberId}
    />
  );
}
