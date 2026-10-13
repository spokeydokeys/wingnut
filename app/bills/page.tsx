import { NotBuiltYet } from "@/components/not-built-yet";
import { requireMember } from "@/lib/dal";

export const dynamic = "force-dynamic";

export default async function Bills() {
  await requireMember();

  return (
    <NotBuiltYet
      title="Bills"
      blurb="The ledger and invoices already exist in the database; the month-close and payment screens that read them are a later phase. The balance on Home comes from that ledger."
    />
  );
}
