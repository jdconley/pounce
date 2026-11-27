import { describe, expect, it } from "vitest";

import { applyHit, fits, highest, newBox, receiveJunk, setDown, trickWeights, turn, useTrick, type Box, type SetDown } from "./box";
import { fromText, toText } from "./codec";
import { toyAt } from "./queue";

import type { ToyId } from "./toys";
import type { Seed } from "../rules/rng";

const SEED: Seed = [7, 7, 7, 7];
const FULL = "############";

/** The first queue index that deals `toy` for SEED. */
const nFor = (toy: ToyId): number => {
  for (let n = 0; n < 64; n++) if (toyAt(SEED, n) === toy) return n;
  throw new Error(`no ${toy}`);
};

/** A box with these bottom rows and tricks, holding toy `toy` (box.next set to its index). */
const boxWith = (rows: string[], toy: ToyId, extra: Partial<Box> = {}, tricks: string[] = []): Box => ({
  ...newBox([1, 2, 3, 4]),
  ...fromText(rows, tricks),
  next: nFor(toy),
  ...extra,
});

const ok = (r: SetDown | { error: string }): SetDown => {
  if ("error" in r) throw new Error(r.error);
  return r;
};

/** The long stick turned upright fills column 0, rows y to y+3, at x = -2. */
const upright = (b: Box, landed: number[] = []) => setDown(b, SEED, b.next, 1, -2, 0, landed);

/** `k` full rows except column 0. */
const notch = (k: number): string[] => Array.from({ length: k }, () => ".###########");

describe("setDown refuses", () => {
  it("a toy that isn't the one in hand", () => {
    const b = boxWith([], "i4");
    expect(setDown(b, SEED, b.next + 1, 0, 0, 0, [])).toEqual({ error: "not_next" });
  });

  it("an overlap or a cell outside the box", () => {
    const b = boxWith(["#..........."], "i4");
    expect(setDown(b, SEED, b.next, 1, -2, 0, [])).toEqual({ error: "bad_place" });
    expect(setDown(b, SEED, b.next, 0, 9, -2, [])).toEqual({ error: "bad_place" });
  });

  it("a toy that could still fall", () => {
    const b = boxWith([], "i4");
    expect(setDown(b, SEED, b.next, 1, -2, 3, [])).toEqual({ error: "not_resting" });
  });

  it("landing junk on a set-down that clears rows, or out of order", () => {
    const waiting = [{ id: 1, rows: 1, gap: 3 }, { id: 2, rows: 1, gap: 4 }];
    expect(upright(boxWith(notch(1), "i4", { waiting }), [1])).toEqual({ error: "bad_landed" });
    expect(upright(boxWith([], "i4", { waiting }), [2])).toEqual({ error: "bad_landed" });
    expect(upright(boxWith([], "i4", { waiting }), [3])).toEqual({ error: "bad_landed" });
  });

  it("anything once the box is out", () => {
    expect(upright(boxWith([], "i4", { out: true }))).toEqual({ error: "box_out" });
  });
});

describe("clearing rows", () => {
  it.each([
    [1, 0],
    [2, 1],
    [3, 2],
    [4, 4],
  ])("%i rows cleared send %i", (rows, sent) => {
    const r = ok(upright(boxWith(notch(rows), "i4")));
    expect(r.cleared).toBe(rows);
    expect(r.sent).toBe(sent);
    expect(r.box.rows).toBe(rows);
    expect(r.box.next).toBe(nFor("i4") + 1);
  });

  it("moves the rows above down", () => {
    const r = ok(upright(boxWith(["...#........", ...notch(1)], "i4")));
    // The stick's top three cells stay in column 0; the lone cell above the cleared row drops to y 0.
    expect(toText(r.box).cells.slice(-3)).toEqual(["3...........", "3...........", "3..#........"]);
  });
});

describe("blocking", () => {
  it("cancels waiting junk oldest first, and only the rest goes out", () => {
    const waiting = [{ id: 1, rows: 2, gap: 0 }, { id: 2, rows: 3, gap: 0 }];
    const r1 = ok(upright(boxWith(notch(3), "i4", { waiting })));
    expect(r1.blocked).toEqual([{ id: 1, rows: 2 }]);
    expect(r1.sent).toBe(0);
    expect(r1.box.waiting).toEqual([{ id: 2, rows: 3, gap: 0 }]);

    const r2 = ok(upright(boxWith(notch(4), "i4", { waiting: r1.box.waiting })));
    expect(r2.blocked).toEqual([{ id: 2, rows: 3 }]);
    expect(r2.sent).toBe(1);
    expect(r2.box.waiting).toEqual([]);
  });

  it("can block part of an attack", () => {
    const r = ok(upright(boxWith(notch(2), "i4", { waiting: [{ id: 5, rows: 3, gap: 0 }] })));
    expect(r.blocked).toEqual([{ id: 5, rows: 1 }]);
    expect(r.box.waiting).toEqual([{ id: 5, rows: 2, gap: 0 }]);
  });
});

describe("landing junk", () => {
  it("pushes the rows in under the stack with one gap, tricks moving with their cells", () => {
    const b = boxWith(["......#....."], "i4", { waiting: [{ id: 1, rows: 2, gap: 7 }, { id: 2, rows: 1, gap: 2 }] }, ["......c....."]);
    const r = ok(setDown(b, SEED, b.next, 0, 0, -2, [1]));
    const { cells, tricks } = toText(r.box);
    expect(cells.slice(-3)).toEqual(["3333..#.....", "#######.####", "#######.####"]);
    expect(tricks.slice(-3)).toEqual(["......c.....", "............", "............"]);
    expect(r.box.waiting).toEqual([{ id: 2, rows: 1, gap: 2 }]);
  });

  it("lands several attacks in order", () => {
    const b = boxWith([], "i4", { waiting: [{ id: 1, rows: 1, gap: 0 }, { id: 2, rows: 1, gap: 11 }] });
    const r = ok(setDown(b, SEED, b.next, 0, 0, -2, [1, 2]));
    // The oldest lands first; the next pushes in under it.
    expect(toText(r.box).cells.slice(-3)).toEqual(["3333........", ".###########", "###########."]);
  });
});

describe("tricks", () => {
  it("adds one trick per row cleared, on filled cells that had none, from the box's own generator", () => {
    const b = boxWith([".#########..", ...notch(2)], "i4");
    const r = ok(upright(b));
    const placed = r.box.tricks.map((t, i) => [t, i] as const).filter(([t]) => t !== 0);
    expect(placed).toHaveLength(2);
    for (const [, i] of placed) expect(r.box.cells[i]).not.toBe(0);
    expect(r.box.rng).not.toEqual(b.rng);
    expect(ok(upright(b))).toEqual(r);
  });

  it("uses the comeback weights while a cell is in the top third", () => {
    expect(trickWeights(boxWith([], "i4"))).toEqual([20, 15, 12, 18, 12, 10, 3, 3]);
    const high = boxWith(["#", ...Array.from({ length: 12 }, () => "")], "i4");
    expect(highest(high)).toBe(12);
    expect(trickWeights(high)).toEqual([20, 15, 12, 36, 12, 10, 9, 9]);
  });

  it("pockets tricks on cleared rows, bottom row first, left to right, up to 6", () => {
    const tricks = [".h.........g", ".abcdef....."];
    const b = boxWith(notch(2), "i4", {}, tricks);
    const r = ok(upright(b));
    expect(r.pocketed).toEqual(["hairball", "swipe", "catnip", "scoop", "settle", "nap"]);
    expect(r.box.held).toHaveLength(6);
  });

  it("uses a held trick by slot", () => {
    const b = boxWith([], "i4", { held: ["nap", "bath"] });
    expect(useTrick(b, 1)?.trick).toBe("bath");
    expect(useTrick(b, 1)?.box.held).toEqual(["nap"]);
    expect(useTrick(b, 2)).toBeNull();
  });
});

describe("going out", () => {
  it("when a set-down leaves a cell above row 17", () => {
    // Column 0 is filled to row 14; the upright stick set on it reaches row 18.
    const tall = boxWith(Array.from({ length: 15 }, () => "#..........."), "i4");
    const over = ok(setDown(tall, SEED, tall.next, 1, -2, 15, []));
    expect(over.out).toBe(true);
    // One row lower it would stay in the box.
    const lower = boxWith(Array.from({ length: 14 }, () => "#..........."), "i4");
    expect(ok(setDown(lower, SEED, lower.next, 1, -2, 14, [])).out).toBe(false);
  });

  it("not while every toy can still appear above the stack", () => {
    // A tower up to row 17 leaves row 18, where toys appear, clear: still in.
    const tower = Array.from({ length: 18 }, () => "....####....");
    const b = boxWith(tower, "i4");
    expect(ok(setDown(b, SEED, b.next, 1, -2, 0, [])).out).toBe(false);
  });
});

describe("turning", () => {
  it("turns in place, or takes the first nudge that fits", () => {
    const b = boxWith([], "l4");
    expect(turn(b, "l4", 0, 4, 5, 1)).toEqual({ rot: 1, x: 4, y: 5 });
    // Against the left wall the upright long stick must nudge right to lie flat.
    expect(turn(boxWith([], "i4"), "i4", 1, -2, 5, 1)).toEqual({ rot: 2, x: 0, y: 5 });
    expect(turn(boxWith([], "i4"), "i4", 0, 0, 5, -1)).toEqual({ rot: 3, x: 0, y: 5 });
  });

  it("refuses when no nudge fits", () => {
    const walls = boxWith(Array.from({ length: 8 }, () => "###.########"), "i4");
    expect(fits(walls, "i4", 1, 1, 0)).toBe(true);
    expect(turn(walls, "i4", 1, 1, 0, 1)).toBeNull();
  });
});

describe("hits", () => {
  it("Hairball adds one junk row at once", () => {
    const { box } = applyHit(boxWith(["1..........."], "i4"), { k: "hairball", gap: 5 });
    expect(toText(box).cells.slice(-2)).toEqual(["1...........", "#####.######"]);
  });

  it("Paw Swipe shoves each row, wrapping, tricks along", () => {
    const shifts = new Array<number>(22).fill(0);
    shifts[0] = 2;
    shifts[1] = -1;
    const { box } = applyHit(boxWith(["1..........2", "12.........."], "i4", {}, ["a...........", "b..........."]), { k: "swipe", shifts });
    expect(toText(box).cells.slice(-2)).toEqual(["..........21", "..12........"]);
    expect(toText(box).tricks.slice(-2)).toEqual(["...........a", "..b........."]);
  });

  it("Scoop removes the bottom two rows and pockets their tricks", () => {
    const { box, pocketed } = applyHit(boxWith(["3...........", FULL, FULL], "i4", {}, ["", "...a........", "b..........."]), { k: "scoop" });
    expect(toText(box).cells.slice(-1)).toEqual(["3..........."]);
    expect(pocketed).toEqual(["swipe", "hairball"]);
  });

  it("Settle drops every cell straight down, then clears full rows with no new tricks", () => {
    const { box, pocketed } = applyHit(boxWith(["#.##########", ".#..........", "............"].slice(0, 2), "i4", {}, ["a...........", ""]), { k: "settle" });
    expect(toText(box).cells.slice(-1)).toEqual(["............"]);
    expect(pocketed).toEqual(["hairball"]);
    expect(box.tricks.every((t) => t === 0)).toBe(true);
  });

  it("Bath empties the box and its waiting junk", () => {
    const { box } = applyHit(boxWith([FULL, FULL], "i4", { waiting: [{ id: 1, rows: 3, gap: 0 }], held: ["nap"] }, [".a.........."]), { k: "bath" });
    expect(highest(box)).toBe(-1);
    expect(box.tricks.every((t) => t === 0)).toBe(true);
    expect(box.waiting).toEqual([]);
    expect(box.held).toEqual(["nap"]);
  });

  it("Swap takes the other box's cells and tricks, and keeps its own held tricks and waiting junk", () => {
    const other = boxWith(["5..........."], "i4", {}, ["c..........."]);
    const mine = boxWith([FULL], "i4", { held: ["bath"], waiting: [{ id: 9, rows: 1, gap: 0 }] });
    const { box } = applyHit(mine, { k: "swap", cells: other.cells, tricks: other.tricks });
    expect(toText(box)).toEqual(toText(other));
    expect(box.held).toEqual(["bath"]);
    expect(box.waiting).toEqual([{ id: 9, rows: 1, gap: 0 }]);
  });

  it("Catnip and Nap change nothing in the box", () => {
    const b = boxWith([FULL], "i4");
    expect(applyHit(b, { k: "catnip" }).box).toEqual(b);
    expect(applyHit(b, { k: "nap" }).box).toEqual(b);
  });

  it("any hit leaving a cell above row 17 puts the box out", () => {
    const b = boxWith(Array.from({ length: 18 }, () => "#..........."), "i4");
    expect(applyHit(b, { k: "hairball", gap: 3 }).box.out).toBe(true);
  });

  it("junk arriving starts its wait", () => {
    expect(receiveJunk(newBox([1, 1, 1, 1]), { id: 4, rows: 2, gap: 6 }).waiting).toEqual([{ id: 4, rows: 2, gap: 6 }]);
  });
});
