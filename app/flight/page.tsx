import Link from "next/link";
import { redirect } from "next/navigation";

import { cancelFlight } from "@/app/flight/actions";
import { Chip } from "@/components/chip";
import { Elapsed } from "@/components/elapsed";
import { FixCard } from "@/components/fix-card";
import { TimerButton } from "@/components/timer-button";
import { requireMember } from "@/lib/dal";
import { getAircraft, getFlightFixes, getRunningFlight } from "@/lib/flights";

export const dynamic = "force-dynamic";

/**
 * The running timer.
 *
 * Deliberately has no state of its own. There is one running flight per
 * aeroplane, enforced by a unique index, so this screen is a view of that row
 * rather than a session: open it on a second device and the clock reads the
 * same.
 *
 * The wireframe's "Wrong start time? Edit" link is not here. The start time is
 * editable on the Confirm screen a few minutes later, and a second editor for
 * the same field -- live, while the clock using it is running -- would be a
 * second set of rules about what a valid start time is.
 */
export default async function FlightTimer() {
  const member = await requireMember();
  const [aircraft, running] = await Promise.all([getAircraft(), getRunningFlight()]);

  // Nothing running means the flight was stopped, possibly on another device.
  if (!running) redirect("/");

  const fixes = await getFlightFixes(running.id);
  const isPilot = running.pilot_member_id === member.id;

  return (
    <>
      <header className="flex min-h-14 flex-none items-center justify-between py-3 pr-4 pl-2">
        <Link
          href="/"
          className="flex min-h-11 items-center gap-0.5 px-2 text-base font-medium"
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
            <path d="M15 5l-7 7 7 7" />
          </svg>
          Home
        </Link>
        <Chip tone="running">Running</Chip>
      </header>

      <main className="flex min-h-0 flex-1 flex-col gap-3 px-4 pt-2 pb-4">
        <Elapsed
          startAt={running.start_at}
          serverNow={new Date().toISOString()}
          tachFactor={Number(running.tach_factor_used)}
          pilotName={isPilot ? "You" : "Another owner"}
        />

        <div className="flex items-center gap-3 rounded-xl border border-line bg-surface px-3.5 py-2.5">
          <svg
            aria-hidden="true"
            width="22"
            height="22"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.75"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M12 21s7-6.2 7-11a7 7 0 10-14 0c0 4.8 7 11 7 11z" />
            <circle cx="12" cy="10" r="2.5" />
          </svg>
          <div className="flex-1">
            <FixCard
              label="Departed"
              placeName={null}
              fix={fixes.start}
              fixAt={running.start_fix_at}
              accuracyM={
                running.start_fix_accuracy_m === null
                  ? null
                  : Number(running.start_fix_accuracy_m)
              }
            />
          </div>
        </div>

        <div className="flex-1" />

        {isPilot ? (
          <>
            <p className="text-center text-[13px] text-muted">
              The timer runs on the server and keeps counting if you lock your
              phone. Your location is saved only when you tap Start or Stop.
            </p>

            <TimerButton action="stop" />

            <form
              action={cancelFlight.bind(null, running.id)}
              className="flex items-center justify-center"
            >
              <button
                type="submit"
                className="flex min-h-12 items-center justify-center text-[15px] font-medium underline"
              >
                Cancel timer
              </button>
            </form>
          </>
        ) : (
          <p className="rounded-xl border border-snag-line bg-snag px-3.5 py-3 text-center text-sm font-medium text-snag-text">
            {aircraft?.registration ?? "The aircraft"} is flying with another
            owner at the controls. Only they can stop this timer.
          </p>
        )}
      </main>
    </>
  );
}
