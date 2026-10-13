"use client";

import { useTransition } from "react";

import { startFlight, stopFlight } from "@/app/flight/actions";
import { currentFix } from "@/lib/geolocation";

/**
 * The Start and Stop buttons. One component because they do the same two
 * things in the same order -- take a fix, call the action -- and differ only in
 * which action and how tall the button is.
 *
 * A button rather than a form so the GPS fix can be taken on the way through.
 * The fix is best-effort: `currentFix` resolves to null on refusal or timeout,
 * and the timer starts anyway. Losing the flight record to protect a
 * coordinate would be the wrong way round.
 */
export function TimerButton({ action }: { action: "start" | "stop" }) {
  const [pending, startTransition] = useTransition();

  const press = () => {
    startTransition(async () => {
      const fix = await currentFix();
      if (action === "start") await startFlight(fix);
      else await stopFlight(fix);
    });
  };

  const starting = action === "start";

  return (
    <button
      type="button"
      onClick={press}
      disabled={pending}
      className={`flex flex-none items-center justify-center gap-3 rounded-2xl bg-accent font-semibold text-white disabled:opacity-70 ${
        starting ? "h-32 text-[28px]" : "h-24 text-[26px]"
      }`}
    >
      {pending ? (
        "Locating…"
      ) : (
        <>
          <svg aria-hidden="true" width={starting ? 36 : 28} height={starting ? 36 : 28} viewBox="0 0 24 24" fill="currentColor">
            {starting ? (
              <path d="M7 4.5v15L19.5 12z" />
            ) : (
              <rect x="5" y="5" width="14" height="14" rx="2" />
            )}
          </svg>
          {starting ? "Start flight" : "Stop flight"}
        </>
      )}
    </button>
  );
}
