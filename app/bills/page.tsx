import Link from "next/link";

import { Chip } from "@/components/chip";
import { TabBar } from "@/components/tab-bar";
import {
  getInvoiceHistory,
  getLastPayment,
  getLooseEntries,
  getMonthCharges,
  type Charge,
} from "@/lib/bills";
import { requireMember } from "@/lib/dal";
import { getAircraft, getBalance } from "@/lib/flights";
import { formatHours, formatMoney } from "@/lib/format";
import {
  currentMonthStart,
  formatDate,
  formatMonthEnd,
  formatMonthLong,
  toAircraftDate,
} from "@/lib/time";

// A balance and a month that is still being flown. Nothing is cacheable.
export const dynamic = "force-dynamic";

/** Every figure on this screen is amount + GST, because the balance is too. */
const gross = (line: { amount: number; gst_amount: number }) =>
  Number(line.amount) + Number(line.gst_amount);

/**
 * The Bills tab: what you owe, what this month is adding up to, and what has
 * happened to the account.
 *
 * SPEC.md 3 ranks paying second, so the balance and the Pay button are the top
 * card and nothing above them competes. The month in progress is labelled a
 * draft and says when it closes, because SPEC.md 4.6 wants the pilot to know
 * that flights are still editable until then.
 *
 * Nothing here adds up money the database has not already added up, with one
 * exception that is deliberate: the "less payments" caption is derived FROM the
 * balance rather than alongside it, so it cannot contradict the big number
 * above it. See `applied` below.
 */
export default async function Bills() {
  const member = await requireMember();
  const aircraft = await getAircraft();

  const month = currentMonthStart();
  const [balance, lastPayment, charges, history, loose] = await Promise.all([
    getBalance(member.id),
    getLastPayment(member.id),
    aircraft ? getMonthCharges(aircraft.id, member.id, month) : [],
    getInvoiceHistory(member.id),
    getLooseEntries(member.id),
  ]);

  // One row per rate component is what the ledger stores, because the GL wants
  // fuel, reserve and operating in different accounts. SPEC.md 4.8 says pilots
  // see one rate, so they are summed back into a single line here -- using the
  // period_hours each line carries rather than adding up six identical
  // quantities, which would multiply the flying by six.
  const flightLines = charges.filter((c) => c.kind === "flight_charge");
  const otherLines = charges.filter((c) => c.kind !== "flight_charge");
  const flightHours = Number(flightLines[0]?.period_hours ?? 0);
  const flightTotal = flightLines.reduce((t, c) => t + gross(c), 0);
  const monthTotal = charges.reduce((t, c) => t + gross(c), 0);
  const monthGst = charges.reduce((t, c) => t + Number(c.gst_amount), 0);

  // What the member has been billed and not yet settled. The difference
  // between this and the balance is what has been paid or credited against it.
  const invoiced = history
    .filter((h) => h.invoice.status === "issued")
    .reduce((t, h) => t + h.total, 0);
  const applied = invoiced - balance;

  const rows = [
    ...history.map((h) => ({
      key: h.invoice.id,
      href: `/bills/${h.invoice.id}`,
      label: `${formatMonthLong(h.invoice.period_month)} invoice`,
      caption:
        h.invoice.status === "void"
          ? "Void"
          : h.invoice.status === "settled"
            ? "Paid"
            : `Due · no. ${h.invoice.number}`,
      // Dated when it was issued, not by the month it covers: that is when it
      // reached the account, and it is what keeps a late close in the right
      // place in the list relative to the payments around it.
      on: h.invoice.issued_at
        ? toAircraftDate(h.invoice.issued_at)
        : h.invoice.period_month,
      amount: h.invoice.status === "void" ? 0 : h.total,
    })),
    ...loose.map((e) => ({
      key: e.id,
      href: null,
      label:
        e.kind === "payment"
          ? "Payment received"
          : e.kind === "payout"
            ? "Paid out to you"
            : e.description,
      caption: e.kind === "adjustment" ? "Adjustment" : null,
      on: e.entry_date,
      amount: gross(e),
    })),
  ].sort((a, b) => b.on.localeCompare(a.on));

  return (
    <>
      <header className="flex flex-none items-center justify-between px-4 pt-5 pb-1">
        <h1 className="text-[26px] font-semibold">Bills</h1>
        {member.role === "admin" && (
          <Link
            href="/bills/close"
            className="flex min-h-11 items-center text-sm font-semibold text-accent"
          >
            Close a month
          </Link>
        )}
      </header>

      <main className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 pt-2.5 pb-4">
        <section className="flex-none rounded-[14px] border border-line bg-surface p-3.5">
          <div className="field-label">{balance > 0 ? "You owe" : "Your balance"}</div>
          <div className="numeric text-[40px] leading-[1.15]">
            {formatMoney(Math.abs(balance))}
          </div>
          <p className="text-[13px] text-muted">
            {balance === 0
              ? "Nothing outstanding."
              : balance < 0
                ? "In credit. It comes off the next invoice."
                : invoiced === 0
                  ? "Raised between invoices."
                  : `Invoiced ${formatMoney(invoiced)}${
                      applied > 0
                        ? `, less ${formatMoney(applied)} paid or credited`
                        : applied < 0
                          ? `, plus ${formatMoney(-applied)} since`
                          : ""
                    }`}
          </p>

          {balance > 0 && (
            <>
              <Link
                href="/bills/pay"
                className="mt-3 flex h-14 items-center justify-center rounded-[14px] bg-accent text-lg font-semibold text-white"
              >
                Pay {formatMoney(balance)}
              </Link>
              <p className="mt-2 text-center text-[13px] text-muted">
                Shows e-Transfer details and your payment reference
              </p>
            </>
          )}

          {lastPayment && (
            <div className="mt-2.5 flex items-center justify-between border-t border-hairline pt-2.5 text-sm">
              <span className="text-muted">Last payment</span>
              <span className="numeric">
                {formatMoney(Math.abs(gross(lastPayment)))} ·{" "}
                {formatDate(lastPayment.entry_date)}
              </span>
            </div>
          )}
        </section>

        <section className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3">
          <div className="mb-1 flex items-center justify-between">
            <h2 className="font-semibold">{formatMonthLong(month)} so far</h2>
            <Chip tone="neutral">Draft</Chip>
          </div>

          {charges.length === 0 ? (
            <p className="py-1 text-[15px] text-muted">
              Nothing yet this month.
            </p>
          ) : (
            <>
              {flightLines.length > 0 && (
                <Row
                  label={`Flight time · ${formatHours(flightHours)}`}
                  amount={flightTotal}
                />
              )}
              {otherLines.map((line: Charge) => (
                <Row
                  key={line.description}
                  label={line.description}
                  amount={gross(line)}
                />
              ))}
              {monthGst > 0 && <Row label="GST" amount={monthGst} />}

              <div className="mt-1 flex min-h-10 items-center justify-between border-t border-ink text-base font-semibold">
                <span>Total to date</span>
                <span className="numeric">{formatMoney(monthTotal)}</span>
              </div>
            </>
          )}

          <p className="mt-0.5 text-[13px] text-muted">
            Closes {formatMonthEnd(month)}. Flights stay editable until then.
          </p>
        </section>

        <section className="flex-none rounded-[14px] border border-line bg-surface px-3.5 pt-3 pb-1">
          <h2 className="mb-0.5 font-semibold">History</h2>

          {rows.length === 0 ? (
            <p className="pb-2 text-[15px] text-muted">
              Nothing has been invoiced or paid yet.
            </p>
          ) : (
            rows.map((row) => {
              const body = (
                <>
                  <div>
                    <div className="text-[15px]">{row.label}</div>
                    <div className="text-[13px] text-muted">
                      {formatDate(row.on)}
                      {row.caption && ` · ${row.caption}`}
                    </div>
                  </div>
                  <span
                    className={`numeric text-[15px] ${row.amount < 0 ? "text-ok" : ""}`}
                  >
                    {formatMoney(row.amount)}
                  </span>
                </>
              );

              return row.href ? (
                <Link
                  key={row.key}
                  href={row.href}
                  className="flex min-h-14 items-center justify-between border-t border-hairline"
                >
                  {body}
                </Link>
              ) : (
                <div
                  key={row.key}
                  className="flex min-h-14 items-center justify-between border-t border-hairline"
                >
                  {body}
                </div>
              );
            })
          )}
        </section>
      </main>

      <TabBar />
    </>
  );
}

/** One line of the draft: what it is, and what it comes to. */
function Row({ label, amount }: { label: string; amount: number }) {
  return (
    <div className="flex min-h-9 items-center justify-between text-[15px]">
      <span>{label}</span>
      <span className={`numeric ${amount < 0 ? "text-ok" : ""}`}>
        {formatMoney(amount)}
      </span>
    </div>
  );
}
