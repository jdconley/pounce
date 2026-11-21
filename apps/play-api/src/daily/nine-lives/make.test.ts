import { createHmac } from "node:crypto";

import { describe, expect, test } from "vitest";

import { seedOf } from "../../../tests/seeds";
import { createRng, type Seed } from "../../rules/rng";

import { grade } from "./grade";
import { clashes, N } from "./grid";
import { carve, givenCount, LEVELS, makePuzzle, MAX_TRIES } from "./make";
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

const YEAR = Array.from({ length: 365 }, (_, k) => new Date(Date.UTC(2027, 0, 1 + k)).toISOString().slice(0, 10));

describe("makePuzzle", () => {
  test("the same seed and level give the same puzzle", () => {
    for (const level of [1, 4, 7] as DayLevel[]) {
      expect(makePuzzle(createRng(seedOf(level)), level)).toEqual(makePuzzle(createRng(seedOf(level)), level));
    }
    expect(makePuzzle(createRng(seedOf(1)), 3).givens).not.toEqual(makePuzzle(createRng(seedOf(2)), 3).givens);
  });

  test("carve keeps the floor and stays at or under the tier", () => {
    const p = carve(createRng(seedOf(9)), 1, 40);
    expect(givenCount(p.givens)).toBeGreaterThanOrEqual(40);
    expect(p.tier).toBe(1);
  });

  test("gives up after MAX_TRIES when no try can work", () => {
    const tries = { n: 0 };
    // Tier 6 with a floor of 81 keeps every given: every try grades 1, never 6.
    const levels = LEVELS as Record<number, { tier: number; floor: number; ceiling: number }>;
    const saved = levels[6]!;
    levels[6] = { tier: 6, floor: N, ceiling: N };
    const rng = createRng(seedOf(3));
    try {
      expect(() =>
        makePuzzle(() => {
          tries.n++;
          return rng();
        }, 6),
      ).toThrow(`no level 6 puzzle in ${MAX_TRIES} tries`);
    } finally {
      levels[6] = saved;
    }
    expect(tries.n).toBeGreaterThan(MAX_TRIES);
  }, 60_000);

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
  }, 300_000);
});
