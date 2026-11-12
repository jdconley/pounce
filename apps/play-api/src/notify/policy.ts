import { dayKey, localMinutes, localToInstant } from "../streaks/clock";

import type { NotifySettings } from "./settings";
import type { AgeBand } from "../players/parse";

/** Every push the server sends (§12.1). */
export type NotifyKind =
  | "your_move"
  | "pounce"
  | "pounce_answered"
  | "reminder"
  | "last_chance"
  | "fresh_start"
  | "going_quiet"
  | "nap"
  | "winback"
  | "paused"
  | "milestone"
  | "play_again"
  /** Someone at the table asks the person whose move it is to take it. */
  | "nudge"
  /** Your move has waited days: tomorrow the others may retire your seat. */
  | "retire_soon"
  /** Someone retired your stalled seat. */
  | "retired"
  /** Parent consent's confirmation, on the consenting parent's own devices (consent design D6). */
  | "consent"
  /** Someone asked you to a table your version of Pounce can't draw (app updates design §5). */
  | "update";

export type Level = "active" | "passive";

/** At most one push every 20 minutes, except your move, pounces, nudges and a retired seat's two (§12.1). */
export const SPACING_MS = 20 * 60_000;
/** Reminder-type pushes a day (§12.1). */
export const MAX_REMINDERS = 2;

const REMINDERS: readonly NotifyKind[] = ["reminder", "last_chance", "fresh_start", "going_quiet"];
// "update" keeps a spacing of its own, per device (`updateDue`), since it answers one person's ask like a pounce.
const UNSPACED: readonly NotifyKind[] = ["your_move", "pounce", "pounce_answered", "nudge", "retire_soon", "retired", "update"];
const STATUS: readonly NotifyKind[] = ["nap", "winback", "paused", "pounce_answered"];
/** A teen's device gets nothing in these local hours (§14.1). */
const TEEN_NIGHT_END_MIN = 6 * 60;
const ROLLOVER_MIN = 4 * 60;
const DAY_MIN = 24 * 60;

export const isReminder = (kind: NotifyKind): boolean => REMINDERS.includes(kind);
export const isSpaced = (kind: NotifyKind): boolean => !UNSPACED.includes(kind);

/** Quiet hours are `[start, end)` local, wrapping midnight; start = end means none. */
export function inQuiet(minutes: number, s: Pick<NotifySettings, "quietStart" | "quietEnd">): boolean {
  const { quietStart: a, quietEnd: b } = s;
  if (a === b) return false;
  return a < b ? minutes >= a && minutes < b : minutes >= a || minutes < b;
}

export type GateInput = {
  kind: NotifyKind;
  band: AgeBand | null;
  zone: string;
  settings: NotifySettings;
  now: number;
  /** The last push that counts toward spacing. */
  spacedAt: number | null;
  remindersToday: number;
};

export type Gate = { send: true; level: Level } | { send: false; retryAt: number | null };

/** The next 06:00 local, from a moment inside a teen's night (00:00–06:00). */
function nightEnd(now: number, zone: string): number {
  const day = dayKey(now, zone);
  // Before 04:00 the day key is still yesterday's date.
  return localMinutes(now, zone) < ROLLOVER_MIN
    ? localToInstant(day, DAY_MIN + TEEN_NIGHT_END_MIN, zone)
    : localToInstant(day, TEEN_NIGHT_END_MIN, zone);
}

/**
 * Whether a push may go out now, and how loud (§12.1, §12.3, §14.1). A
 * teen gets nothing overnight; reminders never go in quiet hours, past the
 * daily cap, or to a kitten (whose settings have them off); spaced kinds
 * wait out the 20 minutes. A kitten's own device refuses every push itself
 * (`DeviceIndex`), while a household kitten's pushes still reach the
 * parent's phone (§14.1).
 */
export function gate(i: GateInput): Gate {
  const minutes = localMinutes(i.now, i.zone);
  const reminder = isReminder(i.kind);
  if (i.band === "teen" && minutes < TEEN_NIGHT_END_MIN) {
    return { send: false, retryAt: reminder || !isSpaced(i.kind) ? null : nightEnd(i.now, i.zone) };
  }
  const quiet = inQuiet(minutes, i.settings);
  if (reminder && (!i.settings.reminders || quiet || i.remindersToday >= MAX_REMINDERS)) return { send: false, retryAt: null };
  if (isSpaced(i.kind) && i.spacedAt !== null && i.now < i.spacedAt + SPACING_MS) {
    return { send: false, retryAt: i.spacedAt + SPACING_MS };
  }
  return { send: true, level: quiet || STATUS.includes(i.kind) ? "passive" : "active" };
}
