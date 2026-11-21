import { describe, expect, test } from "vitest";

import { shape, type Piece } from "./pieces";
import {
  anyFits,
  CLUTTER,
  comboBonus,
  deal,
  fits,
  FULL_FORT,
  lineBonus,
  place,
  setFits,
  SIZE,
  start,
  step,
  type BoxFortState,
} from "./rules";

/** A rug from eight strings of eight: "#" is a box (tint CLUTTER), anything else empty. */
function rugOf(...rows: string[]): number[] {
  expect(rows).toHaveLength(SIZE);
  return rows.flatMap((row) => [...row].map((ch) => (ch === "#" ? CLUTTER : 0)));
}

const piece = (id: string, tint = 1): Piece => ({ id, tint, cells: shape(id).cells });
const EMPTY = Array<number>(SIZE * SIZE).fill(0);

describe("scoring", () => {
  test("line bonus grows with lines cleared at once", () => {
    expect([0, 1, 2, 3, 4].map(lineBonus)).toEqual([0, 10, 30, 60, 100]);
  });

  test("combo bonus starts at the second clearing placement in a row", () => {
    expect([0, 1, 2, 3].map(comboBonus)).toEqual([0, 0, 15, 30]);
  });

  test("the full fort bonus is 200", () => {
    expect(FULL_FORT).toBe(200);
  });
});

describe("fits", () => {
  test("an empty rug takes a piece anywhere it stays on the rug", () => {
    const sq3 = shape("sq3").cells;
    expect(fits(EMPTY, sq3, 0, 0)).toBe(true);
    expect(fits(EMPTY, sq3, 5, 5)).toBe(true);
    expect(fits(EMPTY, sq3, 6, 5)).toBe(false);
    expect(fits(EMPTY, sq3, 5, 6)).toBe(false);
    expect(fits(EMPTY, sq3, -1, 0)).toBe(false);
    expect(fits(EMPTY, sq3, 0, -1)).toBe(false);
  });

  test("a box in the way refuses it", () => {
    const rug = rugOf("........", ".#......", "........", "........", "........", "........", "........", "........");
    expect(fits(rug, shape("sq2").cells, 0, 0)).toBe(false);
    expect(fits(rug, shape("sq2").cells, 0, 2)).toBe(true);
    // The paws skip the box between them.
    expect(fits(rug, shape("paws-b").cells, 0, 0)).toBe(true);
  });

  test("anyFits looks at every spot for every piece", () => {
    const full = rugOf("########", "########", "########", "########", "########", "########", "#######.", "########");
    expect(anyFits(full, [piece("sq2"), piece("dot")])).toBe(true);
    expect(anyFits(full, [piece("sq2"), piece("duo-h")])).toBe(false);
    expect(anyFits(full, [])).toBe(false);
  });

  test("setFits wants room for the whole set at once, not each piece alone", () => {
    // Boxes on every other spot, and one more spot open at the top left: one domino's worth of room.
    const rug = Array.from({ length: SIZE * SIZE }, (_, i) => (i !== 0 && (Math.floor(i / SIZE) + (i % SIZE)) % 2 === 0 ? CLUTTER : 0));
    expect(anyFits(rug, [piece("duo-h")])).toBe(true);
    expect(setFits(rug, [piece("duo-h"), piece("dot")])).toBe(true);
    expect(setFits(rug, [piece("duo-h"), piece("duo-h")])).toBe(false);
    expect(setFits(rug, [])).toBe(true);
  });

  test("setFits counts the room a clear makes", () => {
    // Every row is one box short: the dot clears one, and then the long piece has that row.
    const rug = rugOf(...Array<string>(SIZE).fill("#######."));
    expect(anyFits(rug, [piece("five-h")])).toBe(false);
    expect(setFits(rug, [piece("five-h"), piece("dot")])).toBe(true);
  });
});

describe("place", () => {
  test("puts the boxes down in the piece's tint", () => {
    const out = place(EMPTY, piece("duo-v", 4), 2, 3);
    expect(out?.cleared).toEqual({ rows: [], cols: [] });
    expect(out?.rug[2 * SIZE + 3]).toBe(4);
    expect(out?.rug[3 * SIZE + 3]).toBe(4);
    expect(out?.rug.filter((v) => v !== 0)).toHaveLength(2);
  });

  test("refuses a spot that doesn't fit", () => {
    expect(place(EMPTY, piece("five-h"), 0, 4)).toBeNull();
  });

  test("a full row clears", () => {
    const rug = rugOf("#####...", "........", "........", "........", "........", "........", "........", "........");
    const out = place(rug, piece("trio-h"), 0, 5);
    expect(out?.cleared).toEqual({ rows: [0], cols: [] });
    expect(out?.rug.every((v) => v === 0)).toBe(true);
  });

  test("row and column clear together, the crossing box once", () => {
    const rug = rugOf(
      "...#....",
      "...#....",
      "...#....",
      "###.####",
      "...#....",
      "...#....",
      "...#....",
      "...#..#.",
    );
    const out = place(rug, piece("dot"), 3, 3);
    expect(out?.cleared).toEqual({ rows: [3], cols: [3] });
    expect(out?.rug.filter((v) => v !== 0)).toEqual([CLUTTER]); // only (7, 6) is left
    expect(out?.rug[7 * SIZE + 6]).toBe(CLUTTER);
  });
});

describe("step and deal", () => {
  const set = [piece("dot"), piece("trio-h"), piece("sq2")];

  test("start: an untouched run", () => {
    expect(start(EMPTY, 15)).toEqual<BoxFortState>({
      rug: EMPTY,
      set: 0,
      sets: 15,
      placed: [false, false, false],
      points: 0,
      combo: 0,
      lines: 0,
      over: null,
    });
  });

  test("a placement scores a point a box and marks its slot", () => {
    const out = step(start(EMPTY, 15), set, 1, 0, 0);
    expect(out?.gained).toBe(3);
    expect(out?.setDone).toBe(false);
    expect(out?.state.placed).toEqual([false, true, false]);
    expect(out?.state.points).toBe(3);
  });

  test("refuses a placed slot, a slot past the set, and a spot that doesn't fit", () => {
    const once = step(start(EMPTY, 15), set, 0, 0, 0)!.state;
    expect(step(once, set, 0, 4, 4)).toBeNull();
    expect(step(once, set, 3, 4, 4)).toBeNull();
    expect(step(once, set, -1, 4, 4)).toBeNull();
    expect(step(once, set, 2, 0, 0)).toBeNull();
    expect(step(once, set, 2, 7, 7)).toBeNull();
  });

  test("refuses everything once the run is over", () => {
    const over: BoxFortState = { ...start(EMPTY, 15), over: "stuck" };
    expect(step(over, set, 0, 0, 0)).toBeNull();
  });

  test("combo grows over clearing placements in a row and resets on one that clears nothing", () => {
    const rug = rugOf("#######.", "#######.", "#######.", "........", "........", "........", "........", "........");
    const pieces = [piece("dot"), piece("dot"), piece("dot")];
    const a = step(start(rug, 15), pieces, 0, 0, 7)!;
    expect(a.gained).toBe(1 + lineBonus(1));
    expect(a.state.combo).toBe(1);
    const b = step(a.state, pieces, 1, 1, 7)!;
    expect(b.gained).toBe(1 + lineBonus(1) + comboBonus(2));
    expect(b.state.combo).toBe(2);
    expect(b.state.lines).toBe(2);
    const c = step(b.state, pieces, 2, 5, 5)!;
    expect(c.gained).toBe(1);
    expect(c.state.combo).toBe(0);
    expect(c.setDone).toBe(true);
    expect(c.state.points).toBe(a.gained + b.gained + 1);
  });

  test("the run is stuck when none of the pieces left fit", () => {
    // A checkerboard: single gaps only, and no line can fill.
    const a = "#.#.#.#.";
    const b = ".#.#.#.#";
    const rug = rugOf(a, b, a, b, a, b, a, b);
    const pieces = [piece("dot"), piece("sq2"), piece("trio-v")];
    const out = step(start(rug, 15), pieces, 0, 0, 1)!;
    expect(out.state.over).toBe("stuck");
    expect(out.setDone).toBe(false);
  });

  test("the last piece of a set never says stuck: the next set decides", () => {
    const pieces = [piece("dot"), piece("dot"), piece("dot")];
    let s = start(EMPTY, 2);
    s = step(s, pieces, 0, 0, 0)!.state;
    s = step(s, pieces, 1, 0, 1)!.state;
    const last = step(s, pieces, 2, 0, 2)!;
    expect(last.setDone).toBe(true);
    expect(last.state.over).toBeNull();
  });

  test("deal moves to the next set and checks it fits", () => {
    const done: BoxFortState = { ...start(EMPTY, 15), placed: [true, true, true], points: 9 };
    expect(deal(done, set)).toEqual({ ...done, set: 1, placed: [false, false, false] });
    const full = rugOf("########", "########", "########", "########", "########", "########", "########", "#######.");
    const stuck = deal({ ...done, rug: full }, [piece("sq2"), piece("duo-h"), piece("sq3")]);
    expect(stuck.over).toBe("stuck");
    expect(stuck.set).toBe(1);
  });

  test("deal with no next set is the full fort", () => {
    const done: BoxFortState = { ...start(EMPTY, 15), set: 14, placed: [true, true, true], points: 40 };
    expect(deal(done, null)).toEqual({ ...done, points: 40 + FULL_FORT, over: "full" });
  });
});
