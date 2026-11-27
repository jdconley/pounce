import { describe, expect, it } from "vitest";

import { checkInk, compact, freshEasel, MAX_POINTS, MAX_STROKES, parseOps, wipes, type InkEasel, type InkOp } from "./ink";

/** Applies batches in order, throwing at the first refusal. */
function draw(...batches: unknown[][]): InkEasel {
  let easel = freshEasel();
  for (const ops of batches) {
    const r = checkInk(ops, easel);
    if (!r.ok) throw new Error(`refused ${JSON.stringify(ops)} (full: ${r.full})`);
    easel = r.easel;
  }
  return easel;
}
const refused = (easel: InkEasel, ops: unknown) => {
  const r = checkInk(ops, easel);
  return r.ok ? "ok" : r.full ? "full" : "bad";
};

describe("parseOps: the shape of spec §6.2", () => {
  it("takes every op", () => {
    const ops = [["s", 0, 0, 1, 384, 210, 3, -1], ["p", 0, 2, 2], ["u", 0], ["c"]];
    expect(parseOps(ops)).toEqual(ops);
    expect(parseOps([["s", 0, 8, 2, 0, 0]])).toEqual([["s", 0, 8, 2, 0, 0]]);
    expect(parseOps([["s", 0, 0, 0, 767, 1023, -768, 768, 768, -768]])).not.toBeNull();
  });

  it.each([
    ["not an array", { s: 1 }],
    ["empty", []],
    ["an op that is not an array", ["c"]],
    ["an unknown op", [["x", 0]]],
    ["an empty op", [[]]],
    ["c with more", [["c", 0]]],
    ["u with no id", [["u"]]],
    ["u with more", [["u", 0, 1]]],
    ["a negative id", [["u", -1]]],
    ["a fractional id", [["u", 0.5]]],
    ["a string id", [["u", "0"]]],
    ["s too short", [["s", 0, 0, 1, 384]]],
    ["s with half a delta", [["s", 0, 0, 1, 384, 210, 3]]],
    ["colour 9", [["s", 0, 9, 1, 0, 0]]],
    ["colour -1", [["s", 0, -1, 1, 0, 0]]],
    ["width 3", [["s", 0, 0, 3, 0, 0]]],
    ["x 768", [["s", 0, 0, 0, 768, 0]]],
    ["y 1024", [["s", 0, 0, 0, 0, 1024]]],
    ["x -1", [["s", 0, 0, 0, -1, 0]]],
    ["a delta of 769", [["s", 0, 0, 0, 0, 0, 769, 0]]],
    ["a delta of -769", [["p", 0, 0, -769]]],
    ["a fractional delta", [["p", 0, 0.5, 1]]],
    ["a string delta", [["p", 0, "1", 1]]],
    ["p with no deltas", [["p", 0]]],
    ["p with half a delta", [["p", 0, 1]]],
    ["a null op", [null]],
  ])("refuses %s", (_, ops) => {
    expect(parseOps(ops)).toBeNull();
    expect(refused(freshEasel(), ops)).toBe("bad");
  });

  it("wipes says whether a batch starts with a clear", () => {
    expect(wipes([["c"], ["s", 0, 0, 0, 1, 1]])).toBe(true);
    expect(wipes([["s", 0, 0, 0, 1, 1], ["c"]])).toBe(false);
    expect(wipes([])).toBe(false);
  });
});

describe("checkInk against the easel", () => {
  it("stroke ids start at 0 and each new one is exactly the next", () => {
    expect(refused(freshEasel(), [["s", 1, 0, 0, 0, 0]])).toBe("bad");
    const e = draw([["s", 0, 0, 0, 0, 0]]);
    expect(refused(e, [["s", 0, 0, 0, 0, 0]])).toBe("bad");
    expect(refused(e, [["s", 2, 0, 0, 0, 0]])).toBe("bad");
    expect(refused(e, [["s", 1, 0, 0, 0, 0]])).toBe("ok");
    // An undo or a clear never gives an id back.
    expect(refused(draw([["s", 0, 0, 0, 0, 0], ["u", 0]]), [["s", 0, 0, 0, 0, 0]])).toBe("bad");
    expect(refused(draw([["s", 0, 0, 0, 0, 0], ["c"]]), [["s", 1, 0, 0, 0, 0]])).toBe("ok");
  });

  it("after a lost log (rebuilt), ids only have to go up", () => {
    const r = checkInk([["c"], ["s", 4, 0, 0, 0, 0], ["s", 9, 0, 0, 0, 0]], freshEasel(true));
    expect(r.ok).toBe(true);
    const e = (r as { easel: InkEasel }).easel;
    expect(refused(e, [["s", 9, 0, 0, 0, 0]])).toBe("bad");
    expect(refused(e, [["s", 13, 0, 0, 0, 0]])).toBe("ok");
  });

  it("p and u name a stroke that is on the easel", () => {
    const e = draw([["s", 0, 0, 0, 10, 10], ["s", 1, 0, 0, 10, 10]]);
    expect(refused(e, [["p", 2, 1, 1]])).toBe("bad");
    expect(refused(e, [["u", 2]])).toBe("bad");
    expect(refused(e, [["p", 0, 1, 1], ["u", 1]])).toBe("ok");
    const undone = draw([["s", 0, 0, 0, 10, 10], ["u", 0]]);
    expect(refused(undone, [["u", 0]])).toBe("bad");
    expect(refused(undone, [["p", 0, 1, 1]])).toBe("bad");
    const cleared = draw([["s", 0, 0, 0, 10, 10], ["c"]]);
    expect(refused(cleared, [["p", 0, 1, 1]])).toBe("bad");
    expect(refused(cleared, [["u", 0]])).toBe("bad");
    // In one batch too.
    expect(refused(freshEasel(), [["s", 0, 0, 0, 10, 10], ["u", 0], ["p", 0, 1, 1]])).toBe("bad");
  });

  it("the running point stays on the grid", () => {
    expect(refused(freshEasel(), [["s", 0, 0, 0, 760, 0, 7, 0]])).toBe("ok");
    expect(refused(freshEasel(), [["s", 0, 0, 0, 760, 0, 8, 0]])).toBe("bad");
    expect(refused(freshEasel(), [["s", 0, 0, 0, 0, 1000, 0, 23, 0, 1]])).toBe("bad");
    expect(refused(freshEasel(), [["s", 0, 0, 0, 5, 5, -5, -5]])).toBe("ok");
    expect(refused(freshEasel(), [["s", 0, 0, 0, 5, 5, -6, 0]])).toBe("bad");
    const e = draw([["s", 0, 0, 0, 767, 1023]]);
    expect(refused(e, [["p", 0, 1, 0]])).toBe("bad");
    expect(refused(e, [["p", 0, 0, 1]])).toBe("bad");
    expect(refused(e, [["p", 0, -767, -1023]])).toBe("bad");
    const left = draw([["s", 0, 0, 0, 767, 1023], ["p", 0, -767, -768]]);
    expect(refused(left, [["p", 0, 0, -255]])).toBe("ok");
    expect(refused(left, [["p", 0, 0, -256]])).toBe("bad");
  });

  it("a refused batch changes nothing", () => {
    const e = draw([["s", 0, 0, 0, 0, 0]]);
    const before = JSON.stringify(e);
    expect(refused(e, [["p", 0, 1, 1], ["s", 1, 0, 0, 0, 0], ["u", 7]])).toBe("bad");
    expect(JSON.stringify(e)).toBe(before);
    expect(refused(e, [["s", 1, 0, 0, 0, 0]])).toBe("ok");
  });

  it("caps an easel at 500 strokes", () => {
    let e = freshEasel();
    for (let id = 0; id < MAX_STROKES; id++) e = step(e, [["s", id, 0, 0, 0, 0]]);
    expect(MAX_STROKES).toBe(500);
    expect(e.strokes).toBe(MAX_STROKES);
    // Over the cap on the way is full, even if a clear follows in the same batch.
    expect(refused(e, [["s", MAX_STROKES, 0, 0, 0, 0], ["c"]])).toBe("full");
    expect(refused(e, [["s", MAX_STROKES, 0, 0, 0, 0]])).toBe("full");
    // Undo makes no room; a clear does.
    expect(refused(step(e, [["u", MAX_STROKES - 1]]), [["s", MAX_STROKES, 0, 0, 0, 0]])).toBe("full");
    expect(refused(step(e, [["c"]]), [["s", MAX_STROKES, 0, 0, 0, 0]])).toBe("ok");
  });

  it("caps an easel at 30 000 points", () => {
    expect(MAX_POINTS).toBe(30_000);
    // A stroke's start is a point, and each delta one more.
    let e = step(freshEasel(), [["s", 0, 0, 0, 0, 0]]);
    const wiggle = (n: number): InkOp => ["p", 0, ...Array.from({ length: n }, (_, i) => (i % 2 === 0 ? 1 : 0) * (Math.floor(i / 2) % 2 === 0 ? 1 : -1))] as InkOp;
    for (let i = 0; i < 29; i++) e = step(e, [wiggle(2000)]);
    e = step(e, [wiggle(1998)]);
    // 1 + 29 * 1000 + 999 = 30 000.
    expect(e.points).toBe(MAX_POINTS);
    expect(refused(e, [["p", 0, 0, 0]])).toBe("full");
    expect(refused(e, [["s", 1, 0, 0, 0, 0]])).toBe("full");
    expect(refused(e, [["u", 0]])).toBe("ok");
    expect(refused(step(e, [["c"]]), [["s", 1, 0, 0, 0, 0, 1, 1]])).toBe("ok");
  });

  it("a bad op in a full batch is bad, not full", () => {
    let e = freshEasel();
    for (let id = 0; id < MAX_STROKES; id++) e = step(e, [["s", id, 0, 0, 0, 0]]);
    expect(refused(e, [["u", 900]])).toBe("bad");
    expect(refused(e, [["s", 7, 0, 0, 0, 0]])).toBe("bad");
  });
});

describe("compact: the smallest drawing that looks the same", () => {
  it("inkSync after s,s,u,c,s carries one stroke", () => {
    const log: InkOp[] = [["s", 0, 1, 1, 10, 10, 1, 1], ["s", 1, 2, 1, 20, 20], ["u", 1], ["c"], ["s", 2, 3, 2, 30, 30, 2, 2]];
    expect(compact(log)).toEqual([["s", 2, 3, 2, 30, 30, 2, 2]]);
  });

  it("drops undone strokes and folds each stroke's points into its start, in stroke order", () => {
    const log: InkOp[] = [
      ["s", 0, 1, 1, 10, 10, 1, 1],
      ["p", 0, 2, 2],
      ["s", 1, 2, 0, 50, 50],
      ["s", 2, 3, 2, 30, 30],
      ["p", 2, 5, 5, 1, 1],
      ["u", 1],
      ["p", 0, 3, 3],
    ];
    expect(compact(log)).toEqual([
      ["s", 0, 1, 1, 10, 10, 1, 1, 2, 2, 3, 3],
      ["s", 2, 3, 2, 30, 30, 5, 5, 1, 1],
    ]);
  });

  it("a clear at the end leaves nothing, and never changes the log it is given", () => {
    const log: InkOp[] = [["s", 0, 1, 1, 10, 10], ["p", 0, 1, 1], ["c"]];
    expect(compact(log)).toEqual([]);
    const kept: InkOp[] = [["s", 0, 1, 1, 10, 10], ["p", 0, 1, 1]];
    compact(kept);
    expect(kept).toEqual([["s", 0, 1, 1, 10, 10], ["p", 0, 1, 1]]);
    expect(compact([])).toEqual([]);
    // Points for a stroke it never saw start (a log that was never checked) are left out.
    expect(compact([["p", 4, 1, 1], ["s", 5, 0, 0, 1, 1]])).toEqual([["s", 5, 0, 0, 1, 1]]);
  });

  it("compacting twice is the same as once", () => {
    const log: InkOp[] = [["s", 0, 1, 1, 10, 10, 1, 1], ["p", 0, 2, 2], ["s", 1, 0, 0, 0, 0], ["u", 0]];
    expect(compact(compact(log))).toEqual(compact(log));
  });
});

function step(easel: InkEasel, ops: unknown[]): InkEasel {
  const r = checkInk(ops, easel);
  if (!r.ok) throw new Error(`refused ${JSON.stringify(ops)}`);
  return r.easel;
}
