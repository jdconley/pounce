import type { AgeBand, Section } from "../players/parse";

const ADULT_QUIET_START = 22 * 60;
/** Teens get gentler defaults: quiet hours from 21:00 (§14.1). */
const TEEN_QUIET_START = 21 * 60;
const ON = ["on", "1", "true"];

const isInt = (v: unknown, max: number): v is number => typeof v === "number" && Number.isInteger(v) && v >= 0 && v < max;

/**
 * When a player's quiet hours start, in minutes after local midnight: the
 * synced setting `quiet.start` (`{h, m}`), else the band's default (§12.3).
 */
export function quietStartMinutes(settings: Section, band: AgeBand | null): number {
  const v = settings["quiet.start"]?.v;
  if (typeof v === "object" && v !== null && !Array.isArray(v)) {
    const { h, m } = v as Record<string, unknown>;
    if (isInt(h, 24) && isInt(m, 60)) return h * 60 + m;
  }
  return band === "teen" ? TEEN_QUIET_START : ADULT_QUIET_START;
}

/** Streaks stay off in production until the app ships them (§15 row 3). */
export function streaksOn(env: { STREAKS?: string }): boolean {
  return ON.includes((env.STREAKS ?? "").toLowerCase());
}
