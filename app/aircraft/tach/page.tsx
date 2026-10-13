import { redirect } from "next/navigation";

import { logTachReading } from "@/app/aircraft/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { getLatestTachReading, getTachEstimate } from "@/lib/aircraft";
import { requireMember } from "@/lib/dal";
import { getAircraft } from "@/lib/flights";
import { formatHours } from "@/lib/format";
import { formatDayShort, toDateInputValue } from "@/lib/time";

export const dynamic = "force-dynamic";

/**
 * Log an actual tach reading (SPEC.md 4.4).
 *
 * The estimate is shown beside the field so the pilot can see what the app
 * thought before they correct it -- a reading far from the estimate is either a
 * typo or a sign the tach factor is wrong, and either way it is worth noticing
 * at the moment of typing.
 */
export default async function LogTach() {
  await requireMember();

  const aircraft = await getAircraft();
  if (!aircraft) redirect("/no-access");

  const [latest, estimate] = await Promise.all([
    getLatestTachReading(aircraft.id),
    getTachEstimate(aircraft.id),
  ]);

  return (
    <>
      <BackHeader
        href="/aircraft"
        label="Aircraft"
        title="Log tach reading"
        subtitle="What the hour meter actually says. Everything on the maintenance list is measured from this."
      />

      <main className="flex min-h-0 flex-1 flex-col px-4 pt-3.5 pb-4">
        <div className="mb-3.5 flex flex-none rounded-xl border border-ink bg-surface px-3.5 py-3">
          <div className="flex-1">
            <div className="field-label">Estimated now</div>
            <div className="numeric text-[28px]">
              {estimate === null ? "– hr" : formatHours(estimate)}
            </div>
            <div className="text-[13px] text-muted">
              {estimate === null ? "No reading logged yet" : "Last reading plus flights"}
            </div>
          </div>
          <div className="mx-3.5 w-px bg-line" />
          <div className="flex-1">
            <div className="field-label">Last read</div>
            <div className="numeric text-[28px]">
              {latest === null ? "– hr" : formatHours(Number(latest.reading))}
            </div>
            <div className="text-[13px] text-muted">
              {latest === null ? "Never" : formatDayShort(latest.read_at)}
            </div>
          </div>
        </div>

        <ActionForm action={logTachReading} submitLabel="Save reading">
          <div>
            <label htmlFor="reading" className="field-label mb-1.5 block">
              Tach reading
            </label>
            <input
              id="reading"
              name="reading"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              required
              autoFocus
              defaultValue={estimate ?? undefined}
              className={`${FIELD} numeric`}
            />
          </div>

          <div>
            <label htmlFor="read_on" className="field-label mb-1.5 block">
              Read on
            </label>
            <input
              id="read_on"
              name="read_on"
              type="date"
              required
              defaultValue={toDateInputValue()}
              className={`${FIELD} numeric`}
            />
          </div>

          <div>
            <label htmlFor="note" className="field-label mb-1.5 block">
              Note (optional)
            </label>
            <input
              id="note"
              name="note"
              type="text"
              placeholder="At the annual, after the ferry flight"
              className={FIELD}
            />
          </div>
        </ActionForm>
      </main>
    </>
  );
}
