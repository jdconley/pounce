/**
 * A local copy of the Daily Dish's game contract (docs/superpowers/plans/2026-11-20-daily-games-1-server.md,
 * Task 3), so Box Fort builds before the server core merges. Once `src/daily/module.ts` and
 * `src/daily/days.ts` are on main, this file goes and the imports point there.
 */
import type { Rng } from "../../rules/rng";

export type Day = string;
export type DayLevel = 1 | 2 | 3 | 4 | 5 | 6 | 7;

export type DailyGameId = "nine-lives" | "box-fort" | "sniff" | "cat-nap" | "test";
export type Outcome = "solved" | "missed" | "gaveUp" | "closed" | "done"; // "done": Box Fort's ending
export type DailyResult = {
  game: DailyGameId;
  date: Day;
  number: number;
  outcome: Outcome;
  timeMs: number;
  hints: number;
  tooFast: boolean;
  guesses?: number; // Sniff
  points?: number; // Box Fort
  progress: number; // 0..1, how far an unsolved run got
};
export type Applied<S> =
  | { ok: true; state: S; reveal?: unknown; end?: "solved" | "missed" | "done" }
  | { ok: false; reason: "illegal" | "too_soon" | "over" };
export interface DailyModule<P = unknown, S = unknown, M = unknown> {
  id: DailyGameId;
  make(rng: Rng, level: DayLevel): P; // server only: the whole puzzle, solution included
  publicPuzzle(p: P): unknown; // what start returns: never the solution, answer or future sets
  init(p: P): S;
  parseMove(raw: unknown): M | null; // exact shape or null
  apply(p: P, s: S, m: M, msSinceStart: number): Applied<S>;
  hint(p: P, s: S): Applied<S> | null; // null: this game has no hints
  progress(p: P, s: S): number; // 0..1, spoiler-free
  publicState(p: P, s: S): unknown; // what a resuming client and a watching TV get
  result(
    p: P,
    s: S,
    outcome: Outcome,
    timeMs: number,
    hints: number,
  ): Omit<DailyResult, "game" | "date" | "number" | "tooFast">;
  compare(a: DailyResult, b: DailyResult): number; // < 0: a ranks above b
  floorMs: Record<DayLevel, number>; // faster than this: tooFast
  minMoveGapMs: number; // moves closer than this are "too_soon"
}
