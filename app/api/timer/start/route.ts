import { handleTimerRequest } from "@/lib/timer";

// POST /api/timer/start
//
//   Authorization: Bearer wingnut_...
//   { "lat": 48.4226, "lon": -123.37, "accuracy": 10, "idempotency_key": "..." }
//
// Opens a draft flight. Safe to retry: the same idempotency key returns the
// same flight, and so does a second Start while the caller's own timer is
// already running.
//
// The proxy lets this through unauthenticated on purpose -- the bearer token is
// the credential, and there is no session.
export async function POST(request: Request) {
  return handleTimerRequest(request, "timer_start");
}
