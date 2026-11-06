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

/**
 * Notifications and Pounce (§15 row 5) need both `STREAKS` and `NOTIFY`:
 * streaks become visible (PR 4) before anything can nag, and PR 5's app half
 * turned `NOTIFY` on in wrangler.jsonc once people could change the settings.
 */
export function notifyOn(env: { STREAKS?: string; NOTIFY?: string }): boolean {
  return streaksOn(env) && ON.includes((env.NOTIFY ?? "").toLowerCase());
}

/**
 * The live table (§15 row 7) needs `LIVE` on top of `NOTIFY`: a kill switch
 * that stops every Live Activity push without an app build. wrangler.jsonc
 * turns it on, since the app half ships in the same PR and nothing is sent
 * until a device uploads a push-to-start token.
 */
export function liveOn(env: { STREAKS?: string; NOTIFY?: string; LIVE?: string }): boolean {
  return notifyOn(env) && ON.includes((env.LIVE ?? "").toLowerCase());
}

/**
 * Parent consent for kittens (§15 row 9, consent design §3) needs `CONSENT`
 * on top of `NOTIFY`. Off, a kitten's device gets nothing, exactly as before.
 * wrangler.jsonc turns it on (D4); the parent's code still needs the Twilio Verify secrets.
 */
export function consentOn(env: { STREAKS?: string; NOTIFY?: string; CONSENT?: string }): boolean {
  return notifyOn(env) && ON.includes((env.CONSENT ?? "").toLowerCase());
}
