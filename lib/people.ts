import "server-only";

import { createClient } from "./supabase/server";
import type { Member } from "./dal";

/**
 * The roster, as an admin manages it.
 *
 * Inactive people are included rather than filtered out. They are the reason
 * the screen exists in the first place -- somebody who has sold their share is
 * still on every invoice and every flight behind them, and a list that hides
 * them is a list that makes an admin wonder whether the row was deleted.
 *
 * Active first, then by name, so the people who fly the aeroplane are the ones
 * at the top.
 */
export async function getPeople(): Promise<Member[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("member")
    .select("*")
    .order("is_active", { ascending: false })
    .order("full_name");

  return data ?? [];
}
