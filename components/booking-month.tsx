import Link from "next/link";

import { BookingRow } from "@/components/booking-row";
import { addMonths, type Booking } from "@/lib/bookings";
import { formatCalendarDay, formatWeekdayNarrow } from "@/lib/time";

/**
 * A month at a glance, and whichever day is selected underneath it.
 *
 * The grid alone would be a dead end -- squares with dots in them and no way
 * to ask what the dots are -- so each square is a link that picks that day,
 * and the day's bookings are listed below in the same rows the other two views
 * use. Picking a day is in the URL rather than in client state for the same
 * reason the view is: this is the screen one owner sends the other.
 *
 * Days spilling out of the month are live squares, not padding: the aeroplane
 * is as bookable on the 1st of November as on the 31st of October, and tapping
 * one moves the whole grid to that month rather than doing nothing.
 */
export function BookingMonth({
  month,
  weeks,
  bookings,
  selected,
  today,
  memberId,
}: {
  /** `2026-10` */
  month: string;
  weeks: string[][];
  bookings: Map<string, Booking[]>;
  /** The day whose bookings are listed below, or null for none. */
  selected: string | null;
  today: string;
  memberId: string;
}) {
  const shown = selected ? (bookings.get(selected) ?? []) : [];

  return (
    <>
      <div className="flex flex-none items-center justify-between">
        <MonthStep month={addMonths(month, -1)} label="Previous month" back />
        <div className="flex items-center gap-2">
          <h2 className="text-base font-semibold">
            {new Intl.DateTimeFormat("en-GB", {
              timeZone: "UTC",
              month: "long",
              year: "numeric",
            }).format(new Date(`${month}-01T00:00:00Z`))}
          </h2>
          {/* Four taps of an arrow is the only other way back from March, and
              the day somebody wants is nearly always near today. Hidden when
              today is already the day on show, so it is never a no-op. */}
          {selected !== today && (
            <Link
              href={`/bookings?view=month&month=${today.slice(0, 7)}&day=${today}`}
              className="flex h-7 items-center rounded-[8px] border border-line px-2 text-[12px] font-semibold text-muted"
            >
              Today
            </Link>
          )}
        </div>
        <MonthStep month={addMonths(month, 1)} label="Next month" />
      </div>

      <div className="flex-none rounded-[14px] border border-line bg-surface p-2">
        <div className="grid grid-cols-7">
          {weeks[0].map((date) => (
            <div
              key={date}
              className="field-label pb-1 text-center"
              aria-hidden="true"
            >
              {formatWeekdayNarrow(date)}
            </div>
          ))}
        </div>

        <div className="grid grid-cols-7 gap-0.5">
          {weeks.flat().map((date) => {
            const day = bookings.get(date) ?? [];
            const outside = !date.startsWith(month);

            return (
              <Link
                key={date}
                href={`/bookings?view=month&month=${date.slice(0, 7)}&day=${date}`}
                aria-label={formatCalendarDay(date)}
                aria-current={date === selected ? "date" : undefined}
                className={`flex h-12 flex-col items-center justify-center gap-1 rounded-[8px] ${
                  date === selected ? "bg-ink text-white" : ""
                }`}
              >
                <span
                  className={`numeric text-[14px] ${
                    date === today ? "font-bold" : ""
                  } ${outside && date !== selected ? "text-muted" : ""}`}
                >
                  {Number(date.slice(8))}
                </span>
                <span className="flex h-1.5 items-center gap-0.5">
                  {/* Three at most: a fourth dot would not fit the square, and
                      the count is not the point -- "taken" is. */}
                  {day.slice(0, 3).map((booking) => (
                    <span
                      key={booking.id}
                      className={`size-1.5 rounded-full ${
                        date === selected
                          ? "bg-white"
                          : booking.pilot_member_id === memberId
                            ? "bg-accent"
                            : "bg-muted"
                      }`}
                    />
                  ))}
                </span>
              </Link>
            );
          })}
        </div>
      </div>

      {selected && (
        <>
          <h3 className="field-label mt-1 flex-none px-0.5">
            {formatCalendarDay(selected)}
          </h3>
          {shown.length === 0 ? (
            <p className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3 text-[15px] text-muted">
              Nothing booked. A dot is somebody holding the aeroplane; an
              orange one is you.
            </p>
          ) : (
            <div className="flex-none divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
              {shown.map((booking) => (
                <BookingRow key={booking.id} booking={booking} memberId={memberId} />
              ))}
            </div>
          )}
        </>
      )}
    </>
  );
}

/** An arrow to the month either side, keeping the view in the URL. */
function MonthStep({
  month,
  label,
  back = false,
}: {
  month: string;
  label: string;
  back?: boolean;
}) {
  return (
    <Link
      href={`/bookings?view=month&month=${month}`}
      aria-label={label}
      className="flex size-11 items-center justify-center"
    >
      <svg
        aria-hidden="true"
        width="24"
        height="24"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d={back ? "M15 5l-7 7 7 7" : "M9 5l7 7-7 7"} />
      </svg>
    </Link>
  );
}
