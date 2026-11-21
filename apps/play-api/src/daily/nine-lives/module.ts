/**
 * Nine Lives as a Daily Dish game (server plan Task 3). The server holds the whole puzzle; a client
 * gets only the givens, sends one cell at a time, and learns a cell's answer only from a hint.
 */
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

import type { Applied, DailyModule, DailyResult, DayLevel } from "./contract";

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

export const nineLives: DailyModule<NineLivesPuzzle, NineLivesState, NineLivesMove> = {
  id: "nine-lives",
  make: makePuzzle,
  publicPuzzle: (p) => ({ givens: [...p.givens] }),
  init: (p) => ({ cells: [...p.givens], hinted: [] }),
  parseMove,
  apply(p, s, m) {
    if (solved(p, s)) return { ok: false, reason: "over" };
    const next = applyMove(p.givens, s, m);
    return next ? ended(p, next) : { ok: false, reason: "illegal" };
  },
  hint(p, s) {
    if (solved(p, s)) return { ok: false, reason: "over" };
    const i = hintCell(p, s);
    const reveal = { i, d: p.solution[i]! };
    return ended(p, applyReveal(s, reveal), reveal);
  },
  progress: (p, s) => progressOf(p.givens, s.cells),
  publicState: (_p, s) => ({ cells: [...s.cells], hinted: [...s.hinted] }),
  result: (p, s, outcome, timeMs, hints) => ({
    outcome,
    timeMs,
    hints,
    progress: outcome === "solved" ? 1 : progressOf(p.givens, s.cells),
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
