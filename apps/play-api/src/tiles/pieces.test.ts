import { describe, expect, test } from "vitest";

import { ALL_TILE_IDS, isTileId, isYarn, rackPoints, rackTotal, SUITS, tile } from "./pieces";

describe("the 106 pieces", () => {
  test("ids run 0-105", () => {
    expect(ALL_TILE_IDS).toHaveLength(106);
    expect(ALL_TILE_IDS[0]).toBe(0);
    expect(ALL_TILE_IDS[105]).toBe(105);
  });

  test("every number 1-13 appears twice in each of four suits, plus two Yarn", () => {
    const counts = new Map<string, number>();
    let yarn = 0;
    for (const id of ALL_TILE_IDS) {
      const t = tile(id);
      if (t.kind === "yarn") yarn++;
      else counts.set(`${t.suit}:${t.value}`, (counts.get(`${t.suit}:${t.value}`) ?? 0) + 1);
    }
    expect(yarn).toBe(2);
    expect(counts.size).toBe(52);
    expect([...counts.values()].every((n) => n === 2)).toBe(true);
  });

  test("ids decode by suit, then copy, then number", () => {
    expect(tile(0)).toEqual({ id: 0, kind: "number", value: 1, suit: "fish" });
    expect(tile(12)).toEqual({ id: 12, kind: "number", value: 13, suit: "fish" });
    expect(tile(13)).toEqual({ id: 13, kind: "number", value: 1, suit: "fish" });
    expect(tile(26)).toEqual({ id: 26, kind: "number", value: 1, suit: "mouse" });
    expect(tile(77)).toEqual({ id: 77, kind: "number", value: 13, suit: "feather" });
    expect(tile(103)).toEqual({ id: 103, kind: "number", value: 13, suit: "bell" });
    expect(tile(104)).toEqual({ id: 104, kind: "yarn" });
    expect(tile(105)).toEqual({ id: 105, kind: "yarn" });
    expect(SUITS).toEqual(["fish", "mouse", "feather", "bell"]);
  });

  test.each([-1, 106, 1.5, Number.NaN, "3", null, undefined])("%s is not a piece", (id) => {
    expect(isTileId(id)).toBe(false);
    expect(() => tile(id as number)).toThrow(RangeError);
  });

  test("isYarn is true only for 104 and 105", () => {
    expect(ALL_TILE_IDS.filter(isYarn)).toEqual([104, 105]);
  });

  test("a piece left on a rack costs its number, and a Yarn 30", () => {
    expect(rackPoints(0)).toBe(1);
    expect(rackPoints(25)).toBe(13);
    expect(rackPoints(104)).toBe(30);
    expect(rackTotal([])).toBe(0);
    expect(rackTotal([0, 25, 104, 105])).toBe(74);
  });

  test("the whole set adds up to 788", () => {
    // Eight copies of 1-13 (8 x 91) and two Yarn at 30.
    expect(rackTotal(ALL_TILE_IDS)).toBe(788);
  });
});
