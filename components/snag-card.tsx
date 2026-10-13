import Link from "next/link";

import { Chip } from "@/components/chip";
import type { Snag } from "@/lib/aircraft";
import { formatDayMonth } from "@/lib/time";

/**
 * One snag in the Aircraft tab's list.
 *
 * `grounding` gets its own chip rather than becoming a fourth status, because
 * it is a different question: the status says how closely to watch it, the
 * grounding flag says whether the aeroplane flies today. An owner glancing at
 * this list needs the second answer first, which is why it is shown even
 * though it makes the row busier.
 */
export function SnagCard({ snag }: { snag: Snag }) {
  // "Since 21 Sep" for a watch item, which has been there a while on purpose;
  // "Reported 8 Oct by ..." for an open one, where who saw it matters.
  const when =
    snag.status === "watch"
      ? `Since ${formatDayMonth(snag.reported_at)}`
      : `Reported ${formatDayMonth(snag.reported_at)} by ${
          snag.reporter?.full_name ?? "a former owner"
        }`;

  return (
    <Link
      href={`/aircraft/snag/${snag.id}`}
      className="flex-none rounded-[14px] border border-line bg-surface px-3.5 py-3"
    >
      <div className="flex items-center justify-between gap-2.5">
        <div className="text-base font-semibold">{snag.title}</div>
        <div className="flex flex-none items-center gap-1.5">
          {snag.grounding && <Chip tone="snag">Grounded</Chip>}
          <Chip tone={snag.status === "open" ? "snag" : "neutral"}>
            {snag.status === "open" ? "Open" : "Watch"}
          </Chip>
        </div>
      </div>
      <div className="mt-1 text-[13px] text-muted">
        {when}
        {snag.notes && ` · ${snag.notes}`}
      </div>
    </Link>
  );
}
