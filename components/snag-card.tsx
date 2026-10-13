import Link from "next/link";

import { Chip } from "@/components/chip";
import type { Snag } from "@/lib/aircraft";
import { formatHourCount } from "@/lib/format";
import { formatDate, formatDayMonth, toDateInputValue } from "@/lib/time";

/**
 * When this snag comes back to anyone's attention, in words.
 *
 * Nothing stores whether a re-check has fallen due, because due-ness is
 * arithmetic on two things that move by themselves -- the running tach estimate
 * and today's date -- so it is worked out here, where it is read.
 *
 * An item-based re-check never reads as due. It is not waiting for a date to
 * arrive, it is waiting for a job to be done, and it is the mark-done screen
 * for that job that raises it.
 */
function recheckText(
  snag: Snag,
  tachNow: number | null,
): { text: string; due: boolean } | null {
  if (snag.recheck_item !== null) {
    return { text: `Re-check at the next ${snag.recheck_item.name}`, due: false };
  }

  if (snag.recheck_tach_hours !== null) {
    const hours = formatHourCount(snag.recheck_tach_hours);
    // No datum means no answer: the re-check was asked for before the aeroplane
    // had ever had a reading logged.
    if (snag.recheck_tach_base === null || tachNow === null) {
      return { text: `Re-check after ${hours} hr — needs a tach reading`, due: false };
    }

    const left = snag.recheck_tach_base + snag.recheck_tach_hours - tachNow;
    return left <= 0
      ? { text: `Re-check due — ${hours} hr flown`, due: true }
      : { text: `Re-check in ${formatHourCount(left)} hr`, due: false };
  }

  if (snag.recheck_on !== null) {
    const today = toDateInputValue();
    if (snag.recheck_on > today) {
      return { text: `Re-check on ${formatDate(snag.recheck_on)}`, due: false };
    }
    return {
      text:
        snag.recheck_on === today
          ? "Re-check today"
          : `Re-check due since ${formatDate(snag.recheck_on)}`,
      due: true,
    };
  }

  return null;
}

/**
 * One snag in the Aircraft tab's list.
 *
 * `grounding` gets its own chip rather than becoming a fourth status, because
 * it is a different question: the status says how closely to watch it, the
 * grounding flag says whether the aeroplane flies today. An owner glancing at
 * this list needs the second answer first, which is why it is shown even
 * though it makes the row busier.
 */
export function SnagCard({
  snag,
  tachNow,
}: {
  snag: Snag;
  tachNow: number | null;
}) {
  // "Since 21 Sep" for a watch item, which has been there a while on purpose;
  // "Reported 8 Oct by ..." for an open one, where who saw it matters.
  const when =
    snag.status === "watch"
      ? `Since ${formatDayMonth(snag.reported_at)}`
      : `Reported ${formatDayMonth(snag.reported_at)} by ${
          snag.reporter?.full_name ?? "a former owner"
        }`;

  const recheck = recheckText(snag, tachNow);

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
      {recheck && (
        <div
          className={`mt-1 text-[13px] ${
            recheck.due ? "font-semibold text-accent" : "text-muted"
          }`}
        >
          {recheck.text}
        </div>
      )}
    </Link>
  );
}
