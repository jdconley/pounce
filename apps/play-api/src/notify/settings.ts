import { quietStartMinutes } from "../streaks/profile";

import type { AgeBand, Section } from "../players/parse";

/** A player's notification settings (§12.6), times in minutes after local midnight. */
export type NotifySettings = {
  /** The bell: every reminder-type push. "Your move" is unaffected. */
  reminders: boolean;
  /** Reminder time learned from the playtime histogram, else the fixed times. */
  auto: boolean;
  weekday: number;
  weekend: number;
  quietStart: number;
  quietEnd: number;
  lastChance: boolean;
};

/** The synced `settings` keys (last writer wins per key, so each dial is its own key). */
export const SETTING_KEYS = {
  reminders: "reminders.on",
  auto: "reminders.auto",
  weekday: "reminders.weekday",
  weekend: "reminders.weekend",
  quietStart: "quiet.start",
  quietEnd: "quiet.end",
  lastChance: "lastChance.on",
} as const;

/** 19:30 local (§12.3: "that timing is fine"). */
export const DEFAULT_REMINDER = 19 * 60 + 30;
const DEFAULT_QUIET_END = 8 * 60;

const isInt = (v: unknown, max: number): v is number => typeof v === "number" && Number.isInteger(v) && v >= 0 && v < max;

function clock(settings: Section, key: string, fallback: number): number {
  const v = settings[key]?.v;
  if (typeof v === "object" && v !== null && !Array.isArray(v)) {
    const { h, m } = v as Record<string, unknown>;
    if (isInt(h, 24) && isInt(m, 60)) return h * 60 + m;
  }
  return fallback;
}

function flag(settings: Section, key: string, fallback: boolean): boolean {
  const v = settings[key]?.v;
  return typeof v === "boolean" ? v : fallback;
}

/**
 * The settings with each band's defaults (§12.3, §14.1): adults get reminders,
 * learned timing and last chance; teens get them off until they turn them on,
 * and quiet hours from 21:00; a kitten gets nothing from the server.
 */
export function notifySettings(settings: Section, band: AgeBand | null): NotifySettings {
  const gentle = band === "teen";
  const kitten = band === "kitten";
  return {
    reminders: !kitten && flag(settings, SETTING_KEYS.reminders, !gentle),
    auto: !kitten && flag(settings, SETTING_KEYS.auto, !gentle),
    weekday: clock(settings, SETTING_KEYS.weekday, DEFAULT_REMINDER),
    weekend: clock(settings, SETTING_KEYS.weekend, DEFAULT_REMINDER),
    quietStart: quietStartMinutes(settings, band),
    quietEnd: clock(settings, SETTING_KEYS.quietEnd, DEFAULT_QUIET_END),
    lastChance: !kitten && flag(settings, SETTING_KEYS.lastChance, !gentle),
  };
}
