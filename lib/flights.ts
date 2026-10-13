import "server-only";

import { cache } from "react";

import { createClient } from "./supabase/server";
import type { Database } from "./database.types";

export type Flight = Database["public"]["Tables"]["flight"]["Row"];
export type Aircraft = Database["public"]["Tables"]["aircraft"]["Row"];
export type FlightFix = Database["public"]["Tables"]["flight_fix"]["Row"];

/**
 * Reads for the flight screens.
 *
 * Every query here goes through the session client, so RLS decides what comes
 * back and none of these functions re-check who is asking. `flight_select_members`
 * makes the flight log shared, which is the point: a co-owner should see that
 * the aeroplane is in the air. `flight_fix_own` does not, so the GPS fixes
 * below are only ever the caller's.
 */

/**
 * The aircraft, singular. One aeroplane is the whole premise of the app, so
 * rather than thread an aircraft id through every screen this picks the only
 * row. If a second aeroplane ever appears, this is the function that has to
 * learn about it, and the type error will say so.
 */
export const getAircraft = cache(async (): Promise<Aircraft | null> => {
  const supabase = await createClient();
  const { data } = await supabase
    .from("aircraft")
    .select("*")
    .order("created_at")
    .limit(1)
    .maybeSingle();
  return data ?? null;
});

/**
 * The flight with the clock running, whoever is flying it.
 *
 * `flight_one_open_per_aircraft` guarantees there is at most one, so this can
 * honestly return a single row rather than a list.
 */
export const getRunningFlight = cache(async (): Promise<Flight | null> => {
  const supabase = await createClient();
  const { data } = await supabase
    .from("flight_running")
    .select("*")
    .maybeSingle();
  return (data as Flight | null) ?? null;
});

export async function getFlight(id: string): Promise<Flight | null> {
  const supabase = await createClient();
  const { data } = await supabase.from("flight").select("*").eq("id", id).maybeSingle();
  return data ?? null;
}

/**
 * The caller's own GPS fixes for a flight, keyed by which end they belong to.
 *
 * Returns an empty record rather than throwing when there are none: starting a
 * flight indoors with location denied is a supported case, not an error.
 */
export async function getFlightFixes(
  flightId: string,
): Promise<Partial<Record<"start" | "end", FlightFix>>> {
  const supabase = await createClient();
  const { data } = await supabase.from("flight_fix").select("*").eq("flight_id", flightId);

  const fixes: Partial<Record<"start" | "end", FlightFix>> = {};
  for (const fix of data ?? []) fixes[fix.which] = fix;
  return fixes;
}

/** What the caller owes. Positive means they owe; see the ledger migration. */
export async function getBalance(memberId: string): Promise<number> {
  const supabase = await createClient();
  const { data } = await supabase.rpc("member_balance", { p_member_id: memberId });
  return Number(data ?? 0);
}

/** Everyone who could be named as the pilot, for the Confirm screen's picker. */
export async function getPilotChoices(): Promise<{ id: string; full_name: string }[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("member")
    .select("id, full_name")
    .eq("is_active", true)
    .order("full_name");
  return data ?? [];
}
