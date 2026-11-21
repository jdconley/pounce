/**
 * A year of Cat Nap: every day's quilt is the same on every run, has exactly one solution (by an
 * independent search, not just the logic solver), is made of whole patches, and needs the logic
 * its weekday asks for. Prints how long each size takes to make (spec: it must fit a Worker
 * request).
 */
import { describe, expect, test } from "vitest";

import { contiguous, dateRng, datesFrom, levelOf, oneCatPerPatch } from "../../../tests/cat-nap-helpers";

import { countSolutions, grade } from "./logic";
import { GRADES, makeNap, SIZES } from "./maker";

const DATES = datesFrom("2027-01-04", 365);

describe("a year of quilts", () => {
  test("deterministic, unique, whole, and graded for the day", { timeout: 120_000 }, () => {
    const times = new Map<number, number[]>();
    for (const date of DATES) {
      const level = levelOf(date);
      const start = performance.now();
      const p = makeNap(dateRng(date), level);
      const ms = performance.now() - start;
      times.set(p.n, [...(times.get(p.n) ?? []), ms]);

      expect(p.n, date).toBe(SIZES[level]);
      expect(countSolutions(p, 2), date).toBe(1);
      expect(contiguous(p.n, p.patches), date).toBe(true);
      expect(oneCatPerPatch(p), date).toBe(true);
      expect(grade(p), date).toEqual({ grade: p.grade, solution: p.solution });
      const [lo, hi] = GRADES[level];
      expect(p.grade, date).toBeGreaterThanOrEqual(lo);
      expect(p.grade, date).toBeLessThanOrEqual(hi);
    }
    // Determinism, on a sample: the same date makes the same quilt.
    for (const date of DATES.filter((_, i) => i % 30 === 0)) {
      expect(makeNap(dateRng(date), levelOf(date))).toEqual(makeNap(dateRng(date), levelOf(date)));
    }
    const rows = [...times].sort(([a], [b]) => a - b).map(([n, ms]) => {
      const sorted = [...ms].sort((a, b) => a - b);
      const mean = ms.reduce((s, x) => s + x, 0) / ms.length;
      return `${n}x${n}: ${ms.length} days, mean ${mean.toFixed(1)} ms, p95 ${sorted[Math.floor(ms.length * 0.95)]!.toFixed(1)} ms, max ${sorted.at(-1)!.toFixed(1)} ms`;
    });
    console.log(`Cat Nap make times\n${rows.join("\n")}`);
  });
});
