/**
 * Box Fort as a Daily Dish game (spec §1 "Box Fort"). The server keeps the whole day's sets and
 * deals each one only after the three pieces before it are placed, so nobody can plan ahead.
 * Every run ends "done", by running out of room or by placing the last set, and ranks by points.
 */
import { make, type BoxFortPuzzle } from "./maker";
import { deal, SIZE, start, step, type BoxFortState } from "./rules";

import type { DailyModule, DayLevel } from "./contract";
import type { Place } from "./greedy";
import type { Piece } from "./pieces";

export type { Place } from "./greedy";

/** What `start` returns as the puzzle: the rug, how many sets the day has, and the first set. */
export type BoxFortPublicPuzzle = { rug: number[]; sets: number; pieces: Piece[] };

/** What a resuming client and a watching TV get: the run so far and the set in play. */
export type BoxFortPublicState = BoxFortState & { pieces: Piece[] };

/** A set dealt after the one before it was placed. */
export type BoxFortReveal = { set: number; pieces: Piece[] };

const FLOOR_MS = 20_000;
const MOVE_KEYS = ["col", "k", "row", "slot"];

const isIndex = (v: unknown, below: number): v is number => Number.isInteger(v) && (v as number) >= 0 && (v as number) < below;

function parseMove(raw: unknown): Place | null {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return null;
  const m = raw as Record<string, unknown>;
  if (Object.keys(m).sort().join() !== MOVE_KEYS.join() || m.k !== "place") return null;
  if (!isIndex(m.slot, 3) || !isIndex(m.row, SIZE) || !isIndex(m.col, SIZE)) return null;
  return { k: "place", slot: m.slot, row: m.row, col: m.col };
}

function progress(_: BoxFortPuzzle, s: BoxFortState): number {
  return (s.set + s.placed.filter(Boolean).length / 3) / s.sets;
}

export const boxFort: DailyModule<BoxFortPuzzle, BoxFortState, Place> = {
  id: "box-fort",
  make,
  publicPuzzle: (p): BoxFortPublicPuzzle => ({ rug: p.rug, sets: p.sets.length, pieces: p.sets[0] as Piece[] }),
  init: (p) => start(p.rug, p.sets.length),
  parseMove,
  apply(p, s, m) {
    if (s.over !== null) return { ok: false, reason: "over" };
    const out = step(s, p.sets[s.set] as Piece[], m.slot, m.row, m.col);
    if (out === null) return { ok: false, reason: "illegal" };
    let state = out.state;
    let reveal: BoxFortReveal | undefined;
    if (out.setDone) {
      const next = p.sets[s.set + 1] ?? null;
      state = deal(state, next);
      if (next !== null) reveal = { set: s.set + 1, pieces: next };
    }
    return {
      ok: true,
      state,
      ...(reveal ? { reveal } : {}),
      ...(state.over !== null ? { end: "done" as const } : {}),
    };
  },
  hint: () => null,
  progress,
  publicState: (p, s): BoxFortPublicState => ({ ...s, pieces: p.sets[s.set] as Piece[] }),
  result: (p, s, outcome, timeMs, hints) => ({ outcome, timeMs, hints, points: s.points, progress: progress(p, s) }),
  compare: (a, b) => (b.points ?? 0) - (a.points ?? 0) || a.timeMs - b.timeMs,
  floorMs: Object.fromEntries(([1, 2, 3, 4, 5, 6, 7] as DayLevel[]).map((l) => [l, FLOOR_MS])) as Record<DayLevel, number>,
  // Moves in one batch arrive together (run-core), so a gap would refuse a batch's second
  // placement. The per-run move limit and the floor keep bots out instead.
  minMoveGapMs: 0,
};
