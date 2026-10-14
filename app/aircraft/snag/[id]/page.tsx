import { notFound } from "next/navigation";

import { deleteSnag, updateSnag } from "@/app/aircraft/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { RecheckField } from "@/components/recheck-field";
import { getMaintenanceChoices, getSnag } from "@/lib/aircraft";
import { requireMember } from "@/lib/dal";
import { formatDayShort } from "@/lib/time";

export const dynamic = "force-dynamic";

/**
 * One snag, and the two things anyone does with one: re-grade it or clear it.
 *
 * Any member may clear a snag, not just whoever reported it -- the owner who
 * fixed the brake is usually not the owner who found it. Deleting is narrower,
 * and stays with the author: it is for a snag entered by mistake, whereas a
 * snag that was real and is now fixed should be cleared so it stays in the
 * record.
 */
export default async function SnagDetail({ params }: PageProps<"/aircraft/snag/[id]">) {
  const { id } = await params;
  const member = await requireMember();

  const snag = await getSnag(id);
  if (!snag) notFound();

  const items = await getMaintenanceChoices(snag.aircraft_id);

  return (
    <>
      <BackHeader
        href="/aircraft"
        label="Aircraft"
        title={snag.title}
        subtitle={`Reported ${formatDayShort(snag.reported_at)} by ${
          snag.reporter?.full_name ?? "a former owner"
        }`}
      />

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5 pb-4">
        <ActionForm action={updateSnag} submitLabel="Save snag">
          <input type="hidden" name="id" value={snag.id} />

          <div>
            <label htmlFor="status" className="field-label mb-1.5 block">
              Status
            </label>
            <select
              id="status"
              name="status"
              defaultValue={snag.status}
              className={FIELD}
            >
              <option value="open">Open — needs fixing</option>
              <option value="watch">Watch — keep an eye on it</option>
              <option value="cleared">Cleared — sorted</option>
            </select>
          </div>

          <label className="flex items-start gap-3 rounded-[10px] border border-field bg-surface px-3 py-3">
            <input
              name="grounding"
              type="checkbox"
              defaultChecked={snag.grounding}
              className="mt-0.5 size-5 flex-none accent-accent"
            />
            <span>
              <span className="block text-base font-medium">Grounds the aircraft</span>
              <span className="block text-[13px] text-muted">
                Clearing the snag clears this too.
              </span>
            </span>
          </label>

          <RecheckField
            items={items}
            itemId={snag.recheck_item_id}
            tachHours={snag.recheck_tach_hours}
            on={snag.recheck_on}
          />

          <div>
            <label htmlFor="notes" className="field-label mb-1.5 block">
              Notes
            </label>
            <textarea
              id="notes"
              name="notes"
              rows={3}
              defaultValue={snag.notes ?? ""}
              placeholder="What was done about it"
              className={`${FIELD} h-auto py-2.5`}
            />
          </div>
        </ActionForm>

        {/*
          Only the author, matching `snag_delete_own`. An admin's own policy
          lets them through as well, which is why the test is on either.
        */}
        {(snag.reported_by === member.id || member.role === "admin") && (
          <form
            action={deleteSnag.bind(null, snag.id)}
            className="mt-2 flex flex-none justify-center"
          >
            <button
              type="submit"
              className="flex min-h-11 items-center justify-center text-[15px] font-medium text-muted underline"
            >
              Delete — this was entered by mistake
            </button>
          </form>
        )}
      </main>
    </>
  );
}
