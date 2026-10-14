import { BookingRow } from "@/components/booking-row";
import type { Booking } from "@/lib/bookings";
import { formatCalendarDay } from "@/lib/time";

/**
 * The next fortnight, every day of it, free ones included.
 *
 * That is the whole difference from the agenda: an agenda answers "what is
 * booked" by listing only the days that are, and this answers "when could I
 * go" by showing the empty ones too. Fourteen days because that is as far
 * ahead as weather makes a float-plane plan worth anything, and because a
 * fortnight of day rows is still one scroll on a phone.
 *
 * Anchored to today and not pageable. Looking further out is what the month
 * view is for, and a second set of arrows here would be two ways to do the
 * same thing.
 */
export function BookingFortnight({
  days,
  memberId,
}: {
  days: { date: string; label: string | null; bookings: Booking[] }[];
  memberId: string;
}) {
  return (
    <div className="flex-none divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
      {days.map((day) => (
        <div key={day.date} className="py-2.5">
          <div
            className={`text-[13px] ${
              day.label === null ? "text-muted" : "font-semibold"
            }`}
          >
            {day.label ?? formatCalendarDay(day.date)}
          </div>

          {day.bookings.length === 0 ? (
            <div className="py-1 text-[15px] text-muted">Free</div>
          ) : (
            <div className="divide-y divide-hairline">
              {day.bookings.map((booking) => (
                <BookingRow key={booking.id} booking={booking} memberId={memberId} />
              ))}
            </div>
          )}
        </div>
      ))}
    </div>
  );
}
