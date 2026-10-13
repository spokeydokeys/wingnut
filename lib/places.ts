import "server-only";

import { createClient } from "./supabase/server";
import type { Database } from "./database.types";

export type Place = Database["public"]["Tables"]["place"]["Row"];

/** A place with how far away it is. What `places_near` returns. */
export type NearbyPlace =
  Database["public"]["Functions"]["places_near"]["Returns"][number];

/** A place with how often this pilot has used it. What `places_used` returns. */
export type UsedPlace =
  Database["public"]["Functions"]["places_used"]["Returns"][number];

/**
 * Reads for the Set place screen and the saved-places manager.
 *
 * Distances and usage counts are computed in the database rather than here.
 * That is not ceremony: `places_near` is also what the auto-match uses through
 * `place_match`, and a second distance formula in TypeScript would eventually
 * disagree with the one that decides whether a landing was "near" anything.
 */

/** Nearest first, with distances, for "Near your GPS fix". */
export async function getPlacesNear(
  lat: number,
  lon: number,
  limit = 6,
): Promise<NearbyPlace[]> {
  const supabase = await createClient();
  const { data } = await supabase.rpc("places_near", {
    p_lat: lat,
    p_lon: lon,
    p_limit: limit,
  });
  return data ?? [];
}

/** The caller's own places, most-used first. The wireframe's "Recent". */
export async function getPlacesUsed(limit = 6): Promise<UsedPlace[]> {
  const supabase = await createClient();
  const { data } = await supabase.rpc("places_used", { p_limit: limit });
  return data ?? [];
}

/**
 * Every place, for search and for the manager.
 *
 * There is no server-side search endpoint because the list is small by design
 * (saved places only, one aeroplane): filtering a few dozen names in the
 * browser is instant and keeps the screen working with no connection, which a
 * dock in a bay rather needs.
 */
export async function getPlaces(): Promise<Place[]> {
  const supabase = await createClient();
  const { data } = await supabase.from("place").select("*").order("name");
  return data ?? [];
}

/**
 * "Origin → Destination", or null while either end is unknown.
 *
 * An RPC rather than two names joined with an arrow in TypeScript. The same
 * sentence is written into `flight.journey_text` by a trigger, and a second
 * copy of the rule here would eventually disagree with the stored one -- which
 * would show up as a Confirm screen claiming the pilot had edited a line they
 * had not touched.
 */
export async function getJourneyText(
  originId: string | null,
  destId: string | null,
): Promise<string | null> {
  if (!originId || !destId) return null;

  const supabase = await createClient();
  const { data } = await supabase.rpc("journey_text_for", {
    p_origin_id: originId,
    p_dest_id: destId,
  });
  return data ?? null;
}

export async function getPlace(id: string): Promise<Place | null> {
  const supabase = await createClient();
  const { data } = await supabase.from("place").select("*").eq("id", id).maybeSingle();
  return data ?? null;
}

/**
 * How many flights name each place, so the manager can say what a rename or a
 * delete would touch. Counts every pilot's flights, unlike the ranking
 * functions: this one is about whether the row is safe to remove.
 */
export async function getPlaceUseCounts(): Promise<Map<string, number>> {
  const supabase = await createClient();
  const { data } = await supabase.from("flight").select("origin_place_id, dest_place_id");

  const counts = new Map<string, number>();
  for (const flight of data ?? []) {
    // Deduplicated per flight, because a circuit names the same place at both
    // ends and "used on 2 flights" would be one flight counted twice.
    const ends = new Set([flight.origin_place_id, flight.dest_place_id]);
    for (const id of ends) {
      if (id) counts.set(id, (counts.get(id) ?? 0) + 1);
    }
  }
  return counts;
}
