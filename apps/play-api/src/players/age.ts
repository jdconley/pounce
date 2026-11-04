import type { AgeBand } from "./parse";

/** A teen's device gets nothing in these local hours (§14.1): [start, end). */
const TEEN_NIGHT_START_HOUR = 0;
const TEEN_NIGHT_END_HOUR = 6;

/** Under 13 without parental consent: nothing at all from the server (§14.1). */
export function pushBlocked(band: AgeBand | null): boolean {
  return band === "kitten";
}

function localHour(timeZone: string | null, now: number): number {
  try {
    const hour = new Intl.DateTimeFormat("en-US", { timeZone: timeZone ?? "UTC", hour: "numeric", hourCycle: "h23" })
      .formatToParts(new Date(now))
      .find((part) => part.type === "hour")?.value;
    return Number(hour);
  } catch {
    return new Date(now).getUTCHours();
  }
}

/** True when nothing may be sent now, "not even passive" (§14.1): a teen's device overnight. */
export function nightBlocked(band: AgeBand | null, timeZone: string | null, now: number): boolean {
  if (band !== "teen") return false;
  const hour = localHour(timeZone, now);
  return hour >= TEEN_NIGHT_START_HOUR && hour < TEEN_NIGHT_END_HOUR;
}
