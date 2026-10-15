import { addOwnershipPeriod } from "@/app/more/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { ShareTally, type Holder } from "@/components/share-tally";
import { requireAdmin } from "@/lib/dal";
import { getAircraft } from "@/lib/flights";
import { getOwnershipPeriods, getTotalShares } from "@/lib/ownership";
import { getPeople } from "@/lib/people";
import { formatDate, toDateInputValue } from "@/lib/time";

export const dynamic = "force-dynamic";

/** The first of next month, which is when a change to the split starts billing. */
function firstOfNextMonth(): string {
  const [year, month] = toDateInputValue().split("-").map(Number);
  return new Date(Date.UTC(year, month, 1)).toISOString().slice(0, 10);
}

/**
 * Change the split, by recording the one that replaces it.
 *
 * The form is prefilled with the latest split rather than with blanks, because
 * the usual change is one person's holding moving -- and retyping the other
 * three from memory is how the other three get a digit wrong.
 *
 * Everybody active is offered a box, whether or not they hold anything today,
 * since that is how a new owner gets their first shares. Somebody retired who
 * still holds shares is offered one too: their holding has to go somewhere, and
 * a screen that did not list them would make it impossible to say where.
 */
export default async function NewOwnershipPeriod() {
  await requireAdmin();

  const aircraft = await getAircraft();
  const [people, periods, totalShares] = await Promise.all([
    getPeople(),
    aircraft ? getOwnershipPeriods(aircraft.id) : [],
    getTotalShares(),
  ]);

  if (!aircraft || totalShares === null) {
    return (
      <>
        <BackHeader href="/more/ownership" label="Ownership" title="New split" />
        <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5">
          <p className="rounded-[14px] border border-line bg-surface p-3.5 text-[15px] text-muted">
            There is no aeroplane and no company on file yet, so there is nothing
            to divide up.
          </p>
        </main>
      </>
    );
  }

  // The latest period recorded, which is not necessarily the one in force: if a
  // change has already been dated for next month, that is the split this one
  // should start from, not the one it is about to replace.
  const latest = periods[0];
  const held = new Map(latest?.holdings.map((h) => [h.member_id, h.shares]) ?? []);

  const holders: Holder[] = [
    ...people
      .filter((person) => person.is_active)
      .map((person) => ({
        id: person.id,
        name: person.full_name,
        shares: held.get(person.id) ?? 0,
        note: null,
      })),
    ...people
      .filter((person) => !person.is_active && (held.get(person.id) ?? 0) > 0)
      .map((person) => ({
        id: person.id,
        name: person.full_name,
        shares: held.get(person.id) ?? 0,
        note: "No longer on the roster, but still holds this. Give it to somebody.",
      })),
  ];

  return (
    <>
      <BackHeader
        href="/more/ownership"
        label="Ownership"
        title="New split"
        subtitle={
          latest
            ? `Starting from the split of ${formatDate(latest.effective_from)}.`
            : "The first split on record."
        }
      />

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5 pb-4">
        <ActionForm action={addOwnershipPeriod} submitLabel="Record this split">
          <input type="hidden" name="aircraft_id" value={aircraft.id} />

          <div>
            <label htmlFor="effective_from" className="field-label mb-1.5 block">
              In force from
            </label>
            <input
              id="effective_from"
              name="effective_from"
              type="date"
              required
              defaultValue={firstOfNextMonth()}
              className={FIELD}
            />
            <p className="mt-1.5 text-[13px] text-muted">
              Fixed costs are split by whoever owned what on the first of the
              month, so a date part-way through one first shows up on the month
              after it.
            </p>
          </div>

          <ShareTally holders={holders} total={totalShares} />

          <div>
            <label htmlFor="note" className="field-label mb-1.5 block">
              What changed
            </label>
            <input
              id="note"
              name="note"
              type="text"
              autoComplete="off"
              className={FIELD}
            />
            <p className="mt-1.5 text-[13px] text-muted">
              Optional, and the only place the reason survives. &ldquo;Two new
              owners joined&rdquo; is enough.
            </p>
          </div>

          <p className="rounded-[10px] border border-line bg-surface px-3 py-2.5 text-[13px] text-muted">
            The split being replaced is kept. Months already closed were billed
            against it and go on reading the way they were invoiced.
          </p>
        </ActionForm>
      </main>
    </>
  );
}
