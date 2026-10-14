import { createTaskSeries } from "@/app/tasks/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { requireAdmin } from "@/lib/dal";

export const dynamic = "force-dynamic";

/**
 * A chore that comes back, and whose turn rotates.
 *
 * Admin-only, matching `task_series_admin_write`. The rotation is not set here
 * because it is not stored: it is the active roster, optionally narrowed to
 * admins, in name order. So a third owner joining joins the rotation without
 * anyone editing a chore, and a departing one leaves it without leaving a
 * dangling id behind.
 *
 * Both numbers are shown at once rather than behind the recurrence choice. A
 * disclosure would need client state for one field each, and the labels say
 * which one applies.
 */
export default async function NewTaskSeries() {
  await requireAdmin();

  return (
    <>
      <BackHeader href="/tasks" label="Tasks" title="Recurring chore" />

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5 pb-4">
        <ActionForm action={createTaskSeries} submitLabel="Add chore">
          <div>
            <label htmlFor="title" className="field-label mb-1.5 block">
              What it is
            </label>
            <input
              id="title"
              name="title"
              required
              placeholder="Reconcile the bank"
              className={FIELD}
            />
          </div>

          <div>
            <label htmlFor="recurrence" className="field-label mb-1.5 block">
              When it comes round
            </label>
            <select
              id="recurrence"
              name="recurrence"
              defaultValue="month_close"
              className={FIELD}
            >
              <option value="month_close">Each time a month is closed</option>
              <option value="interval_days">
                A number of days after it was last done
              </option>
            </select>
          </div>

          <div>
            <label htmlFor="due_offset_days" className="field-label mb-1.5 block">
              Days after month end it is due
            </label>
            <input
              id="due_offset_days"
              name="due_offset_days"
              type="number"
              min="0"
              step="1"
              defaultValue="10"
              className={FIELD}
            />
            <p className="mt-1.5 text-[13px] text-muted">
              For a month-close chore. The statement has to arrive before anyone
              can reconcile it.
            </p>
          </div>

          <div>
            <label htmlFor="interval_days" className="field-label mb-1.5 block">
              Days between turns
            </label>
            <input
              id="interval_days"
              name="interval_days"
              type="number"
              min="1"
              step="1"
              placeholder="90"
              className={FIELD}
            />
            <p className="mt-1.5 text-[13px] text-muted">
              For a chore on a count of days. Counted from when it was done, not
              from when it fell due, so a late turn does not shorten the next one.
            </p>
          </div>

          <label className="flex items-start gap-3 rounded-[10px] border border-field bg-surface px-3 py-3">
            <input
              name="admins_only"
              type="checkbox"
              defaultChecked
              className="mt-0.5 size-5 flex-none accent-accent"
            />
            <span>
              <span className="block text-base font-medium">Admins only</span>
              <span className="block text-[13px] text-muted">
                Leave this on for anything involving the books. Off puts every
                active member in the rotation.
              </span>
            </span>
          </label>

          <div>
            <label htmlFor="detail" className="field-label mb-1.5 block">
              Detail
            </label>
            <textarea
              id="detail"
              name="detail"
              rows={3}
              placeholder="What the person whose turn it is actually has to do"
              className={`${FIELD} h-auto py-2.5`}
            />
          </div>
        </ActionForm>
      </main>
    </>
  );
}
