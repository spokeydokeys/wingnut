import { notFound, redirect } from "next/navigation";

import {
  setMaintenanceItemActive,
  updateMaintenanceItem,
} from "@/app/aircraft/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { getMaintenanceItemRow } from "@/lib/aircraft";
import { requireMember } from "@/lib/dal";

export const dynamic = "force-dynamic";

/**
 * What an item is, as opposed to when it was last done.
 *
 * Admin only, because `maintenance_item_admin_write` says so: a pilot who could
 * shorten the grease interval could also lengthen it. A pilot who arrives here
 * is sent back to the item rather than shown a form that would be refused.
 *
 * The basis is shown and not editable. Which clock an item runs on is what it
 * is -- an inspection that moved from hours to months is a different item, and
 * switching it here would leave its history measured in units it no longer
 * uses.
 */
export default async function EditMaintenanceItem({
  params,
}: PageProps<"/aircraft/maintenance/[id]/edit">) {
  const { id } = await params;
  const member = await requireMember();

  const item = await getMaintenanceItemRow(id);
  if (!item) notFound();
  if (member.role !== "admin") redirect(`/aircraft/maintenance/${id}`);

  const onTach = item.basis === "tach";

  return (
    <>
      <BackHeader
        // A retired item is not in `maintenance_status`, so its own screen
        // would be a 404. The list it came from is the way back.
        href={
          item.is_active
            ? `/aircraft/maintenance/${id}`
            : "/aircraft/maintenance/retired"
        }
        label={item.is_active ? "Item" : "Retired"}
        title="Edit item"
        subtitle={
          onTach ? "Measured on the tach" : "Measured on the calendar"
        }
      />

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5 pb-4">
        <ActionForm
          action={updateMaintenanceItem.bind(null, id)}
          submitLabel="Save"
        >
          <div>
            <label htmlFor="name" className="field-label mb-1.5 block">
              Name
            </label>
            <input
              id="name"
              name="name"
              type="text"
              required
              defaultValue={item.name}
              className={FIELD}
            />
          </div>

          {onTach ? (
            <>
              <div>
                <label
                  htmlFor="interval_hours"
                  className="field-label mb-1.5 block"
                >
                  Every
                </label>
                <input
                  id="interval_hours"
                  name="interval_hours"
                  type="number"
                  inputMode="decimal"
                  step="0.1"
                  min="0.1"
                  required
                  defaultValue={item.interval_hours ?? undefined}
                  className={`${FIELD} numeric`}
                />
                <p className="mt-1.5 text-[13px] text-muted">
                  Tach hours between jobs.
                </p>
              </div>

              <div>
                <label htmlFor="lead_hours" className="field-label mb-1.5 block">
                  Warn at
                </label>
                <input
                  id="lead_hours"
                  name="lead_hours"
                  type="number"
                  inputMode="decimal"
                  step="0.1"
                  min="0"
                  defaultValue={item.lead_hours ?? undefined}
                  className={`${FIELD} numeric`}
                />
                <p className="mt-1.5 text-[13px] text-muted">
                  Hours left when it starts reading &ldquo;due soon&rdquo;.
                  Leave empty for no warning.
                </p>
              </div>
            </>
          ) : (
            <>
              <div>
                <label
                  htmlFor="interval_months"
                  className="field-label mb-1.5 block"
                >
                  Every
                </label>
                <input
                  id="interval_months"
                  name="interval_months"
                  type="number"
                  inputMode="numeric"
                  step="1"
                  min="1"
                  defaultValue={item.interval_months ?? undefined}
                  className={`${FIELD} numeric`}
                />
                <p className="mt-1.5 text-[13px] text-muted">
                  Months between jobs, counted from the last one done.
                </p>
              </div>

              <div>
                <label htmlFor="due_date" className="field-label mb-1.5 block">
                  Or due on
                </label>
                <input
                  id="due_date"
                  name="due_date"
                  type="date"
                  defaultValue={item.due_date ?? undefined}
                  className={`${FIELD} numeric`}
                />
                <p className="mt-1.5 text-[13px] text-muted">
                  One or the other. A fixed date is for the limit that happens
                  once, like a prop overhaul; filling it in clears the months.
                </p>
              </div>

              <div>
                <label htmlFor="lead_days" className="field-label mb-1.5 block">
                  Warn at
                </label>
                <input
                  id="lead_days"
                  name="lead_days"
                  type="number"
                  inputMode="numeric"
                  step="1"
                  min="0"
                  defaultValue={item.lead_days ?? undefined}
                  className={`${FIELD} numeric`}
                />
                <p className="mt-1.5 text-[13px] text-muted">
                  Days left when it starts reading &ldquo;due soon&rdquo;.
                </p>
              </div>
            </>
          )}

          <div>
            <label htmlFor="est_cost" className="field-label mb-1.5 block">
              Expected cost
            </label>
            <input
              id="est_cost"
              name="est_cost"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              defaultValue={item.est_cost ?? undefined}
              className={`${FIELD} numeric`}
            />
            <p className="mt-1.5 text-[13px] text-muted">
              What the job is expected to cost. An estimate for planning, not a
              bill: the real figure arrives as a receipt.
            </p>
          </div>
        </ActionForm>

        {/*
          Below Save, because it is the rarer thing and the one worth a pause.
          Not a delete: the events behind an item are a logbook, and this only
          decides whether the board is still counting down to the next one.
        */}
        <form
          action={setMaintenanceItemActive.bind(null, id, !item.is_active)}
          className="mt-3.5 flex-none"
        >
          <p className="mb-2 text-[13px] text-muted">
            {item.is_active
              ? "Retiring takes it off the board and out of the re-check list on a snag. Everything already recorded against it is kept, and it can be put back."
              : "This item is retired, so nothing is counting down to it. Putting it back picks up from the last time it was marked done."}
          </p>
          <button
            type="submit"
            className="flex h-12 w-full items-center justify-center rounded-xl border-[1.5px] border-ink bg-surface text-base font-semibold"
          >
            {item.is_active ? "Retire this item" : "Put it back on the board"}
          </button>
        </form>
      </main>
    </>
  );
}
