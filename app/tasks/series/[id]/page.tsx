import { notFound } from "next/navigation";

import { retireTaskSeries, updateTaskSeries } from "@/app/tasks/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { requireAdmin } from "@/lib/dal";
import { getTaskSeriesById } from "@/lib/tasks";

export const dynamic = "force-dynamic";

/**
 * Correcting a chore that comes back.
 *
 * The same fields as adding one, in the same order, because they are the same
 * chore -- an editor that reordered or renamed them would make the reader
 * wonder which screen was authoritative.
 *
 * Admin-only, matching `task_series_admin_write` and the add screen. Whose
 * turn it is next is absent on purpose: it is derived from the roster and from
 * who took the last turn, so the only control here that moves it is the
 * admins-only switch.
 */
export default async function EditTaskSeries({
  params,
}: PageProps<"/tasks/series/[id]">) {
  const { id } = await params;
  await requireAdmin();

  const series = await getTaskSeriesById(id);
  if (!series) notFound();

  return (
    <>
      <BackHeader
        href="/tasks"
        label="Tasks"
        title={series.title}
        subtitle={
          series.is_active
            ? "Changes reach the next turn, not the ones already handed out."
            : "Stopped — this one no longer comes back."
        }
      />

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5 pb-4">
        <ActionForm
          action={updateTaskSeries.bind(null, series.id)}
          submitLabel="Save chore"
        >
          <div>
            <label htmlFor="title" className="field-label mb-1.5 block">
              What it is
            </label>
            <input
              id="title"
              name="title"
              required
              defaultValue={series.title}
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
              defaultValue={series.recurrence}
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
              defaultValue={series.due_offset_days}
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
              defaultValue={series.interval_days ?? ""}
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
              defaultChecked={series.admins_only}
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
              defaultValue={series.detail ?? ""}
              placeholder="What the person whose turn it is actually has to do"
              className={`${FIELD} h-auto py-2.5`}
            />
          </div>
        </ActionForm>

        {/*
          Here as well as on the list, because this is the screen somebody
          opens when a chore has stopped being worth doing -- and finding the
          switch-off only after backing out would be a reason to delete the
          thing instead, taking the record of every turn with it.
        */}
        {series.is_active && (
          <form action={retireTaskSeries.bind(null, series.id)} className="flex-none">
            <button
              type="submit"
              className="flex min-h-11 w-full items-center justify-center text-[15px] font-medium text-muted underline"
            >
              Stop this coming back
            </button>
          </form>
        )}
      </main>
    </>
  );
}
