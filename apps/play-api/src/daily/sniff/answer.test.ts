import { describe, expect, it } from "vitest";

import { createRng, type Seed } from "../../rules/rng";

import { isAllowed } from "./allowed-check";
import { answerFor, levelOf, pickAnswer, poolDay, poolFor, POOLS, SNIFF_EPOCH, type Pool } from "./answer";

import type { DayLevel } from "./contract";

const KEY: Seed = [0x12345678, 0x9abcdef0, 0x0fedcba9, 0x87654321];
const OTHER: Seed = [1, 2, 3, 4];

function addDays(date: string, n: number): string {
  return new Date(Date.parse(`${date}T00:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10);
}

describe("the answer pools", () => {
  it("split the answers by tier and repeated letters, each big enough", () => {
    const repeats = (w: string) => new Set(w).size < 5;
    for (const w of POOLS.easy) expect(repeats(w), w).toBe(false);
    for (const w of POOLS.mid) expect(repeats(w), w).toBe(false);
    expect(POOLS.hard.some(repeats)).toBe(true);
    const all = [...POOLS.easy, ...POOLS.mid, ...POOLS.hard];
    expect(new Set(all).size).toBe(all.length);
    for (const pool of ["easy", "mid", "hard"] as const) expect(POOLS[pool].length).toBeGreaterThan(250);
  });

  it("each weekday uses its pool: Mon and Tue easy, Wed Thu Sun mid, Fri Sat hard", () => {
    const week = ["2026-11-23", "2026-11-24", "2026-11-25", "2026-11-26", "2026-11-27", "2026-11-28", "2026-11-29"];
    expect(week.map(levelOf)).toEqual([1, 2, 3, 4, 5, 6, 7]);
    expect(week.map((d) => poolFor(levelOf(d)))).toEqual(["easy", "easy", "mid", "mid", "hard", "hard", "mid"]);
    for (const d of week) expect(POOLS[poolFor(levelOf(d))]).toContain(answerFor(KEY, d));
  });
});

describe("poolDay", () => {
  it("counts the pool's earlier dates from the epoch, across weeks", () => {
    expect(levelOf(SNIFF_EPOCH)).toBe(1);
    expect(poolDay(SNIFF_EPOCH, "easy")).toBe(0);
    expect(poolDay("2026-01-06", "easy")).toBe(1);
    expect(poolDay("2026-01-12", "easy")).toBe(2);
    expect(poolDay("2026-01-12", "mid")).toBe(3);
    expect(poolDay("2026-01-12", "hard")).toBe(2);
    expect(poolDay(addDays(SNIFF_EPOCH, 70), "mid")).toBe(30);
  });

  it("counts back before the epoch", () => {
    expect(poolDay("2026-01-04", "mid")).toBe(-1);
    expect(poolDay("2026-01-04", "easy")).toBe(0);
    expect(poolDay("2025-12-29", "easy")).toBe(-2);
  });
});

describe("answerFor", () => {
  it("the same key and date give the same answer", () => {
    expect(answerFor(KEY, "2026-12-01")).toBe(answerFor(KEY, "2026-12-01"));
  });

  it("no word repeats until its pool is used up, then a new order starts", () => {
    const pool: Pool = "easy";
    const n = POOLS[pool].length;
    const seen: string[] = [];
    for (let d = SNIFF_EPOCH; seen.length < 2 * n; d = addDays(d, 1)) {
      if (poolFor(levelOf(d)) === pool) seen.push(answerFor(KEY, d));
    }
    const first = seen.slice(0, n);
    const second = seen.slice(n);
    expect(new Set(first).size).toBe(n);
    expect(new Set(second).size).toBe(n);
    expect([...first].sort()).toEqual([...POOLS[pool]].sort());
    expect(second).not.toEqual(first);
  });

  it("different keys give different orders", () => {
    const days = Array.from({ length: 20 }, (_, i) => addDays("2026-12-01", i));
    expect(days.map((d) => answerFor(KEY, d))).not.toEqual(days.map((d) => answerFor(OTHER, d)));
  });

  it("an all-zero key still works", () => {
    expect(isAllowed(answerFor([0, 0, 0, 0], "2026-12-01"))).toBe(true);
  });

  it("dates before the epoch still give an answer from the right pool", () => {
    expect(POOLS.mid).toContain(answerFor(KEY, "2025-06-01"));
  });

  it("a year of dates: every answer allowed and in its day's pool", () => {
    for (let i = 0; i < 366; i++) {
      const d = addDays("2026-12-01", i);
      const w = answerFor(KEY, d);
      expect(isAllowed(w), w).toBe(true);
      expect(POOLS[poolFor(levelOf(d))]).toContain(w);
    }
  });
});

describe("pickAnswer", () => {
  it("stays in the level's pool", () => {
    const rng = createRng([5, 6, 7, 8]);
    for (const level of [1, 2, 3, 4, 5, 6, 7] as DayLevel[]) {
      for (let i = 0; i < 20; i++) expect(POOLS[poolFor(level)]).toContain(pickAnswer(rng, level));
    }
  });
});
