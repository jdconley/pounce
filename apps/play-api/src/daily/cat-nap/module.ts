/**
 * Cat Nap as a Daily Dish game (`DailyModule`, server plan Task 3). The server makes the quilt,
 * referees every mark, and ends the run "solved" only when the cats are exactly its solution. A
 * client sees the patches, never the solution; a hint is the only way the server tells it where a
 * cat goes.
 */
import { makeNap, type NapPuzzle } from "./maker";
import {
  applyHint,
  applyMark,
  catsPlaced,
  emptyState,
  hintTarget,
  parseNapMove,
  type NapMove,
  type NapState,
  type Quilt,
} from "./rules";

import type { DailyModule, DailyResult } from "./contract";

const solvedBy = (p: NapPuzzle, s: NapState): boolean => {
  const cats = s.cells.flatMap((m, i) => (m === 2 ? [i] : []));
  return cats.length === p.n && p.solution.every((c, r) => s.cells[r * p.n + c] === 2);
};

const unsolved = (r: DailyResult): number => (r.outcome === "solved" ? 0 : 1);

export const catNap: DailyModule<NapPuzzle, NapState, NapMove> = {
  id: "cat-nap",
  make: (rng, level) => makeNap(rng, level),
  publicPuzzle: (p): Quilt => ({ n: p.n, patches: p.patches }),
  init: (p) => emptyState(p),
  parseMove: parseNapMove,
  apply(p, s, m) {
    const state = applyMark(p, s, m);
    if (!state) return { ok: false, reason: "illegal" };
    return solvedBy(p, state) ? { ok: true, state, end: "solved" } : { ok: true, state };
  },
  hint(p, s) {
    const cell = hintTarget(p, s, p.solution);
    if (cell === null) return { ok: false, reason: "over" };
    const state = applyHint(p, s, cell);
    return solvedBy(p, state) ? { ok: true, state, reveal: { cell }, end: "solved" } : { ok: true, state, reveal: { cell } };
  },
  progress: (p, s) => catsPlaced(p, s) / p.n,
  publicState: (_p, s) => s,
  result: (p, s, outcome, timeMs, hints) => ({ outcome, timeMs, hints, progress: catsPlaced(p, s) / p.n }),
  compare(a, b) {
    return unsolved(a) - unsolved(b) || (unsolved(a) ? b.progress - a.progress : 0) || a.timeMs - b.timeMs;
  },
  /** The fastest a strong player could tap out each size: faster runs are kept but marked. */
  floorMs: { 1: 6000, 2: 9000, 3: 12000, 4: 12000, 5: 16000, 6: 16000, 7: 20000 },
  /** A batch's moves arrive together; the floors guard speed instead. */
  minMoveGapMs: 0,
};
