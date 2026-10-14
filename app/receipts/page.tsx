import Link from "next/link";

import { TabBar } from "@/components/tab-bar";
import { requireMember } from "@/lib/dal";
import {
  canReview,
  describeStatus,
  getAwaitingApproval,
  getExpenses,
  type ExpenseWithNames,
} from "@/lib/expenses";
import { getAircraft } from "@/lib/flights";
import { formatMoney } from "@/lib/format";
import { formatDate } from "@/lib/time";

// Whose turn it is to approve depends on who is signed in, and what is waiting
// changes the moment the other owner acts.
export const dynamic = "force-dynamic";

/**
 * Receipts: what is waiting on you, then everything lately.
 *
 * "Waiting on you" is first and separate because it is the only part of this
 * screen that is anybody's job. The rest is a record -- useful, checkable, and
 * nothing to do.
 *
 * The two waiting lists are split by who can act on them rather than merged
 * and sorted by date. A pilot looking at their own unapproved fuel bill cannot
 * do anything about it, and showing it under the same heading as the ones they
 * can agree to would make the queue look permanently stuck.
 */
export default async function Receipts() {
  const member = await requireMember();
  const aircraft = await getAircraft();

  const [waiting, recent] = await Promise.all([
    getAwaitingApproval(),
    getExpenses(),
  ]);

  const mine = aircraft
    ? waiting.filter((e) => canReview(e, member, aircraft))
    : [];
  const mineIds = new Set(mine.map((e) => e.id));
  const theirs = waiting.filter((e) => !mineIds.has(e.id));

  // Everything that is not in one of the queues above, so nothing appears
  // twice: a receipt is either a decision somebody owes or part of the record.
  const settled = recent.filter((e) => e.status !== "submitted");

  return (
    <>
      <header className="flex flex-none items-center justify-between px-4 pt-4 pb-1">
        <h1 className="text-[26px] font-semibold">Receipts</h1>
        <Link
          href="/receipts/new"
          className="flex h-11 items-center rounded-[10px] border-[1.5px] border-ink bg-surface px-4 text-[15px] font-semibold"
        >
          + Receipt
        </Link>
      </header>

      <main className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto px-4 pt-2.5 pb-4">
        <h2 className="field-label px-0.5">Waiting on you</h2>
        {mine.length === 0 ? (
          <p className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3 text-[15px] text-muted">
            Nothing to agree to.
          </p>
        ) : (
          <div className="flex-none divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
            {mine.map((expense) => (
              <ReceiptRow key={expense.id} expense={expense} />
            ))}
          </div>
        )}

        {theirs.length > 0 && (
          <>
            <h2 className="field-label mt-1.5 px-0.5">Waiting on someone else</h2>
            <div className="flex-none divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
              {theirs.map((expense) => (
                <ReceiptRow key={expense.id} expense={expense} />
              ))}
            </div>
          </>
        )}

        <h2 className="field-label mt-1.5 px-0.5">Lately</h2>
        {settled.length === 0 ? (
          <p className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3 text-[15px] text-muted">
            No receipts yet. Fuel you buy is paid back in full on your next
            bill, once another owner has agreed to it.
          </p>
        ) : (
          <div className="flex-none divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
            {settled.map((expense) => (
              <ReceiptRow key={expense.id} expense={expense} />
            ))}
          </div>
        )}
      </main>

      <TabBar />
    </>
  );
}

/**
 * One line of the list.
 *
 * The amount is the total as printed on the paper, tax included, because that
 * is the figure a pilot can check against the receipt in their pocket. It is
 * shown unsigned here even though a reimbursement reaches the bill as a credit
 * -- a minus sign on a list of things you bought reads as a mistake, and the
 * bill is where the sign means something.
 */
function ReceiptRow({ expense }: { expense: ExpenseWithNames }) {
  return (
    <Link
      href={`/receipts/${expense.id}`}
      className="flex items-center justify-between gap-2.5 py-3"
    >
      <span className="min-w-0">
        <span className="block truncate text-[15px] font-medium">
          {expense.vendor}
        </span>
        <span className="block text-[13px] text-muted">
          {formatDate(expense.spent_on)} · {expense.category_name}
          {expense.paid_by_name && ` · ${expense.paid_by_name}`}
        </span>
        <span className="block text-[13px] text-muted">
          {describeStatus(expense)}
          {/*
            Said on the list, not just on the detail screen: a receipt with no
            photo cannot be approved at all, so it is stuck until somebody goes
            back and adds one. That is worth seeing without opening it.
          */}
          {!expense.receipt_key && " · no photo yet"}
        </span>
      </span>
      <span className="numeric text-[15px]">
        {formatMoney(expense.total_amount)}
      </span>
    </Link>
  );
}
