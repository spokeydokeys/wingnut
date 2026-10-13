import { notFound } from "next/navigation";

import { BackHeader } from "@/components/back-header";
import { Chip } from "@/components/chip";
import { getInvoice, getInvoiceHours, getInvoiceLines } from "@/lib/bills";
import { requireMember } from "@/lib/dal";
import { formatHours, formatMoney } from "@/lib/format";
import { formatDate, formatMonthLong, toAircraftDate } from "@/lib/time";

export const dynamic = "force-dynamic";

const gross = (line: { amount: number; gst_amount: number }) =>
  Number(line.amount) + Number(line.gst_amount);

/**
 * One issued invoice, as it was sent.
 *
 * Read straight off the ledger lines locked to it rather than re-priced, which
 * is the whole point of SPEC.md 4.6's "a sent invoice never changes silently":
 * a rate rise next month must not change what this screen says about last
 * month. No RLS test is written here -- `invoice_select_own` means someone
 * else's id simply does not exist as far as this query is concerned.
 */
export default async function InvoiceDetail({ params }: PageProps<"/bills/[id]">) {
  const { id } = await params;
  await requireMember();

  const invoice = await getInvoice(id);
  if (!invoice) notFound();

  const [lines, hours] = await Promise.all([
    getInvoiceLines(invoice.id),
    getInvoiceHours(invoice.id),
  ]);

  // Collapsed the same way the Bills screen collapses a draft: one stored line
  // per rate component, one row for the pilot. The hours come from the flights
  // the invoice locked, because every component line repeats the same quantity.
  const flightLines = lines.filter((l) => l.kind === "flight_charge");
  const otherLines = lines.filter((l) => l.kind !== "flight_charge");
  const flightTotal = flightLines.reduce((t, l) => t + gross(l), 0);
  // The all-in wet rate: the components summed, which is the one rate SPEC.md
  // 4.8 says pilots see, and the figure 4.6's "12.4 hr x rate" asks for.
  const flightRate = flightLines.reduce((t, l) => t + Number(l.unit_rate ?? 0), 0);
  const gst = lines.reduce((t, l) => t + Number(l.gst_amount), 0);
  const total = lines.reduce((t, l) => t + gross(l), 0);

  return (
    <>
      <BackHeader
        href="/bills"
        label="Bills"
        title={`${formatMonthLong(invoice.period_month)} invoice`}
        subtitle={
          invoice.issued_at
            ? `No. ${invoice.number} · issued ${formatDate(toAircraftDate(invoice.issued_at))}`
            : "Not issued"
        }
      />

      <main className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 pt-3.5 pb-4">
        <div className="flex flex-none items-center justify-between">
          <div>
            <div className="field-label">Total</div>
            <div className="numeric text-[32px] leading-tight">
              {formatMoney(total)}
            </div>
          </div>
          <Chip tone={invoice.status === "issued" ? "caution" : "neutral"}>
            {invoice.status === "issued"
              ? "Due"
              : invoice.status === "settled"
                ? "Paid"
                : invoice.status}
          </Chip>
        </div>

        <div className="flex-none divide-y divide-hairline rounded-[14px] border border-line bg-surface px-3.5">
          {flightLines.length > 0 && (
            <Line
              label="Flight time"
              caption={`${formatHours(hours)} × ${formatMoney(flightRate)}`}
              amount={flightTotal}
            />
          )}
          {/* No caption: a fixed cost's description already names the share. */}
          {otherLines.map((line) => (
            <Line
              key={line.id}
              label={line.description}
              caption={null}
              amount={gross(line)}
            />
          ))}
          {gst > 0 && <Line label="GST" caption={null} amount={gst} />}
        </div>

        {invoice.settled_at && (
          <p className="flex-none text-[13px] text-muted">
            Settled {formatDate(toAircraftDate(invoice.settled_at))}.
          </p>
        )}

        <p className="flex-none text-[13px] text-muted">
          The flights on this invoice are locked. A correction after it was sent
          becomes an adjustment on the next bill, so this stays a record of what
          was sent.
        </p>
      </main>
    </>
  );
}

function Line({
  label,
  caption,
  amount,
}: {
  label: string;
  caption: string | null;
  amount: number;
}) {
  return (
    <div className="flex min-h-14 items-center justify-between gap-3 py-2.5">
      <div>
        <div className="text-[15px]">{label}</div>
        {caption && <div className="text-[13px] text-muted">{caption}</div>}
      </div>
      <span className={`numeric text-[15px] ${amount < 0 ? "text-ok" : ""}`}>
        {formatMoney(amount)}
      </span>
    </div>
  );
}
