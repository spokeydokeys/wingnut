import Link from "next/link";
import { redirect } from "next/navigation";

import { createMaintenanceItem } from "@/app/aircraft/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { getSnag } from "@/lib/aircraft";
import { requireMember } from "@/lib/dal";

export const dynamic = "force-dynamic";

/**
 * A new maintenance item, in two steps: which clock it runs on, then the item.
 *
 * The basis is asked first and on its own because it decides what the rest of
 * the form is. Showing hours and months and a fixed date together, with a
 * dropdown greying out two of the three, would be the same question asked worse
 * -- and it is the one answer Edit will never let anybody change afterwards, so
 * it deserves its own screen rather than a line in the middle of one.
 *
 * Admin only, for the same reason as Edit: `maintenance_item_admin_write`.
 */
export default async function NewMaintenanceItem({
  searchParams,
}: PageProps<"/aircraft/maintenance/new">) {
  const member = await requireMember();
  if (member.role !== "admin") redirect("/aircraft");

  const { basis, from } = await searchParams;
  const onTach = basis === "tach";

  // Promoted out of a snag, when it came from one. The snag survives and is
  // set to wait on the new item, so the fault and the job stay joined up.
  const snagId = typeof from === "string" ? from : undefined;
  const snag = snagId ? await getSnag(snagId) : null;
  const carry = snag ? `&from=${snag.id}` : "";

  if (basis !== "tach" && basis !== "calendar") {
    return (
      <>
        <BackHeader
          href={snag ? `/aircraft/snag/${snag.id}` : "/aircraft"}
          label={snag ? "Snag" : "Aircraft"}
          title={snag ? "Make it a job" : "New item"}
          subtitle="Which clock does it run on?"
        />

        <main className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto px-4 pt-3.5 pb-4">
          <Link
            href={`/aircraft/maintenance/new?basis=tach${carry}`}
            className="flex-none rounded-xl border border-line bg-surface px-3.5 py-3"
          >
            <span className="block text-[15px] font-semibold">
              Tach hours
            </span>
            <span className="block text-[13px] text-muted">
              Comes due after the aeroplane has flown so many hours. The hub
              grease and the engine overhaul are these.
            </span>
          </Link>

          <Link
            href={`/aircraft/maintenance/new?basis=calendar${carry}`}
            className="flex-none rounded-xl border border-line bg-surface px-3.5 py-3"
          >
            <span className="block text-[15px] font-semibold">
              The calendar
            </span>
            <span className="block text-[13px] text-muted">
              Comes due on a date, whether it has flown or not. The blade clip
              inspection and the prop overhaul are these.
            </span>
          </Link>
        </main>
      </>
    );
  }

  return (
    <>
      <BackHeader
        href={`/aircraft/maintenance/new${snag ? `?from=${snag.id}` : ""}`}
        label="Back"
        title={snag ? "Make it a job" : "New item"}
        subtitle={onTach ? "Measured on the tach" : "Measured on the calendar"}
      />

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5 pb-4">
        <ActionForm
          action={createMaintenanceItem.bind(null, basis)}
          submitLabel={snag ? "Make it a job" : "Add item"}
        >
          {snag && <input type="hidden" name="from" value={snag.id} />}

          <div>
            <label htmlFor="name" className="field-label mb-1.5 block">
              Name
            </label>
            <input
              id="name"
              name="name"
              type="text"
              required
              // The snag's words, to be edited: "Oil seep at valve cover" is
              // how the fault was described, and the job is probably called
              // something nearer "Valve cover torque check".
              defaultValue={snag?.title}
              placeholder={onTach ? "Oil and filter change" : "Annual inspection"}
              className={FIELD}
            />
          </div>

          {/*
            Nothing on the Aircraft tab reads this yet, but it is the difference
            between a job that comes round again and a limit the part reaches
            once, and that is not something to guess at later from an interval.
          */}
          <div>
            <label htmlFor="kind" className="field-label mb-1.5 block">
              Sort of item
            </label>
            <select
              id="kind"
              name="kind"
              defaultValue="recurring_task"
              className={FIELD}
            >
              <option value="recurring_task">A job that comes round again</option>
              <option value="recurring_inspection">
                An inspection that comes round again
              </option>
              <option value="life_limit">
                A limit the part reaches once
              </option>
            </select>
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
              className={`${FIELD} numeric`}
            />
            <p className="mt-1.5 text-[13px] text-muted">
              What the job is expected to cost. An estimate for planning, not a
              bill: the real figure arrives as a receipt.
            </p>
          </div>

          {/*
            A new item has never been done, so the board will show it as needing
            a date before it can count down to anything. Saying so here, inside
            the form, saves the puzzled trip back.
          */}
          <p className="rounded-[10px] border border-line bg-surface px-3 py-2.5 text-[13px] text-muted">
            Nothing counts down until the item has been marked done once, so the
            next screen asks when the job was last actually carried out.
            {snag &&
              ` “${snag.title}” stays open and will be set to wait on this job, so whoever does it is told.`}
          </p>
        </ActionForm>
      </main>
    </>
  );
}
