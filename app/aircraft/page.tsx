import Link from "next/link";

import { MaintenanceRow } from "@/components/maintenance-row";
import { SnagCard } from "@/components/snag-card";
import { TabBar } from "@/components/tab-bar";
import { getLiveSnags, getMaintenance } from "@/lib/aircraft";
import { requireMember } from "@/lib/dal";
import { getAircraft } from "@/lib/flights";

// Due-soon and overdue are computed against today's date and the running tach
// estimate, both of which move. Nothing here is cacheable.
export const dynamic = "force-dynamic";

/**
 * The Aircraft tab: what is wrong with the aeroplane, and what is coming due.
 *
 * SPEC.md 3 ranks this third, after flying and paying, and the layout says so:
 * snags are cards because each one is a thing someone must decide about, while
 * maintenance items are rows in a single card because together they are one
 * status board.
 *
 * Reserves (SPEC.md 4.8) are deliberately absent -- the spec puts them on the
 * admin Pool page, and what an overhaul will cost is a different question from
 * when it falls due.
 */
export default async function Aircraft() {
  await requireMember();

  const aircraft = await getAircraft();
  if (!aircraft) {
    return (
      <>
        <header className="flex-none px-4 pt-5 pb-1">
          <h1 className="text-[26px] font-semibold">Aircraft</h1>
        </header>
        <main className="flex min-h-0 flex-1 flex-col px-4 pt-3">
          <p className="rounded-[14px] border border-line bg-surface p-4 text-[15px] text-muted">
            No aircraft has been set up yet.
          </p>
        </main>
        <TabBar />
      </>
    );
  }

  const [snags, maintenance] = await Promise.all([
    getLiveSnags(aircraft.id),
    getMaintenance(aircraft.id),
  ]);

  const open = snags.filter((snag) => snag.status === "open").length;
  const watch = snags.length - open;
  const counts = [open > 0 && `${open} open`, watch > 0 && `${watch} watch`].filter(
    Boolean,
  );

  return (
    <>
      <header className="flex flex-none items-center justify-between px-4 pt-4 pb-1">
        <h1 className="numeric text-2xl tracking-[1px]">{aircraft.registration}</h1>
        <Link
          href="/aircraft/snag/new"
          className="flex h-11 items-center rounded-[10px] border-[1.5px] border-ink bg-surface px-4 text-[15px] font-semibold"
        >
          + Snag
        </Link>
      </header>

      <main className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto px-4 pt-2.5 pb-4">
        <h2 className="field-label px-0.5">
          Snags{counts.length > 0 && ` · ${counts.join(", ")}`}
        </h2>

        {snags.length === 0 ? (
          <p className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3 text-[15px] text-muted">
            Nothing reported. Anything you notice goes here, however small.
          </p>
        ) : (
          snags.map((snag) => <SnagCard key={snag.id} snag={snag} />)
        )}

        <div className="mt-1.5 flex items-center justify-between px-0.5">
          <h2 className="field-label">Maintenance</h2>
          <Link
            href="/aircraft/tach"
            className="flex min-h-11 items-center text-sm font-semibold text-accent"
          >
            Log tach reading
          </Link>
        </div>

        {maintenance.length === 0 ? (
          <p className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3 text-[15px] text-muted">
            No maintenance items have been set up yet.
          </p>
        ) : (
          <div className="flex-none divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
            {maintenance.map((item) => (
              <MaintenanceRow key={item.id} item={item} />
            ))}
          </div>
        )}
      </main>

      <TabBar />
    </>
  );
}
