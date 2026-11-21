import { describe, expect, test } from "vitest";

import { createRng } from "../../rules/rng";

import { greedyMove } from "./greedy";
import { boxFort, type BoxFortPublicState } from "./module";
import { shape, type Piece } from "./pieces";
import { CLUTTER, FULL_FORT, SIZE } from "./rules";

import type { DailyResult, DayLevel } from "./contract";
import type { BoxFortPuzzle } from "./maker";

const piece = (id: string, tint = 1): Piece => ({ id, tint, cells: shape(id).cells });
const EMPTY = Array<number>(SIZE * SIZE).fill(0);
const dots = (): Piece[] => [piece("dot"), piece("dot"), piece("dot")];

describe("parseMove", () => {
  test("takes exactly a placement", () => {
    expect(boxFort.parseMove({ k: "place", slot: 2, row: 7, col: 0 })).toEqual({ k: "place", slot: 2, row: 7, col: 0 });
  });

  test.each([
    ["null", null],
    ["a string", "place"],
    ["an array", [0, 1, 2]],
    ["another kind", { k: "hint", slot: 0, row: 0, col: 0 }],
    ["an extra key", { k: "place", slot: 0, row: 0, col: 0, points: 999 }],
    ["a missing key", { k: "place", slot: 0, row: 0 }],
    ["a slot past the set", { k: "place", slot: 3, row: 0, col: 0 }],
    ["a negative slot", { k: "place", slot: -1, row: 0, col: 0 }],
    ["a row off the rug", { k: "place", slot: 0, row: 8, col: 0 }],
    ["a negative col", { k: "place", slot: 0, row: 0, col: -1 }],
    ["a fraction", { k: "place", slot: 0, row: 1.5, col: 0 }],
    ["a string number", { k: "place", slot: "0", row: 0, col: 0 }],
  ])("refuses %s", (_, raw) => {
    expect(boxFort.parseMove(raw)).toBeNull();
  });
});

describe("the puzzle a client sees", () => {
  const p = boxFort.make(createRng([5, 6, 7, 8]), 5);

  test("publicPuzzle is the rug, the set count and the first set, nothing more", () => {
    expect(boxFort.publicPuzzle(p)).toEqual({ rug: p.rug, sets: p.sets.length, pieces: p.sets[0] });
  });

  test("init starts at the first set", () => {
    const s = boxFort.init(p);
    expect(boxFort.publicState(p, s)).toEqual<BoxFortPublicState>({
      rug: p.rug,
      set: 0,
      sets: p.sets.length,
      pieces: p.sets[0]!,
      placed: [false, false, false],
      points: 0,
      combo: 0,
      lines: 0,
      over: null,
    });
    expect(boxFort.progress(p, s)).toBe(0);
  });

  test.each([1, 2, 3, 4, 5, 6, 7] as DayLevel[])(
    "level %s: no future set ever leaks, and each set comes after the third piece",
    (level) => {
      const day = boxFort.make(createRng([level, 2, 3, 4]), level);
      let s = boxFort.init(day);
      let placedInSet = 0;
      for (;;) {
        const view = boxFort.publicState(day, s) as BoxFortPublicState;
        expect(Object.keys(view).sort()).toEqual(["combo", "lines", "over", "pieces", "placed", "points", "rug", "set", "sets"]);
        expect(view.pieces).toEqual(day.sets[view.set]);
        const move = greedyMove(view.rug, view.pieces, view.placed);
        if (move === null) break;
        const out = boxFort.apply(day, s, move, 1000);
        if (!out.ok) throw new Error("greedy moves are legal");
        placedInSet++;
        if (out.reveal !== undefined) {
          expect(placedInSet).toBe(3);
          expect(out.reveal).toEqual({ set: view.set + 1, pieces: day.sets[view.set + 1] });
          placedInSet = 0;
        } else if (placedInSet === 3) {
          expect(out.state.over).not.toBeNull(); // the last set: nothing more to deal
        }
        s = out.state;
        if (out.end !== undefined) {
          expect(out.end).toBe("done");
          break;
        }
      }
      expect(s.over).not.toBeNull();
    },
  );
});

test("the greedy player passes when nothing fits", () => {
  expect(greedyMove(Array<number>(SIZE * SIZE).fill(CLUTTER), dots(), [false, false, false])).toBeNull();
  expect(greedyMove(EMPTY, dots(), [true, true, true])).toBeNull();
});

describe("apply", () => {
  const day = (rug: number[], sets: Piece[][]): BoxFortPuzzle => ({ rug, sets });

  test("a placement that leaves room carries on", () => {
    const p = day(EMPTY, [dots(), dots()]);
    const out = boxFort.apply(p, boxFort.init(p), { k: "place", slot: 1, row: 3, col: 3 }, 500);
    expect(out).toMatchObject({ ok: true });
    expect(out.ok && out.end).toBeUndefined();
    expect(out.ok && out.reveal).toBeUndefined();
    expect(out.ok && out.state.placed).toEqual([false, true, false]);
  });

  test("a spot that doesn't fit, or a placed slot, is illegal and changes nothing", () => {
    const rug = [...EMPTY];
    rug[0] = CLUTTER;
    const p = day(rug, [dots(), dots()]);
    const s = boxFort.init(p);
    expect(boxFort.apply(p, s, { k: "place", slot: 0, row: 0, col: 0 }, 500)).toEqual({ ok: false, reason: "illegal" });
    const once = boxFort.apply(p, s, { k: "place", slot: 0, row: 1, col: 1 }, 500);
    if (!once.ok) throw new Error("legal");
    expect(boxFort.apply(p, once.state, { k: "place", slot: 0, row: 2, col: 2 }, 500)).toEqual({ ok: false, reason: "illegal" });
  });

  test("a dealt set that can't fit ends the run, and is still revealed", () => {
    // Every other spot is a box: dots fit, a 2 by 2 never does.
    const rug = EMPTY.map((_, i) => ((Math.floor(i / SIZE) + (i % SIZE)) % 2 === 0 ? CLUTTER : 0));
    const big = [piece("sq2"), piece("sq2"), piece("sq2")];
    const p = day(rug, [dots(), big, dots()]);
    let s = boxFort.init(p);
    for (const [slot, col] of [
      [0, 1],
      [1, 3],
    ] as const) {
      const out = boxFort.apply(p, s, { k: "place", slot, row: 0, col }, 500);
      if (!out.ok) throw new Error("legal");
      s = out.state;
    }
    const last = boxFort.apply(p, s, { k: "place", slot: 2, row: 0, col: 5 }, 500);
    expect(last).toMatchObject({ ok: true, end: "done", reveal: { set: 1, pieces: big } });
    if (!last.ok) throw new Error("legal");
    expect(last.state.over).toBe("stuck");
    expect(boxFort.apply(p, last.state, { k: "place", slot: 0, row: 1, col: 1 }, 500)).toEqual({ ok: false, reason: "over" });
  });

  test("placing the last set is the full fort", () => {
    const p = day(EMPTY, [dots()]);
    let s = boxFort.init(p);
    for (const slot of [0, 1, 2]) {
      const out = boxFort.apply(p, s, { k: "place", slot, row: 4, col: slot }, 500);
      if (!out.ok) throw new Error("legal");
      expect(out.reveal).toBeUndefined();
      expect(out.end).toBe(slot === 2 ? "done" : undefined);
      s = out.state;
    }
    expect(s.over).toBe("full");
    expect(s.points).toBe(3 + FULL_FORT);
    expect(boxFort.progress(p, s)).toBe(1);
    expect(boxFort.apply(p, s, { k: "place", slot: 0, row: 0, col: 0 }, 500)).toEqual({ ok: false, reason: "over" });
  });

  test("progress counts placed pieces over the whole day", () => {
    const p = day(EMPTY, [dots(), dots()]);
    const out = boxFort.apply(p, boxFort.init(p), { k: "place", slot: 0, row: 0, col: 0 }, 500);
    if (!out.ok) throw new Error("legal");
    expect(boxFort.progress(p, out.state)).toBeCloseTo(1 / 6);
  });
});

describe("the result and the board", () => {
  const p = boxFort.make(createRng([1, 1, 1, 1]), 1);

  test("result is the server's points, no hints, the outcome given", () => {
    const s = { ...boxFort.init(p), points: 321 };
    expect(boxFort.result(p, s, "done", 95_000, 0)).toEqual({
      outcome: "done",
      timeMs: 95_000,
      hints: 0,
      points: 321,
      progress: 0,
    });
    expect(boxFort.result(p, s, "closed", 1, 0).outcome).toBe("closed");
  });

  test("no hints", () => {
    expect(boxFort.hint(p, boxFort.init(p))).toBeNull();
  });

  test("compare ranks points first, then the faster time", () => {
    const r = (points: number, timeMs: number): DailyResult => ({
      game: "box-fort",
      date: "2027-01-04",
      number: 1,
      outcome: "done",
      timeMs,
      hints: 0,
      tooFast: false,
      points,
      progress: 1,
    });
    const ranked = [r(100, 50_000), r(300, 200_000), r(300, 90_000), r(0, 10_000)].sort(boxFort.compare);
    expect(ranked.map((x) => [x.points, x.timeMs])).toEqual([
      [300, 90_000],
      [300, 200_000],
      [100, 50_000],
      [0, 10_000],
    ]);
    const noPoints: DailyResult = { ...r(5, 1), points: undefined };
    expect(boxFort.compare(noPoints, r(1, 1))).toBeGreaterThan(0);
    expect(boxFort.compare(r(1, 1), noPoints)).toBeLessThan(0);
  });

  test("floors and spacing", () => {
    expect(Object.values(boxFort.floorMs)).toEqual([20_000, 20_000, 20_000, 20_000, 20_000, 20_000, 20_000]);
    expect(boxFort.minMoveGapMs).toBe(0);
    expect(boxFort.id).toBe("box-fort");
  });
});
