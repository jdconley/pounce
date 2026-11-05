import { localToInstant, ROLLOVER_MIN, type Day } from "../streaks/clock";

import { dayType, learnedMinutes, type Playtime } from "./playtime";
import { DEFAULT_REMINDER, type NotifySettings } from "./settings";

const DAY_MIN = 24 * 60;
/** The daily reminder lands at least 2 hours before quiet hours (§12.3). */
const REMINDER_BEFORE_QUIET_MIN = 120;
/** Last chance: 90 minutes before quiet hours (§12.1). */
const LAST_CHANCE_BEFORE_QUIET_MIN = 90;

const mod = (m: number) => ((m % DAY_MIN) + DAY_MIN) % DAY_MIN;
/** Minutes since 04:00, the order a streak day runs in. */
const dayOrder = (m: number) => mod(m - ROLLOVER_MIN);

/** Keeps a reminder outside quiet hours and at least 2 hours before they start. */
export function clampReminder(minutes: number, s: NotifySettings): number {
  const latest = dayOrder(s.quietStart - REMINDER_BEFORE_QUIET_MIN);
  const earliest = dayOrder(s.quietEnd);
  let v = Math.min(dayOrder(minutes), latest);
  if (earliest <= latest) v = Math.max(v, earliest);
  return mod(v + ROLLOVER_MIN);
}

/** The day's reminder time: learned (or 19:30 until there's data), or the fixed time for that kind of day. */
export function reminderMinutes(day: Day, s: NotifySettings, p: Playtime | null): number {
  const type = dayType(day);
  const raw = s.auto ? ((p ? learnedMinutes(p, type) : null) ?? DEFAULT_REMINDER) : s[type];
  return clampReminder(raw, s);
}

export function lastChanceMinutes(s: NotifySettings): number {
  return mod(s.quietStart - LAST_CHANCE_BEFORE_QUIET_MIN);
}

/** The instant of a local time on streak day `day`: times before 04:00 belong to the next date. */
export function slotAt(day: Day, minutes: number, zone: string): number {
  return localToInstant(day, minutes >= ROLLOVER_MIN ? minutes : minutes + DAY_MIN, zone);
}
