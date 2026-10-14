import { BackHeader } from "@/components/back-header";
import { getInvoiceHistory, getPaymentDetails } from "@/lib/bills";
import { requireMember } from "@/lib/dal";
import { getBalance } from "@/lib/flights";
import { formatMoney } from "@/lib/format";

export const dynamic = "force-dynamic";

/**
 * How to pay (SPEC.md 4.6): "pilots pay by Interac e-Transfer outside the app.
 * The Pay button shows e-Transfer details and a payment reference."
 *
 * So this screen has no button. Money moves in a banking app, and an admin
 * records it when it lands -- deliberately, because a pilot-side "I've sent it"
 * would put a figure on the ledger that nothing has confirmed. SPEC.md 8.7
 * left that open; the owners chose admin-records-it.
 *
 * The reference is derived, not stored. 8.7 also leaves the format open, and a
 * made-up code in a column would be a decision pretending to have been made.
 * A name and an invoice number are what an admin matches a transfer against.
 */
export default async function Pay() {
  const member = await requireMember();

  const [balance, details, history] = await Promise.all([
    getBalance(member.id),
    getPaymentDetails(),
    getInvoiceHistory(member.id),
  ]);

  const outstanding = history.filter((h) => h.invoice.status === "issued");
  const reference =
    outstanding.length === 1
      ? `${member.full_name} · invoice ${outstanding[0].invoice.number}`
      : member.full_name;

  return (
    <>
      <BackHeader
        href="/bills"
        label="Bills"
        title="Pay by e-Transfer"
        subtitle="Send it from your own banking app. An admin records it against your ledger once it arrives."
      />

      <main className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 pt-3.5 pb-4">
        <div className="flex-none rounded-[14px] border border-ink bg-surface px-3.5 py-3">
          <div className="field-label">Amount</div>
          <div className="numeric text-[40px] leading-[1.15]">
            {formatMoney(Math.max(0, balance))}
          </div>
          <p className="text-[13px] text-muted">
            {balance > 0
              ? "Your balance in full. A part payment is fine too."
              : "Nothing is outstanding."}
          </p>
        </div>

        <dl className="flex-none divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
          <Detail label="Send to">
            {details?.recipient ?? "Not set up yet — ask an admin."}
          </Detail>
          <Detail label="Payable to">{details?.legalName ?? "—"}</Detail>
          <Detail label="Reference / message">{reference}</Detail>
        </dl>

        <p className="flex-none text-[13px] text-muted">
          Put the reference in the e-Transfer message so the payment can be
          matched to you. If your bank asks a security question, agree it with
          an admin first.
        </p>
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
