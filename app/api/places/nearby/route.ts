import { requireMember } from "@/lib/dal";
import { getPlacesNear } from "@/lib/places";

// GET /api/places/nearby?lat=48.4226&lon=-123.3878
//
// Ranked candidates for a coordinate (SPEC.md 10). The Set place screen renders
// its own list on the server from the flight's GPS fix; this exists for the map,
// where the pin moves and the list under it has to follow without a round trip
// through the whole page.
//
// Session-authenticated, unlike the timer endpoints: this one is called by the
// app's own screens, so there is no Shortcut and no bearer token.
export async function GET(request: Request) {
  await requireMember();

  const params = new URL(request.url).searchParams;
  const lat = Number(params.get("lat"));
  const lon = Number(params.get("lon"));

  if (
    !Number.isFinite(lat) || !Number.isFinite(lon) ||
    lat < -90 || lat > 90 || lon < -180 || lon > 180
  ) {
    return Response.json({ error: "lat and lon are required" }, { status: 400 });
  }

  const places = await getPlacesNear(lat, lon);

  // No caching header: the list is short, it is per-member (the ranking counts
  // the caller's own flights), and a place saved thirty seconds ago must appear.
  return Response.json({ places });
}
