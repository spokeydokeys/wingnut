"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireMember } from "@/lib/dal";
import { getAircraft } from "@/lib/flights";
import { KIND_CHOICES, type PlaceKind } from "@/lib/place-kind";
import { createClient } from "@/lib/supabase/server";

/**
 * Server Actions for places and the journey log.
 *
 * Each is a public POST endpoint, so each starts with requireMember(). Beyond
 * that they lean on RLS and on the triggers from the places migration:
 * `flight_update_own` means another pilot's flight simply matches no rows,
 * `place_insert_members` refuses to let anyone forge an imported place, and
 * `place_guard_in_use` is what actually stops a delete that would blank a
 * journey. None of those rules are restated here, because a restatement is a
 * second copy that can fall out of step.
 */

type Failed = { error: string };

const UUID = /^[0-9a-f-]{36}$/i;

/**
 * Anything unrecognised becomes 'other' rather than a refusal. The kind is a
 * label on a pill; a flight that cannot be filed because a select was tampered
 * with would be a worse outcome than a place filed as "Place".
 */
function readKind(raw: FormDataEntryValue | null): PlaceKind {
  const value = String(raw ?? "");
  return (KIND_CHOICES as string[]).includes(value) ? (value as PlaceKind) : "other";
}

/**
 * A coordinate typed by a human or dragged on a map, so it is input and gets
 * checked. Unlike a GPS fix -- which is dropped when it is nonsense, because a
 * flight with no fix is still a flight -- a bad coordinate here is refused: the
 * whole point of the field is to say where the place is.
 */
function readCoordinate(raw: FormDataEntryValue | null, max: number): number | null {
  const value = Number(String(raw ?? "").trim());
  if (!Number.isFinite(value) || value < -max || value > max) return null;
  return value;
}

/**
 * `start` or `end`, as the patch that names that end of the flight.
 *
 * Returns the whole object rather than a column name because the generated
 * row types reject a computed key -- and that is a feature: a typo in a column
 * name here would silently write nothing.
 */
function readWhich(
  raw: FormDataEntryValue | null,
  placeId: string,
): { origin_place_id: string } | { dest_place_id: string } | null {
  const which = String(raw ?? "");
  if (which === "start") return { origin_place_id: placeId };
  if (which === "end") return { dest_place_id: placeId };
  return null;
}

/**
 * Name one end of a flight.
 *
 * Setting the destination also clears the forgot-to-stop warning, but that
 * happens in `flight_set_journey`, not here -- the warning has to clear for
 * every writer, and this is only one of them.
 */
export async function setFlightPlace(
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | never> {
  await requireMember();

  const flightId = String(form.get("flight_id") ?? "");
  const placeId = String(form.get("place_id") ?? "");
  const patch = readWhich(form.get("which"), placeId);

  if (!UUID.test(flightId) || !patch) return { error: "That flight could not be read." };
  if (!UUID.test(placeId)) return { error: "Choose a place first." };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("flight")
    .update(patch)
    .eq("id", flightId)
    .select("id, status")
    .maybeSingle();

  if (error) return { error: error.message };
  if (!data) return { error: "That flight is not yours to edit." };

  revalidatePath("/", "layout");
  redirect(data.status === "draft" ? `/flight/${flightId}/confirm` : "/");
}

/**
 * Save a new place and, if a flight asked for it, name that flight's end with
 * it in the same step.
 *
 * The two halves are deliberately one action. The screen that creates a place
 * is almost always the one that needed it, and leaving the pilot on a list to
 * tap their own new dock is a step that exists only because the code was
 * written in two pieces.
 */
export async function createPlace(
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | never> {
  const member = await requireMember();

  const name = String(form.get("name") ?? "").trim();
  if (name === "") return { error: "Give the place a name." };

  const lat = readCoordinate(form.get("lat"), 90);
  const lon = readCoordinate(form.get("lon"), 180);
  if (lat === null || lon === null) {
    return { error: "That latitude and longitude could not be read." };
  }

  const aircraft = await getAircraft();
  if (!aircraft) return { error: "No aircraft has been set up yet." };

  const supabase = await createClient();
  const { data: place, error } = await supabase
    .from("place")
    .insert({
      company_id: aircraft.company_id,
      name,
      kind: readKind(form.get("kind")),
      // Not a choice on any screen. Everything a person types is a saved place;
      // 'ourairports' and the rest mean "came from that dataset", and a row
      // claiming to be imported would make a future import ambiguous.
      source: "saved",
      lat,
      lon,
      created_by: member.id,
    })
    .select("id")
    .single();

  if (error) return { error: error.message };

  const flightId = String(form.get("flight_id") ?? "");
  const patch = readWhich(form.get("which"), place.id);

  if (UUID.test(flightId) && patch) {
    const { error: linkError } = await supabase
      .from("flight")
      .update(patch)
      .eq("id", flightId);
    if (linkError) return { error: linkError.message };

    revalidatePath("/", "layout");
    redirect(`/flight/${flightId}/confirm`);
  }

  revalidatePath("/", "layout");
  redirect("/more/places");
}

/**
 * Rename a place.
 *
 * Renaming is the operation the manager is really for: a place on a flight
 * flown last year cannot be deleted, and "Dock" turning out to be "Tod Inlet
 * dock" should fix the journey log everywhere at once, which it does, because
 * journey_text is derived from the place rather than copied from it.
 */
export async function renamePlace(
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | never> {
  await requireMember();

  const id = String(form.get("place_id") ?? "");
  const name = String(form.get("name") ?? "").trim();
  if (!UUID.test(id)) return { error: "That place could not be read." };
  if (name === "") return { error: "Give the place a name." };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("place")
    .update({ name })
    .eq("id", id)
    .select("id")
    .maybeSingle();

  if (error) return { error: error.message };
  if (!data) return { error: "That place is not yours to rename." };

  // Every journey_text naming this place is now stale. They are derived rather
  // than stored per flight, so nothing has to be rewritten -- but the pages
  // showing them were rendered with the old name.
  revalidatePath("/", "layout");
  redirect("/more/places");
}

export async function deletePlace(
  _prev: Failed | null,
  form: FormData,
): Promise<Failed | never> {
  await requireMember();

  const id = String(form.get("place_id") ?? "");
  if (!UUID.test(id)) return { error: "That place could not be read." };

  const supabase = await createClient();
  const { error } = await supabase.from("place").delete().eq("id", id);

  // `place_guard_in_use` raises when a flight still names it, and its message
  // names the place and the count, which is more use than anything this file
  // could say.
  if (error) return { error: error.message };

  revalidatePath("/", "layout");
  redirect("/more/places");
}
