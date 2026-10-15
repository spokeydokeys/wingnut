import { BackHeader } from "@/components/back-header";
import { Chip } from "@/components/chip";
import { requireAdmin } from "@/lib/dal";
import { getAircraft } from "@/lib/flights";
import { getOwnershipPeriods, getTotalShares } from "@/lib/ownership";
import { formatDate, toDateInputValue } from "@/lib/time";

export const dynamic = "force-dynamic";

/**
 * Who has owned what, and since when.
 *
 * This screen only reads. Changing the split is adding a period, which is the
 * next screen along -- there is deliberately no edit on a period that is in the
 * past, because `fixed_cost_share` resolves the split as of the first of each
 * month and rewriting a period silently rewrites what every closed month
 * should have charged.
 *
 * Admin only, like People, because `ownership_period_admin_write` is what
 * actually enforces it and a pilot shown a list they cannot change is a worse
 * screen than no screen. Everyone can already see their own share: it is on
 * the hangarage line of their bill, in the units it is held in.
 */
export default async function Ownership() {
  await requireAdmin();
  const aircraft = await getAircraft();
  const [periods, totalShares] = await Promise.all([
    aircraft ? getOwnershipPeriods(aircraft.id) : [],
    getTotalShares(),
  ]);

  // The newest period whose date has arrived. A period dated next month is
  // already recorded but is not what today's costs are split by, and saying
  // "In force" on it would be a lie an admin would act on.
  const today = toDateInputValue();
  const inForce = periods.find((p) => p.effective_from <= today)?.id;

  return (
    <>
      <BackHeader
        href="/more"
        label="More"
        title="Ownership"
        subtitle="Who holds what, and since when. Fixed costs are split by this."
      />

      <main className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto px-4 pt-3.5 pb-4">
        {periods.length === 0 && (
          <p className="flex-none rounded-[14px] border border-line bg-surface p-3.5 text-[15px] text-muted">
            No ownership has been recorded yet. Until it is, nobody is billed a
            share of the hangarage.
          </p>
        )}

        {periods.map((period) => (
          <div
            key={period.id}
            className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3"
          >
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="text-base font-semibold">
                  From {formatDate(period.effective_from)}
                </div>
                {period.note && (
                  <div className="text-[13px] text-muted">{period.note}</div>
                )}
              </div>

              {period.id === inForce && (
                <span className="flex-none">
                  <Chip tone="neutral">In force</Chip>
                </span>
              )}
            </div>

            <dl className="mt-2.5 flex flex-col gap-1">
              {period.holdings.map((holding) => (
                <div
                  key={holding.member_id}
                  className="flex items-baseline justify-between gap-3 text-[15px]"
                >
                  <dt className="min-w-0 truncate">{holding.full_name}</dt>
                  {/*
                    The company's share count, not this period's sum, because
                    that is the denominator month_charges prints on the
                    hangarage line. They are the same number -- the constraint
                    trigger sees to that -- and if they ever were not, the one
                    the money was divided by is the one to show.
                  */}
                  <dd className="flex-none tabular-nums">
                    {holding.shares} of {totalShares ?? period.total}
                  </dd>
                </div>
              ))}
            </dl>
          </div>
        ))}
      </main>
    </>
  );
}
