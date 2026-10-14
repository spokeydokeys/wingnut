import { notFound } from "next/navigation";

import { releaseBooking } from "@/app/bookings/actions";
import { BackHeader } from "@/components/back-header";
import { getBooking } from "@/lib/bookings";
import { requireMember } from "@/lib/dal";
import { formatClock, formatDayShort } from "@/lib/time";

export const dynamic = "force-dynamic";

/**
 * One booking, and the one thing you can do to it.
 *
 * Giving a slot up is here rather than on the list, so that nothing
 * irreversible sits under a thumb scrolling the calendar -- the same reason a
 * task's "Drop it" lives on the task. The button only appears on a booking you
 * are allowed to release, because RLS would otherwise refuse by matching no
 * rows and the screen would read as though it had worked.
 *
 * Changing the times is deliberately not offered yet: giving the slot up and
 * taking the one you meant is two taps and cannot get the overlap rule wrong.
 */
export default async function BookingDetail({ params }: PageProps<"/bookings/[id]">) {
  const { id } = await params;
  const member = await requireMember();

  const booking = await getBooking(id);
  if (!booking) notFound();

  const mine = booking.pilot_member_id === member.id;
  const canRelease = mine || member.role === "admin";

  return (
    <>
      <BackHeader
        href="/bookings"
        label="Bookings"
        title={formatDayShort(booking.start_at)}
        subtitle={`${formatClock(booking.start_at)}–${formatClock(booking.end_at)}`}
      />

      <main className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 pt-3.5 pb-4">
        <div className="flex-none rounded-[14px] border border-line bg-surface p-3.5">
          <div className="field-label">Held by</div>
          <div className="text-base font-semibold">
            {booking.pilot?.full_name ?? "A former owner"}
            {mine && <span className="font-normal text-muted"> — you</span>}
          </div>
        </div>

        {booking.note && (
          <div className="flex-none rounded-[14px] border border-line bg-surface p-3.5">
            <div className="field-label">What for</div>
            <p className="text-[15px] whitespace-pre-wrap">{booking.note}</p>
          </div>
        )}

        {!canRelease && (
          <p className="flex-none text-[13px] text-muted">
            It is{" "}
            {booking.pilot?.full_name ?? "another owner"}
            &apos;s slot. Ask them if you need it.
          </p>
        )}

        <div className="flex-1" />

        {canRelease && (
          <form action={releaseBooking.bind(null, booking.id)} className="flex-none">
            <button
              type="submit"
              className="flex h-12 w-full items-center justify-center rounded-xl border-[1.5px] border-ink bg-surface text-base font-semibold"
            >
              Give up this slot
            </button>
          </form>
        )}
      </main>
    </>
  );
}
