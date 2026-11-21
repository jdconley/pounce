import { describe, expect, test } from "vitest";

import { shape, SHAPES } from "./pieces";

describe("SHAPES", () => {
  test("40 shapes: 10 easy, 16 medium, 14 awkward", () => {
    expect(SHAPES).toHaveLength(40);
    expect(SHAPES.filter((s) => s.tier === 0)).toHaveLength(10);
    expect(SHAPES.filter((s) => s.tier === 1)).toHaveLength(16);
    expect(SHAPES.filter((s) => s.tier === 2)).toHaveLength(14);
  });

  test("ids are unique", () => {
    expect(new Set(SHAPES.map((s) => s.id)).size).toBe(SHAPES.length);
  });

  test("no two shapes have the same boxes", () => {
    const keys = SHAPES.map((s) =>
      s.cells
        .map(([r, c]) => r * 8 + c)
        .sort((a, b) => a - b)
        .join(","),
    );
    expect(new Set(keys).size).toBe(SHAPES.length);
  });

  test.each(SHAPES)("$id starts at the top-left, has no repeats and fits in 5 by 5", ({ cells }) => {
    expect(Math.min(...cells.map(([r]) => r))).toBe(0);
    expect(Math.min(...cells.map(([, c]) => c))).toBe(0);
    expect(Math.max(...cells.flat())).toBeLessThan(5);
    expect(new Set(cells.map(([r, c]) => r * 8 + c)).size).toBe(cells.length);
  });

  test("the awkward ones include our diagonal paws and the plus", () => {
    expect(shape("paws-a").cells).toEqual([
      [0, 0],
      [1, 1],
    ]);
    expect(shape("plus").tier).toBe(2);
    expect(shape("sq3").cells).toHaveLength(9);
  });

  test("an unknown id throws", () => {
    expect(() => shape("nope")).toThrow(RangeError);
  });
});
