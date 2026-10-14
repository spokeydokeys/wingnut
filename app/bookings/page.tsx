import Link from "next/link";
import { redirect } from "next/navigation";

import { BackHeader } from "@/components/back-header";
import { groupByDay, getUpcomingBookings } from "@/lib/bookings";
import { requireMember } from "@/lib/dal";
import { getAircraft } from "@/lib/flights";
import { formatClock, formatDayShort } from "@/lib/time";

// "Still to come" is measured against the clock, which moves on its own.
export const dynamic = "force-dynamic";

/**
 * The calendar, as an agenda: the next however-many days, each with who has
 * the aeroplane and why.
 *
 * SPEC.md 4.5 asks for a calendar with the other pilot's bookings visible, and
 * for two or three owners this list is the most honest shape for it -- a month
 * grid of mostly empty squares answers "what is the 19th" when the question
 * anybody actually opens this with is "when can I have it next". The fortnight
 * and month grids are the other two views, and they read the same rows.
 *
 * Every booking is a link, including the other owner's: tapping it is how you
 * see the whole note, and giving a slot up lives on that screen rather than
 * under a thumb scrolling this one.
 */
export default async function Bookings() {
  const member = await requireMember();

  const aircraft = await getAircraft();
  if (!aircraft) redirect("/no-access");

  const days = groupByDay(await getUpcomingBookings(aircraft.id));

  return (
    <>
      <BackHeader
        href="/more"
        label="More"
        title="Bookings"
        action={
          <Link
            href="/bookings/new"
            className="flex h-11 items-center rounded-[10px] border-[1.5px] border-ink bg-surface px-4 text-[15px] font-semibold"
          >
            + Book
          </Link>
        }
      />

      <main className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto px-4 pt-3.5 pb-4">
        {days.length === 0 ? (
          <p className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3 text-[15px] text-muted">
            Nothing booked. The aeroplane is free as far ahead as this list
            looks.
          </p>
        ) : (
          days.map((day) => (
            <div key={day.date} className="flex-none">
              <h2 className="field-label mb-1.5 px-0.5">
                {day.label === null
                  ? formatDayShort(day.bookings[0].start_at)
                  : day.label}
              </h2>
              <div className="divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
                {day.bookings.map((booking) => {
                  const mine = booking.pilot_member_id === member.id;
                  return (
                    <Link
                      key={booking.id}
                      href={`/bookings/${booking.id}`}
                      className="flex items-baseline gap-3 py-3"
                    >
                      <span className="numeric w-[104px] flex-none text-[15px]">
                        {formatClock(booking.start_at)}–
                        {formatClock(booking.end_at)}
                      </span>
                      <span className="min-w-0">
                        <span className="block truncate text-[15px] font-medium">
                          {mine
                            ? "You"
                            : (booking.pilot?.full_name ?? "A former owner")}
                        </span>
                        {booking.note && (
                          <span className="block truncate text-[13px] text-muted">
                            {booking.note}
                          </span>
                        )}
                      </span>
                    </Link>
                  );
                })}
              </div>
            </div>
          ))
        )}
      </main>
    </>
  );
}
