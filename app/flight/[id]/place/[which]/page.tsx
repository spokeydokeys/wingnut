import { notFound, redirect } from "next/navigation";

import { BackHeader } from "@/components/back-header";
import { PlacePicker } from "@/components/place-picker";
import { requireMember } from "@/lib/dal";
import { getFlight, getFlightFixes } from "@/lib/flights";
import { getPlaces, getPlacesNear, getPlacesUsed } from "@/lib/places";

export const dynamic = "force-dynamic";

/**
 * Name one end of a flight. SPEC.md 4.6, from the Place wireframe.
 *
 * Every candidate is fetched here, on the server, before the picker mounts --
 * the whole saved list, the pilot's most-used places, and whatever is near
 * their fix. That is what lets the screen work with no network: the map is the
 * only part that needs one, and it is added by the client when there is one.
 */
export default async function SetFlightPlace({
  params,
}: PageProps<"/flight/[id]/place/[which]">) {
  const { id, which } = await params;
  if (which !== "start" && which !== "end") notFound();

  await requireMember();

  const flight = await getFlight(id);
  if (!flight) notFound();
  // `guard_flight_locked` would refuse the update anyway. Refusing to draw the
  // screen is kinder than letting someone pick a place and then be told no.
  if (flight.status === "billed") redirect("/");

  const fixes = await getFlightFixes(flight.id);
  const fix = fixes[which];
  const accuracy = which === "end" ? flight.end_fix_accuracy_m : flight.start_fix_accuracy_m;
  const point = fix
    ? {
        lat: Number(fix.lat),
        lon: Number(fix.lon),
        accuracyM: accuracy === null ? null : Number(accuracy),
      }
    : null;

  const [recent, near, all] = await Promise.all([
    getPlacesUsed(),
    point ? getPlacesNear(point.lat, point.lon) : Promise.resolve([]),
    getPlaces(),
  ]);

  const landed = which === "end";

  return (
    <>
      <BackHeader
        href={flight.status === "draft" ? `/flight/${flight.id}/confirm` : "/"}
        label="Back"
        title={landed ? "Where did you land?" : "Where did you take off?"}
      />

      <main className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto px-4 pt-3 pb-4">
        <PlacePicker
          flightId={flight.id}
          which={which}
          currentPlaceId={landed ? flight.dest_place_id : flight.origin_place_id}
          fix={point}
          recent={recent.map((place) => ({
            id: place.id,
            name: place.name,
            kind: place.kind,
            times_used: Number(place.times_used),
          }))}
          near={near.map((place) => ({
            id: place.id,
            name: place.name,
            kind: place.kind,
            distance_m: Number(place.distance_m),
          }))}
          all={all.map((place) => ({
            id: place.id,
            name: place.name,
            kind: place.kind,
          }))}
        />
      </main>
    </>
  );
}
