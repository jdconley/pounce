import { describe, expect, test } from "vitest";

import { createRng } from "../../rules/rng";

import { countSolutions } from "./logic";
import { GRADES, growPatches, makeNap, placeCats, repair, SIZES } from "./maker";
import { contiguous, oneCatPerPatch } from "../../../tests/cat-nap-helpers";

import type { DayLevel } from "./contract";

const LEVELS: DayLevel[] = [1, 2, 3, 4, 5, 6, 7];

describe("makeNap", () => {
  test("is deterministic for a seed", () => {
    for (const level of LEVELS) {
      expect(makeNap(createRng([level, 2, 3, 4]), level)).toEqual(makeNap(createRng([level, 2, 3, 4]), level));
    }
    expect(makeNap(createRng([1, 2, 3, 4]), 4)).not.toEqual(makeNap(createRng([1, 2, 3, 5]), 4));
  });

  test("sizes follow the level: 5 on Monday up to 8 on Saturday, 9 on Sunday", () => {
    expect(SIZES).toEqual({ 1: 5, 2: 6, 3: 7, 4: 7, 5: 8, 6: 8, 7: 9 });
    for (const level of LEVELS) {
      const p = makeNap(createRng([9, level, 9, 9]), level);
      expect(p.n).toBe(SIZES[level]);
      expect(p.patches).toHaveLength(p.n * p.n);
      expect(p.solution).toHaveLength(p.n);
      expect(p.level).toBe(level);
    }
  });

  test("the logic gets deeper through the week", () => {
    for (let level = 2; level <= 6; level++) {
      expect(GRADES[level as DayLevel][0]).toBeGreaterThanOrEqual(GRADES[(level - 1) as DayLevel][0]);
    }
    expect(GRADES[6][0]).toBeGreaterThan(GRADES[1][1]);
  });

  test("patches are contiguous, numbered in reading order, and each holds one solution cat", () => {
    for (const level of LEVELS) {
      const p = makeNap(createRng([5, level, 5, 5]), level);
      expect(contiguous(p.n, p.patches)).toBe(true);
      expect(oneCatPerPatch(p)).toBe(true);
      const firsts = Array.from({ length: p.n }, (_, k) => p.patches.indexOf(k));
      expect(firsts).toEqual([...firsts].sort((a, b) => a - b));
    }
  });

  test("make always returns a unique puzzle, even when the band is impossible", () => {
    // 5 by 5 quilts never need trial at this seed's first tries; settle for any logical quilt.
    const p = makeNap(createRng([3, 1, 4, 1]), 1, { band: [4, 4], tries: 3 });
    expect(p.grade).toBeLessThan(4);
    expect(countSolutions(p, 2)).toBe(1);
    expect(contiguous(p.n, p.patches)).toBe(true);
  });

  test("gives up loudly rather than looping", () => {
    expect(() => makeNap(createRng([1, 1, 1, 1]), 7, { giveUp: 0 })).toThrow(/no quilt/);
  });
});

describe("parts", () => {
  test("placeCats: one per row and column, none touching", () => {
    for (let n = 4; n <= 9; n++) {
      const cols = placeCats(n, createRng([n, 1, 1, 1]));
      expect([...cols].sort()).toEqual(Array.from({ length: n }, (_, i) => i).sort());
      for (let r = 1; r < n; r++) expect(Math.abs(cols[r]! - cols[r - 1]!)).toBeGreaterThan(1);
    }
  });

  test("growPatches grows a patch around each cat", () => {
    const rng = createRng([7, 7, 7, 7]);
    const solution = placeCats(9, rng);
    const patches = growPatches(9, solution, rng);
    expect(contiguous(9, patches)).toBe(true);
    solution.forEach((c, r) => expect(patches[r * 9 + c]).toBe(r));
  });

  test("repair leaves one solution, or gives up", () => {
    const rng = createRng([8, 8, 8, 8]);
    let fixed = 0;
    let gaveUp = 0;
    for (let i = 0; i < 40; i++) {
      const solution = placeCats(8, rng);
      const patches = repair(8, growPatches(8, solution, rng), solution, rng);
      if (!patches) {
        gaveUp++;
        continue;
      }
      fixed++;
      expect(countSolutions({ n: 8, patches }, 2)).toBe(1);
      expect(contiguous(8, patches)).toBe(true);
    }
    expect(fixed).toBeGreaterThan(0);
    expect(gaveUp).toBeGreaterThan(0);
  });
});
