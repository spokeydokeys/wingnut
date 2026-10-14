import Link from "next/link";
import { notFound } from "next/navigation";

import { deleteExpense } from "@/app/receipts/actions";
import { BackHeader } from "@/components/back-header";
import { ReceiptPhoto } from "@/components/receipt-photo";
import { ReceiptReview } from "@/components/receipt-review";
import { requireMember } from "@/lib/dal";
import {
  canReview,
  describeStatus,
  getDuplicates,
  getExpense,
  getReceiptUrl,
  isMonthClosed,
  lockReason,
} from "@/lib/expenses";
import { getAircraft } from "@/lib/flights";
import { formatMoney } from "@/lib/format";
import { formatDate, formatDayShort } from "@/lib/time";

// Whether this can still be changed depends on whether a bill has been issued
// since, which happens elsewhere and without warning.
export const dynamic = "force-dynamic";

/**
 * One receipt, and whatever is left to do about it.
 *
 * Which is usually nothing. Most visits here are to look at the photo and
 * check a figure, so the picture is first and the controls are last. The
 * decision panel appears only for the person whose decision it is: a pilot
 * looking at their own fuel bill has no buttons, because they have no say.
 *
 * Every control on this screen is a copy of a rule the database also holds.
 * Hiding one is a courtesy, not the enforcement -- `expense_zz_validate` and
 * `expense_zz_guard_frozen` raise either way, and if the two ever disagree the
 * database is right.
 */
export default async function ReceiptDetail({
  params,
}: PageProps<"/receipts/[id]">) {
  const { id } = await params;
  const member = await requireMember();

  const expense = await getExpense(id);
  if (!expense) notFound();

  const [aircraft, photoUrl, duplicates, monthClosed] = await Promise.all([
    getAircraft(),
    getReceiptUrl(expense),
    getDuplicates(expense.id),
    isMonthClosed(expense.company_id, expense.spent_on),
  ]);

  const locked = lockReason(expense, monthClosed);
  const mine = aircraft ? canReview(expense, member, aircraft) : false;

  // Deleting stays with whoever entered it (`expense_delete_own`) or an admin
  // (`expense_admin_all`). It is for a receipt entered by mistake -- one that
  // was declined is a record of a decision and is kept.
  const canDelete =
    locked === null &&
    (expense.submitted_by === member.id || member.role === "admin");

  return (
    <>
      <BackHeader
        href="/receipts"
        label="Receipts"
        title={expense.vendor}
        subtitle={`${formatDate(expense.spent_on)} · ${formatMoney(expense.total_amount)}`}
      />

      <main className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto px-4 pt-3.5 pb-4">
        <ReceiptPhoto
          expenseId={expense.id}
          url={photoUrl}
          canChange={locked === null}
        />

        {/*
          A warning, never a refusal. SPEC.md 4.7 only asks for the flag, and
          two real fills on one day do happen -- the pilot can see both and
          decide, which is more than a blocked save would let them do.
        */}
        {duplicates.length > 0 && (
          <div className="flex-none rounded-[14px] border border-snag-line bg-snag px-3.5 py-3">
            <p className="text-[13px] font-medium text-snag-text">
              Same vendor, same day, same amount as{" "}
              {duplicates.length === 1 ? "another receipt" : "others"}. Check
              this is not the same one twice.
            </p>
            <ul className="mt-1.5 flex flex-col gap-1">
              {duplicates.map((other) => (
                <li key={other.id}>
                  <Link
                    href={`/receipts/${other.id}`}
                    className="text-[13px] font-medium text-snag-text underline"
                  >
                    {formatDate(other.spent_on)} · {formatMoney(other.total_amount)}
                    {other.paid_by_name ? ` · ${other.paid_by_name}` : ""}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        )}

        <dl className="flex-none divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
          <Detail label="What it was for">{expense.category_name}</Detail>
          <Detail label="Who paid">
            {expense.payer === "company"
              ? "The company card"
              : (expense.paid_by_name ?? "A former owner")}
          </Detail>
          {/*
            The total as printed on the paper, tax included. Shown unsigned:
            the minus sign belongs on the bill, where it means a credit.
          */}
          <Detail label="Total paid">
            <span className="numeric">{formatMoney(expense.total_amount)}</span>
          </Detail>
          {expense.gst_amount > 0 && (
            <Detail label="GST included in the total">
              <span className="numeric">{formatMoney(expense.gst_amount)}</span>
            </Detail>
          )}
          {expense.vendor_gst_number && (
            <Detail label="Their GST number">{expense.vendor_gst_number}</Detail>
          )}
          {expense.litres !== null && (
            <Detail label="Litres">
              <span className="numeric">{expense.litres}</span>
            </Detail>
          )}
          {expense.note && <Detail label="Note">{expense.note}</Detail>}
          <Detail label="Entered">
            {formatDayShort(expense.created_at)}
            {expense.submitted_by_name ? ` by ${expense.submitted_by_name}` : ""}
          </Detail>
          <Detail label="Where it stands">{describeStatus(expense)}</Detail>
        </dl>

        {/*
          The reason comes with the decision or not at all -- `rejectExpense`
          requires it. Shown in its own panel rather than as another row,
          because it is the one thing on this screen that asks somebody to do
          something.
        */}
        {expense.status === "rejected" && expense.review_note && (
          <p className="flex-none rounded-[14px] border border-snag-line bg-snag px-3.5 py-3 text-[15px] font-medium text-snag-text">
            {expense.review_note}
          </p>
        )}

        {mine && <ReceiptReview expenseId={expense.id} />}

        {locked ? (
          <p className="flex-none text-[13px] text-muted">{locked}</p>
        ) : (
          <Link
            href={`/receipts/${expense.id}/edit`}
            className="flex h-12 flex-none items-center justify-center rounded-[10px] border-[1.5px] border-ink bg-surface text-base font-semibold"
          >
            Correct a mistake
          </Link>
        )}

        {canDelete && (
          <form
            action={deleteExpense.bind(null, expense.id)}
            className="flex flex-none justify-center"
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

function Detail({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex min-h-14 flex-col justify-center gap-0.5 py-2.5">
      <dt className="field-label">{label}</dt>
      <dd className="text-[15px] font-medium break-words">{children}</dd>
    </div>
  );
}
