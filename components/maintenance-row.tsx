import Link from "next/link";

import { Chip } from "@/components/chip";
import type { MaintenanceStatus } from "@/lib/aircraft";
import { formatHourCount } from "@/lib/format";
import { formatDate } from "@/lib/time";

/**
 * One maintenance item: name, a status in words, and a progress bar.
 *
 * SPEC.md 4.4 asks for "a progress bar plus a text status (never colour
 * alone)", so the bar is `aria-hidden` and the chip beside it says the same
 * thing in words. The bar is decoration on top of the sentence, not the other
 * way round.
 *
 * The four states come from `public.maintenance_status`; nothing is computed
 * here. `unknown` is a real state and not an error: a tach item cannot say how
 * much life is left until someone has logged a reading.
 */

const BAR = {
  overdue: "bg-accent",
  due_soon: "bg-warn",
  ok: "bg-ok",
  unknown: "bg-line",
} as const;

const TONE = {
  overdue: "snag",
  due_soon: "caution",
  ok: "neutral",
  unknown: "neutral",
} as const;

type State = keyof typeof BAR;

/**
 * How much life is left, in words. Exported because the item's own screen says
 * the same thing in its "Due" box, and a negative number of hours left is not a
 * sentence -- "1.4 hr over" is.
 */
export function statusText(item: MaintenanceStatus): string {
  if (item.basis === "tach") {
    if (item.hours_remaining === null) return "No tach reading";
    const left = Number(item.hours_remaining);
    if (left <= 0) return `${formatHourCount(-left)} hr over`;
    return `${formatHourCount(left)} hr left`;
  }

  if (item.days_remaining === null) return "No due date";
  const days = item.days_remaining;
  if (days < 0) return `${-days} days over`;
  if (days === 0) return "Due today";
  if (days === 1) return "1 day";
  return `${days} days`;
}

function captionText(item: MaintenanceStatus): string {
  if (item.basis === "tach") {
    const interval = formatHourCount(Number(item.interval_hours));
    const used =
      item.hours_used === null ? null : formatHourCount(Number(item.hours_used));

    // A life limit counts up to a total; a recurring task counts since the
    // last time it was done. Same arithmetic, different story.
    if (item.kind === "life_limit") {
      return used === null
        ? `${interval} hr life limit (est. tach)`
        : `${used} of ${interval} hr (est. tach)`;
    }
    return used === null
      ? `Every ${interval} hr · never done`
      : `Every ${interval} hr · ${used} hr since last`;
  }

  // A calendar limit with no interval is a single fixed date -- the 2034 prop
  // overhaul -- so there is nothing to say about recurrence.
  if (item.interval_months === null) {
    return item.due_date
      ? `Calendar limit ${item.due_date.slice(0, 4)}`
      : "No due date";
  }

  const months = item.interval_months;
  const every =
    months % 12 === 0
      ? `Every ${months / 12} year${months === 12 ? "" : "s"}`
      : `Every ${months} months`;

  return item.next_due_on ? `${every} · due ${formatDate(item.next_due_on)}` : every;
}

export function MaintenanceRow({ item }: { item: MaintenanceStatus }) {
  const state = (item.state ?? "unknown") as State;
  const fraction = item.fraction_used === null ? null : Number(item.fraction_used);

  return (
    <Link href={`/aircraft/maintenance/${item.id}`} className="block min-h-11 py-3">
      {/*
        No fraction means no bar, and then the row collapses to a single line
        with its caption on the right. That is the 2034 prop overhaul: a date
        with no known start, so there is no proportion to draw. It is also an
        item still waiting for its first tach reading.
      */}
      {fraction === null ? (
        <div className="flex items-center justify-between gap-2.5">
          <div className="text-[15px] font-semibold">{item.name}</div>
          <div className="text-[13px] text-muted">{captionText(item)}</div>
        </div>
      ) : (
        <>
          <div className="flex items-center justify-between gap-2.5">
            <div className="text-[15px] font-semibold">{item.name}</div>
            <Chip tone={TONE[state]}>{statusText(item)}</Chip>
          </div>
          <div className="mt-0.5 mb-2 text-[13px] text-muted">{captionText(item)}</div>
          <div
            aria-hidden="true"
            className="h-2 overflow-hidden rounded-[4px] bg-hairline"
          >
            <div
              className={`h-full ${BAR[state]}`}
              style={{ width: `${Math.round(fraction * 100)}%` }}
            />
          </div>
        </>
      )}
    </Link>
  );
}
