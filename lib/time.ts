/**
 * Dates and times, always in the aeroplane's time zone.
 *
 * Not the viewer's. A logbook is kept in local time at the aircraft's base: a
 * flight that landed at 23:00 in Victoria happened on that day, and should not
 * read as the next morning because an owner opened the app from a hotel in
 * Toronto. Fixing the zone also makes every timestamp render identically on
 * the server and in the browser, so there are no hydration mismatches and no
 * timestamps that have to flash in after mount.
 *
 * One aeroplane, one base, so this is a constant. It belongs on the company
 * row the day there is a second base, and these functions are where it would
 * be read from.
 */
export const AIRCRAFT_TIME_ZONE = "America/Vancouver";

const parts = (date: Date) => {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: AIRCRAFT_TIME_ZONE,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });

  const found: Record<string, string> = {};
  for (const part of formatter.formatToParts(date)) found[part.type] = part.value;
  return found;
};

/** `08:14` */
export function formatClock(iso: string): string {
  const p = parts(new Date(iso));
  return `${p.hour}:${p.minute}`;
}

/** `Mon 12 Oct`. en-GB for day-before-month; en-CA gives "Mon, Oct 12". */
export function formatDayShort(iso: string): string {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: AIRCRAFT_TIME_ZONE,
    weekday: "short",
    day: "numeric",
    month: "short",
  }).format(new Date(iso));
}

/**
 * `2026-10-12T08:14`, the only shape `<input type="datetime-local">` accepts.
 *
 * Note that the input itself has no time zone: whatever string goes in comes
 * back out, so this function and `fromInputValue` are a matched pair and the
 * value in between is in the aircraft's zone, not the browser's.
 */
export function toInputValue(iso: string): string {
  const p = parts(new Date(iso));
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`;
}

/**
 * The inverse: a datetime-local value read as aircraft-local time, returned as
 * a real instant.
 *
 * Works by reading the string as though it were UTC and then subtracting the
 * zone's offset at that moment. The offset is looked up twice because the
 * first lookup uses an instant that may be up to an hour off, which matters
 * only on the two days a year the clocks change -- and on those days it is the
 * difference between a flight logged at 02:30 and one logged at 01:30.
 */
export function fromInputValue(value: string): Date | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(value);
  if (!match) return null;

  const [, y, mo, d, h, mi] = match.map(Number);
  const asIfUtc = Date.UTC(y, mo - 1, d, h, mi);

  let guess = asIfUtc;
  for (let i = 0; i < 2; i++) guess = asIfUtc - offsetMs(new Date(guess));

  const result = new Date(guess);
  return Number.isNaN(result.valueOf()) ? null : result;
}

/** How far ahead of UTC the aircraft's zone is at a given instant. */
function offsetMs(at: Date): number {
  const p = parts(at);
  const asUtc = Date.UTC(
    Number(p.year),
    Number(p.month) - 1,
    Number(p.day),
    Number(p.hour),
    Number(p.minute),
    Number(p.second),
  );
  // Seconds and below are dropped by the formatter's own rounding, so compare
  // on whole seconds to keep the offset a clean multiple of a minute.
  return asUtc - Math.floor(at.valueOf() / 1000) * 1000;
}
