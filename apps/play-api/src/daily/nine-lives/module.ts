/**
 * Nine Lives as a Daily Dish game (server plan Task 3). The server holds the whole puzzle; a client
 * gets only the givens, sends one cell at a time, and learns a cell's answer only from a hint.
 *
 * Two sets of rules, fixed at a run's first start (spec, "Nine Lives: lives and hints"):
 * - **The first rules** (no `rules`: every app before 2026-11-26): any digit anywhere, changed and
 *   cleared at will; unlimited hints at 30 seconds each.
 * - **`"lives"`:** each set is checked against the solution as it comes. A right digit locks; a
 *   wrong one costs one of three lives and never reaches the board, and the third ends the run
 *   `missed`. Three hints, free, never a life.
 */
import { HINT_PENALTY_MS } from "../run-core";

import {
  applyMove,
  applyReveal,
  N,
  parseMove,
  peers,
  progressOf,
  type NineLivesMove,
  type NineLivesState,
} from "./grid";
import { makePuzzle, type NineLivesPuzzle } from "./make";
import { POP } from "./solve";


import type { DayLevel } from "../days";
import type { Applied, DailyModule, DailyResult } from "../module";

/** The rules a start asks for to play with lives. */
export const LIVES_RULES = "lives";
/** Lives a run starts with, under the `"lives"` rules. */
export const LIVES = 3;
/** Hints a run may use, under the `"lives"` rules. */
export const HINTS = 3;

const withLives = (s: NineLivesState): boolean => s.lives !== undefined;

/** Faster than this is kept but marked too fast (spec §3). Builder's numbers, from the levels. */
export const FLOOR_MS: Record<DayLevel, number> = {
  1: 45_000,
  2: 55_000,
  3: 65_000,
  4: 75_000,
  5: 90_000,
  6: 105_000,
  7: 80_000,
};

const solved = (p: NineLivesPuzzle, s: NineLivesState): boolean => s.cells.every((d, i) => d === p.solution[i]);

const ended = (p: NineLivesPuzzle, state: NineLivesState, reveal?: { i: number; d: number }): Applied<NineLivesState> => {
  const base = reveal ? { ok: true as const, state, reveal } : { ok: true as const, state };
  return solved(p, state) ? { ...base, end: "solved" } : base;
};

/** How many digits cell `i` could still take, given every digit on the board. */
function candidates(cells: number[], i: number): number {
  let used = 0;
  for (const p of peers(i)) if (cells[p] !== 0) used |= 1 << (cells[p]! - 1);
  return POP[0x1ff & ~used]!;
}

/**
 * The cell a hint fills: the open cell with the fewest digits left (the one a player is most
 * likely stuck near), lowest index first; a cell with none left (a mistake nearby) comes last.
 * On a full grid, the first wrong cell.
 */
function hintCell(p: NineLivesPuzzle, s: NineLivesState): number {
  let best = -1;
  let bestCount = 99;
  for (let i = 0; i < N; i++) {
    if (s.cells[i] !== 0) continue;
    const n = candidates(s.cells, i) || 10;
    if (n < bestCount) {
      best = i;
      bestCount = n;
    }
  }
  return best >= 0 ? best : s.cells.findIndex((d, i) => d !== p.solution[i]);
}

/**
 * A move under the `"lives"` rules: a set in an open cell only, checked on entry. A right digit is
 * placed and locks; a wrong one costs a life, is remembered, and reveals itself (with the solution
 * when it was the last life). `clear` is illegal: the board never holds a wrong digit to clear.
 */
function applyWithLives(p: NineLivesPuzzle, s: NineLivesState, m: NineLivesMove): Applied<NineLivesState> {
  if ((s.lives as number) <= 0) return { ok: false, reason: "over" };
  if (m.k !== "set" || p.givens[m.i] !== 0 || s.cells[m.i] !== 0) return { ok: false, reason: "illegal" };
  if (m.d === p.solution[m.i]) {
    const next = applyMove(p.givens, s, m);
    return next ? ended(p, next) : { ok: false, reason: "illegal" };
  }
  const lives = (s.lives as number) - 1;
  const state: NineLivesState = { ...s, lives, wrong: [...(s.wrong ?? []), { i: m.i, d: m.d }] };
  const reveal = { k: "wrong", i: m.i, d: m.d, lives, ...(lives === 0 ? { solution: [...p.solution] } : {}) };
  return lives === 0 ? { ok: true, state, reveal, end: "missed" } : { ok: true, state, reveal };
}

/**
 * How far an unfinished run got, by the fair measure (spec §6, "Ranking"): the cells the player
 * filled right, out of the cells that started empty. A hinted cell doesn't count, and neither
 * does a wrong number. Only ever worked out for a result: during play it would say which numbers
 * are right, so live progress stays `progressOf`, cells filled.
 */
function earned(p: NineLivesPuzzle, s: NineLivesState): number {
  let open = 0;
  let right = 0;
  for (let i = 0; i < N; i++) {
    if (p.givens[i] !== 0) continue;
    open++;
    if (s.cells[i] === p.solution[i] && !s.hinted.includes(i)) right++;
  }
  return open === 0 ? 1 : right / open;
}

export const nineLives: DailyModule<NineLivesPuzzle, NineLivesState, NineLivesMove> = {
  id: "nine-lives",
  make: makePuzzle,
  publicPuzzle: (p) => ({ givens: [...p.givens] }),
  init: (p, rules) => (rules === LIVES_RULES ? { cells: [...p.givens], hinted: [], lives: LIVES, wrong: [] } : { cells: [...p.givens], hinted: [] }),
  parseMove,
  apply(p, s, m) {
    if (solved(p, s)) return { ok: false, reason: "over" };
    if (withLives(s)) return applyWithLives(p, s, m);
    const next = applyMove(p.givens, s, m);
    return next ? ended(p, next) : { ok: false, reason: "illegal" };
  },
  hint(p, s) {
    if (solved(p, s) || (withLives(s) && (s.lives as number) <= 0)) return { ok: false, reason: "over" };
    if (withLives(s) && s.hinted.length >= HINTS) return { ok: false, reason: "illegal" };
    const i = hintCell(p, s);
    const reveal = { i, d: p.solution[i]! };
    return ended(p, applyReveal(s, reveal), reveal);
  },
  hintMs: (s) => (withLives(s) ? 0 : HINT_PENALTY_MS),
  progress: (p, s) => progressOf(p.givens, s.cells),
  publicState(p, s) {
    if (!withLives(s)) return { cells: [...s.cells], hinted: [...s.hinted] };
    const lives = s.lives as number;
    return {
      cells: [...s.cells],
      hinted: [...s.hinted],
      rules: LIVES_RULES,
      lives,
      hintsLeft: Math.max(0, HINTS - s.hinted.length),
      wrong: (s.wrong ?? []).map((w) => ({ ...w })),
      // Only once the run ended out of lives: the solution, to show kindly.
      ...(lives === 0 ? { solution: [...p.solution] } : {}),
    };
  },
  result: (p, s, outcome, timeMs, hints) => ({
    outcome,
    timeMs,
    hints,
    progress: outcome === "solved" ? 1 : earned(p, s),
  }),
  compare(a: DailyResult, b: DailyResult): number {
    const aSolved = a.outcome === "solved";
    if (aSolved !== (b.outcome === "solved")) return aSolved ? -1 : 1;
    if (aSolved) return a.timeMs - b.timeMs || a.hints - b.hints;
    return b.progress - a.progress || a.timeMs - b.timeMs;
  },
  floorMs: FLOOR_MS,
  minMoveGapMs: 100,
};
