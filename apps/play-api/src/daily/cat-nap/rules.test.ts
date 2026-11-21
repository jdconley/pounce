import { describe, expect, test } from "vitest";

import {
  applyHint,
  applyMark,
  catsPlaced,
  clashes,
  complete,
  dragMove,
  dragPaint,
  emptyState,
  hintTarget,
  parseNapMove,
  tapMove,
  type NapState,
  type Quilt,
} from "./rules";

/**
 * A 5 by 5 quilt with one solution: cats at (0,1) (1,3) (2,0) (3,2) (4,4).
 *
 *   0 0 1 1 1
 *   0 2 2 1 1
 *   3 2 2 2 1
 *   3 3 2 4 4
 *   3 3 4 4 4
 */
const Q: Quilt = { n: 5, patches: [0, 0, 1, 1, 1, 0, 2, 2, 1, 1, 3, 2, 2, 2, 1, 3, 3, 2, 4, 4, 3, 3, 4, 4, 4] };
const SOLUTION = [1, 3, 0, 2, 4];
const at = (r: number, c: number) => r * 5 + c;

function withCats(cells: number[], hinted: number[] = []): NapState {
  const s = emptyState(Q);
  for (const c of cells) s.cells[c] = 2;
  for (const c of hinted) s.cells[c] = 2;
  return { cells: s.cells, hinted: [...hinted].sort((a, b) => a - b) };
}

describe("parseNapMove", () => {
  test("takes only the exact shape", () => {
    expect(parseNapMove({ k: "mark", cells: [3], to: "cat" })).toEqual({ k: "mark", cells: [3], to: "cat" });
    expect(parseNapMove({ k: "mark", cells: [0, 1, 2], to: "x" })).toEqual({ k: "mark", cells: [0, 1, 2], to: "x" });
    expect(parseNapMove({ k: "mark", cells: [4], to: "clear" })).toEqual({ k: "mark", cells: [4], to: "clear" });
    expect(parseNapMove({ k: "mark", cells: [3], to: "cat", x: 1 })).toBeNull();
    expect(parseNapMove({ k: "mark", cells: [3], to: "dog" })).toBeNull();
    expect(parseNapMove({ k: "mark", cells: [1.5], to: "x" })).toBeNull();
    expect(parseNapMove({ k: "mark", cells: [-1], to: "x" })).toBeNull();
    expect(parseNapMove({ k: "mark", cells: ["1"], to: "x" })).toBeNull();
    expect(parseNapMove({ k: "mark", cells: [1, 1], to: "x" })).toBeNull();
    expect(parseNapMove({ k: "mark", cells: [], to: "x" })).toBeNull();
    expect(parseNapMove({ k: "mark", cells: Array.from({ length: 82 }, (_, i) => i), to: "x" })).toBeNull();
    expect(parseNapMove({ k: "mark", cells: [1, 2], to: "cat" })).toBeNull();
    expect(parseNapMove({ k: "mark", cells: 3, to: "x" })).toBeNull();
    expect(parseNapMove({ k: "step", cells: [3], to: "x" })).toBeNull();
    expect(parseNapMove({ cells: [3], to: "x" })).toBeNull();
    expect(parseNapMove(null)).toBeNull();
    expect(parseNapMove([1])).toBeNull();
    expect(parseNapMove("mark")).toBeNull();
  });

  test("returns a copy, not the caller's array", () => {
    const cells = [1, 2];
    const m = parseNapMove({ k: "mark", cells, to: "x" });
    cells.push(3);
    expect(m?.cells).toEqual([1, 2]);
  });
});

describe("applyMark", () => {
  test("marks set, overwrite and clear", () => {
    const s0 = emptyState(Q);
    expect(s0).toEqual({ cells: Array(25).fill(0), hinted: [] });
    const s1 = applyMark(Q, s0, { k: "mark", cells: [0, 1, 2], to: "x" });
    expect(s1?.cells.slice(0, 4)).toEqual([1, 1, 1, 0]);
    const s2 = applyMark(Q, s1!, { k: "mark", cells: [1], to: "cat" });
    expect(s2?.cells.slice(0, 4)).toEqual([1, 2, 1, 0]);
    const s3 = applyMark(Q, s2!, { k: "mark", cells: [0, 1], to: "clear" });
    expect(s3?.cells.slice(0, 4)).toEqual([0, 0, 1, 0]);
    expect(s0.cells[0]).toBe(0); // never mutates
  });

  test("a hinted cell is locked", () => {
    const s = withCats([], [at(0, 1)]);
    expect(applyMark(Q, s, { k: "mark", cells: [at(0, 1)], to: "clear" })).toBeNull();
    expect(applyMark(Q, s, { k: "mark", cells: [0, at(0, 1)], to: "x" })).toBeNull();
    expect(applyMark(Q, s, { k: "mark", cells: [0], to: "x" })?.hinted).toEqual([at(0, 1)]);
  });

  test("out of range is illegal", () => {
    expect(applyMark(Q, emptyState(Q), { k: "mark", cells: [25], to: "x" })).toBeNull();
  });
});

describe("clashes", () => {
  test("none on an empty quilt or a solution", () => {
    expect(clashes(Q, emptyState(Q))).toEqual({ rows: [], cols: [], patches: [], touching: [], cells: [] });
    expect(clashes(Q, withCats(SOLUTION.map((c, r) => at(r, c)))).cells).toEqual([]);
  });

  test("two cats in a row, column or patch clash", () => {
    const row = clashes(Q, withCats([at(0, 0), at(0, 4)]));
    expect(row).toMatchObject({ rows: [0], cols: [], touching: [], cells: [at(0, 0), at(0, 4)] });
    const col = clashes(Q, withCats([at(0, 0), at(3, 0)]));
    expect(col).toMatchObject({ rows: [], cols: [0], patches: [], cells: [at(0, 0), at(3, 0)] });
    // (1,1) and (3,2) are both in patch 2, far apart.
    const patch = clashes(Q, withCats([at(1, 1), at(3, 2)]));
    expect(patch).toEqual({ rows: [], cols: [], patches: [2], touching: [], cells: [at(1, 1), at(3, 2)] });
  });

  test("many clashes at once come back in order", () => {
    const many = clashes(Q, withCats([at(4, 0), at(4, 4), at(0, 0), at(0, 4)]));
    expect(many.rows).toEqual([0, 4]);
    expect(many.cols).toEqual([0, 4]);
    expect(many.cells).toEqual([at(0, 0), at(0, 4), at(4, 0), at(4, 4)]);
  });

  test("touching includes diagonals", () => {
    const diag = clashes(Q, withCats([at(1, 1), at(2, 2), at(4, 4)]));
    expect(diag.touching).toEqual([at(1, 1), at(2, 2)]);
    expect(diag.cells).toEqual([at(1, 1), at(2, 2)]);
    const side = clashes(Q, withCats([at(2, 3), at(2, 4)]));
    expect(side.touching).toEqual([at(2, 3), at(2, 4)]);
    expect(side.rows).toEqual([2]);
    // Edges: the left column's cats don't wrap to the right column of the row above.
    expect(clashes(Q, withCats([at(1, 4), at(2, 0)])).touching).toEqual([]);
  });
});

describe("complete", () => {
  test("needs n cats and no clash", () => {
    const solved = withCats(SOLUTION.map((c, r) => at(r, c)));
    expect(complete(Q, solved)).toBe(true);
    expect(complete(Q, withCats(SOLUTION.slice(0, 4).map((c, r) => at(r, c))))).toBe(false);
    // n cats, but two touch.
    expect(complete(Q, withCats([at(0, 0), at(1, 1), at(2, 3), at(3, 2), at(4, 4)]))).toBe(false);
    // n cats with no clash still need every row: impossible without one, but x marks never count.
    const marked = { ...solved, cells: solved.cells.map((m) => (m === 0 ? 1 : m)) as NapState["cells"] };
    expect(complete(Q, marked)).toBe(true);
  });
});

describe("hints", () => {
  test("the first row without its cat", () => {
    expect(hintTarget(Q, emptyState(Q), SOLUTION)).toBe(at(0, 1));
    expect(hintTarget(Q, withCats([at(0, 1)]), SOLUTION)).toBe(at(1, 3));
  });

  test("hint is null once solved", () => {
    expect(hintTarget(Q, withCats(SOLUTION.map((c, r) => at(r, c))), SOLUTION)).toBeNull();
  });

  test("a solution cat that clashes is hinted again", () => {
    // Every solution cat placed, plus a wrong one at (4,0) that shares row 4 and column 0.
    const s = withCats([...SOLUTION.map((c, r) => at(r, c)), at(4, 0)]);
    expect(hintTarget(Q, s, SOLUTION)).toBe(at(2, 0));
  });

  test("hint clears the cats that clash with it", () => {
    // Wrong cats at (0,0) (same row), (2,1) (touching (1,3)? no) and (1,2) (touching (0,1)).
    const s = withCats([at(0, 0), at(1, 2), at(4, 4)]);
    s.cells[at(0, 1)] = 1;
    const h = applyHint(Q, s, at(0, 1));
    expect(h.cells[at(0, 1)]).toBe(2);
    expect(h.hinted).toEqual([at(0, 1)]);
    expect(h.cells[at(0, 0)]).toBe(0);
    expect(h.cells[at(1, 2)]).toBe(0);
    expect(h.cells[at(4, 4)]).toBe(2);
    // A hinted cat is never cleared by a later hint.
    const h2 = applyHint(Q, { ...h, cells: h.cells.map((m, i) => (i === at(1, 1) ? 2 : m)) as NapState["cells"] }, at(1, 3));
    expect(h2.hinted).toEqual([at(0, 1), at(1, 3)]);
    expect(h2.cells[at(0, 1)]).toBe(2);
    expect(h2.cells[at(1, 1)]).toBe(0);
    // Same patch, far away: cleared too.
    const h3 = applyHint(Q, withCats([at(3, 2)]), at(1, 1));
    expect(h3.cells[at(3, 2)]).toBe(0);
    // Hinting a cell already hinted keeps one entry.
    expect(applyHint(Q, h, at(0, 1)).hinted).toEqual([at(0, 1)]);
  });
});

describe("catsPlaced", () => {
  test("ignores clashing cats and caps at n", () => {
    expect(catsPlaced(Q, emptyState(Q))).toBe(0);
    expect(catsPlaced(Q, withCats([at(0, 1), at(1, 3)]))).toBe(2);
    expect(catsPlaced(Q, withCats([at(0, 1), at(1, 2)]))).toBe(0);
    expect(catsPlaced(Q, withCats(SOLUTION.map((c, r) => at(r, c))))).toBe(5);
  });
});

describe("client helpers", () => {
  test("tap cycles empty, x, cat, empty", () => {
    const s0 = emptyState(Q);
    const m1 = tapMove(s0, 7)!;
    expect(m1).toEqual({ k: "mark", cells: [7], to: "x" });
    const s1 = applyMark(Q, s0, m1)!;
    const m2 = tapMove(s1, 7)!;
    expect(m2).toEqual({ k: "mark", cells: [7], to: "cat" });
    const s2 = applyMark(Q, s1, m2)!;
    expect(tapMove(s2, 7)).toEqual({ k: "mark", cells: [7], to: "clear" });
    expect(tapMove(withCats([], [7]), 7)).toBeNull();
  });

  test("a drag from empty paints x over empties only", () => {
    const s = withCats([2]);
    expect(dragPaint(s, 0)).toBe("x");
    expect(dragMove(s, "x", [0, 1, 2, 3])).toEqual({ k: "mark", cells: [0, 1, 3], to: "x" });
  });

  test("a drag from x clears x only", () => {
    const s = applyMark(Q, withCats([2]), { k: "mark", cells: [0, 1], to: "x" })!;
    expect(dragPaint(s, 0)).toBe("clear");
    expect(dragMove(s, "clear", [0, 1, 2, 3])).toEqual({ k: "mark", cells: [0, 1], to: "clear" });
  });

  test("a drag skips hinted cells and cats, and from them paints nothing", () => {
    const s = withCats([1], [2]);
    expect(dragPaint(s, 1)).toBeNull();
    expect(dragPaint(s, 2)).toBeNull();
    expect(dragMove(s, "x", [0, 1, 2, 3, 3])).toEqual({ k: "mark", cells: [0, 3], to: "x" });
    expect(dragMove(s, "x", [1, 2])).toBeNull();
  });
});
