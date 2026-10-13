"use client";

import { useEffect, useState } from "react";

import { formatElapsed, formatHours, nearestTenth, roundUpTenth } from "@/lib/format";
import { formatClock } from "@/lib/time";

/**
 * The big ticking clock, and the two figures derived from it.
 *
 * The timer is not really running here -- `start_at` is in the database and the
 * elapsed time is just now minus that. So locking the phone, force-quitting
 * the browser or flying out of signal cannot stop the clock or lose time, and
 * two owners looking at it see the same number.
 *
 * `serverNow` is the one odd-looking prop. The first frame has to render the
 * same string on the server and in the browser or hydration fails, and
 * `Date.now()` differs between the two by definition. So the server states
 * what time it is, that becomes the initial state, and the interval takes over
 * a second later. The alternative -- render a placeholder, fill it in on mount
 * -- shows the pilot a row of dashes for no reason.
 */
export function Elapsed({
  startAt,
  serverNow,
  tachFactor,
  pilotName,
}: {
  startAt: string;
  serverNow: string;
  tachFactor: number;
  pilotName: string;
}) {
  const startedAt = new Date(startAt).valueOf();
  const [now, setNow] = useState(() => new Date(serverNow).valueOf());

  useEffect(() => {
    const tick = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(tick);
  }, []);

  const elapsedMs = Math.max(0, now - startedAt);
  const hours = elapsedMs / 3_600_000;

  return (
    <>
      <div className="pt-7 text-center">
        <div className="field-label">Elapsed</div>
        <div className="numeric text-[72px] leading-[1.1] tracking-tighter tabular-nums">
          {formatElapsed(elapsedMs)}
        </div>
        <div className="text-[15px] text-muted">
          Started {formatClock(startAt)} · {pilotName}
        </div>
      </div>

      <div className="mt-2 flex gap-3">
        <div className="flex-1 rounded-xl border border-line bg-surface p-3">
          <div className="field-label">Billable</div>
          <div className="numeric text-[26px]">{formatHours(roundUpTenth(hours))}</div>
        </div>
        <div className="flex-1 rounded-xl border border-line bg-surface p-3">
          <div className="field-label">Est. tach</div>
          <div className="numeric text-[26px]">
            {formatHours(nearestTenth(hours / tachFactor))}
          </div>
        </div>
      </div>
    </>
  );
}
