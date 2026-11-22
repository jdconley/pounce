import { addDays, dayEnd, dayKey, daysBetween, dayStart, FALLBACK_ZONE, isZone, type Day } from "../streaks/clock";

/** The weekday ramp (spec §2): Mon 1 … Sat 6; Sun 7 is level 4, bigger. */
export type DayLevel = 1 | 2 | 3 | 4 | 5 | 6 | 7;

/**
 * Puzzle 1's date, for every game (spec §11): launch day, Sunday 22 November 2026, so No. 1 is a
 * Sunday puzzle (level 7) and the weekday ramp carries on from there. Before it, numbers are below 1,
 * and the app and the web player don't show them.
 */
export const LAUNCH: Day = "2026-11-22";

/**
 * The zone a player's daily puzzles follow. A reported change waits for the next 04:00 of the zone
 * that rules today (spec §3, "The day and time zones"): `before` rules until `since` starts there,
 * then `zone` does. Without `before`, `zone` rules, and `since` is the day it started to.
 */
export type DailyZone = { zone: string; since: Day; before?: string };

/** The date's level: its weekday, Monday 1 to Sunday 7. */
export function levelFor(date: Day): DayLevel {
  const weekday = new Date(`${date}T00:00:00Z`).getUTCDay();
  return (weekday === 0 ? 7 : weekday) as DayLevel;
}

/** The date's puzzle number, the same in every game: 1 on `LAUNCH`. */
export function puzzleNumber(date: Day): number {
  return daysBetween(LAUNCH, date) + 1;
}

/** When a run on `date` closes: the end of that day, 04:00 the next morning in `zone`. */
export function closesAt(date: Day, zone: string): number {
  return dayEnd(date, zone);
}

/**
 * The player's daily day now, and the zone to keep for next time. `zone` is what was kept (null
 * for a player who has none yet); `reported` is the zone the player's device last reported (null
 * or not a zone: none). Hopping zones never opens tomorrow's puzzles early, and never goes back
 * to yesterday's.
 */
export function dailyDay(now: number, zone: DailyZone | null, reported: string | null): { day: Day; zone: DailyZone } {
  const told = reported !== null && isZone(reported) ? reported : null;
  if (!zone) {
    const first = told ?? FALLBACK_ZONE;
    const day = dayKey(now, first);
    return { day, zone: { zone: first, since: day } };
  }
  // A waiting change applies once its day starts in the zone it waited on.
  const current: DailyZone =
    zone.before !== undefined && now >= dayStart(zone.since, zone.before) ? { zone: zone.zone, since: zone.since } : zone;
  const ruling = current.before ?? current.zone;
  const day = dayKey(now, ruling);
  if (told === null || told === current.zone) return { day, zone: current };
  // Back to the zone that rules today before the change applied: nothing waits any more.
  if (told === ruling) return { day, zone: { zone: ruling, since: day } };
  return { day, zone: { zone: told, since: addDays(day, 1), before: ruling } };
}
