import { describe, expect, test } from "vitest";

import { seedOf } from "../../tests/seeds";

import { createRng, shuffle, type Seed } from "./rng";

const U32 = 2 ** 32;

describe("createRng", () => {
  test("matches the xoshiro128** 1.1 reference for seed [1, 2, 3, 4]", () => {
    const rng = createRng([1, 2, 3, 4]);
    // The first ten outputs of the published reference C implementation
    // (prng.di.unimi.it/xoshiro128starstar.c) from s = {1, 2, 3, 4}.
    expect(Array.from({ length: 10 }, () => rng() * U32)).toEqual([
      11520, 0, 5927040, 70819200, 2031721883, 1637235492, 1287239034, 3734860849, 3729100597, 4258142804,
    ]);
  });

  test("matches the reference for a seed using all 32 bits of every word", () => {
    const rng = createRng([0x9e3779b9, 0x243f6a88, 0xb7e15162, 0xdeadbeef]);
    expect(Array.from({ length: 6 }, () => rng() * U32)).toEqual([
      2463954730, 5524658, 74256371, 1905451993, 3123413897, 314453775,
    ]);
  });

  test("same seed yields the same sequence", () => {
    const a = createRng(seedOf(7));
    const b = createRng(seedOf(7));
    expect([a(), a(), a()]).toEqual([b(), b(), b()]);
  });

  test("seeds differing in any one word differ", () => {
    const base: Seed = [1, 2, 3, 4];
    const first = (seed: Seed) => {
      const rng = createRng(seed);
      return [rng(), rng(), rng()];
    };
    for (let word = 0; word < 4; word++) {
      const other = [...base] as Seed;
      other[word] = (other[word] as number) + 1;
      expect(first(other)).not.toEqual(first(base));
    }
  });

  test("does not alias or modify the seed", () => {
    const seed: Seed = [1, 2, 3, 4];
    const rng = createRng(seed);
    rng();
    rng();
    expect(seed).toEqual([1, 2, 3, 4]);
  });

  test("values are in [0, 1)", () => {
    const rng = createRng(seedOf(123));
    for (let i = 0; i < 1000; i++) {
      const n = rng();
      expect(n).toBeGreaterThanOrEqual(0);
      expect(n).toBeLessThan(1);
    }
  });

  test("rejects the all-zero seed, which would only ever yield 0", () => {
    expect(() => createRng([0, 0, 0, 0])).toThrow(RangeError);
    expect(() => createRng([0, 0, 0, 1])).not.toThrow();
  });
});

describe("shuffle", () => {
  test("returns a new array and leaves the input untouched", () => {
    const input = [1, 2, 3, 4, 5];
    const out = shuffle(input, createRng(seedOf(9)));
    expect(out).not.toBe(input);
    expect(input).toEqual([1, 2, 3, 4, 5]);
    expect([...out].sort((a, b) => a - b)).toEqual([1, 2, 3, 4, 5]);
  });

  test("handles empty and single-element arrays", () => {
    expect(shuffle([], createRng(seedOf(1)))).toEqual([]);
    expect(shuffle(["x"], createRng(seedOf(1)))).toEqual(["x"]);
  });
});
