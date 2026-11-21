import { createHash } from "node:crypto";

import { describe, expect, test } from "vitest";

import { createRng, type Seed } from "../../rules/rng";

import { clutter, LEVELS, make, type BoxFortPuzzle } from "./maker";
import { shape, type Piece } from "./pieces";
import { anyFits, CLUTTER, setFits, SIZE } from "./rules";

import type { DayLevel } from "../days";

/** A stand-in for the server's seed: the first 16 bytes of sha256(date). */
function seedFor(date: string): Seed {
  const bytes = createHash("sha256").update(date).digest();
  return [0, 1, 2, 3].map((i) => bytes.readUInt32LE(i * 4)) as Seed;
}

/** Mon 1 … Sat 6, Sun 7. */
function levelOf(date: string): DayLevel {
  const day = new Date(`${date}T12:00:00Z`).getUTCDay();
  return (day === 0 ? 7 : day) as DayLevel;
}

function year(from: string): string[] {
  const out: string[] = [];
  const d = new Date(`${from}T12:00:00Z`);
  for (let i = 0; i < 365; i++) {
    out.push(d.toISOString().slice(0, 10));
    d.setUTCDate(d.getUTCDate() + 1);
  }
  return out;
}

const DATES = year("2027-01-01");
const PUZZLES = new Map(DATES.map((date) => [date, make(createRng(seedFor(date)), levelOf(date))]));
const lines = [...Array(SIZE).keys()];

describe("make", () => {
  test("the same seed gives the same puzzle", () => {
    const a = make(createRng([1, 2, 3, 4]), 4);
    const b = make(createRng([1, 2, 3, 4]), 4);
    expect(a).toEqual(b);
  });

  test("a year of dates is deterministic and every date differs", () => {
    const seen = new Set<string>();
    for (const date of DATES) {
      const again = make(createRng(seedFor(date)), levelOf(date));
      expect(again, date).toEqual(PUZZLES.get(date));
      seen.add(JSON.stringify(again));
    }
    expect(seen.size).toBe(DATES.length);
  });

  test.each(DATES)("%s holds the level's shape", (date) => {
    const level = levelOf(date);
    const spec = LEVELS[level];
    const p = PUZZLES.get(date) as BoxFortPuzzle;
    expect(p.sets).toHaveLength(spec.sets);
    expect(p.rug).toHaveLength(SIZE * SIZE);
    const boxes = p.rug.filter((v) => v !== 0);
    expect(boxes.length).toBeLessThanOrEqual(spec.boxes);
    expect(boxes.every((v) => v === CLUTTER)).toBe(true);
    for (const y of lines) expect(lines.filter((x) => p.rug[y * SIZE + x] !== 0).length).toBeLessThanOrEqual(5);
    for (const x of lines) expect(lines.filter((y) => p.rug[y * SIZE + x] !== 0).length).toBeLessThanOrEqual(5);
    expect(setFits(p.rug, p.sets[0]!), "the whole first set fits").toBe(true);
    for (const set of p.sets) {
      expect(set).toHaveLength(3);
      expect(set.filter((piece) => shape(piece.id).tier === 2).length).toBeLessThanOrEqual(spec.maxAwkward);
      for (const piece of set) {
        expect(piece.cells).toEqual(shape(piece.id).cells);
        expect(piece.tint).toBeGreaterThanOrEqual(1);
        expect(piece.tint).toBeLessThanOrEqual(6);
      }
    }
  });

  test("the rug starts with the level's boxes nearly always", () => {
    const short = DATES.filter((date) => PUZZLES.get(date)!.rug.filter((v) => v !== 0).length < LEVELS[levelOf(date)].boxes);
    expect(short.length).toBeLessThan(DATES.length / 50);
  });

  test("awkward pieces grow from Monday to Saturday, and Sunday is longer", () => {
    const share = (level: DayLevel) => {
      const pieces = DATES.filter((d) => levelOf(d) === level).flatMap((d) => PUZZLES.get(d)!.sets.flat());
      return pieces.filter((piece) => shape(piece.id).tier === 2).length / pieces.length;
    };
    const shares = ([1, 2, 3, 4, 5, 6] as const).map(share);
    for (let i = 1; i < shares.length; i++) expect(shares[i]).toBeGreaterThan(shares[i - 1]!);
    expect(LEVELS[7].sets).toBeGreaterThan(LEVELS[6].sets);
  });

  test("every day of a year, at every level, the whole first set fits the starting rug", () => {
    for (const date of DATES) {
      for (const level of [1, 2, 3, 4, 5, 6, 7] as DayLevel[]) {
        const p = make(createRng(seedFor(date)), level);
        expect(setFits(p.rug, p.sets[0]!), `${date} at level ${level}`).toBe(true);
      }
    }
  });

  test("days whose first set used to be stuck now fit", () => {
    // Saturdays (level 6) where the old maker dealt pieces that each fit alone but not together:
    // 2035-04-14 was a big D, a 3 by 3 and a big D; 2070-03-01 a nook, and two 3 by 3s.
    for (const date of ["2035-04-14", "2070-03-01"]) {
      expect(levelOf(date)).toBe(6);
      const p = make(createRng(seedFor(date)), levelOf(date));
      expect(setFits(p.rug, p.sets[0]!), date).toBe(true);
    }
  });

  test("the first set fits as a whole, not just piece by piece", () => {
    // Seeds where a dot and two 3 by 3s each fit the rug alone, but the two 3 by 3s wanted the same gap.
    for (const [seed, level] of [
      [[7068, 4, 2027, 1], 4],
      [[3244, 5, 2027, 1], 5],
      [[11047, 5, 2027, 1], 5],
    ] as [Seed, DayLevel][]) {
      const p = make(createRng(seed), level);
      expect(setFits(p.rug, p.sets[0]!), JSON.stringify(seed)).toBe(true);
    }
  });

  test("clutter that can't hold gives up a box at a time", () => {
    const sq3: Piece = { id: "sq3", tint: 1, cells: shape("sq3").cells };
    const rug = clutter(createRng([9, 9, 9, 9]), 40, [sq3]);
    const boxes = rug.filter((v) => v !== 0).length;
    expect(boxes).toBeLessThan(40);
    expect(boxes).toBeGreaterThan(0);
    expect(anyFits(rug, [sq3])).toBe(true);
    expect(clutter(createRng([9, 9, 9, 9]), 0, [sq3]).every((v) => v === 0)).toBe(true);
  });
});
