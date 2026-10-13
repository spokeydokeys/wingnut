import "server-only";

import { cache } from "react";

import { createClient } from "./supabase/server";
import type { Database } from "./database.types";

export type Snag = Database["public"]["Tables"]["snag"]["Row"] & {
  reporter: { full_name: string } | null;
};
export type MaintenanceStatus =
  Database["public"]["Views"]["maintenance_status"]["Row"];
export type TachReading = Database["public"]["Tables"]["tach_reading"]["Row"];

/**
 * Reads for the Aircraft tab.
 *
 * As with lib/flights.ts, every query goes through the session client and RLS
 * decides what comes back. Snags, readings and maintenance items are all
 * readable by any active member, so nothing here filters by caller -- the
 * aeroplane's condition is shared knowledge and that is the point of the tab.
 */

/**
 * Open and watch snags, newest first. Cleared ones are deliberately absent:
 * SPEC.md 4.3 shows this list as the current state of the aeroplane, and a
 * brake fixed in March is not that. The history is still in the table.
 */
export async function getLiveSnags(aircraftId: string): Promise<Snag[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("snag")
    .select("*, reporter:member!snag_reported_by_fkey(full_name)")
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
    .select("*, reporter:member!snag_reported_by_fkey(full_name)")
    .eq("id", id)
    .maybeSingle();
  return (data as Snag | null) ?? null;
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
