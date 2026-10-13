import { NotBuiltYet } from "@/components/not-built-yet";
import { requireMember } from "@/lib/dal";

export const dynamic = "force-dynamic";

export default async function Aircraft() {
  await requireMember();

  return (
    <NotBuiltYet
      title="Aircraft"
      blurb="Snags, maintenance items and tach readings live here. The tables behind them are the next phase."
    />
  );
}
