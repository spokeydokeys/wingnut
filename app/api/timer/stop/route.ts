import { handleTimerRequest } from "@/lib/timer";

// POST /api/timer/stop
//
// Closes the caller's running flight and records the stop fix. The flight stays
// a draft: SPEC.md 4.1 has Stop open the Confirm screen, so a human still has
// to look at it before it counts.
export async function POST(request: Request) {
  return handleTimerRequest(request, "timer_stop");
}
