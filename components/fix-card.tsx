import type { ReactNode } from "react";

import type { FlightFix } from "@/lib/flights";
import { formatAccuracy } from "@/lib/format";
import { formatClock } from "@/lib/time";

/**
 * One end of a flight: where it happened and what the phone thought at the time.
 *
 * `fix` is the raw coordinate and is only ever the caller's own -- RLS hands a
 * co-owner nothing here, which is the privacy rule in SPEC.md 4.2 doing its
 * job. A flight with no fix at all is normal, so every line below is optional.
 */
export function FixCard({
  label,
  placeName,
  fix,
  fixAt,
  accuracyM,
  trailing,
  children,
}: {
  label: string;
  placeName: string | null;
  fix: FlightFix | undefined;
  fixAt: string | null;
  accuracyM: number | null;
  trailing?: ReactNode;
  children?: ReactNode;
}) {
  const accuracy = formatAccuracy(accuracyM);

  return (
    <div>
      <div className="flex items-center justify-between">
        <div className="field-label">{label}</div>
        {trailing}
      </div>

      <div className="text-base font-semibold">
        {placeName ??
          (fix
            ? `${Number(fix.lat).toFixed(4)}, ${Number(fix.lon).toFixed(4)}`
            : "Place not set")}
      </div>

      <div className="text-[13px] text-muted">
        {fixAt
          ? `GPS fix ${formatClock(fixAt)}${accuracy ? ` · ${accuracy}` : ""}`
          : "No GPS fix recorded"}
      </div>

      {children}
    </div>
  );
}
