import { notFound, redirect } from "next/navigation";

import { updateExpense } from "@/app/receipts/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { VendorField } from "@/components/vendor-field";
import { requireMember } from "@/lib/dal";
import {
  getCategories,
  getExpense,
  getVendorSuggestions,
  isMonthClosed,
  lockReason,
} from "@/lib/expenses";

export const dynamic = "force-dynamic";

/**
 * Correcting a receipt.
 *
 * The same fields as entry minus two. The payer is absent because changing who
 * paid changes which transaction this is -- a company-card purchase re-labelled
 * as out of pocket would owe somebody money that was never spent -- and the
 * photo is absent because it is replaced on the detail screen, where it is the
 * thing you are looking at.
 *
 * A locked receipt is sent back rather than shown read-only. There is nothing
 * to do here once it is agreed, and the detail screen already says why in
 * words.
 */
export default async function EditReceipt({
  params,
}: PageProps<"/receipts/[id]/edit">) {
  const { id } = await params;
  const member = await requireMember();

  const expense = await getExpense(id);
  if (!expense) notFound();

  const [categories, vendors, monthClosed] = await Promise.all([
    getCategories(),
    getVendorSuggestions(member.id),
    isMonthClosed(expense.company_id, expense.spent_on),
  ]);

  if (lockReason(expense, monthClosed)) redirect(`/receipts/${expense.id}`);

  return (
    <>
      <BackHeader
        href={`/receipts/${expense.id}`}
        label="Receipt"
        title="Correct a receipt"
        subtitle={expense.vendor}
      />

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5 pb-4">
        <ActionForm action={updateExpense} submitLabel="Save the receipt">
          <input type="hidden" name="id" value={expense.id} />

          <VendorField vendors={vendors} defaultValue={expense.vendor} />

          <div className="flex gap-3">
            <label className="flex flex-1 flex-col gap-1.5">
              <span className="field-label">Date</span>
              <input
                type="date"
                name="spent_on"
                required
                defaultValue={expense.spent_on}
                className={FIELD}
              />
            </label>

            <label className="flex flex-1 flex-col gap-1.5">
              <span className="field-label">Total paid</span>
              <input
                name="total_amount"
                inputMode="decimal"
                required
                defaultValue={expense.total_amount}
                className={`${FIELD} numeric`}
              />
            </label>
          </div>

          <label className="flex flex-col gap-1.5">
            <span className="field-label">What it was for</span>
            <select
              name="gl_account_code"
              required
              defaultValue={expense.gl_account_code}
              className={FIELD}
            >
              {categories.map((category) => (
                <option key={category.code} value={category.code}>
                  {category.name}
                </option>
              ))}
            </select>
          </label>

          <label className="flex flex-col gap-1.5">
            <span className="field-label">Litres (fuel only)</span>
            <input
              name="litres"
              inputMode="decimal"
              defaultValue={expense.litres ?? ""}
              className={`${FIELD} numeric`}
            />
          </label>

          <label className="flex flex-col gap-1.5">
            <span className="field-label">Note</span>
            <textarea
              name="note"
              rows={2}
              defaultValue={expense.note ?? ""}
              className={`${FIELD} h-auto py-2.5`}
            />
          </label>

          {/*
            Open rather than folded when there is something in it. On entry
            these are hidden because the company is not GST registered and
            filling them in is work for nothing; here, a figure that was
            captured must not be quietly dropped by a correction.
          */}
          <details
            open={expense.gst_amount > 0 || expense.vendor_gst_number !== null}
            className="rounded-[10px] border border-field px-3 py-2.5"
          >
            <summary className="field-label cursor-pointer">
              Tax on the receipt
            </summary>
            <div className="mt-2.5 flex flex-col gap-3">
              <label className="flex flex-col gap-1.5">
                <span className="field-label">GST included in the total</span>
                <input
                  name="gst_amount"
                  inputMode="decimal"
                  defaultValue={expense.gst_amount || ""}
                  placeholder="0.00"
                  className={`${FIELD} numeric`}
                />
              </label>
              <label className="flex flex-col gap-1.5">
                <span className="field-label">Their GST number</span>
                <input
                  name="vendor_gst_number"
                  autoComplete="off"
                  defaultValue={expense.vendor_gst_number ?? ""}
                  className={FIELD}
                />
              </label>
            </div>
          </details>
        </ActionForm>
      </main>
    </>
  );
}
