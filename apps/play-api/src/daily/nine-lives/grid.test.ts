import { describe, expect, test } from "vitest";

import {
  applyMove,
  applyReveal,
  BOXES,
  clashes,
  COLS,
  isFull,
  N,
  parseMove,
  peers,
  placed,
  progressOf,
  ROWS,
  type Cells,
  type NineLivesState,
} from "./grid";
import { cellsOf, SOLVED } from "./samples";

function empty(): Cells {
  return new Array<number>(N).fill(0);
}

describe("units and peers", () => {
  test("rows, columns and boxes each hold nine cells, all 81 covered three times", () => {
    const seen = new Array<number>(N).fill(0);
    for (const unit of [...ROWS, ...COLS, ...BOXES]) {
      expect(unit).toHaveLength(9);
      for (const i of unit) seen[i]! += 1;
    }
    expect(seen.every((n) => n === 3)).toBe(true);
    expect(BOXES[4]).toEqual([30, 31, 32, 39, 40, 41, 48, 49, 50]);
  });

  test("every cell has 20 peers, and peers are symmetric", () => {
    for (let i = 0; i < N; i++) {
      expect(peers(i)).toHaveLength(20);
      expect(peers(i)).not.toContain(i);
      for (const p of peers(i)) expect(peers(p)).toContain(i);
    }
  });
});

describe("clashes", () => {
  test("a solved grid has none", () => {
    expect(clashes(SOLVED)).toEqual([]);
  });

  test("a repeat in a row, a column or a box marks both cells", () => {
    const row = empty();
    row[0] = 5;
    row[8] = 5;
    expect(clashes(row)).toEqual([0, 8]);
    const col = empty();
    col[4] = 2;
    col[76] = 2;
    expect(clashes(col)).toEqual([4, 76]);
    const box = empty();
    box[0] = 7;
    box[20] = 7;
    expect(clashes(box)).toEqual([0, 20]);
  });

  test("three of a kind and empties", () => {
    const g = empty();
    g[9] = 1;
    g[10] = 1;
    g[17] = 1;
    g[11] = 3;
    expect(clashes(g)).toEqual([9, 10, 17]);
  });
});

test("cellsOf reads dots and zeros, and needs 81 cells", () => {
  expect(cellsOf(`1.0${".".repeat(78)}`).slice(0, 3)).toEqual([1, 0, 0]);
  expect(() => cellsOf("123")).toThrow(RangeError);
});

describe("full and progress", () => {
  test("isFull", () => {
    expect(isFull(SOLVED)).toBe(true);
    const g = [...SOLVED];
    g[40] = 0;
    expect(isFull(g)).toBe(false);
  });

  test("placed and progress count only cells that were empty", () => {
    const givens = [...SOLVED];
    givens[0] = 0;
    givens[1] = 0;
    givens[2] = 0;
    givens[3] = 0;
    const cells = [...givens];
    expect(placed(givens, cells)).toBe(0);
    expect(progressOf(givens, cells)).toBe(0);
    cells[0] = 9;
    expect(placed(givens, cells)).toBe(1);
    expect(progressOf(givens, cells)).toBe(0.25);
    expect(progressOf(SOLVED, SOLVED)).toBe(1);
  });
});

describe("parseMove", () => {
  test("accepts the two exact shapes", () => {
    expect(parseMove({ k: "set", i: 0, d: 1 })).toEqual({ k: "set", i: 0, d: 1 });
    expect(parseMove({ k: "set", i: 80, d: 9 })).toEqual({ k: "set", i: 80, d: 9 });
    expect(parseMove({ k: "clear", i: 5 })).toEqual({ k: "clear", i: 5 });
  });

  test.each([
    null,
    7,
    "set",
    [],
    { k: "set", i: 0 },
    { k: "set", i: 0, d: 0 },
    { k: "set", i: 0, d: 10 },
    { k: "set", i: 0, d: 1.5 },
    { k: "set", i: -1, d: 1 },
    { k: "set", i: 81, d: 1 },
    { k: "set", i: "0", d: 1 },
    { k: "set", i: 0, d: 1, x: 1 },
    { k: "clear", i: 0, d: 1 },
    { k: "clear", i: 2.5 },
    { k: "clear" },
    { k: "erase", i: 0 },
  ])("refuses %j", (raw) => {
    expect(parseMove(raw)).toBeNull();
  });
});

describe("applyMove", () => {
  const givens = [...SOLVED];
  givens[10] = 0;
  givens[11] = 0;
  const start: NineLivesState = { cells: [...givens], hinted: [] };

  test("sets and clears an open cell without touching the input", () => {
    const set = applyMove(givens, start, { k: "set", i: 10, d: 4 });
    expect(set?.cells[10]).toBe(4);
    expect(start.cells[10]).toBe(0);
    const cleared = applyMove(givens, set!, { k: "clear", i: 10 });
    expect(cleared?.cells[10]).toBe(0);
  });

  test("a clash is legal", () => {
    const s = applyMove(givens, start, { k: "set", i: 10, d: SOLVED[0]! });
    expect(s).not.toBeNull();
    expect(clashes(s!.cells).length).toBeGreaterThan(0);
  });

  test("givens and hinted cells are refused", () => {
    expect(applyMove(givens, start, { k: "set", i: 0, d: 1 })).toBeNull();
    expect(applyMove(givens, start, { k: "clear", i: 0 })).toBeNull();
    const hinted = applyReveal(start, { i: 11, d: SOLVED[11]! });
    expect(hinted.hinted).toEqual([11]);
    expect(applyMove(givens, hinted, { k: "set", i: 11, d: 1 })).toBeNull();
    expect(applyMove(givens, hinted, { k: "clear", i: 11 })).toBeNull();
  });

  test("applyReveal keeps hinted sorted and unique", () => {
    let s = applyReveal(start, { i: 11, d: 3 });
    s = applyReveal(s, { i: 10, d: 2 });
    s = applyReveal(s, { i: 10, d: 2 });
    expect(s.hinted).toEqual([10, 11]);
    expect(s.cells[10]).toBe(2);
    expect(start.hinted).toEqual([]);
  });
});
