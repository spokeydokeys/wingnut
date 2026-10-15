import "server-only";

import { createClient } from "./supabase/server";

export type Holding = {
  member_id: string;
  full_name: string;
  shares: number;
};

export type OwnershipPeriod = {
  id: string;
  effective_from: string;
  note: string | null;
  holdings: Holding[];
  total: number;
};

/**
 * The ownership history, newest first.
 *
 * Every period is kept and shown, not just the one in force, because that is
 * the whole point of the table: a month closed in March was billed at March's
 * split, and an admin looking at that invoice needs to be able to see the split
 * it was billed at rather than today's.
 *
 * Holdings come back with the member's name attached and a zero-share holder
 * left in. Nought shares is not an absence -- it is the record of somebody
 * having exited as of that date, and dropping the row would make a period where
 * an owner left look identical to one where they were never there.
 */
export async function getOwnershipPeriods(
  aircraftId: string,
): Promise<OwnershipPeriod[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("ownership_period")
    .select("id, effective_from, note, ownership_share(member_id, shares, member(full_name))")
    .eq("aircraft_id", aircraftId)
    .order("effective_from", { ascending: false });

  return (data ?? []).map((period) => {
    const holdings = period.ownership_share
      .map((share) => ({
        member_id: share.member_id,
        full_name: share.member?.full_name ?? "Somebody who has left",
        shares: share.shares,
      }))
      // Biggest holding first, then by name, so the list reads in the order
      // somebody would say it out loud.
      .sort((a, b) => b.shares - a.shares || a.full_name.localeCompare(b.full_name));

    return {
      id: period.id,
      effective_from: period.effective_from,
      note: period.note,
      holdings,
      total: holdings.reduce((sum, h) => sum + h.shares, 0),
    };
  });
}

/**
 * How many shares the company is divided into.
 *
 * Read from the company rather than hard-coded at 1200, even though it is 1200
 * and is set once at incorporation: the number a form validates against and the
 * number the billing functions divide by have to be the same number, and the
 * database is where that one lives.
 */
export async function getTotalShares(): Promise<number | null> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("company")
    .select("total_shares")
    .limit(1)
    .maybeSingle();

  return data?.total_shares ?? null;
}
