import type { DayLevel } from "./days";
import type { Rng, Seed } from "../rules/rng";
import type { Day } from "../streaks/clock";

/**
 * The contract every daily game implements (server plan Task 3). Each game session writes
 * `src/daily/<game>/module.ts` exporting `const <game>: DailyModule<P, S, M>` and adds one line to
 * `games.ts`. The server referees every run with it (`run-core.ts`): it makes the puzzle, checks
 * each move, and works out the result. No route ever takes a result from a client (spec §3).
 */
export type DailyGameId = "nine-lives" | "box-fort" | "sniff" | "cat-nap" | "test";
export type Outcome = "solved" | "missed" | "gaveUp" | "closed" | "done"; // "done": Box Fort's ending
export type DailyResult = {
  game: DailyGameId; date: Day; number: number; outcome: Outcome;
  timeMs: number; hints: number; tooFast: boolean;
  guesses?: number;   // Sniff
  points?: number;    // Box Fort
  progress: number;   // 0..1, how far the run got by its game's fair measure (spec §6, "Ranking"); 1 when solved
  /**
   * `progress` as a whole percent, rounded down: what the boards show for a run that didn't
   * finish. Every result made from 2026-11-26 has it; one stored before has only `progress`.
   */
  percent?: number;
};
export type Applied<S> =
  | { ok: true; state: S; reveal?: unknown; end?: "solved" | "missed" | "done" }
  | { ok: false; reason: "illegal" | "too_soon" | "over" };
export interface DailyModule<P = unknown, S = unknown, M = unknown> {
  id: DailyGameId;
  make(rng: Rng, level: DayLevel, day: { date: Day; key: Seed }): P; // server only: the whole puzzle, solution included; key: cycleKey, the same every day
  publicPuzzle(p: P): unknown;                  // what start returns: never the solution, answer or future sets
  /** The run's first state. `rules`: what the start asked for (`{ "rules": ... }`); a game ignores rules it doesn't know. */
  init(p: P, rules?: string): S;
  parseMove(raw: unknown): M | null;            // exact shape or null
  apply(p: P, s: S, m: M, msSinceStart: number): Applied<S>;
  hint(p: P, s: S): Applied<S> | null;          // null: this game has no hints
  hintMs?(s: S): number;                        // what one hint adds to the time; unset: HINT_PENALTY_MS
  progress(p: P, s: S): number;                 // 0..1, spoiler-free
  publicState(p: P, s: S): unknown;             // what a resuming client and a watching TV get
  result(p: P, s: S, outcome: Outcome, timeMs: number, hints: number): Omit<DailyResult, "game" | "date" | "number" | "tooFast" | "percent">;
  compare(a: DailyResult, b: DailyResult): number; // < 0: a ranks above b; the board uses it between finished runs only (`rankGame`)
  floorMs: Record<DayLevel, number>;            // faster than this: tooFast
  minMoveGapMs: number;                         // moves closer than this are "too_soon"
}
