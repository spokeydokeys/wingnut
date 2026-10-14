import { BackHeader } from "@/components/back-header";
import { ReceiptForm } from "@/components/receipt-form";
import { requireMember } from "@/lib/dal";
import { getCategories } from "@/lib/expenses";
import { toDateInputValue } from "@/lib/time";

// The date it defaults to is today where the aeroplane is, which moves.
export const dynamic = "force-dynamic";

/**
 * Entering a receipt.
 *
 * The date defaults to today in the aircraft's zone rather than the browser's.
 * An owner filing a fuel receipt from a hotel in Toronto at nine in the
 * evening is still filing it against a Pacific day, and a receipt dated
 * tomorrow would fall in the wrong month at the turn of one.
 */
export default async function NewReceipt({
  searchParams,
}: PageProps<"/receipts/new">) {
  const member = await requireMember();
  const categories = await getCategories();

  // Set when the Confirm-flight screen sends a pilot here after asking whether
  // they bought fuel, so the receipt lands attached to the flight it was for.
  const { flight } = await searchParams;

  return (
    <>
      <BackHeader href="/receipts" label="Receipts" title="Add a receipt" />

      <main className="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 pt-3.5 pb-4">
        {categories.length === 0 ? (
          <p className="rounded-[14px] border border-line bg-surface px-3.5 py-3 text-[15px] text-muted">
            The chart of accounts has no expense categories yet, so there is
            nothing to code a receipt to.
          </p>
        ) : (
          <ReceiptForm
            categories={categories}
            defaultDate={toDateInputValue()}
            memberName={member.full_name}
            flightId={typeof flight === "string" ? flight : undefined}
          />
        )}
      </main>
    </>
  );
}
