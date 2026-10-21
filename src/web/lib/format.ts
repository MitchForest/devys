/**
 * How the web shows amounts, dates and sizes: one place, in the owner's locale. Money keeps the
 * currency it was recorded in.
 */

/** `$500` or `€1,250.50`: whole amounts without cents. */
export function money({ cents, currency }: { cents: number; currency: string }) {
  return (cents / 100).toLocaleString(undefined, {
    style: "currency",
    currency,
    minimumFractionDigits: cents % 100 === 0 ? 0 : 2,
    maximumFractionDigits: 2,
  });
}

const day = 86_400_000;
const sameDay = (a: Date, b: Date) => a.toDateString() === b.toDateString();

/** `2:21 PM`. */
export const clock = (date: Date) =>
  date.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });

/** `Oct 21, 2026`. */
export const shortDate = (at: string | Date) =>
  new Date(at).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });

/** `Tue, Oct 21`: a due date, near enough that the year goes without saying. */
export const dueDate = (at: string) =>
  new Date(at).toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });

/** `Oct 21, 2026, 2:21 PM`. */
export const dateTime = (at: string | Date) =>
  new Date(at).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });

/** "Today 2:21 PM", "Yesterday 9:04 AM", "Mon 9:04 AM" or a date: a conversation's headings. */
export function relativeDay(date: Date, now = new Date()) {
  const time = clock(date);
  if (sameDay(date, now)) return `Today ${time}`;
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (sameDay(date, yesterday)) return `Yesterday ${time}`;
  if (now.getTime() - date.getTime() < 7 * day)
    return `${date.toLocaleDateString(undefined, { weekday: "short" })} ${time}`;
  return shortDate(date);
}

/**
 * A time still to come: "Today 2:21 PM", "Tomorrow 9:00 AM", "Thu 9:00 AM" within the week,
 * else "Oct 30, 9:00 AM". A next run, or when waiting work looks again.
 */
export function upcoming(at: string | Date, now = new Date()) {
  const date = new Date(at);
  const time = clock(date);
  if (sameDay(date, now)) return `Today ${time}`;
  const tomorrow = new Date(now);
  tomorrow.setDate(now.getDate() + 1);
  if (sameDay(date, tomorrow)) return `Tomorrow ${time}`;
  if (date > now && date.getTime() - now.getTime() < 6 * day)
    return `${date.toLocaleDateString(undefined, { weekday: "short" })} ${time}`;
  return `${date.toLocaleDateString(undefined, { month: "short", day: "numeric" })}, ${time}`;
}

/** A deadline (a calendar date) and how far off it is: `Dec 1 · 5d`, `· today`, `· 2d late`. */
export function deadline(date: string, now = Date.now()) {
  const at = new Date(`${date}T00:00:00`);
  const days = Math.ceil((at.getTime() - now) / day);
  const label = at.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  return days < 0
    ? `${label} · ${-days}d late`
    : days === 0
      ? `${label} · today`
      : `${label} · ${days}d`;
}

/** `840 bytes`, `12 KB`, `3.4 MB`. */
export function bytes(count: number) {
  if (count < 1000) return `${count} bytes`;
  const units = ["KB", "MB", "GB"];
  let value = count / 1000;
  let unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  return `${value < 10 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`;
}
