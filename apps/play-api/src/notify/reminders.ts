import { addDays, dayKey, daysBetween, FALLBACK_ZONE, type Day } from "../streaks/clock";

import { DAILY_LINES, freshStartBody, GOING_QUIET, LAST_CHANCE_LINES, pickLine, type Line } from "./copy";
import { emptyPlaytime, recordPlay, type Playtime } from "./playtime";
import { gate, isReminder, isSpaced, type Level, type NotifyKind } from "./policy";
import { lastChanceMinutes, reminderMinutes, slotAt } from "./schedule";

import type { NotifySettings } from "./settings";
import type { Outgoing, StreakBlock } from "./types";
import type { AgeBand } from "../players/parse";

/**
 * A player's reminder bookkeeping (§13.2 `reminders`), one JSON row on the
 * `Player`. Pure: the Player DO loads it, calls these functions with the
 * time, saves it and sends what they return.
 */
export type NotifyState = {
  /** The day `reminders` counts. */
  day: Day | null;
  /** Reminder-type pushes sent that day. */
  reminders: number;
  /** The last push that counts toward the 20-minute spacing. */
  spacedAt: number | null;
  /** The day each slot was last decided (sent or skipped). */
  decided: { daily: Day | null; lastChance: Day | null };
  /** A slot deferred by spacing waits until then. */
  retryAt: number | null;
  lastTurnDay: Day | null;
  lastDailyDay: Day | null;
  /** "The cats will keep your seat warm." went out for this idle run. */
  quietSent: boolean;
  lines: Record<string, number>;
  cursor: { daily: number; lastChance: number };
  /** `pair:breakId` keys whose fresh start went out. */
  freshStart: string[];
  playtime: Playtime;
};

/** What a reminder needs to know about one pair, from the `Pair` (never sent to anyone as is). */
export type PairFacts = {
  pair: string;
  partner: string;
  count: number;
  /** In for today: took a turn, or the late move pass after the cutoff. */
  me: boolean;
  kept: boolean;
  paused: boolean;
  myMove: string[];
  breakId: number;
  brokeOn: Day | null;
  pinned: boolean;
  lastTurnAt: number;
  streak: StreakBlock;
};

export type ReminderInput = {
  now: number;
  zone: string | null;
  band: AgeBand | null;
  settings: NotifySettings;
  /** The player's own name: the title of reminder pushes. */
  name: string;
  lastOpenAt: number | null;
  pairs: PairFacts[];
  tableNames: Record<string, string>;
};

export type Slot = "daily" | "lastChance";

const H = 60 * 60 * 1000;
/** Opened the app this recently: no daily reminder (§12.1). */
const RECENT_OPEN_MS = 2 * H;
/** A slot this late (a late alarm, a player just created) is skipped, not sent late. */
const LATE_MS = H;
const LAST_CHANCE_MIN_COUNT = 3;
const BACKOFF_NO_LAST_CHANCE = 2;
const BACKOFF_EVERY_OTHER_DAY = 4;
const BACKOFF_QUIET = 7;
const MAX_FRESH_KEYS = 20;
const SLOTS: Slot[] = ["daily", "lastChance"];

export function emptyNotifyState(): NotifyState {
  return {
    day: null,
    reminders: 0,
    spacedAt: null,
    decided: { daily: null, lastChance: null },
    retryAt: null,
    lastTurnDay: null,
    lastDailyDay: null,
    quietSent: false,
    lines: {},
    cursor: { daily: 0, lastChance: 0 },
    freshStart: [],
    playtime: emptyPlaytime(),
  };
}

const zoneOf = (i: ReminderInput) => i.zone ?? FALLBACK_ZONE;
const enabled = (i: ReminderInput) => i.band !== "kitten" && i.settings.reminders;

function slotTime(st: NotifyState, i: ReminderInput, day: Day, slot: Slot): number | null {
  const s = i.settings;
  if (slot === "lastChance") return s.lastChance ? slotAt(day, lastChanceMinutes(s), zoneOf(i)) : null;
  return slotAt(day, reminderMinutes(day, s, s.auto ? st.playtime : null), zoneOf(i));
}

/** When an undecided slot of `day` should be decided, or null when it's off or an hour stale. */
function slotWake(st: NotifyState, i: ReminderInput, day: Day, slot: Slot): number | null {
  if (st.decided[slot] === day) return null;
  const t = slotTime(st, i, day, slot);
  if (t === null || i.now > t + LATE_MS) return null;
  return Math.max(t, st.retryAt ?? t);
}

/** Today's slots whose time has come and that haven't been decided. */
export function dueSlots(st: NotifyState, i: ReminderInput): Slot[] {
  if (!enabled(i)) return [];
  const today = dayKey(i.now, zoneOf(i));
  return SLOTS.filter((slot) => {
    const at = slotWake(st, i, today, slot);
    return at !== null && i.now >= at;
  });
}

/** The next time the Player's alarm should decide something; null when it never will. */
export function nextWake(st: NotifyState, i: ReminderInput): number | null {
  if (!enabled(i)) return null;
  const today = dayKey(i.now, zoneOf(i));
  const times = [today, addDays(today, 1)].flatMap((day) =>
    SLOTS.map((slot) => slotWake(st, i, day, slot)).filter((t): t is number => t !== null),
  );
  return Math.max(i.now, Math.min(...times));
}

function rollDay(st: NotifyState, today: Day): void {
  if (st.day === today) return;
  st.day = today;
  st.reminders = 0;
}

/** A push went out: it counts toward today's cap and the spacing. */
export function noteSent(st: NotifyState, kind: NotifyKind, now: number, zone: string | null): void {
  rollDay(st, dayKey(now, zone ?? FALLBACK_ZONE));
  if (isReminder(kind)) st.reminders += 1;
  if (isSpaced(kind)) st.spacedAt = now;
}

/** The player took a turn at a shared table: backoff resets; with `learn`, the histogram counts it. */
export function noteTurn(st: NotifyState, at: number, zone: string | null, learn: boolean): void {
  const z = zone ?? FALLBACK_ZONE;
  const day = dayKey(at, z);
  if (st.lastTurnDay === null || day > st.lastTurnDay) {
    st.lastTurnDay = day;
    st.quietSent = false;
  }
  if (learn) recordPlay(st.playtime, at, z);
}

/** The first Monday or 1st of the month after the break (§8.4). */
export function freshStartDay(brokeOn: Day): Day {
  let d = addDays(brokeOn, 1);
  while (new Date(`${d}T12:00:00Z`).getUTCDay() !== 1 && !d.endsWith("-01")) d = addDays(d, 1);
  return d;
}

/** Pinned first, then the longest streak, then the latest turn (§7). */
const byTop = (x: PairFacts, y: PairFacts) =>
  Number(y.pinned) - Number(x.pinned) || y.count - x.count || y.lastTurnAt - x.lastTurnAt;

type Candidate = { push: Outgoing; commit: () => void };

function lineFor(st: NotifyState, i: ReminderInput, p: PairFacts, slot: Slot, lines: readonly Line[]) {
  const code = p.myMove.find((c) => i.tableNames[c] !== undefined);
  const ctx = { table: code === undefined ? null : (i.tableNames[code] as string), partner: p.partner, count: p.count };
  return pickLine(lines, ctx, st.lines, st.cursor[slot], i.now);
}

function rotated(st: NotifyState, i: ReminderInput, p: PairFacts, slot: Slot, kind: NotifyKind): Candidate {
  // Every list has lines that need neither a table name nor a count.
  const line = lineFor(st, i, p, slot, slot === "daily" ? DAILY_LINES : LAST_CHANCE_LINES) as NonNullable<ReturnType<typeof lineFor>>;
  return {
    push: {
      kind,
      title: i.name,
      body: line.text,
      code: p.myMove[0] as string,
      thread: `pair:${p.pair}`,
      collapse: `${kind}:${p.pair}`,
      streak: p.streak,
    },
    commit: () => {
      st.lines[line.id] = i.now;
      st.cursor[slot] = line.cursor;
    },
  };
}

function dailyCandidate(st: NotifyState, i: ReminderInput, today: Day, idle: number, pairs: PairFacts[]): Candidate | null {
  const top = pairs[0];
  if (idle >= BACKOFF_QUIET) {
    if (st.quietSent || !top) return null;
    return {
      push: { kind: "going_quiet", title: i.name, body: GOING_QUIET, thread: `pair:${top.pair}`, collapse: `going_quiet:${top.pair}` },
      commit: () => {
        st.quietSent = true;
      },
    };
  }
  const fresh = pairs.find(
    (p) => p.count === 0 && p.breakId > 0 && p.brokeOn !== null && freshStartDay(p.brokeOn) === today && !st.freshStart.includes(`${p.pair}:${p.breakId}`),
  );
  if (fresh) {
    return {
      push: {
        kind: "fresh_start",
        title: i.name,
        body: freshStartBody(fresh.partner, today.endsWith("-01")),
        thread: `pair:${fresh.pair}`,
        collapse: `fresh_start:${fresh.pair}`,
        streak: fresh.streak,
      },
      commit: () => {
        st.freshStart = [...st.freshStart, `${fresh.pair}:${fresh.breakId}`].slice(-MAX_FRESH_KEYS);
      },
    };
  }
  if (!top || top.kept || top.me || top.myMove.length === 0) return null;
  if (i.lastOpenAt !== null && i.now - i.lastOpenAt < RECENT_OPEN_MS) return null;
  if (idle >= BACKOFF_EVERY_OTHER_DAY && st.lastDailyDay !== null && daysBetween(st.lastDailyDay, today) < 2) return null;
  const c = rotated(st, i, top, "daily", "reminder");
  return {
    push: c.push,
    commit: () => {
      c.commit();
      st.lastDailyDay = today;
    },
  };
}

function lastChanceCandidate(st: NotifyState, i: ReminderInput, idle: number, pairs: PairFacts[]): Candidate | null {
  const top = pairs[0];
  if (!i.settings.lastChance || idle >= BACKOFF_NO_LAST_CHANCE || !top) return null;
  if (top.count < LAST_CHANCE_MIN_COUNT || top.me || top.kept || top.myMove.length === 0) return null;
  return rotated(st, i, top, "lastChance", "last_chance");
}

/**
 * Decides one slot (§12.1, §12.3): the push to send, or none. The slot is
 * marked decided unless spacing defers it (`retryAt`). A push it returns is
 * already counted toward the cap and spacing.
 */
export function decide(st: NotifyState, i: ReminderInput, slot: Slot): { push: Outgoing | null; level: Level | null; retryAt: number | null } {
  const zone = zoneOf(i);
  const today = dayKey(i.now, zone);
  rollDay(st, today);
  const done = () => {
    st.decided[slot] = today;
    st.retryAt = null;
    return { push: null, level: null, retryAt: null };
  };
  const t = slotTime(st, i, today, slot);
  if (!enabled(i) || t === null || i.now > t + LATE_MS) return done();
  if (st.lastTurnDay === null) st.lastTurnDay = today;
  const idle = Math.max(0, daysBetween(st.lastTurnDay, today) - 1);
  const pairs = i.pairs.filter((p) => !p.paused).sort(byTop);
  const c = slot === "daily" ? dailyCandidate(st, i, today, idle, pairs) : lastChanceCandidate(st, i, idle, pairs);
  if (!c) return done();
  const g = gate({ kind: c.push.kind, band: i.band, zone, settings: i.settings, now: i.now, spacedAt: st.spacedAt, remindersToday: st.reminders });
  if (!g.send) {
    if (g.retryAt === null) return done();
    st.retryAt = g.retryAt;
    return { push: null, level: null, retryAt: g.retryAt };
  }
  c.commit();
  done();
  noteSent(st, c.push.kind, i.now, zone);
  return { push: c.push, level: g.level, retryAt: null };
}
