import "server-only";

import { cache } from "react";

import { createClient } from "./supabase/server";
import type { Database } from "./database.types";

export type SnagRow = Database["public"]["Tables"]["snag"]["Row"];
export type Snag = SnagRow & {
  reporter: { full_name: string } | null;
  /** The maintenance item this snag is waiting on, when it is waiting on one. */
  recheck_item: { id: string; name: string } | null;
};
export type MaintenanceStatus =
  Database["public"]["Views"]["maintenance_status"]["Row"];
export type TachReading = Database["public"]["Tables"]["tach_reading"]["Row"];
export type AircraftNote = Database["public"]["Tables"]["aircraft_note"]["Row"] & {
  author: { full_name: string } | null;
};

/**
 * Reads for the Aircraft tab.
 *
 * As with lib/flights.ts, every query goes through the session client and RLS
 * decides what comes back. Snags, readings and maintenance items are all
 * readable by any active member, so nothing here filters by caller -- the
 * aeroplane's condition is shared knowledge and that is the point of the tab.
 */

/**
 * The re-check item is named by both FKs that reach maintenance_item -- the
 * table and the status view share one -- so the embed says which relation it
 * means as well as which key.
 */
const SNAG_SELECT =
  "*, reporter:member!snag_reported_by_fkey(full_name)," +
  " recheck_item:maintenance_item!snag_recheck_item_id_fkey(id, name)";

/**
 * Open and watch snags, newest first. Cleared ones are deliberately absent:
 * SPEC.md 4.3 shows this list as the current state of the aeroplane, and a
 * brake fixed in March is not that. The history is still in the table.
 */
export async function getLiveSnags(aircraftId: string): Promise<Snag[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("snag")
    .select(SNAG_SELECT)
    .eq("aircraft_id", aircraftId)
    .neq("status", "cleared")
    // Grounding snags first: one of those is the only thing on this screen
    // that means the aeroplane does not fly today.
    .order("grounding", { ascending: false })
    .order("reported_at", { ascending: false });
  return (data as Snag[] | null) ?? [];
}

export async function getSnag(id: string): Promise<Snag | null> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("snag")
    .select(SNAG_SELECT)
    .eq("id", id)
    .maybeSingle();
  return (data as Snag | null) ?? null;
}

/**
 * The live snags waiting on one maintenance item, for the prompt on its
 * mark-done screen. This is the point of the link: it catches the person who
 * has the cowling off, not the one reading the app at the kitchen table.
 */
export async function getSnagsWaitingOn(itemId: string): Promise<SnagRow[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("snag")
    .select("*")
    .eq("recheck_item_id", itemId)
    .neq("status", "cleared")
    .order("grounding", { ascending: false })
    .order("reported_at", { ascending: false });
  return data ?? [];
}

/**
 * Every active maintenance item with its derived status. The arithmetic -- hours
 * used, days left, the fraction for the bar, the state word -- is all done by
 * `public.maintenance_status`, so this is a plain read.
 */
export async function getMaintenance(
  aircraftId: string,
): Promise<MaintenanceStatus[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("maintenance_status")
    .select("*")
    .eq("aircraft_id", aircraftId)
    .order("sort_order");
  return data ?? [];
}

/**
 * Just the names, for the "re-check at the next ..." dropdown on a snag. The
 * status view is not used here because none of its arithmetic is wanted: this
 * is a list of jobs that recur, not a report on how overdue they are.
 */
export async function getMaintenanceChoices(
  aircraftId: string,
): Promise<{ id: string; name: string }[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("maintenance_item")
    .select("id, name")
    .eq("aircraft_id", aircraftId)
    .eq("is_active", true)
    .order("sort_order");
  return data ?? [];
}

export async function getMaintenanceItem(
  id: string,
): Promise<MaintenanceStatus | null> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("maintenance_status")
    .select("*")
    .eq("id", id)
    .maybeSingle();
  return data ?? null;
}

/**
 * The running log: oil added, tyres pumped, the things nobody has to act on.
 *
 * Newest first. `limit` is how many to show, not a ceiling on how many are
 * kept: the Aircraft tab asks for a handful and says how many there are in
 * total, and /aircraft/log asks for the lot. A cap with nothing to say it was
 * applied would be the worst of the three, because the log's whole job is to
 * be a complete record and a silently truncated one is not.
 */
export async function getAircraftNotes(
  aircraftId: string,
  limit?: number,
): Promise<AircraftNote[]> {
  const supabase = await createClient();
  let query = supabase
    .from("aircraft_note")
    .select("*, author:member(full_name)")
    .eq("aircraft_id", aircraftId)
    // created_at breaks the tie, so two notes written about the same day stay
    // in the order they were written.
    .order("noted_on", { ascending: false })
    .order("created_at", { ascending: false });
  if (limit !== undefined) query = query.limit(limit);

  const { data } = await query;
  return (data as AircraftNote[] | null) ?? [];
}

/**
 * How many notes there are in total, for the "Log · 38 notes" header.
 *
 * `head: true` sends no rows back -- the count comes from the Content-Range
 * header -- so showing the number costs nothing on a tab that only renders
 * five of them.
 */
export async function countAircraftNotes(aircraftId: string): Promise<number> {
  const supabase = await createClient();
  const { count } = await supabase
    .from("aircraft_note")
    .select("id", { count: "exact", head: true })
    .eq("aircraft_id", aircraftId);
  return count ?? 0;
}

/**
 * The most recent real reading, for the "estimated since" caption and as the
 * default on the log-a-reading form.
 */
export const getLatestTachReading = cache(
  async (aircraftId: string): Promise<TachReading | null> => {
    const supabase = await createClient();
    const { data } = await supabase
      .from("tach_reading")
      .select("*")
      .eq("aircraft_id", aircraftId)
      .order("read_at", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    return data ?? null;
  },
);

/**
 * The running tach estimate: the last reading plus the estimated tach of every
 * flight since. Null when no reading has ever been logged, which the screens
 * report as unknown rather than guessing from nothing.
 */
export const getTachEstimate = cache(
  async (aircraftId: string): Promise<number | null> => {
    const supabase = await createClient();
    const { data } = await supabase.rpc("aircraft_tach_estimate", {
      p_aircraft_id: aircraftId,
    });
    return data === null ? null : Number(data);
  },
);
