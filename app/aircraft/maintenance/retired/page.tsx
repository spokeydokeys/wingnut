import Link from "next/link";
import { redirect } from "next/navigation";

import { BackHeader } from "@/components/back-header";
import { getRetiredMaintenance } from "@/lib/aircraft";
import { requireMember } from "@/lib/dal";
import { formatHourCount } from "@/lib/format";
import { getAircraft } from "@/lib/flights";
import { formatDate } from "@/lib/time";

export const dynamic = "force-dynamic";

/**
 * The items that are no longer being counted down to.
 *
 * A screen of its own rather than a greyed-out tail on the Aircraft tab: the
 * board is what is coming due, and something nobody has to do does not belong
 * in the middle of that. Each row goes to Edit, which is where it was retired
 * and where it can be put back.
 */
export default async function RetiredMaintenance() {
  const member = await requireMember();
  if (member.role !== "admin") redirect("/aircraft");

  const aircraft = await getAircraft();
  const items = aircraft ? await getRetiredMaintenance(aircraft.id) : [];

  return (
    <>
      <BackHeader
        href="/aircraft"
        label="Aircraft"
        title="Retired items"
        subtitle="Kept, but not counted down to"
      />

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5 pb-4">
        {items.length === 0 ? (
          <p className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3 text-[15px] text-muted">
            Nothing has been retired.
          </p>
        ) : (
          <div className="flex-none divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
            {items.map((item) => (
              <Link
                key={item.id}
                href={`/aircraft/maintenance/${item.id}/edit`}
                className="flex min-h-11 items-center justify-between gap-2.5 py-3"
              >
                <span className="min-w-0">
                  <span className="block text-[15px] font-medium">
                    {item.name}
                  </span>
                  <span className="block text-[13px] text-muted">
                    {item.basis === "tach"
                      ? `Every ${formatHourCount(Number(item.interval_hours))} hr on the tach`
                      : item.interval_months
                        ? `Every ${item.interval_months} months`
                        : item.due_date
                          ? `Was due ${formatDate(item.due_date)}`
                          : "A fixed calendar limit"}
                  </span>
                </span>
                <span aria-hidden="true" className="flex-none text-muted">
                  ›
                </span>
              </Link>
            ))}
          </div>
        )}
      </main>
    </>
  );
}
