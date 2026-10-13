/**
 * Durations, hours and money, shared by the server pages and the ticking
 * client timer. Clock times and dates live in ./time.ts, which has a time zone
 * to worry about and these do not.
 */

/**
 * Hours rounded the way the aircraft is billed.
 *
 * `public.round_hours(numeric, hour_rounding)` is the authority -- every stored
 * `billed_hours` comes from it, inside a trigger, so the database cannot be
 * talked out of it. This duplicate exists only because the running timer has to
 * tick in the browser with no row to read yet. Keep the two in step: if the
 * SQL changes, this changes.
 */
export function roundUpTenth(hours: number): number {
  return Math.ceil(hours * 10) / 10;
}

/**
 * Hours rounded to the nearest tenth, for the tach estimate.
 *
 * Nearest, not up, and the asymmetry is deliberate: billed hours are a charge,
 * so a part-tenth rounds in the company's favour, but the tach estimate feeds
 * engine life. Rounding it up every flight would overstate hours and retire
 * the engine early.
 */
export function nearestTenth(hours: number): number {
  return Math.round(hours * 10) / 10;
}

/** `0:42:18` -- hours are not zero-padded, matching the wireframe. */
export function formatElapsed(milliseconds: number): string {
  const total = Math.max(0, Math.floor(milliseconds / 1000));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = total % 60;
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${hours}:${pad(minutes)}:${pad(seconds)}`;
}

/** `0:48` -- the compact form used as a caption beside billed hours. */
export function formatDuration(milliseconds: number): string {
  const total = Math.max(0, Math.floor(milliseconds / 60000));
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

/** `0.8 hr`. Always one decimal, so a column of them lines up. */
export function formatHours(hours: number): string {
  return `${hours.toFixed(1)} hr`;
}

/**
 * `6`, `19`, `1,500`, `6.5` -- an hour count for a maintenance caption.
 *
 * Unlike formatHours this drops a trailing zero and groups thousands, because
 * these read as prose ("19 hr since last", "1,500 hr left") rather than lining
 * up in a column. Life limits run to four figures, where "1500" is a misread
 * waiting to happen.
 */
export function formatHourCount(hours: number): string {
  return new Intl.NumberFormat("en-CA", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 1,
  }).format(Math.round(hours * 10) / 10);
}

export function formatMoney(amount: number): string {
  return new Intl.NumberFormat("en-CA", {
    style: "currency",
    currency: "CAD",
    currencyDisplay: "narrowSymbol",
  }).format(amount);
}

/** `within 10 m`, or nothing at all when the fix carried no accuracy. */
export function formatAccuracy(metres: number | null): string | null {
  if (metres === null) return null;
  return `within ${Math.round(metres)} m`;
}

/**
 * `80 m away`, `1.1 km away` -- how far a candidate place is from a fix.
 *
 * Switches to kilometres at 1 km because that is the match radius: inside it
 * the metres matter ("30 m" is the same dock, "900 m" is across the harbour),
 * and beyond it they do not.
 */
export function formatDistance(metres: number): string {
  if (metres < 1000) return `${Math.round(metres)} m away`;
  return `${(metres / 1000).toFixed(1)} km away`;
}
