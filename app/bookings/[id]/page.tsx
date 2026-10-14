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
 * task's "Drop it" lives on the task.
 *
 * Anybody may release anybody's slot: three people who fly one aeroplane sort
 * this out by phone, and the owner taking the call should be able to act on it.
 * The wording changes rather than the button disappearing, because releasing
 * somebody else's Saturday should not feel like releasing your own.
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
  const holder = booking.pilot?.full_name ?? "A former owner";

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
            {holder}
            {mine && <span className="font-normal text-muted"> — you</span>}
          </div>
        </div>

        {booking.note && (
          <div className="flex-none rounded-[14px] border border-line bg-surface p-3.5">
            <div className="field-label">What for</div>
            <p className="text-[15px] whitespace-pre-wrap">{booking.note}</p>
          </div>
        )}

        <div className="flex-1" />

        {!mine && (
          <p className="flex-none text-[13px] text-muted">
            This is {holder}&apos;s slot. Nothing tells them it has gone, so
            only do this if they asked.
          </p>
        )}

        <form action={releaseBooking.bind(null, booking.id)} className="flex-none">
          <button
            type="submit"
            className="flex h-12 w-full items-center justify-center rounded-xl border-[1.5px] border-ink bg-surface text-base font-semibold"
          >
            {mine ? "Give up this slot" : "Release this slot"}
          </button>
        </form>
      </main>
    </>
  );
}
