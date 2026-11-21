import { createHmac } from "node:crypto";

import { describe, expect, test } from "vitest";

import { seedOf } from "../../../tests/seeds";
import { createRng, type Seed } from "../../rules/rng";

import { FALLBACK } from "./fallback";
import { grade } from "./grade";
import { clashes, N } from "./grid";
import { carve, fallback, givenCount, LEVELS, makePuzzle, MAX_TRIES } from "./make";
import { countSolutions } from "./solve";

import type { DayLevel } from "../days";

/** Stands in for the server's `dailySeed` (an HMAC of the game and date, first 16 bytes). */
function seedFor(date: string): Seed {
  const mac = createHmac("sha256", "nine-lives test secret").update(`daily.v1|nine-lives|${date}`).digest();
  return [0, 1, 2, 3].map((k) => mac.readUInt32BE(k * 4)) as Seed;
}

/** Mon 1 … Sat 6, Sun 7, as the server's `levelFor`. */
function levelOf(date: string): DayLevel {
  const day = new Date(`${date}T12:00:00Z`).getUTCDay();
  return (day === 0 ? 7 : day) as DayLevel;
}

/**
 * One carve's cost on a CI runner under coverage, the slowest place these run, at the costliest
 * level (Saturday, level 6): 11 ms on an M-series Mac under coverage (400 tries in 4.4 s), and a
 * GitHub runner takes about 3 times as long. So no `makePuzzle` can take longer than
 * MAX_TRIES * TRY_MS (14 s), and a test's timeout is its calls times that.
 */
const TRY_MS = 35;
const MAKE_MS = MAX_TRIES * TRY_MS;

const YEAR = Array.from({ length: 365 }, (_, k) => new Date(Date.UTC(2027, 0, 1 + k)).toISOString().slice(0, 10));

describe("makePuzzle", () => {
  test("the same seed and level give the same puzzle", () => {
    for (const level of [1, 4, 7] as DayLevel[]) {
      expect(makePuzzle(createRng(seedOf(level)), level)).toEqual(makePuzzle(createRng(seedOf(level)), level));
    }
    expect(makePuzzle(createRng(seedOf(1)), 3).givens).not.toEqual(makePuzzle(createRng(seedOf(2)), 3).givens);
  }, 8 * MAKE_MS);

  test("carve keeps the floor and stays at or under the tier", () => {
    const p = carve(createRng(seedOf(9)), 1, 40);
    expect(givenCount(p.givens)).toBeGreaterThanOrEqual(40);
    expect(p.tier).toBe(1);
  });

  test("falls back after MAX_TRIES when no try can work: a pool puzzle at the level", () => {
    const tries = { n: 0 };
    // Tier 6 with a floor of 81 keeps every given: every try grades 1, never 6.
    const levels = LEVELS as Record<number, { tier: number; floor: number; ceiling: number }>;
    const saved = levels[6]!;
    levels[6] = { tier: 6, floor: N, ceiling: N };
    const rng = createRng(seedOf(3));
    let p;
    try {
      p = makePuzzle(() => {
        tries.n++;
        return rng();
      }, 6);
    } finally {
      levels[6] = saved;
    }
    expect(tries.n).toBeGreaterThan(MAX_TRIES);
    expect(FALLBACK[6]).toContain(p.givens.join(""));
    expect(p.tier).toBe(6);
    expect(clashes(p.solution)).toEqual([]);
    // Each of these tries keeps every given, so grades nothing: far under MAKE_MS.
  }, MAKE_MS);

  test("every fallback puzzle has one solution, its level's exact grade and givens, and is mirrored", () => {
    for (const level of [1, 2, 3, 4, 5, 6, 7] as DayLevel[]) {
      expect(FALLBACK[level].length).toBeGreaterThan(1);
      for (const text of FALLBACK[level]) {
        const givens = [...text].map(Number);
        const n = givenCount(givens);
        expect(givens).toHaveLength(N);
        expect(countSolutions(givens, 2), text).toBe(1);
        expect(grade(givens)?.tier, text).toBe(LEVELS[level].tier);
        expect(n, text).toBeGreaterThanOrEqual(LEVELS[level].floor);
        expect(n, text).toBeLessThanOrEqual(LEVELS[level].ceiling);
        for (let i = 0; i < N; i++) expect(givens[i] === 0, `${text} mirrored at ${i}`).toBe(givens[N - 1 - i] === 0);
      }
    }
  });

  test("the fallback is the seed's: the same seed picks the same puzzle, with its solution", () => {
    for (const level of [1, 4, 7] as DayLevel[]) {
      const p = fallback(createRng(seedOf(level)), level);
      expect(fallback(createRng(seedOf(level)), level)).toEqual(p);
      expect(p.givens.every((d, i) => d === 0 || d === p.solution[i])).toBe(true);
    }
    const picked = new Set(Array.from({ length: 40 }, (_, k) => fallback(createRng(seedOf(k)), 5).givens.join("")));
    expect(picked.size).toBe(FALLBACK[5].length);
  });

  test("a year of dates: one solution each, the weekday's grade, and in time", () => {
    const ms = new Map<DayLevel, number[]>();
    const givens = new Map<DayLevel, number[]>();
    for (const date of YEAR) {
      const level = levelOf(date);
      const t0 = performance.now();
      const p = makePuzzle(createRng(seedFor(date)), level);
      ms.set(level, [...(ms.get(level) ?? []), performance.now() - t0]);
      const n = givenCount(p.givens);
      givens.set(level, [...(givens.get(level) ?? []), n]);

      expect(countSolutions(p.givens, 2), date).toBe(1);
      expect(grade(p.givens)?.tier, date).toBe(LEVELS[level].tier);
      expect(p.tier).toBe(LEVELS[level].tier);
      expect(n, date).toBeGreaterThanOrEqual(LEVELS[level].floor);
      expect(n, date).toBeLessThanOrEqual(LEVELS[level].ceiling);
      expect(clashes(p.solution)).toEqual([]);
      // 2027 needs at most 298 tries a date: every day is the search's own puzzle, not the pool's.
      expect(FALLBACK[level], date).not.toContain(p.givens.join(""));
      for (let i = 0; i < N; i++) {
        expect(p.givens[i] === 0, `${date} symmetric at ${i}`).toBe(p.givens[N - 1 - i] === 0);
        if (p.givens[i] !== 0) expect(p.givens[i]).toBe(p.solution[i]);
      }
    }
    // Sunday is Thursday's tier with more to fill.
    expect(Math.max(...givens.get(7)!)).toBeLessThan(Math.min(...givens.get(4)!));
    const lines = [...ms]
      .sort(([a], [b]) => a - b)
      .map(([level, t]) => {
        const sorted = [...t].sort((a, b) => a - b);
        const g = givens.get(level)!;
        return `level ${level}: median ${sorted[sorted.length >> 1]!.toFixed(0)} ms, max ${sorted.at(-1)!.toFixed(0)} ms, givens ${Math.min(...g)}-${Math.max(...g)}`;
      });
    console.log(`Nine Lives, 2027:\n${lines.join("\n")}`);
    // Measured: about 110 s on a CI runner under coverage, 25 s on an M-series Mac. Bounded by
    // MAX_TRIES, the sum stays near the measured one; 300 s is close to 3 times it.
  }, 300_000);
});
