import { describe, expect, test } from "vitest";

import { countSolutions, grade, otherSolution } from "./logic";
import { complete, emptyState, type Quilt } from "./rules";

/** 6 by 6 quilts pinned from the maker, one per grade, each with its one solution. */
const SAMPLES: { grade: 1 | 2 | 3 | 4; quilt: Quilt; solution: number[] }[] = [
  {
    grade: 1,
    quilt: { n: 6, patches: [0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 2, 2, 3, 3, 3, 4, 2, 2, 5, 3, 3, 5, 2, 5, 5, 5, 3, 5, 5, 5, 5, 5, 5] },
    solution: [1, 4, 2, 0, 5, 3],
  },
  {
    grade: 2,
    quilt: { n: 6, patches: [0, 1, 0, 0, 0, 2, 0, 0, 0, 0, 0, 2, 3, 4, 4, 0, 0, 2, 3, 3, 5, 2, 2, 2, 3, 5, 5, 5, 2, 2, 5, 5, 2, 2, 2, 2] },
    solution: [1, 4, 2, 0, 3, 5],
  },
  {
    grade: 3,
    quilt: { n: 6, patches: [0, 0, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 2, 2, 3, 1, 1, 1, 4, 4, 3, 5, 5, 5, 4, 4, 5, 5, 5, 5, 5, 4] },
    solution: [1, 3, 5, 0, 4, 2],
  },
  {
    grade: 4,
    quilt: { n: 6, patches: [0, 0, 0, 1, 1, 1, 2, 2, 0, 0, 0, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 3, 3, 0, 0, 4, 4, 3, 5, 5, 0, 4, 4, 4, 5, 5] },
    solution: [3, 0, 2, 4, 1, 5],
  },
];

/** Each row its own patch: many solutions. */
const STRIPES: Quilt = { n: 5, patches: Array.from({ length: 25 }, (_, i) => Math.floor(i / 5)) };

/** Two one-cell patches side by side: their cats would touch, so no solution at all. */
const NONE: Quilt = { n: 5, patches: [0, 1, 2, 2, 2, 3, 3, 2, 2, 2, 3, 3, 4, 4, 4, 3, 3, 4, 4, 4, 3, 3, 4, 4, 4] };

describe("countSolutions", () => {
  test("one for each pinned sample", () => {
    for (const s of SAMPLES) expect(countSolutions(s.quilt, 2)).toBe(1);
  });

  test("stops at the limit, and finds none when there is none", () => {
    expect(countSolutions(STRIPES, 3)).toBe(3);
    expect(countSolutions(NONE, 2)).toBe(0);
  });
});

describe("otherSolution", () => {
  test("null when the solution is the only one", () => {
    for (const s of SAMPLES) expect(otherSolution(s.quilt, s.solution)).toBeNull();
  });

  test("a different solution when there is one", () => {
    const first = otherSolution(STRIPES, [0, 0, 0, 0, 0])!;
    const second = otherSolution(STRIPES, first)!;
    expect(second).not.toEqual(first);
    expect(countSolutions(STRIPES, 100)).toBeGreaterThan(2);
  });
});

describe("grade", () => {
  test("each pinned sample needs exactly its step", () => {
    for (const s of SAMPLES) expect(grade(s.quilt)).toEqual({ grade: s.grade, solution: s.solution });
  });

  test("every grade's solution passes complete", () => {
    for (const s of SAMPLES) {
      const g = grade(s.quilt)!;
      const state = emptyState(s.quilt);
      g.solution.forEach((c, r) => (state.cells[r * 6 + c] = 2));
      expect(complete(s.quilt, state)).toBe(true);
    }
  });

  test("null when there are two solutions, or none", () => {
    expect(grade(STRIPES)).toBeNull();
    expect(grade(NONE)).toBeNull();
  });
});
