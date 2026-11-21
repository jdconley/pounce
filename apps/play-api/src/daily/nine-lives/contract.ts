/**
 * A verbatim copy of the `DailyModule` contract from the server core's plan (Task 3,
 * `src/daily/module.ts`), kept here only until that file lands on main. Then every import
 * switches to `../module` and this file goes.
 */
import type { Rng, Seed } from "../../rules/rng";
import type { Day } from "../../streaks/clock";

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
  make(rng: Rng, level: DayLevel, day: { date: Day; key: Seed }): P; // server only: the whole puzzle, solution included; key: cycleKey, the same every day
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
