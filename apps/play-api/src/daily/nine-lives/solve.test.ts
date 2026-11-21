import { describe, expect, test } from "vitest";

import { seedOf } from "../../../tests/seeds";
import { createRng } from "../../rules/rng";

import { clashes, isFull, N } from "./grid";
import { cellsOf, SOLVED } from "./samples";
import { countSolutions, randomSolution, solveOne } from "./solve";

/** A well-known puzzle with one solution. */
const CLASSIC = cellsOf(
  "53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79",
);

describe("countSolutions", () => {
  test("one for a proper puzzle, and it stops at the limit", () => {
    expect(countSolutions(CLASSIC, 2)).toBe(1);
    expect(countSolutions(new Array<number>(N).fill(0), 2)).toBe(2);
    expect(countSolutions(new Array<number>(N).fill(0), 1)).toBe(1);
  });

  test("zero for a grid that breaks a rule or can't be finished", () => {
    const bad = [...CLASSIC];
    bad[2] = 5; // 5 twice in row 0
    expect(countSolutions(bad, 2)).toBe(0);
    const stuck = new Array<number>(N).fill(0);
    // Row 0 holds 1..8, and column 8 already holds a 9: cell 8 has no digit left.
    for (let c = 0; c < 8; c++) stuck[c] = c + 1;
    stuck[80] = 9;
    expect(countSolutions(stuck, 2)).toBe(0);
  });

  test("a full valid grid is its own one solution", () => {
    expect(countSolutions(SOLVED, 2)).toBe(1);
  });
});

describe("solveOne", () => {
  test("solves a puzzle without changing it", () => {
    const copy = [...CLASSIC];
    const out = solveOne(CLASSIC)!;
    expect(CLASSIC).toEqual(copy);
    expect(isFull(out)).toBe(true);
    expect(clashes(out)).toEqual([]);
    for (let i = 0; i < N; i++) if (CLASSIC[i] !== 0) expect(out[i]).toBe(CLASSIC[i]);
  });

  test("null when there is none", () => {
    const bad = [...CLASSIC];
    bad[2] = 5;
    expect(solveOne(bad)).toBeNull();
  });
});

describe("randomSolution", () => {
  test("a full valid grid, the same for the same seed, different for another", () => {
    const a = randomSolution(createRng(seedOf(1)));
    const b = randomSolution(createRng(seedOf(1)));
    const c = randomSolution(createRng(seedOf(2)));
    expect(isFull(a)).toBe(true);
    expect(clashes(a)).toEqual([]);
    expect(a).toEqual(b);
    expect(a).not.toEqual(c);
  });
});
