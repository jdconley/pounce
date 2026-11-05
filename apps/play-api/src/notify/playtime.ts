import { dayKey, daysBetween, localMinutes, ROLLOVER_MIN, type Day } from "../streaks/clock";

/**
 * The local time of a player's first turn each day (§12.3), in 48 half-hour
 * buckets, weekdays and weekends apart. Old weights decay by ×0.85 a day.
 */
export type Playtime = {
  weekday: number[];
  weekend: number[];
  /** Days recorded of each type (not decayed): learning starts at 5. */
  days: { weekday: number; weekend: number };
  lastDay: Day | null;
};

export type DayType = "weekday" | "weekend";

const BUCKETS = 48;
const BUCKET_MIN = 30;
const DECAY = 0.85;
const MIN_DAYS = 5;
/** The reminder fires 15 minutes before the median, which sits mid-bucket. */
const BEFORE_MEDIAN_MIN = 15;
const FIRST_BUCKET = ROLLOVER_MIN / BUCKET_MIN;

export function emptyPlaytime(): Playtime {
  return {
    weekday: new Array<number>(BUCKETS).fill(0),
    weekend: new Array<number>(BUCKETS).fill(0),
    days: { weekday: 0, weekend: 0 },
    lastDay: null,
  };
}

export function dayType(day: Day): DayType {
  const weekday = new Date(`${day}T12:00:00Z`).getUTCDay();
  return weekday === 0 || weekday === 6 ? "weekend" : "weekday";
}

/** Counts a turn at `at`, if it's the first of its day (a later day than any recorded). */
export function recordPlay(p: Playtime, at: number, zone: string): void {
  const day = dayKey(at, zone);
  if (p.lastDay !== null && day <= p.lastDay) return;
  if (p.lastDay !== null) {
    const factor = DECAY ** daysBetween(p.lastDay, day);
    p.weekday = p.weekday.map((w) => w * factor);
    p.weekend = p.weekend.map((w) => w * factor);
  }
  const type = dayType(day);
  const bucket = Math.floor(localMinutes(at, zone) / BUCKET_MIN);
  p[type][bucket] = (p[type][bucket] as number) + 1;
  p.days[type] += 1;
  p.lastDay = day;
}

function median(weights: number[]): number {
  const total = weights.reduce((a, b) => a + b, 0);
  let sum = 0;
  let i = 0;
  // Day order: 04:00 first, so a 00:30 turn is "tonight", after the evening.
  for (; i < BUCKETS - 1; i++) {
    sum += weights[(FIRST_BUCKET + i) % BUCKETS] as number;
    if (sum >= total / 2) break;
  }
  return (FIRST_BUCKET + i) % BUCKETS;
}

/**
 * The learned reminder time for a day type, in minutes after local midnight:
 * 15 minutes before the weighted median. Null under 5 days of data. A type
 * with no days yet borrows the other's.
 */
export function learnedMinutes(p: Playtime, type: DayType): number | null {
  if (p.days.weekday + p.days.weekend < MIN_DAYS) return null;
  const use: DayType = p.days[type] > 0 ? type : type === "weekday" ? "weekend" : "weekday";
  return median(p[use]) * BUCKET_MIN + BUCKET_MIN / 2 - BEFORE_MEDIAN_MIN;
}
