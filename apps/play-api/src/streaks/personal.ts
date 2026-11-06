import { addDays, dayEnd, dayKey, type Day } from "./clock";

import type { WeekDot } from "./pair-core";

/**
 * Your own streak (trophy room design §2, D1): a day counts when you take a
 * turn at a table with another person. It uses the pair streak's day (04:00
 * in your own zone), naps, win-back and fresh start (§6, §8), and has no
 * rewards: personal records instead (§3). The `Player` stores a `Personal`
 * as JSON and calls these with the time; nothing here reads a clock.
 */

/** A day with a turn not yet counted, a kept day, a nap, or the miss that started a win-back. */
type DayMark = "turn" | "kept" | "nap" | "winback";

export type Personal = {
  /** The first day with a turn: earlier days aren't the streak's. */
  firstDay: Day;
  lastSettled: Day | null;
  count: number;
  best: number;
  lifetimeKept: number;
  perfectWeeks: number;
  /** Kept days since the last nap or miss: a perfect week at 7. */
  perfectRun: number;
  naps: number;
  winback: { missedDay: Day; kept: number } | null;
  /** Recent days only (the week strip); a settled day without a mark was missed. */
  days: Record<Day, DayMark>;
};

/** What the app shows of your own streak (the strip's first chip, the trophy room). */
export type OwnStreak = {
  count: number;
  best: number;
  /** Today is kept. */
  kept: boolean;
  naps: number;
  winback: { kept: number } | null;
  lifetimeKept: number;
  perfectWeeks: number;
  week: WeekDot[];
};

/** A day settles ten minutes after it ends, so a turn reported a moment late still counts (as for pairs). */
const SETTLE_AFTER_MS = 10 * 60_000;
const MAX_NAPS = 2;
const PERFECT_WEEK = 7;
const NAP_MILESTONE = 7;
const WIN_BACK_DAYS = 2;
const WEEK = 7;
/** Days kept for the week strip, past today. */
const KEEP_DAYS = 8;

function fresh(firstDay: Day): Personal {
  return {
    firstDay,
    lastSettled: null,
    count: 0,
    best: 0,
    lifetimeKept: 0,
    perfectWeeks: 0,
    perfectRun: 0,
    naps: 0,
    winback: null,
    days: {},
  };
}

/** Count, naps and win-back progress for a kept day (§8.1, §8.2). */
function applyKept(s: Personal, d: Day): void {
  s.days[d] = "kept";
  s.count += 1;
  s.best = Math.max(s.best, s.count);
  s.lifetimeKept += 1;
  s.perfectRun += 1;
  if (s.perfectRun === PERFECT_WEEK) {
    s.perfectWeeks += 1;
    s.perfectRun = 0;
    s.naps = Math.min(MAX_NAPS, s.naps + 1);
  }
  if (s.count === NAP_MILESTONE) s.naps = Math.min(MAX_NAPS, s.naps + 1);
  if (s.winback) {
    s.winback.kept += 1;
    if (s.winback.kept === WIN_BACK_DAYS) {
      s.days[s.winback.missedDay] = "nap";
      s.winback = null;
    }
  }
}

/** A day's outcome, as a pair settles one with nobody else to wait for (§8). */
function finalize(s: Personal, d: Day): void {
  const mark = s.days[d];
  if (mark === "turn") applyKept(s, d);
  else if (mark === "kept") {
    // Kept as it happened.
  } else if (s.count > 0 && s.naps > 0) {
    s.days[d] = "nap";
    s.naps -= 1;
    s.perfectRun = 0;
  } else if (s.count > 0 && !s.winback) {
    s.days[d] = "winback";
    s.winback = { missedDay: d, kept: 0 };
    s.perfectRun = 0;
  } else {
    // The fresh start (§8.4): the count goes to 0, best and total days stay.
    s.count = 0;
    s.winback = null;
    s.perfectRun = 0;
  }
  s.lastSettled = d;
}

/**
 * Brings the record up to `now`: settles every day that has ended, in order,
 * and counts a day with a turn as soon as every day before it is settled.
 */
export function advancePersonal(s: Personal | null, zone: string, now: number): void {
  if (!s) return;
  const today = dayKey(now, zone);
  let ordered = true;
  for (let d = s.lastSettled === null ? s.firstDay : addDays(s.lastSettled, 1); d <= today; d = addDays(d, 1)) {
    if (ordered && dayEnd(d, zone) + SETTLE_AFTER_MS <= now) {
      finalize(s, d);
      continue;
    }
    if (ordered && s.days[d] === "turn") applyKept(s, d);
    ordered &&= s.days[d] === "kept";
  }
  const oldest = addDays(today, -KEEP_DAYS);
  for (const d of Object.keys(s.days)) if (d < oldest && s.lastSettled !== null && d <= s.lastSettled) delete s.days[d];
}

/** A turn of yours at a table with another person, at `at`. Returns the record (made by the first turn). */
export function recordTurn(p: Personal | null, at: number, zone: string, now: number): Personal {
  const d = dayKey(at, zone);
  const s = p ?? fresh(d);
  advancePersonal(s, zone, now);
  if (d < s.firstDay || (s.lastSettled !== null && d <= s.lastSettled)) return s;
  s.days[d] ??= "turn";
  advancePersonal(s, zone, now);
  return s;
}

function weekDot(s: Personal | null, d: Day): WeekDot["state"] {
  if (!s || d < s.firstDay) return "none";
  const mark = s.days[d];
  if (s.lastSettled === null || d > s.lastSettled) return mark === "kept" ? "kept" : "live";
  return mark === "kept" ? "kept" : mark === "nap" ? "nap" : "missed";
}

/** What you see of your own streak now. Brings the record up to `now` first. */
export function ownView(s: Personal | null, zone: string, now: number): OwnStreak {
  advancePersonal(s, zone, now);
  const today = dayKey(now, zone);
  return {
    count: s?.count ?? 0,
    best: s?.best ?? 0,
    kept: s?.days[today] === "kept",
    naps: s?.naps ?? 0,
    winback: s?.winback ? { kept: s.winback.kept } : null,
    lifetimeKept: s?.lifetimeKept ?? 0,
    perfectWeeks: s?.perfectWeeks ?? 0,
    week: Array.from({ length: WEEK }, (_, i) => {
      const d = addDays(today, i - (WEEK - 1));
      return { day: d, state: weekDot(s, d) };
    }),
  };
}

/**
 * Two players' records after an account merge (§13.1), as pairs merge: the
 * longer current streak wins whole; best, total days and perfect weeks take
 * the maximum; naps take the maximum, capped at 2.
 */
export function mergePersonal(a: Personal | null, b: Personal | null): Personal | null {
  if (!a || !b) return a ?? b;
  const [win, lose] = b.count > a.count ? [b, a] : [a, b];
  const merged = structuredClone(win);
  merged.best = Math.max(win.best, lose.best);
  merged.lifetimeKept = Math.max(win.lifetimeKept, lose.lifetimeKept);
  merged.perfectWeeks = Math.max(win.perfectWeeks, lose.perfectWeeks);
  merged.naps = Math.min(MAX_NAPS, Math.max(win.naps, lose.naps));
  return merged;
}
