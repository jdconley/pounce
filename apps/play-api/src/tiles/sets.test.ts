import { readFileSync } from "node:fs";

import { describe, expect, test } from "vitest";

import { bell, feather, fish, mouse, YARN, YARN2 } from "../../tests/tiles-helpers";

import { readSet, sameSet } from "./sets";

type Vector = { name: string; tiles: number[]; kind: "run" | "group" | null; points?: number; start?: number };

/** Shared with the iOS client, which checks sets the same way to light up a valid one before submit. */
const vectors = JSON.parse(
  readFileSync(new URL("../../fixtures/tiles-sets.json", import.meta.url), "utf8"),
) as Vector[];

describe("readSet: shared vectors", () => {
  test.each(vectors)("$name", ({ tiles, kind, points, start }) => {
    const reading = readSet(tiles);
    expect(reading?.kind ?? null).toBe(kind);
    if (points !== undefined) expect(reading?.points).toBe(points);
    if (start !== undefined) expect(reading).toMatchObject({ start });
  });

  test("every vector that is a set says what it is worth", () => {
    for (const v of vectors) expect(v.kind === null || v.points !== undefined, v.name).toBe(true);
  });
});

describe("readSet: runs", () => {
  test("reads the suit and both ends", () => {
    expect(readSet([mouse(4), mouse(5), mouse(6), mouse(7)])).toEqual({
      kind: "run",
      suit: "mouse",
      start: 4,
      end: 7,
      points: 22,
    });
  });

  test("a Yarn stands for the number its place in the run gives it, in every place", () => {
    const run = [bell(5), bell(6), bell(7), bell(8), bell(9)];
    for (let i = 0; i < run.length; i++) {
      const withYarn = run.map((id, j) => (j === i ? YARN : id));
      expect(readSet(withYarn), `Yarn at ${i}`).toEqual({ kind: "run", suit: "bell", start: 5, end: 9, points: 35 });
    }
  });

  test("two Yarn fit any two places of a run", () => {
    const run = [feather(9), feather(10), feather(11), feather(12), feather(13)];
    for (let i = 0; i < run.length; i++) {
      for (let j = i + 1; j < run.length; j++) {
        const withYarn = run.map((id, k) => (k === i ? YARN : k === j ? YARN2 : id));
        expect(readSet(withYarn), `Yarn at ${i} and ${j}`).toMatchObject({ kind: "run", start: 9, end: 13, points: 55 });
      }
    }
  });

  test("a Yarn makes a run longer at either end, but never past 1 or 13", () => {
    expect(readSet([YARN, fish(2), fish(3), fish(4)])).toMatchObject({ start: 1, end: 4, points: 10 });
    expect(readSet([YARN, fish(1), fish(2), fish(3)])).toBeNull();
    expect(readSet([fish(10), fish(11), fish(12), YARN])).toMatchObject({ start: 10, end: 13, points: 46 });
    expect(readSet([fish(11), fish(12), fish(13), YARN])).toBeNull();
    expect(readSet([YARN, YARN2, fish(2), fish(3)])).toBeNull();
    expect(readSet([fish(11), fish(12), YARN, YARN2])).toBeNull();
  });

  test("thirteen is the longest run: a Yarn has nowhere to go on a full one", () => {
    const full = Array.from({ length: 13 }, (_, i) => fish(i + 1));
    expect(readSet(full)).toMatchObject({ kind: "run", start: 1, end: 13 });
    expect(readSet([...full, YARN])).toBeNull();
    expect(readSet([YARN, ...full])).toBeNull();
  });

  test("the twin of a piece is the same number, so the two cannot share a run", () => {
    expect(readSet([fish(4), fish(4, true), fish(5)])).toBeNull();
    expect(readSet([fish(4), fish(5, true), fish(6)])).toMatchObject({ kind: "run", start: 4 });
  });
});

describe("readSet: groups", () => {
  test("a Yarn fits any place of a group of three or four", () => {
    const group = [fish(9), mouse(9), feather(9), bell(9)];
    for (const size of [3, 4]) {
      for (let i = 0; i < size; i++) {
        const withYarn = group.slice(0, size).map((id, j) => (j === i ? YARN : id));
        expect(readSet(withYarn), `Yarn at ${i} of ${size}`).toEqual({ kind: "group", value: 9, points: 9 * size });
      }
    }
  });

  test("two Yarn and two pieces of different suits make a group of four", () => {
    expect(readSet([fish(2), YARN, mouse(2), YARN2])).toEqual({ kind: "group", value: 2, points: 8 });
  });

  test("a Yarn cannot make a fifth suit", () => {
    expect(readSet([fish(9), mouse(9), feather(9), bell(9), YARN])).toBeNull();
  });

  test("twins are the same suit, so they cannot share a group, with or without a Yarn", () => {
    expect(readSet([fish(9), fish(9, true), mouse(9)])).toBeNull();
    expect(readSet([fish(9), fish(9, true), YARN])).toBeNull();
  });
});

describe("readSet: one piece and two Yarn can be read both ways", () => {
  test("it is the reading worth more", () => {
    // 7, Yarn, Yarn: the run 7-8-9 (24) beats three 7s (21).
    expect(readSet([fish(7), YARN, YARN2])).toEqual({ kind: "run", suit: "fish", start: 7, end: 9, points: 24 });
    // Yarn, Yarn, 7: three 7s (21) beat the run 5-6-7 (18).
    expect(readSet([YARN, YARN2, fish(7)])).toEqual({ kind: "group", value: 7, points: 21 });
  });

  test("a tie is a run", () => {
    expect(readSet([YARN, fish(7), YARN2])).toEqual({ kind: "run", suit: "fish", start: 6, end: 8, points: 21 });
  });

  test("when the run would leave 1-13, it is the group", () => {
    expect(readSet([fish(13), YARN, YARN2])).toEqual({ kind: "group", value: 13, points: 39 });
    expect(readSet([YARN, fish(13), YARN2])).toEqual({ kind: "group", value: 13, points: 39 });
    expect(readSet([YARN, YARN2, fish(2)])).toEqual({ kind: "group", value: 2, points: 6 });
  });

  test("two pieces and a Yarn are never both: the pieces settle it", () => {
    expect(readSet([fish(7), mouse(7), YARN])?.kind).toBe("group");
    expect(readSet([fish(7), fish(8), YARN])?.kind).toBe("run");
    expect(readSet([fish(7), mouse(8), YARN])).toBeNull();
  });
});

describe("sameSet", () => {
  test("the same pieces in the same order", () => {
    expect(sameSet([1, 2, 3], [1, 2, 3])).toBe(true);
    expect(sameSet([], [])).toBe(true);
  });

  test("not in another order, and not a longer or shorter set", () => {
    expect(sameSet([1, 2, 3], [3, 2, 1])).toBe(false);
    expect(sameSet([1, 2, 3], [1, 2, 3, 4])).toBe(false);
    expect(sameSet([1, 2, 3, 4], [1, 2, 3])).toBe(false);
  });
});
