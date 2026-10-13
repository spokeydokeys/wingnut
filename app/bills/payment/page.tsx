import { recordPayment } from "@/app/bills/actions";
import { ActionForm } from "@/components/action-form";
import { BackHeader } from "@/components/back-header";
import { FIELD } from "@/components/field";
import { getRoster } from "@/lib/bills";
import { requireAdmin } from "@/lib/dal";
import { formatMoney } from "@/lib/format";
import { toDateInputValue } from "@/lib/time";

export const dynamic = "force-dynamic";

/**
 * Record an e-Transfer that has landed (SPEC.md 4.6: "An admin records the
 * payment against the ledger").
 *
 * Both owners are admins here, so the owners' rule is four eyes: another admin
 * records it whenever another admin exists. That is enforced by
 * `guard_payment_four_eyes`; what this screen does is leave the caller out of
 * the picker, so the honest case never meets the refusal.
 *
 * When there is only one admin -- the first weeks, or after a departure -- the
 * guard stands down and their own name is back in the list. A rule that locked
 * the only admin out of recording their own payment would just mean the ledger
 * stopped being true.
 */
export default async function RecordPayment() {
  const admin = await requireAdmin();
  const roster = await getRoster();

  const anotherAdmin = roster.some((m) => m.role === "admin" && m.id !== admin.id);
  const subjects = anotherAdmin ? roster.filter((m) => m.id !== admin.id) : roster;

  return (
    <>
      <BackHeader
        href="/bills/close"
        label="Close a month"
        title="Record a payment"
        subtitle="What arrived, from whom, on the day the bank says."
      />

      <main className="flex min-h-0 flex-1 flex-col px-4 pt-3.5 pb-4">
        <ActionForm action={recordPayment} submitLabel="Record payment">
          <div>
            <label htmlFor="member_id" className="field-label mb-1.5 block">
              From
            </label>
            <select id="member_id" name="member_id" required className={FIELD}>
              {subjects.map((m) => (
                <option key={m.id} value={m.id}>
                  {m.full_name} — owes {formatMoney(m.balance)}
                </option>
              ))}
            </select>
            {anotherAdmin && (
              <p className="mt-1.5 text-[13px] text-muted">
                Your own name is not here: a payment to you is recorded by the
                other admin.
              </p>
            )}
          </div>

          <div>
            <label htmlFor="amount" className="field-label mb-1.5 block">
              Amount received
            </label>
            <input
              id="amount"
              name="amount"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0.01"
              required
              autoFocus
              placeholder="800.00"
              className={`${FIELD} numeric`}
            />
          </div>

          <div>
            <label htmlFor="paid_on" className="field-label mb-1.5 block">
              Received on
            </label>
            <input
              id="paid_on"
              name="paid_on"
              type="date"
              required
              defaultValue={toDateInputValue()}
              className={`${FIELD} numeric`}
            />
          </div>

          <div>
            <label htmlFor="note" className="field-label mb-1.5 block">
              Note (optional)
            </label>
            <input
              id="note"
              name="note"
              type="text"
              placeholder="e-Transfer ref 4821"
              className={FIELD}
            />
          </div>
        </ActionForm>
      </main>
    </>
  );
}
