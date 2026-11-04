import { createRng, type Rng, type Seed } from "../rules/rng";

import {
  condoStage,
  DEFAULT_BACK,
  DEFAULT_RUG,
  FULL_SET_BACK,
  isBack,
  isMilestone,
  isRug,
  nextMilestone,
  TOYS,
} from "./catalog";
import { addDays, cutoffAt, dayEnd, dayKey, daysBetween, dayStart, FALLBACK_ZONE, type Day } from "./clock";
import { CONFETTI, drawToy, giftItem, type Pity } from "./rewards";

import type { PounceView } from "../pounce/limits";

/**
 * The pure streak of one pair (§6–§9). The `Pair` Durable Object stores a
 * `PairState` as JSON and calls these functions with the time; nothing here
 * reads a clock or does I/O.
 */

export type PairPerson = { id: string; name: string; cat: number; zone: string | null; quietStart: number };

export type DayState = "live" | "kept" | "nap" | "held" | "paused" | "missed" | "winback";

/**
 * One day of the pair. Per-person fields are keyed by player id and never
 * leave the server for past days (§14: no blame).
 */
export type DayRow = {
  turns: Record<string, number>;
  /** Held the move at a shared table between 04:00 and their evening cutoff. */
  held: Record<string, boolean>;
  /** Some of that window had no shared table in play (or wasn't seen). */
  gap: Record<string, boolean>;
  state: DayState;
  /** The kept-day effects (count, toy, milestone) have run. */
  applied: boolean;
  toy: string | null;
};

export type Gift = { id: string; milestone: number; item: string; openedBy: string[] };

export type Streak = {
  count: number;
  best: number;
  lifetimeKept: number;
  perfectWeeks: number;
  /** Kept days since the last nap or miss: a perfect week at 7. */
  perfectRun: number;
  naps: number;
  winback: { missedDay: Day; kept: number } | null;
  pausedFrom: Day | null;
  pausedUntil: Day | null;
  pausedBy: string | null;
  /** Bumped each time a streak ends, so a fresh-start push goes once per break (§8.4). */
  breakId: number;
  /** The day the last streak ended: the fresh start comes the next Monday or 1st (§8.4). Absent in older pairs. */
  brokeOn?: Day | null;
};

/** What settlement and keeping days tell the pair's people (§12.1): drained by the `Pair` DO. */
export type PairEvent = { kind: "nap" | "winback" | "milestone"; count: number };

export type PairState = {
  id: string;
  /** Sorted by id. */
  people: [PairPerson, PairPerson];
  createdAt: number;
  /** Time integrated up to: the moves map has held since. */
  lastAt: number;
  /** Shared tables in play, and who holds the move there (a member, or null for anyone else). */
  moves: Record<string, { holder: string | null; since: number }>;
  days: Record<Day, DayRow>;
  firstDay: Day;
  lastSettled: Day | null;
  streak: Streak;
  /** Toys, card backs and rugs the pair has. */
  owned: string[];
  gifts: Gift[];
  nextGift: number;
  pity: Pity;
  lastTurnAt: number;
  rng: { seed: Seed; calls: number };
  /** Events not yet handed to the glue. Absent in older pairs. */
  events?: PairEvent[];
};

/** `{code, at, by, holder, over}`: a turn and where the move went, as a room reports it. */
export type TableReport = { code: string; at: number; by: string | null; holder: string | null; over: boolean };

export type WeekDot = { day: Day; state: "kept" | "nap" | "held" | "paused" | "missed" | "live" | "none" };

/** What one person sees of a pair (§13.4). Only today's paws are per person. */
export type StreakView = {
  pair: string;
  partner: { name: string; cat: number };
  count: number;
  /** Today's paws: each lights when that person is in, once someone has played today. */
  me: boolean;
  them: boolean;
  /** Today is kept. */
  kept: boolean;
  naps: number;
  winback: { kept: number } | null;
  pausedUntil: Day | null;
  best: number;
  lifetimeKept: number;
  perfectWeeks: number;
  week: WeekDot[];
  next: number;
  condoStage: number;
  toys: string[];
  todayToy: string | null;
  unlocked: { backs: string[]; rugs: string[] };
  gifts: { id: string; milestone: number; item: string }[];
  myMove: string[];
  theirMove: string[];
  /** Filled in from the players' pounces (§12.4); empty from the pair alone. */
  pounce: PounceView;
};

export const NO_POUNCE: PounceView = { sent: false, resting: false, quiet: false, answer: null, code: null, waiting: null };

const SETTLE_AFTER_MS = 10 * 60_000;
const MAX_NAPS = 2;
const PERFECT_WEEK = 7;
const NAP_MILESTONE = 7;
const MAX_PAUSE_DAYS = 14;
const KEEP_DAYS = 120;
const WEEK = 7;
const WIN_BACK_DAYS = 2;

const emptyRow = (): DayRow => ({ turns: {}, held: {}, gap: {}, state: "live", applied: false, toy: null });

function row(s: PairState, day: Day): DayRow {
  let r = s.days[day];
  if (!r) {
    r = emptyRow();
    s.days[day] = r;
  }
  return r;
}

const isMember = (s: PairState, id: string | null): id is string => s.people.some((p) => p.id === id);
const personOf = (s: PairState, id: string): PairPerson => s.people.find((p) => p.id === id) as PairPerson;
const partnerOf = (s: PairState, id: string): PairPerson => s.people.find((p) => p.id !== id) as PairPerson;

/** A person's zone, else their partner's, else Los Angeles (§6.3). */
function zoneOf(s: PairState, p: PairPerson): string {
  return p.zone ?? partnerOf(s, p.id).zone ?? FALLBACK_ZONE;
}

/** A replayable draw from the pair's seed: the same pair always draws the same toys. */
function rngOf(s: PairState): Rng {
  const r = createRng(s.rng.seed);
  for (let i = 0; i < s.rng.calls; i++) r();
  return () => {
    s.rng.calls += 1;
    return r();
  };
}

const sortPeople = (people: PairPerson[]): [PairPerson, PairPerson] =>
  [...people].sort((x, y) => (x.id < y.id ? -1 : 1)) as [PairPerson, PairPerson];

/** The latest day key either person is in now. */
function latestDay(s: PairState, now: number): Day {
  const [a, b] = s.people.map((p) => dayKey(now, zoneOf(s, p))) as [Day, Day];
  return a > b ? a : b;
}

const dayAfter = (d: Day | null, s: PairState): Day => (d === null ? s.firstDay : addDays(d, 1));

/**
 * A new pair, formed now. The first day was only partly seen, so it can't be
 * a held day. `turnedAt` credits each person's last turn at the table that
 * formed the pair, so that day can be kept at once.
 */
export function newPair(
  id: string,
  people: [PairPerson, PairPerson],
  now: number,
  seed: Seed,
  turnedAt: Record<string, number> = {},
): PairState {
  if (people[0].id === people[1].id) throw new Error("a pair needs two players");
  const s: PairState = {
    id,
    people: sortPeople(people),
    createdAt: now,
    lastAt: now,
    moves: {},
    days: {},
    firstDay: "",
    lastSettled: null,
    streak: {
      count: 0,
      best: 0,
      lifetimeKept: 0,
      perfectWeeks: 0,
      perfectRun: 0,
      naps: 0,
      winback: null,
      pausedFrom: null,
      pausedUntil: null,
      pausedBy: null,
      breakId: 0,
    },
    owned: [],
    gifts: [],
    nextGift: 1,
    pity: { shiny: 0, golden: 0 },
    lastTurnAt: Math.max(now, ...Object.values(turnedAt)),
    rng: { seed, calls: 0 },
  };
  s.firstDay = s.people.map((p) => dayKey(now, zoneOf(s, p))).sort()[0] as Day;
  for (const p of s.people) {
    const today = dayKey(now, zoneOf(s, p));
    for (let d = s.firstDay; d <= today; d = addDays(d, 1)) row(s, d).gap[p.id] = true;
  }
  for (const [pid, t] of Object.entries(turnedAt)) {
    if (!isMember(s, pid)) continue;
    const d = dayKey(t, zoneOf(s, personOf(s, pid)));
    if (d >= s.firstDay) addTurn(s, pid, d);
  }
  return s;
}

function addTurn(s: PairState, pid: string, d: Day): void {
  const r = row(s, d);
  r.turns[pid] = (r.turns[pid] ?? 0) + 1;
}

/**
 * Marks what happened between `lastAt` and `to`, during which the moves map
 * didn't change: who held the move inside their window (04:00 to their
 * cutoff), and windows with no shared table in play.
 */
function integrate(s: PairState, to: number): void {
  const from = s.lastAt;
  if (to <= from) return;
  const empty = Object.keys(s.moves).length === 0;
  for (const p of s.people) {
    const holding = Object.values(s.moves).some((m) => m.holder === p.id);
    if (!holding && !empty) continue;
    const zone = zoneOf(s, p);
    const last = dayKey(to, zone);
    for (let d = dayKey(from, zone); d <= last; d = addDays(d, 1)) {
      if (s.lastSettled !== null && d <= s.lastSettled) continue;
      const cutoff = cutoffAt(d, zone, p.quietStart);
      if (from >= cutoff || to <= dayStart(d, zone)) continue;
      const r = row(s, d);
      if (holding) r.held[p.id] = true;
      else r.gap[p.id] = true;
    }
  }
  s.lastAt = to;
}

/** In for the day (§6.1): took a turn, or never held the move before a cutoff that has passed. */
function isIn(s: PairState, p: PairPerson, d: Day, now: number): boolean {
  const r = s.days[d];
  if ((r?.turns[p.id] ?? 0) > 0) return true;
  return !r?.held[p.id] && now >= cutoffAt(d, zoneOf(s, p), p.quietStart);
}

function bothIn(s: PairState, d: Day, r: DayRow, now: number): boolean {
  const turns = Object.values(r.turns).reduce((a, b) => a + b, 0);
  return turns > 0 && s.people.every((p) => isIn(s, p, d, now));
}

function paused(s: PairState, d: Day): boolean {
  const { pausedFrom, pausedUntil } = s.streak;
  return pausedFrom !== null && pausedUntil !== null && d >= pausedFrom && d <= pausedUntil;
}

function settleAt(s: PairState, d: Day): number {
  return Math.max(...s.people.map((p) => dayEnd(d, zoneOf(s, p)))) + SETTLE_AFTER_MS;
}

const emit = (s: PairState, e: PairEvent): void => {
  (s.events ??= []).push(e);
};

/** Hands over and forgets the events queued since the last call. */
export function drainEvents(s: PairState): PairEvent[] {
  const out = s.events ?? [];
  s.events = [];
  return out;
}

const own = (s: PairState, item: string): void => {
  if (item !== CONFETTI && !s.owned.includes(item)) s.owned.push(item);
};

/** Count, toy, milestone, naps and win-back progress for a kept day (§6.1, §8, §9). */
function applyKept(s: PairState, d: Day): void {
  const r = row(s, d);
  const st = s.streak;
  const rng = rngOf(s);
  r.state = "kept";
  r.applied = true;
  st.count += 1;
  st.best = Math.max(st.best, st.count);
  st.lifetimeKept += 1;
  st.perfectRun += 1;
  if (st.perfectRun === PERFECT_WEEK) {
    st.perfectWeeks += 1;
    st.perfectRun = 0;
    st.naps = Math.min(MAX_NAPS, st.naps + 1);
  }
  const drawn = drawToy(s.owned, s.pity, rng);
  s.pity = drawn.pity;
  r.toy = drawn.toy;
  own(s, drawn.toy);
  if (isMilestone(st.count)) {
    const item = giftItem(st.count, s.owned, rng);
    s.gifts.push({ id: `g${s.nextGift}`, milestone: st.count, item, openedBy: [] });
    s.nextGift += 1;
    own(s, item);
    emit(s, { kind: "milestone", count: st.count });
    if (st.count === NAP_MILESTONE) st.naps = Math.min(MAX_NAPS, st.naps + 1);
  }
  if (TOYS.every((t) => s.owned.includes(t.id))) own(s, FULL_SET_BACK);
  if (st.winback) {
    st.winback.kept += 1;
    if (st.winback.kept === WIN_BACK_DAYS) {
      row(s, st.winback.missedDay).state = "nap";
      st.winback = null;
    }
  }
}

/** The first rule that applies sets a due day's outcome (§13.3). */
function finalize(s: PairState, d: Day, now: number): void {
  const r = row(s, d);
  const st = s.streak;
  if (r.applied) r.state = "kept";
  else if (paused(s, d)) r.state = "paused";
  else if (bothIn(s, d, r, now)) applyKept(s, d);
  else if (heldDay(s, r)) r.state = "held";
  else if (st.count > 0 && st.naps > 0) {
    r.state = "nap";
    st.naps -= 1;
    st.perfectRun = 0;
    emit(s, { kind: "nap", count: st.count });
  } else if (st.count > 0 && !st.winback) {
    r.state = "winback";
    st.winback = { missedDay: d, kept: 0 };
    st.perfectRun = 0;
    emit(s, { kind: "winback", count: st.count });
  } else {
    r.state = "missed";
    if (st.count > 0) {
      st.count = 0;
      st.winback = null;
      st.breakId += 1;
      st.brokeOn = d;
    }
    st.perfectRun = 0;
  }
  s.lastSettled = d;
}

/** Nobody played, nobody held the move before their cutoff, and a shared table was in play throughout. */
function heldDay(s: PairState, r: DayRow): boolean {
  return s.people.every((p) => !r.turns[p.id] && !r.held[p.id] && !r.gap[p.id]);
}

/**
 * Brings the pair up to `now`: marks the time since the last call, settles
 * every due day in order, and keeps a live day as soon as both are in,
 * provided every earlier day is settled or kept (so effects run in order).
 */
export function advance(s: PairState, now: number): void {
  integrate(s, now);
  const latest = latestDay(s, now);
  let ordered = true;
  for (let d = dayAfter(s.lastSettled, s); d <= latest; d = addDays(d, 1)) {
    if (ordered && settleAt(s, d) <= now) {
      finalize(s, d, now);
      continue;
    }
    const r = s.days[d];
    if (ordered && r && !r.applied && !paused(s, d) && bothIn(s, d, r, now)) applyKept(s, d);
    ordered &&= r?.applied === true;
  }
  for (const d of Object.keys(s.days)) {
    if (daysBetween(d, latest) >= KEEP_DAYS && s.lastSettled !== null && d <= s.lastSettled) delete s.days[d];
  }
}

/** A room's report: a member's turn counts on their own day, and the table's move is updated. */
export function report(s: PairState, r: TableReport, now: number): void {
  advance(s, now);
  if (isMember(s, r.by)) {
    const d = dayKey(r.at, zoneOf(s, personOf(s, r.by)));
    if (d >= s.firstDay && (s.lastSettled === null || d > s.lastSettled)) addTurn(s, r.by, d);
    s.lastTurnAt = Math.max(s.lastTurnAt, r.at);
  }
  if (r.over) delete s.moves[r.code];
  else s.moves[r.code] = { holder: isMember(s, r.holder) ? r.holder : null, since: now };
  advance(s, now);
}

/** When the pair next needs waking: the next settlement, while there's a streak to keep. */
export function nextSettleAt(s: PairState): number | null {
  if (s.streak.count === 0) return null;
  return settleAt(s, dayAfter(s.lastSettled, s));
}

/**
 * The pair's next alarm: the next settlement, or the moment its oldest day
 * row passes 120 days (§14 retention), so an idle pair still forgets.
 */
export function nextWakeAt(s: PairState): number | null {
  const settle = nextSettleAt(s);
  const oldest = Object.keys(s.days).sort()[0];
  const prune = oldest === undefined ? null : Date.parse(`${addDays(oldest, KEEP_DAYS + 1)}T00:00:00Z`);
  const times = [settle, prune].filter((t): t is number => t !== null);
  return times.length === 0 ? null : Math.min(...times);
}

const todayOf = (s: PairState, id: string, now: number): Day => dayKey(now, zoneOf(s, personOf(s, id)));

/**
 * Pauses the pair (§8.3) for 1–14 days from today, or from tomorrow when
 * today is already kept. Pausing again extends, never past 14 days from today.
 */
export function pause(s: PairState, by: string, days: number, now: number): boolean {
  if (!isMember(s, by) || !Number.isInteger(days) || days < 1 || days > MAX_PAUSE_DAYS) return false;
  // Settle first: whether the old pause still has unsettled days depends on it.
  advance(s, now);
  const st = s.streak;
  const today = todayOf(s, by, now);
  const start = s.days[today]?.applied ? addDays(today, 1) : today;
  const until = [addDays(start, days - 1), addDays(today, MAX_PAUSE_DAYS - 1)].sort()[0] as Day;
  // A pause is still on while any of its days is today or later, or hasn't settled yet.
  const active =
    st.pausedUntil !== null && (st.pausedUntil >= today || s.lastSettled === null || st.pausedUntil > s.lastSettled);
  st.pausedFrom = active && (st.pausedFrom as Day) < start ? st.pausedFrom : start;
  st.pausedUntil = active && (st.pausedUntil as Day) > until ? st.pausedUntil : until;
  st.pausedBy = by;
  return true;
}

/** Ends a pause early: today counts again, unless it's past the person's evening cutoff. */
export function unpause(s: PairState, by: string, now: number): void {
  const st = s.streak;
  if (!isMember(s, by)) return;
  const today = todayOf(s, by, now);
  if (st.pausedUntil === null || st.pausedUntil < today) return;
  const p = personOf(s, by);
  const until = now >= cutoffAt(today, zoneOf(s, p), p.quietStart) ? today : addDays(today, -1);
  if (until < (st.pausedFrom as Day)) {
    st.pausedFrom = null;
    st.pausedUntil = null;
    st.pausedBy = null;
  } else st.pausedUntil = until;
}

/** Unwraps a gift for one person. False when there's no such gift for them. */
export function openGift(s: PairState, by: string, giftId: string): boolean {
  const gift = s.gifts.find((g) => g.id === giftId);
  if (!gift || !isMember(s, by)) return false;
  if (!gift.openedBy.includes(by)) gift.openedBy.push(by);
  return true;
}

/** The card backs and rugs a person may put on a table from this pair: defaults, plus what they've unwrapped. */
export function unlockedFor(s: PairState, playerId: string): { backs: string[]; rugs: string[] } {
  const wrapped = new Set(s.gifts.filter((g) => !g.openedBy.includes(playerId)).map((g) => g.item));
  const mine = isMember(s, playerId) ? s.owned.filter((id) => !wrapped.has(id)) : [];
  return {
    backs: [DEFAULT_BACK, ...mine.filter(isBack)],
    rugs: [DEFAULT_RUG, ...mine.filter(isRug)],
  };
}

function weekDot(s: PairState, d: Day): WeekDot["state"] {
  if (d < s.firstDay) return "none";
  const r = s.days[d];
  if (s.lastSettled === null || d > s.lastSettled) return r?.applied ? "kept" : "live";
  // Settled days always have a row (finalize makes one); the week never reaches pruned ones.
  const { state } = r as DayRow;
  return state === "winback" || state === "live" ? "missed" : state;
}

/** What `playerId` sees now. Brings the pair up to `now` first. */
export function view(s: PairState, playerId: string, now: number): StreakView {
  advance(s, now);
  const me = personOf(s, playerId);
  const partner = partnerOf(s, playerId);
  const today = todayOf(s, playerId, now);
  const st = s.streak;
  const moves = Object.entries(s.moves);
  const row = s.days[today];
  // Waiting lights a paw only once someone has played: two lit paws on a day nobody played would read as kept.
  const played = Object.values(row?.turns ?? {}).some((n) => n > 0);
  return {
    pair: s.id,
    partner: { name: partner.name, cat: partner.cat },
    count: st.count,
    me: played && isIn(s, me, today, now),
    them: played && isIn(s, partner, today, now),
    kept: row?.applied === true,
    naps: st.naps,
    winback: st.winback ? { kept: st.winback.kept } : null,
    pausedUntil: st.pausedUntil !== null && st.pausedUntil >= today ? st.pausedUntil : null,
    best: st.best,
    lifetimeKept: st.lifetimeKept,
    perfectWeeks: st.perfectWeeks,
    week: Array.from({ length: WEEK }, (_, i) => {
      const d = addDays(today, i - (WEEK - 1));
      return { day: d, state: weekDot(s, d) };
    }),
    next: nextMilestone(st.count),
    condoStage: condoStage(st.lifetimeKept),
    toys: s.owned.filter((id) => id.startsWith("toy-")),
    todayToy: s.days[today]?.toy ?? null,
    unlocked: unlockedFor(s, playerId),
    gifts: s.gifts
      .filter((g) => !g.openedBy.includes(playerId))
      .map((g) => ({ id: g.id, milestone: g.milestone, item: g.item })),
    myMove: moves.filter(([, m]) => m.holder === me.id).map(([code]) => code),
    theirMove: moves.filter(([, m]) => m.holder === partner.id).map(([code]) => code),
    pounce: NO_POUNCE,
  };
}

/** What reminders need from a pair (§12.1), for the server only: never sent to anyone as is. */
export type Facts = {
  view: StreakView;
  /** In for today, by a turn or the late move pass (`view.me` waits for someone to have played). */
  in: boolean;
  paused: boolean;
  breakId: number;
  brokeOn: Day | null;
  lastTurnAt: number;
  /** The shared tables in play. */
  tables: string[];
};

export function facts(s: PairState, playerId: string, now: number): Facts {
  const v = view(s, playerId, now);
  const today = todayOf(s, playerId, now);
  return {
    view: v,
    in: isIn(s, personOf(s, playerId), today, now),
    paused: paused(s, today),
    breakId: s.streak.breakId,
    brokeOn: s.streak.brokeOn ?? null,
    lastTurnAt: s.lastTurnAt,
    tables: Object.keys(s.moves),
  };
}

/** A person's new name, cat, zone or quiet hours, from now on. */
export function setPerson(s: PairState, p: PairPerson, now: number): void {
  if (!isMember(s, p.id)) return;
  integrate(s, now);
  s.people = sortPeople(s.people.map((q) => (q.id === p.id ? p : q)));
}

function renameKeys<T>(rec: Record<string, T>, from: string, to: string): void {
  if (from in rec) {
    rec[to] = rec[from] as T;
    delete rec[from];
  }
}

/** After an account merge (§13.1): every trace of `from` now means `to`. */
export function repoint(s: PairState, from: string, to: string): void {
  if (!isMember(s, from)) return;
  if (isMember(s, to)) throw new Error("a pair needs two players");
  s.people = sortPeople(s.people.map((p) => (p.id === from ? { ...p, id: to } : p)));
  for (const r of Object.values(s.days)) {
    renameKeys(r.turns, from, to);
    renameKeys(r.held, from, to);
    renameKeys(r.gap, from, to);
  }
  for (const m of Object.values(s.moves)) if (m.holder === from) m.holder = to;
  for (const g of s.gifts) g.openedBy = g.openedBy.map((id) => (id === from ? to : id));
  if (s.streak.pausedBy === from) s.streak.pausedBy = to;
}

/**
 * Two pairs of the same two people, after a merge (§13.1): the longer current
 * streak wins; lifetime counters take the maximum; rewards are unioned; naps
 * take the maximum, capped at 2. `keep`'s id survives.
 */
export function mergeStates(keep: PairState, other: PairState): PairState {
  const [win, lose] = other.streak.count > keep.streak.count ? [other, keep] : [keep, other];
  const merged: PairState = structuredClone(win);
  merged.id = keep.id;
  const st = merged.streak;
  st.best = Math.max(win.streak.best, lose.streak.best);
  st.lifetimeKept = Math.max(win.streak.lifetimeKept, lose.streak.lifetimeKept);
  st.perfectWeeks = Math.max(win.streak.perfectWeeks, lose.streak.perfectWeeks);
  st.naps = Math.min(MAX_NAPS, Math.max(win.streak.naps, lose.streak.naps));
  for (const item of lose.owned) own(merged, item);
  for (const [code, m] of Object.entries(lose.moves)) merged.moves[code] ??= { ...m };
  for (const g of lose.gifts) {
    merged.gifts.push({ ...g, id: `g${merged.nextGift}`, openedBy: [...g.openedBy] });
    merged.nextGift += 1;
  }
  merged.gifts = merged.gifts.filter((g) => !merged.people.every((p) => g.openedBy.includes(p.id)));
  merged.lastTurnAt = Math.max(win.lastTurnAt, lose.lastTurnAt);
  return merged;
}
