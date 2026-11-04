/** A local calendar date, `YYYY-MM-DD`: the streak's day (§6.3). */
export type Day = string;

/** Days roll over at 04:00 local, so a turn at 1 a.m. counts as "tonight". */
export const ROLLOVER_MIN = 4 * 60;
/** The zone of a pair with no time zone from either person (§6.3). */
export const FALLBACK_ZONE = "America/Los_Angeles";

const MIN_MS = 60_000;
const DAY_MIN = 24 * 60;
const DAY_MS = DAY_MIN * MIN_MS;
const CUTOFF_BEFORE_QUIET_MIN = 120;
const MAX_ZONE_LENGTH = 64;

const formats = new Map<string, Intl.DateTimeFormat>();

function format(zone: string): Intl.DateTimeFormat {
  let f = formats.get(zone);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", {
      timeZone: zone,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    });
    formats.set(zone, f);
  }
  return f;
}

export function isZone(zone: unknown): zone is string {
  if (typeof zone !== "string" || zone.length > MAX_ZONE_LENGTH) return false;
  try {
    format(zone);
    return true;
  } catch {
    return false;
  }
}

/** The wall clock in `zone`, as if it were UTC: the date plus minutes since midnight. */
function wall(instant: number, zone: string): { date: Day; minutes: number; asUtc: number } {
  const parts = Object.fromEntries(format(zone).formatToParts(new Date(instant)).map((p) => [p.type, p.value]));
  const [y, mo, d, h, mi] = [parts.year, parts.month, parts.day, parts.hour, parts.minute].map(Number) as number[];
  const minutes = (h as number) * 60 + (mi as number);
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    minutes,
    asUtc: Date.UTC(y as number, (mo as number) - 1, d as number) + minutes * MIN_MS,
  };
}

const dateMs = (day: Day): number => Date.parse(`${day}T00:00:00Z`);
const fromMs = (ms: number): Day => new Date(ms).toISOString().slice(0, 10);

/** Minutes since local midnight. */
export function localMinutes(instant: number, zone: string): number {
  return wall(instant, zone).minutes;
}

/**
 * The day an instant belongs to: the local date, or the one before when the
 * local time is before 04:00. Uses the wall clock, so a DST morning still
 * rolls over at 04:00 local.
 */
export function dayKey(instant: number, zone: string): Day {
  const { date, minutes } = wall(instant, zone);
  return minutes >= ROLLOVER_MIN ? date : addDays(date, -1);
}

export function addDays(day: Day, n: number): Day {
  return fromMs(dateMs(day) + n * DAY_MS);
}

/** `b − a` in days. */
export function daysBetween(a: Day, b: Day): number {
  return Math.round((dateMs(b) - dateMs(a)) / DAY_MS);
}

/** The instant of a wall-clock time on `day` in `zone`; `minutes` past 1440 run into the next date. */
export function localToInstant(day: Day, minutes: number, zone: string): number {
  const naive = dateMs(day) + minutes * MIN_MS;
  const offset = (t: number) => wall(t, zone).asUtc - Math.floor(t / MIN_MS) * MIN_MS;
  const guess = naive - offset(naive);
  return naive - offset(guess);
}

export function dayStart(day: Day, zone: string): number {
  return localToInstant(day, ROLLOVER_MIN, zone);
}

export function dayEnd(day: Day, zone: string): number {
  return dayStart(addDays(day, 1), zone);
}

/**
 * The evening cutoff (§6.1): two hours before quiet hours start. A cutoff
 * before 04:00 falls on the next date, so it always lies inside the day.
 */
export function cutoffAt(day: Day, zone: string, quietStartMin: number): number {
  const c = (((quietStartMin - CUTOFF_BEFORE_QUIET_MIN) % DAY_MIN) + DAY_MIN) % DAY_MIN;
  return localToInstant(day, c >= ROLLOVER_MIN ? c : c + DAY_MIN, zone);
}
