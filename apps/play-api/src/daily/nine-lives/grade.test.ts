import { describe, expect, test } from "vitest";

import {
  boardOf,
  coloring,
  fish,
  grade,
  hiddenSingles,
  hiddenSubset,
  lockedCandidates,
  nakedSingles,
  nakedSubset,
  place,
  xyChain,
  xyWing,
  xyzWing,
  type Board,
} from "./grade";
import { COLS, N, ROWS } from "./grid";
import { cellsOf } from "./samples";

const at = (r: number, c: number): number => r * 9 + c;
const bit = (d: number): number => 1 << (d - 1);
const mask = (...ds: number[]): number => ds.reduce((m, d) => m | bit(d), 0);
const has = (b: Board, i: number, d: number): boolean => (b.cand[i]! & bit(d)) !== 0;

/** An empty board: every cell open, every digit possible. */
function open(): Board {
  return boardOf(new Array<number>(N).fill(0))!;
}

/** Leaves digit `d` in `unit` only at `keep`. */
function only(b: Board, unit: readonly number[], d: number, keep: number[]): void {
  for (const i of unit) if (!keep.includes(i)) b.cand[i]! &= ~bit(d);
}

describe("tier 1: singles", () => {
  test("a naked single fills its cell and clears the digit from its peers", () => {
    const b = open();
    expect(nakedSingles(b)).toBe(false);
    b.cand[0] = bit(5);
    expect(nakedSingles(b)).toBe(true);
    expect(b.vals[0]).toBe(5);
    expect(has(b, 1, 5)).toBe(false);
    expect(has(b, 10, 5)).toBe(false);
    expect(has(b, 72, 5)).toBe(false);
    expect(has(b, 13, 5)).toBe(true);
  });

  test("a hidden single fills the one place left for a digit", () => {
    const b = open();
    expect(hiddenSingles(b)).toBe(false);
    only(b, ROWS[0]!, 3, [4]);
    expect(hiddenSingles(b)).toBe(true);
    expect(b.vals[4]).toBe(3);
  });
});

describe("tier 2: locked candidates", () => {
  test("pointing: a box's places in one row clear the rest of the row", () => {
    const b = open();
    expect(lockedCandidates(b)).toBe(false);
    for (const i of [2, 9, 10, 11, 18, 19, 20]) b.cand[i]! &= ~bit(1);
    expect(lockedCandidates(b)).toBe(true);
    for (const i of [3, 4, 5, 6, 7, 8]) expect(has(b, i, 1)).toBe(false);
    expect(has(b, 0, 1)).toBe(true);
    expect(has(b, 27, 1)).toBe(true);
  });

  test("pointing down a column", () => {
    const b = open();
    for (const i of [1, 2, 10, 11, 19, 20]) b.cand[i]! &= ~bit(4);
    expect(lockedCandidates(b)).toBe(true);
    for (let r = 3; r < 9; r++) expect(has(b, at(r, 0), 4)).toBe(false);
  });

  test("claiming: a row's places in one box clear the rest of the box", () => {
    const b = open();
    only(b, ROWS[0]!, 2, [0, 1, 2]);
    expect(lockedCandidates(b)).toBe(true);
    for (const i of [9, 10, 11, 18, 19, 20]) expect(has(b, i, 2)).toBe(false);
    expect(has(b, 0, 2)).toBe(true);
  });
});

describe("tiers 3 and 4: subsets", () => {
  test("a naked pair clears its digits from both shared units", () => {
    const b = open();
    expect(nakedSubset(b, 2)).toBe(false);
    b.cand[0] = mask(1, 2);
    b.cand[1] = mask(1, 2);
    expect(nakedSubset(b, 2)).toBe(true);
    expect(has(b, 5, 1)).toBe(false);
    expect(has(b, 2, 2)).toBe(false);
    expect(has(b, 9, 1)).toBe(false);
    expect(has(b, 27, 1)).toBe(true);
    expect(b.cand[0]).toBe(mask(1, 2));
  });

  test("a naked triple need not have all three digits in each cell", () => {
    const b = open();
    place(b, 80, 9);
    b.cand[0] = mask(1, 2);
    b.cand[1] = mask(2, 3);
    b.cand[2] = mask(1, 3);
    expect(nakedSubset(b, 3)).toBe(true);
    for (const i of [3, 8, 9, 20]) expect(b.cand[i]! & mask(1, 2, 3)).toBe(0);
  });

  test("a hidden pair strips the other digits from its two cells", () => {
    const b = open();
    expect(hiddenSubset(b, 2)).toBe(false);
    place(b, 80, 9);
    only(b, ROWS[0]!, 1, [0, 1]);
    only(b, ROWS[0]!, 2, [0, 1]);
    expect(hiddenSubset(b, 2)).toBe(true);
    expect(b.cand[0]).toBe(mask(1, 2));
    expect(b.cand[1]).toBe(mask(1, 2));
    expect(hiddenSubset(b, 2)).toBe(false);
  });

  test("a hidden triple", () => {
    const b = open();
    for (const d of [4, 5, 6]) only(b, COLS[3]!, d, [at(0, 3), at(4, 3), at(8, 3)]);
    b.cand[at(4, 3)]! &= ~bit(6);
    expect(hiddenSubset(b, 3)).toBe(true);
    expect(b.cand[at(0, 3)]).toBe(mask(4, 5, 6));
    expect(b.cand[at(4, 3)]).toBe(mask(4, 5));
  });
});

describe("tier 5: fish and wings", () => {
  test("an x-wing clears its digit from both columns", () => {
    const b = open();
    expect(fish(b, 2)).toBe(false);
    only(b, ROWS[0]!, 1, [at(0, 2), at(0, 6)]);
    only(b, ROWS[4]!, 1, [at(4, 2), at(4, 6)]);
    expect(fish(b, 2)).toBe(true);
    expect(has(b, at(2, 2), 1)).toBe(false);
    expect(has(b, at(8, 6), 1)).toBe(false);
    expect(has(b, at(0, 2), 1)).toBe(true);
    expect(has(b, at(2, 3), 1)).toBe(true);
  });

  test("a swordfish on columns clears its rows", () => {
    const b = open();
    only(b, COLS[0]!, 7, [at(0, 0), at(4, 0)]);
    only(b, COLS[3]!, 7, [at(4, 3), at(8, 3)]);
    only(b, COLS[7]!, 7, [at(0, 7), at(8, 7)]);
    expect(fish(b, 3)).toBe(true);
    expect(has(b, at(0, 5), 7)).toBe(false);
    expect(has(b, at(4, 8), 7)).toBe(false);
    expect(has(b, at(8, 1), 7)).toBe(false);
    expect(has(b, at(2, 5), 7)).toBe(true);
  });

  test("an xy-wing clears the shared digit from what sees both pincers", () => {
    const b = open();
    expect(xyWing(b)).toBe(false);
    b.cand[0] = mask(1, 2);
    b.cand[at(0, 4)] = mask(1, 3);
    b.cand[at(3, 0)] = mask(2, 3);
    // Look-alikes that are no wing: pincers that share the pivot's digit, and share both digits.
    b.cand[at(7, 0)] = mask(1, 4);
    b.cand[at(8, 0)] = mask(1, 4);
    expect(xyWing(b)).toBe(true);
    expect(has(b, at(3, 4), 3)).toBe(false);
    expect(has(b, at(3, 5), 3)).toBe(true);
    expect(xyWing(b)).toBe(false);
  });

  test("an xyz-wing clears the shared digit from what sees all three", () => {
    const b = open();
    expect(xyzWing(b)).toBe(false);
    b.cand[0] = mask(1, 2, 3);
    b.cand[1] = mask(1, 3);
    b.cand[at(3, 0)] = mask(2, 3);
    b.cand[2] = mask(1, 3);
    expect(xyzWing(b)).toBe(true);
    expect(has(b, at(1, 0), 3)).toBe(false);
    expect(has(b, at(2, 0), 3)).toBe(false);
    expect(has(b, at(1, 1), 3)).toBe(true);
    expect(xyzWing(b)).toBe(false);
  });
});

describe("tier 6: chains", () => {
  test("coloring, trap: a cell that sees both colors loses the digit", () => {
    const b = open();
    only(b, ROWS[0]!, 1, [at(0, 0), at(0, 4)]);
    only(b, COLS[4]!, 1, [at(0, 4), at(5, 4)]);
    only(b, ROWS[5]!, 1, [at(5, 4), at(5, 1)]);
    expect(coloring(b)).toBe(true);
    for (const i of [at(1, 1), at(2, 1), at(3, 0), at(4, 0)]) expect(has(b, i, 1)).toBe(false);
    expect(has(b, at(3, 1), 1)).toBe(true);
    expect(has(b, at(0, 0), 1)).toBe(true);
    expect(coloring(b)).toBe(false);
  });

  test("coloring, wrap: two cells of one color see each other, so that color goes", () => {
    const b = open();
    only(b, ROWS[0]!, 1, [at(0, 0), at(0, 4)]);
    only(b, COLS[4]!, 1, [at(0, 4), at(4, 4)]);
    only(b, ROWS[4]!, 1, [at(4, 4), at(4, 1)]);
    only(b, COLS[1]!, 1, [at(4, 1), at(1, 1)]);
    expect(coloring(b)).toBe(true);
    for (const i of [at(0, 0), at(4, 4), at(1, 1)]) expect(has(b, i, 1)).toBe(false);
    for (const i of [at(0, 4), at(4, 1)]) expect(has(b, i, 1)).toBe(true);
  });

  test("coloring: a lone linked pair gives nothing", () => {
    const b = open();
    expect(coloring(b)).toBe(false);
    only(b, ROWS[0]!, 1, [at(0, 0), at(0, 4)]);
    expect(coloring(b)).toBe(false);
  });

  test("an xy-chain clears the end digit from what sees both ends", () => {
    const b = open();
    expect(xyChain(b)).toBe(false);
    b.cand[at(0, 0)] = mask(1, 2);
    b.cand[at(0, 4)] = mask(2, 3);
    b.cand[at(4, 4)] = mask(3, 4);
    b.cand[at(4, 8)] = mask(4, 1);
    b.cand[at(8, 8)] = mask(5, 6);
    expect(xyChain(b)).toBe(true);
    expect(has(b, at(0, 8), 1)).toBe(false);
    expect(has(b, at(4, 0), 1)).toBe(false);
    expect(has(b, at(4, 1), 1)).toBe(true);
    expect(xyChain(b)).toBe(false);
  });
});

describe("grade", () => {
  test("a classic easy puzzle needs only singles", () => {
    const g = grade(
      cellsOf("53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79"),
    );
    expect(g?.tier).toBe(1);
    expect(g?.solution.slice(0, 9)).toEqual([5, 3, 4, 6, 7, 8, 9, 1, 2]);
  });

  test("null for an empty grid, a clash, or a cap below what's needed", () => {
    expect(grade(new Array<number>(N).fill(0))).toBeNull();
    const clash = new Array<number>(N).fill(0);
    clash[0] = 1;
    clash[1] = 1;
    expect(grade(clash)).toBeNull();
    expect(boardOf(clash)).toBeNull();
  });
});
