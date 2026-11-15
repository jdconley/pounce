import { describe, expect, test } from "vitest";

import { checkDraft, ghostOf, placedThisTurn, sortRack, toNewSet, toRack, toSet } from "../src/table/tiles-draft";

// Fish 1-13 are ids 0-12; mouse 1-13 are 26-38; Yarn is 104.
describe("a Tuna Tiles turn on this device", () => {
  const base = [[0, 1, 2]];
  test("pieces move between the rack, sets and new sets", () => {
    let d = { table: base.map((s) => [...s]), rack: [3, 26, 104] };
    d = toSet(d, 3, 0, 3);
    expect(d).toEqual({ table: [[0, 1, 2, 3]], rack: [26, 104] });
    d = toNewSet(d, 26);
    expect(d.table).toEqual([[0, 1, 2, 3], [26]]);
    d = toRack(d, 26, 0);
    expect(d).toEqual({ table: [[0, 1, 2, 3]], rack: [26, 104] });
    expect(placedThisTurn(base, 3)).toBe(true);
    expect(placedThisTurn(base, 1)).toBe(false);
  });

  test("whether it plays is the server's checkPlay", () => {
    const before = checkDraft(base, [3, 4, 5], true, { table: base, rack: [3, 4, 5] });
    expect(before.changed).toBe(false);
    const good = checkDraft(base, [3, 4, 5], true, { table: [[0, 1, 2, 3]], rack: [4, 5] });
    expect(good.check).toEqual({ ok: true, placed: [3], points: 10 });
    expect(good.marks).toEqual(["good"]);
    const bad = checkDraft(base, [3, 30], true, { table: [[0, 1, 2], [3, 30]], rack: [] });
    expect(bad.check).toEqual({ ok: false, error: "bad_set" });
    expect(bad.marks).toEqual(["kept", "bad"]);
    const low = checkDraft([], [0, 1, 2], false, { table: [[0, 1, 2]], rack: [] });
    expect(low.opening).toBe(6);
    expect(low.check).toEqual({ ok: false, error: "opening_too_low" });
  });

  test("a Yarn shows the number it stands for; racks sort by number or toy", () => {
    expect(ghostOf([0, 104, 2], 1)).toBe(2);
    expect(ghostOf([0, 104], 1)).toBeNull();
    expect(sortRack([104, 27, 1, 26], "number")).toEqual([26, 1, 27, 104]);
    expect(sortRack([104, 27, 1, 26], "toy")).toEqual([1, 26, 27, 104]);
  });
});
