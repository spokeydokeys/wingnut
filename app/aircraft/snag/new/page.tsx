import { addSnag } from "@/app/aircraft/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { RecheckField } from "@/components/recheck-field";
import { getMaintenanceChoices } from "@/lib/aircraft";
import { requireMember } from "@/lib/dal";
import { getAircraft } from "@/lib/flights";

export const dynamic = "force-dynamic";

/**
 * Report a snag. SPEC.md 4.3's fields, less the photos, which need object
 * storage that does not exist yet.
 *
 * The aircraft is not a field: one aeroplane is the premise of the app, and
 * `addSnag` reads it rather than trusting a hidden input.
 */
export default async function NewSnag() {
  await requireMember();

  const aircraft = await getAircraft();
  const items = aircraft ? await getMaintenanceChoices(aircraft.id) : [];

  return (
    <>
      <BackHeader
        href="/aircraft"
        label="Aircraft"
        title="Report a snag"
        subtitle="Anything you noticed. Small things are worth writing down too."
      />

      <main className="flex min-h-0 flex-1 flex-col px-4 pt-3.5 pb-4">
        <ActionForm action={addSnag} submitLabel="Report snag">
          <div>
            <label htmlFor="title" className="field-label mb-1.5 block">
              What is wrong
            </label>
            <input
              id="title"
              name="title"
              type="text"
              required
              autoFocus
              placeholder="Left brake squeals on taxi"
              className={FIELD}
            />
          </div>

          <div>
            <label htmlFor="status" className="field-label mb-1.5 block">
              How closely to watch it
            </label>
            <select id="status" name="status" defaultValue="open" className={FIELD}>
              <option value="open">Open — needs fixing</option>
              <option value="watch">Watch — keep an eye on it</option>
            </select>
          </div>

          {/*
            A separate question from the status, and the only one on this form
            that stops the aeroplane flying, so it is spelled out rather than
            being a word in a dropdown.
          */}
          <label className="flex items-start gap-3 rounded-[10px] border border-field bg-surface px-3 py-3">
            <input
              name="grounding"
              type="checkbox"
              className="mt-0.5 size-5 flex-none accent-accent"
            />
            <span>
              <span className="block text-base font-medium">Grounds the aircraft</span>
              <span className="block text-[13px] text-muted">
                Nobody should fly it until this is sorted.
              </span>
            </span>
          </label>

          <RecheckField items={items} itemId={null} tachHours={null} on={null} />

          <div>
            <label htmlFor="notes" className="field-label mb-1.5 block">
              Notes (optional)
            </label>
            <textarea
              id="notes"
              name="notes"
              rows={3}
              placeholder="When it happens, what it sounds like, anything the engineer would want"
              className={`${FIELD} h-auto py-2.5`}
            />
          </div>
        </ActionForm>
      </main>
    </>
  );
}
