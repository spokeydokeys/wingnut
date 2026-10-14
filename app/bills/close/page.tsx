import Link from "next/link";

import { closeMonth, issueInvoice } from "@/app/bills/actions";
import { BackHeader } from "@/components/back-header";
import { InlineAction } from "@/components/inline-action";
import { getDrafts, getRoster } from "@/lib/bills";
import { requireAdmin } from "@/lib/dal";
import { getAwaitingApproval } from "@/lib/expenses";
import { formatMoney } from "@/lib/format";
import { currentMonthStart, formatMonthLong } from "@/lib/time";

export const dynamic = "force-dynamic";

/** `2026-09`, the month before the one it is now where the aeroplane lives. */
function lastMonth(): string {
  const [y, m] = currentMonthStart().split("-").map(Number);
  const previous = new Date(Date.UTC(y, m - 2, 1));
  return previous.toISOString().slice(0, 7);
}

/**
 * The admin's month close (SPEC.md 4.6).
 *
 * Two steps, deliberately. Building the drafts is reversible -- it can be run
 * again after a flight is corrected, and `close_month` rebuilds a draft it
 * already made -- while issuing is not: the invoice takes a gapless number and
 * the month's flights lock. So the review step 4.6 asks for is not a
 * confirmation dialog, it is the gap between the two buttons, with the figures
 * on screen in between.
 *
 * The month lives in the URL rather than in form state so that the drafts
 * shown and the drafts the Issue buttons act on cannot come apart.
 */
export default async function CloseMonth({
  searchParams,
}: PageProps<"/bills/close">) {
  await requireAdmin();

  const asked = (await searchParams).month;
  const param = typeof asked === "string" && /^\d{4}-\d{2}$/.test(asked) ? asked : lastMonth();
  const month = `${param}-01`;

  const [drafts, roster, waiting] = await Promise.all([
    getDrafts(month),
    getRoster(),
    getAwaitingApproval(),
  ]);
  const outstanding = roster.reduce((t, m) => t + m.balance, 0);

  // Receipts bought in this month or earlier that nobody has agreed to yet.
  // `month_expense_ids` credits on reviewed_at, so these are not on the drafts
  // below and will not be until somebody agrees to them -- at which point they
  // are swept into whichever month is closed next. Later ones are not this
  // month's problem.
  const unagreed = waiting.filter((e) => e.spent_on.slice(0, 7) <= param);
  const unagreedTotal = unagreed.reduce((t, e) => t + Number(e.total_amount), 0);

  return (
    <>
      <BackHeader
        href="/bills"
        label="Bills"
        title="Close a month"
        subtitle="Build the drafts, read them, then issue. Issuing numbers the invoice and locks the month's flights."
      />

      <main className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 pt-3.5 pb-4">
        <form method="get" className="flex flex-none items-end gap-2">
          <div className="flex-1">
            <label htmlFor="month" className="field-label mb-1.5 block">
              Month
            </label>
            <input
              id="month"
              name="month"
              type="month"
              defaultValue={param}
              className="numeric h-12 w-full rounded-[10px] border border-field bg-surface px-3 text-base font-medium text-ink"
            />
          </div>
          <button
            type="submit"
            className="flex h-12 flex-none items-center rounded-[10px] border-[1.5px] border-ink bg-surface px-4 text-[15px] font-semibold"
          >
            Show
          </button>
        </form>

        {/*
          Above the drafts because it is the thing to deal with before building
          them, not after reading them. A caution rather than a refusal: issuing
          with a receipt outstanding is not wrong, it just means the money comes
          back a month later than whoever is out of pocket expects.
        */}
        {unagreed.length > 0 && (
          <Link
            href="/receipts"
            className="flex-none rounded-[14px] border border-caution-line bg-caution px-3.5 py-3"
          >
            <div className="flex items-center justify-between gap-3">
              <span className="text-[15px] font-semibold text-caution-text">
                {unagreed.length === 1
                  ? "1 receipt is still waiting to be agreed"
                  : `${unagreed.length} receipts are still waiting to be agreed`}
              </span>
              <span className="numeric flex-none text-[15px] text-caution-text">
                {formatMoney(unagreedTotal)}
              </span>
            </div>
            <p className="mt-0.5 text-[13px] text-caution-text">
              Not credited on the drafts below. Agree to them first and they
              land on this month; leave them and they land on the next one.
            </p>
          </Link>
        )}

        <section className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3">
          <h2 className="font-semibold">{formatMonthLong(month)} drafts</h2>

          {drafts.length === 0 ? (
            <>
              <p className="mt-0.5 mb-3 text-[15px] text-muted">
                Nothing drafted for this month yet. Building them is safe: it
                can be run again, and an invoice already issued is left alone.
              </p>
              <InlineAction
                action={closeMonth}
                label={`Build ${formatMonthLong(month)} drafts`}
                fields={{ month: param }}
              />
            </>
          ) : (
            <div className="divide-y divide-hairline">
              {drafts.map(({ invoice, member, total }) => (
                <div
                  key={invoice.id}
                  className="flex items-center justify-between gap-3 py-3"
                >
                  <div>
                    <div className="text-[15px] font-medium">{member}</div>
                    <Link
                      href={`/bills/${invoice.id}`}
                      className="numeric text-[15px] text-accent underline"
                    >
                      {formatMoney(total)}
                    </Link>
                  </div>
                  <InlineAction
                    action={issueInvoice}
                    label="Issue"
                    fields={{ invoice_id: invoice.id, month: param }}
                  />
                </div>
              ))}
            </div>
          )}
        </section>

        <section className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3">
          <div className="flex items-center justify-between">
            <h2 className="font-semibold">Balances</h2>
            <span className="numeric text-[15px]">{formatMoney(outstanding)}</span>
          </div>

          <div className="mt-1 divide-y divide-hairline">
            {roster.map((m) => (
              <div
                key={m.id}
                className="flex min-h-11 items-center justify-between gap-3"
              >
                <span className="text-[15px]">{m.full_name}</span>
                <span
                  className={`numeric text-[15px] ${m.balance < 0 ? "text-ok" : ""}`}
                >
                  {formatMoney(m.balance)}
                </span>
              </div>
            ))}
          </div>
        </section>

        <Link
          href="/bills/payment"
          className="flex h-12 flex-none items-center justify-center rounded-xl border-[1.5px] border-ink bg-surface text-base font-semibold"
        >
          Record a payment
        </Link>
      </main>
    </>
  );
}
