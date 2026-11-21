/**
 * A local copy of the daily game contract (server plan Task 3, `src/daily/module.ts`) until the
 * server core merges. Phase B deletes this file and imports `../module` and `../days` instead.
 *
 * One addition, approved by the daily-games lead: `make` gets the puzzle's day with a per-game
 * secret key that doesn't change by date (`cycleKey(secret, game)` in `src/daily/seed.ts`,
 * server-only), so a game can avoid repeats across days (Sniff's answer cycle).
 */
import type { Rng, Seed } from "../../rules/rng";
import type { Day } from "../../streaks/clock";

export type { Day };
export type DayLevel = 1 | 2 | 3 | 4 | 5 | 6 | 7;

export type DailyGameId = "nine-lives" | "box-fort" | "sniff" | "cat-nap" | "test";
export type Outcome = "solved" | "missed" | "gaveUp" | "closed" | "done";
export type DailyResult = {
  game: DailyGameId;
  date: Day;
  number: number;
  outcome: Outcome;
  timeMs: number;
  hints: number;
  tooFast: boolean;
  guesses?: number;
  points?: number;
  progress: number;
};
export type Applied<S> =
  | { ok: true; state: S; reveal?: unknown; end?: "solved" | "missed" | "done" }
  | { ok: false; reason: "illegal" | "too_soon" | "over" };

/** The puzzle's day: the date, and the game's secret cycle key (the same every day). */
export type PuzzleDay = { date: Day; key: Seed };

export interface DailyModule<P = unknown, S = unknown, M = unknown> {
  id: DailyGameId;
  make(rng: Rng, level: DayLevel, day: PuzzleDay): P;
  publicPuzzle(p: P): unknown;
  init(p: P): S;
  parseMove(raw: unknown): M | null;
  apply(p: P, s: S, m: M, msSinceStart: number): Applied<S>;
  hint(p: P, s: S): Applied<S> | null;
  progress(p: P, s: S): number;
  publicState(p: P, s: S): unknown;
  result(p: P, s: S, outcome: Outcome, timeMs: number, hints: number): Omit<DailyResult, "game" | "date" | "number" | "tooFast">;
  compare(a: DailyResult, b: DailyResult): number;
  floorMs: Record<DayLevel, number>;
  minMoveGapMs: number;
}
