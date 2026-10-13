import type { Fix } from "@/app/flight/actions";

/**
 * The phone's position, or null.
 *
 * Null for every failure -- denied, unavailable, timed out, or no geolocation
 * API at all. SPEC.md 4.2 lists "indoors, permission denied" as a case the app
 * has to handle, so a missing fix is an ordinary outcome and this never
 * rejects: the caller starts the flight either way.
 *
 * The timeout matters more than the accuracy. A float plane dock has a poor
 * view of the sky, and waiting thirty seconds for a better fix while the pilot
 * stares at a spinner is worse than recording a vaguer one.
 */
export function currentFix(timeoutMs = 8000): Promise<Fix | null> {
  if (typeof navigator === "undefined" || !navigator.geolocation) {
    return Promise.resolve(null);
  }

  return new Promise((resolve) => {
    navigator.geolocation.getCurrentPosition(
      (position) =>
        resolve({
          lat: position.coords.latitude,
          lon: position.coords.longitude,
          accuracy: position.coords.accuracy ?? null,
        }),
      () => resolve(null),
      { enableHighAccuracy: true, timeout: timeoutMs, maximumAge: 0 },
    );
  });
}
