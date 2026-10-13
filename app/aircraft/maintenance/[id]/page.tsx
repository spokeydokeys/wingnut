import Link from "next/link";
import { notFound } from "next/navigation";

import { markMaintenanceDone } from "@/app/aircraft/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { statusText } from "@/components/maintenance-row";
import { getMaintenanceItem, getSnagsWaitingOn } from "@/lib/aircraft";
import { requireMember } from "@/lib/dal";
import { formatHourCount } from "@/lib/format";
import { formatDate, formatDayMonth, toDateInputValue } from "@/lib/time";

export const dynamic = "force-dynamic";

/**
 * One maintenance item, and the only thing anyone does to one from the app:
 * record that it has been done (SPEC.md 4.4).
 *
 * Intervals and life limits are not editable here. They come off an
 * airworthiness document rather than off this screen, and
 * `maintenance_item_admin_write` says so -- a pilot who could shorten the
 * grease interval could also lengthen it.
 */
export default async function MaintenanceItem({
  params,
}: PageProps<"/aircraft/maintenance/[id]">) {
  const { id } = await params;
  await requireMember();

  const item = await getMaintenanceItem(id);
  if (!item) notFound();

  const waiting = await getSnagsWaitingOn(id);
  const onTach = item.basis === "tach";

  const lastDone =
    item.last_done_on === null
      ? "Never recorded"
      : `${formatDate(item.last_done_on)}${
          item.last_done_tach === null
            ? ""
            : ` at ${formatHourCount(Number(item.last_done_tach))} hr`
        }`;

  const due = onTach
    ? item.hours_remaining === null
      ? "Needs a tach reading"
      : statusText(item)
    : item.next_due_on === null
      ? "No due date"
      : formatDate(item.next_due_on);

  return (
    <>
      <BackHeader
        href="/aircraft"
        label="Aircraft"
        title={item.name ?? "Maintenance item"}
        subtitle={
          onTach
            ? `Every ${formatHourCount(Number(item.interval_hours))} hr on the tach`
            : item.interval_months
              ? `Every ${item.interval_months} months`
              : "A fixed calendar limit"
        }
      />

      <main className="flex min-h-0 flex-1 flex-col px-4 pt-3.5 pb-4">
        <div className="mb-3.5 flex flex-none rounded-xl border border-line bg-surface px-3.5 py-3">
          <div className="flex-1">
            <div className="field-label">Last done</div>
            <div className="mt-0.5 text-[15px] font-medium">{lastDone}</div>
          </div>
          <div className="mx-3.5 w-px bg-line" />
          <div className="flex-1">
            <div className="field-label">Due</div>
            <div className="mt-0.5 text-[15px] font-medium">{due}</div>
          </div>
        </div>

        {/*
          The payoff for linking a snag to a job: it is said here, to the person
          who is about to do the job, rather than in a list someone reads at the
          kitchen table that evening. Above the form because it is something to
          act on before pressing Mark done, not after.
        */}
        {waiting.length > 0 && (
          <section className="mb-3.5 flex-none rounded-xl border border-snag-line bg-snag px-3.5 py-2.5">
            <h2 className="field-label text-snag-text">⚠ Waiting on this job</h2>
            <div className="divide-y divide-snag-line">
              {waiting.map((snag) => (
                <Link
                  key={snag.id}
                  href={`/aircraft/snag/${snag.id}`}
                  className="flex min-h-11 items-center justify-between gap-2.5 py-2"
                >
                  <span>
                    <span className="block text-[15px] font-medium">
                      {snag.title}
                    </span>
                    <span className="block text-[13px] text-snag-text">
                      {snag.status === "watch" ? "Watch" : "Open"} · since{" "}
                      {formatDayMonth(snag.reported_at)}
                    </span>
                  </span>
                  <span aria-hidden="true" className="flex-none text-snag-text">
                    ›
                  </span>
                </Link>
              ))}
            </div>
          </section>
        )}

        <ActionForm action={markMaintenanceDone} submitLabel="Mark done">
          <input type="hidden" name="item_id" value={item.id ?? ""} />

          <div>
            <label htmlFor="done_on" className="field-label mb-1.5 block">
              Done on
            </label>
            <input
              id="done_on"
              name="done_on"
              type="date"
              required
              defaultValue={toDateInputValue()}
              className={`${FIELD} numeric`}
            />
          </div>

          {onTach && (
            <div>
              <label htmlFor="tach" className="field-label mb-1.5 block">
                Tach when done
              </label>
              <input
                id="tach"
                name="tach"
                type="number"
                inputMode="decimal"
                step="0.01"
                min="0"
                defaultValue={item.tach_now ?? undefined}
                className={`${FIELD} numeric`}
              />
              <p className="mt-1.5 text-[13px] text-muted">
                Defaulted to the running estimate. Correct it if you read the meter.
              </p>
            </div>
          )}

          <div>
            <label htmlFor="note" className="field-label mb-1.5 block">
              Note (optional)
            </label>
            <input
              id="note"
              name="note"
              type="text"
              placeholder="Who did it, what they found"
              className={FIELD}
            />
          </div>
        </ActionForm>
      </main>
    </>
  );
}
