import { redirect } from "next/navigation";

import { addAircraftNote } from "@/app/aircraft/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { getTachEstimate } from "@/lib/aircraft";
import { requireMember } from "@/lib/dal";
import { getAircraft } from "@/lib/flights";
import { formatHours } from "@/lib/format";
import { toDateInputValue } from "@/lib/time";

export const dynamic = "force-dynamic";

/**
 * Write a note in the running log.
 *
 * One free-text field and a date, which is the whole point: a typed "oil added,
 * N quarts" form was considered and declined by the owner, because the thing
 * that stops a note being written is being asked questions at the dock.
 *
 * The tach is last and optional. It is NOT defaulted to the running estimate --
 * unlike the mark-done screen, where the estimate is the best available answer
 * about a job that has certainly happened. Here a pre-filled number would be
 * saved by anyone who did not look, and a reading that nobody read is worse
 * than no reading at all: it resets the estimate to a guess and then everything
 * on the maintenance list is measured from it.
 */
export default async function NewAircraftNote() {
  await requireMember();

  const aircraft = await getAircraft();
  if (!aircraft) redirect("/no-access");

  const estimate = await getTachEstimate(aircraft.id);

  return (
    <>
      <BackHeader
        href="/aircraft"
        label="Aircraft"
        title="Add a note"
        subtitle="What you did to the aeroplane that nobody has to act on. Oil, air, a wipe-down."
      />

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5 pb-4">
        <ActionForm action={addAircraftNote} submitLabel="Save note">
          <div>
            <label htmlFor="body" className="field-label mb-1.5 block">
              What you did
            </label>
            <textarea
              id="body"
              name="body"
              rows={3}
              required
              autoFocus
              placeholder="Added a qt of oil. Put air in the tires."
              className={`${FIELD} h-auto py-2.5`}
            />
          </div>

          <div>
            <label htmlFor="noted_on" className="field-label mb-1.5 block">
              Done on
            </label>
            <input
              id="noted_on"
              name="noted_on"
              type="date"
              required
              defaultValue={toDateInputValue()}
              className={`${FIELD} numeric`}
            />
          </div>

          <div>
            <label htmlFor="tach" className="field-label mb-1.5 block">
              Tach reading (optional)
            </label>
            <input
              id="tach"
              name="tach"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              placeholder={estimate === null ? "–" : formatHours(estimate)}
              className={`${FIELD} numeric`}
            />
            <p className="mt-1.5 text-[13px] text-muted">
              {estimate === null
                ? "Only if you looked. Nothing on the maintenance list has a reading to measure from yet."
                : `Only if you looked at the meter. The estimate is ${formatHours(estimate)}, and a real reading corrects it.`}
            </p>
          </div>
        </ActionForm>
      </main>
    </>
  );
}
