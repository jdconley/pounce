/**
 * The daily puzzle maker (spec §1, §2). Server only: it runs once per date, inside `DailyPuzzle`.
 *
 * A random full grid, then cells taken away in mirrored pairs (i and 80 - i) in random order, each
 * kept away only while the logic solver can still finish the grid using techniques no harder than
 * the day's tier. That keeps the puzzle at one solution and at or under the tier. Then the
 * puzzle's own grade must equal the tier exactly; if not, try again, up to `MAX_TRIES` times, then
 * take a puzzle from the fallback pool. So a date's puzzle always comes, at its level, in a bounded
 * time, and the same seed always gives the same one.
 */
import { shuffle, type Rng } from "../../rules/rng";

import { FALLBACK } from "./fallback";
import { grade, type Tier } from "./grade";
import { N, type Cells } from "./grid";
import { randomSolution, solveOne } from "./solve";

import type { DayLevel } from "../days";

/**
 * Each weekday's hardest technique and how many givens it keeps (spec §2). Sunday is Thursday's
 * tier with more to fill: at most 26 givens, where Thursday keeps at least 28.
 */
export const LEVELS: Record<DayLevel, { tier: Tier; floor: number; ceiling: number }> = {
  1: { tier: 1, floor: 34, ceiling: N },
  2: { tier: 2, floor: 28, ceiling: N },
  3: { tier: 3, floor: 26, ceiling: N },
  4: { tier: 4, floor: 28, ceiling: N },
  5: { tier: 5, floor: 24, ceiling: N },
  6: { tier: 6, floor: 22, ceiling: N },
  7: { tier: 4, floor: 22, ceiling: 26 },
};

export type NineLivesPuzzle = { givens: Cells; solution: Cells; tier: Tier };

export const givenCount = (cells: Cells): number => cells.filter((d) => d !== 0).length;

/**
 * Tries before the fallback: the bound on a puzzle's making. Over 2027 and 2028 the most any date
 * needed was 298, a Sunday (level 7, median 44); every other level stayed under 130. At 400, about
 * one Sunday in 600 falls back, and no other day in thousands of years. A try costs most on
 * Saturday (chains): 400 of them take 1.6 s in Node on an M-series Mac, about 5 s on a CI runner,
 * well inside a Worker's 30 s of CPU. Every other level's 400 take under 1 s on the Mac.
 */
export const MAX_TRIES = 400;

/** One try: a puzzle at or under `tier`, kept to at least `floor` givens. */
export function carve(rng: Rng, tier: Tier, floor: number): NineLivesPuzzle {
  const solution = randomSolution(rng);
  const givens = [...solution];
  let count = N;
  for (const i of shuffle([...Array(41).keys()], rng)) {
    const pair = i === 40 ? [40] : [i, N - 1 - i];
    if (count - pair.length < floor) continue;
    for (const j of pair) givens[j] = 0;
    if (grade(givens, tier)) {
      count -= pair.length;
    } else {
      for (const j of pair) givens[j] = solution[j]!;
    }
  }
  return { givens, solution, tier: grade(givens)!.tier };
}

export function makePuzzle(rng: Rng, level: DayLevel): NineLivesPuzzle {
  const { tier, floor, ceiling } = LEVELS[level];
  for (let t = 0; t < MAX_TRIES; t++) {
    const p = carve(rng, tier, floor);
    if (p.tier === tier && givenCount(p.givens) <= ceiling) return p;
  }
  return fallback(rng, level);
}

/** One of `level`'s fallback puzzles, picked by `rng`. */
export function fallback(rng: Rng, level: DayLevel): NineLivesPuzzle {
  const pool = FALLBACK[level];
  const givens = [...pool[Math.floor(rng() * pool.length)]!].map(Number);
  return { givens, solution: solveOne(givens)!, tier: LEVELS[level].tier };
}
