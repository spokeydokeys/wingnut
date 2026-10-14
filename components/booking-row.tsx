import Link from "next/link";

import type { Booking } from "@/lib/bookings";
import { formatClock } from "@/lib/time";

/**
 * One booking in a list: when, who, and what for.
 *
 * Shared by the agenda and the fortnight so the two cannot drift into saying
 * the same slot differently. The whole row is the link, because the thing you
 * want from a booking is the rest of the note and the way to give it up, and
 * both of those are on its own screen.
 *
 * "You" rather than your own name: the question this list answers is whether
 * the aeroplane is free, and reading your own name back is a slower way of
 * being told it is not.
 */
export function BookingRow({
  booking,
  memberId,
}: {
  booking: Booking;
  memberId: string;
}) {
  const mine = booking.pilot_member_id === memberId;

  return (
    <Link
      href={`/bookings/${booking.id}`}
      className="flex items-baseline gap-3 py-3"
    >
      <span className="numeric w-[104px] flex-none text-[15px]">
        {formatClock(booking.start_at)}–{formatClock(booking.end_at)}
      </span>
      <span className="min-w-0">
        <span className="block truncate text-[15px] font-medium">
          {mine ? "You" : (booking.pilot?.full_name ?? "A former owner")}
        </span>
        {booking.note && (
          <span className="block truncate text-[13px] text-muted">
            {booking.note}
          </span>
        )}
      </span>
    </Link>
  );
}
