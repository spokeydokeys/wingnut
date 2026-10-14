import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { Chip } from "@/components/chip";
import { ConfirmForm } from "@/components/confirm-form";
import { FixCard } from "@/components/fix-card";
import { requireMember } from "@/lib/dal";
import { getAircraft, getFlight, getFlightFixes, getPilotChoices } from "@/lib/flights";
import { getJourneyText, getPlace } from "@/lib/places";
import { formatClock, formatDayShort } from "@/lib/time";

export const dynamic = "force-dynamic";

/**
 * Confirm a stopped flight. SPEC.md 4.1: Stop does not file the flight, it
 * opens this. A draft counts for nothing until a human has looked at it.
 *
 * One thing from the wireframe is still missing: "Add a snag", which wants a
 * snag to exist before the flight does and has not been designed yet.
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

  const [aircraft, fixes, pilots, origin, dest, derivedJourney] = await Promise.all([
    getAircraft(),
    getFlightFixes(flight.id),
    getPilotChoices(),
    flight.origin_place_id ? getPlace(flight.origin_place_id) : null,
    flight.dest_place_id ? getPlace(flight.dest_place_id) : null,
    getJourneyText(flight.origin_place_id, flight.dest_place_id),
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

      <main className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 pt-3.5 pb-4">
        {/*
          SPEC.md 4.2's forgot-to-stop warning. `landing_place_uncertain` is set
          by the database when the end fix matched nothing known, and cleared by
          naming a landing place -- so this banner cannot linger after the thing
          it asks for has been done.
        */}
        {flight.landing_place_uncertain && (
          <p className="rounded-[10px] border border-caution-line bg-caution px-3 py-2.5 text-[13px] font-medium text-caution-text">
            You landed nowhere you have been before. If you forgot to stop the clock, fix
            the end time below; otherwise name where you landed.
          </p>
        )}

        <div className="divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
          <div className="py-3">
            <FixCard
              label="Departed"
              placeName={origin?.name ?? null}
              fix={fixes.start}
              fixAt={flight.start_fix_at}
              accuracyM={
                flight.start_fix_accuracy_m === null
                  ? null
                  : Number(flight.start_fix_accuracy_m)
              }
              trailing={<PlaceLink flightId={flight.id} which="start" isSet={origin !== null} />}
            />
          </div>
          <div className="py-3">
            <FixCard
              label="Landed"
              placeName={dest?.name ?? null}
              fix={fixes.end}
              fixAt={flight.end_fix_at}
              accuracyM={
                flight.end_fix_accuracy_m === null
                  ? null
                  : Number(flight.end_fix_accuracy_m)
              }
              trailing={<PlaceLink flightId={flight.id} which="end" isSet={dest !== null} />}
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
          journeyText={flight.journey_text ?? ""}
          derivedJourney={derivedJourney}
          canChangePilot={member.role === "admin"}
        />
      </main>
    </>
  );
}

/** "Set place" or "Edit", as the wireframe has it, beside a FixCard's label. */
function PlaceLink({
  flightId,
  which,
  isSet,
}: {
  flightId: string;
  which: "start" | "end";
  isSet: boolean;
}) {
  return (
    <Link
      href={`/flight/${flightId}/place/${which}`}
      className="-mr-2 flex min-h-11 items-center px-2 text-[15px] font-medium underline"
    >
      {isSet ? "Edit" : "Set place"}
    </Link>
  );
}
