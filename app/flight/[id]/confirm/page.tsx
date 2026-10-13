import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { Chip } from "@/components/chip";
import { ConfirmForm } from "@/components/confirm-form";
import { FixCard } from "@/components/fix-card";
import { requireMember } from "@/lib/dal";
import { getAircraft, getFlight, getFlightFixes, getPilotChoices } from "@/lib/flights";
import { formatClock, formatDayShort } from "@/lib/time";

export const dynamic = "force-dynamic";

/**
 * Confirm a stopped flight. SPEC.md 4.1: Stop does not file the flight, it
 * opens this. A draft counts for nothing until a human has looked at it.
 *
 * Two things from the wireframe are missing because what they need does not
 * exist yet: the place pickers (SPEC.md 4.6, a later phase) and "Add a snag".
 * The forgot-to-stop warning is also absent -- it is supposed to fire when the
 * end fix is nowhere near an aerodrome, and without place matching there is
 * nothing to compare the fix against. Guessing would train people to ignore it.
 */
export default async function ConfirmFlight({ params }: PageProps<"/flight/[id]/confirm">) {
  const { id } = await params;
  const member = await requireMember();

  const flight = await getFlight(id);
  if (!flight) notFound();

  // Still running: there is nothing to confirm yet.
  if (!flight.end_at) redirect("/flight");
  // Already confirmed or billed. Editing a filed flight is a later phase with
  // its own screen, and silently reopening it here would be a surprise.
  if (flight.status !== "draft") redirect("/");

  const [aircraft, fixes, pilots] = await Promise.all([
    getAircraft(),
    getFlightFixes(flight.id),
    getPilotChoices(),
  ]);

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
        <Chip tone="neutral">Draft</Chip>
      </header>

      <div className="flex-none px-4">
        <h1 className="text-[26px] font-semibold">Confirm flight</h1>
        <p className="mt-0.5 text-sm text-muted">
          {formatDayShort(flight.end_at)}, timer stopped at{" "}
          {formatClock(flight.end_at)}. Fix anything that is off, then save.
        </p>
      </div>

      <main className="flex min-h-0 flex-1 flex-col gap-3 px-4 pt-3.5 pb-4">
        <div className="divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
          <div className="py-3">
            <FixCard
              label="Departed"
              placeName={null}
              fix={fixes.start}
              fixAt={flight.start_fix_at}
              accuracyM={
                flight.start_fix_accuracy_m === null
                  ? null
                  : Number(flight.start_fix_accuracy_m)
              }
            />
          </div>
          <div className="py-3">
            <FixCard
              label="Landed"
              placeName={null}
              fix={fixes.end}
              fixAt={flight.end_fix_at}
              accuracyM={
                flight.end_fix_accuracy_m === null
                  ? null
                  : Number(flight.end_fix_accuracy_m)
              }
            />
          </div>
        </div>

        <ConfirmForm
          flightId={flight.id}
          startAt={flight.start_at}
          endAt={flight.end_at}
          pilotMemberId={flight.pilot_member_id}
          pilots={pilots}
          tachFactor={Number(flight.tach_factor_used || aircraft?.tach_factor || 1.3)}
          actualTachHours={flight.actual_tach_hours?.toString() ?? ""}
          notes={flight.notes ?? ""}
          canChangePilot={member.role === "admin"}
        />
      </main>
    </>
  );
}
