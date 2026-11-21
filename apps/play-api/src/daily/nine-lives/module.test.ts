import { describe, expect, test } from "vitest";

import { seedOf } from "../../../tests/seeds";
import { createRng } from "../../rules/rng";

import { clashes, N, peers, type NineLivesState } from "./grid";
import { FLOOR_MS, nineLives } from "./module";
import { SAMPLE } from "./samples";

import type { DailyResult } from "./contract";

const P = SAMPLE;
const open = P.givens.flatMap((d, i) => (d === 0 ? [i] : []));

/** Plays every open cell right, in order; returns the state before the last move. */
function almost(): NineLivesState {
  let s = nineLives.init(P);
  for (const i of open.slice(0, -1)) {
    const a = nineLives.apply(P, s, { k: "set", i, d: P.solution[i]! }, 0);
    if (!a.ok) throw new Error("refused");
    s = a.state;
  }
  return s;
}

function result(over: Partial<DailyResult>): DailyResult {
  return {
    game: "nine-lives",
    date: "2027-01-04",
    number: 1,
    outcome: "solved",
    timeMs: 100_000,
    hints: 0,
    tooFast: false,
    progress: 1,
    ...over,
  };
}

describe("nine lives module", () => {
  test("make and the public puzzle: givens only, never the solution", () => {
    const p = nineLives.make(createRng(seedOf(1)), 2);
    const pub = nineLives.publicPuzzle(p) as Record<string, unknown>;
    expect(Object.keys(pub)).toEqual(["givens"]);
    expect(pub.givens).toEqual(p.givens);
    expect(pub.givens).not.toBe(p.givens);
    expect(JSON.stringify(pub)).not.toContain(p.solution.join(","));
  });

  test("init is the givens and nothing hinted", () => {
    expect(nineLives.init(P)).toEqual({ cells: P.givens, hinted: [] });
    expect(nineLives.progress(P, nineLives.init(P))).toBe(0);
  });

  test("parseMove is the rules' exact shape", () => {
    expect(nineLives.parseMove({ k: "set", i: open[0], d: 3 })).toEqual({ k: "set", i: open[0], d: 3 });
    expect(nineLives.parseMove({ k: "set", i: 1, d: 3, solved: true })).toBeNull();
  });

  test("filling every cell right ends solved, and then everything is over", () => {
    const s = almost();
    const last = open.at(-1)!;
    const a = nineLives.apply(P, s, { k: "set", i: last, d: P.solution[last]! }, 90_000);
    expect(a).toMatchObject({ ok: true, end: "solved" });
    if (!a.ok) return;
    expect(nineLives.progress(P, a.state)).toBe(1);
    expect(nineLives.apply(P, a.state, { k: "clear", i: last }, 0)).toEqual({ ok: false, reason: "over" });
    expect(nineLives.hint(P, a.state)).toEqual({ ok: false, reason: "over" });
  });

  test("a clash is legal and shown; givens are refused", () => {
    const s = nineLives.init(P);
    const i = open[0]!;
    const peerGiven = P.givens.find((d, j) => d !== 0 && Math.floor(j / 9) === Math.floor(i / 9))!;
    const a = nineLives.apply(P, s, { k: "set", i, d: peerGiven }, 0);
    expect(a.ok).toBe(true);
    if (a.ok) {
      expect(a.end).toBeUndefined();
      expect(clashes(a.state.cells)).toContain(i);
    }
    const given = P.givens.findIndex((d) => d !== 0);
    expect(nineLives.apply(P, s, { k: "set", i: given, d: 1 }, 0)).toEqual({ ok: false, reason: "illegal" });
  });

  test("a full grid with a mistake is not solved, and play goes on", () => {
    const s = almost();
    const last = open.at(-1)!;
    const wrong = (P.solution[last]! % 9) + 1;
    const a = nineLives.apply(P, s, { k: "set", i: last, d: wrong }, 0);
    expect(a).toMatchObject({ ok: true });
    expect(a.ok && a.end).toBeFalsy();
    if (!a.ok) return;
    expect(clashes(a.state.cells).length).toBeGreaterThan(0);
    const fixed = nineLives.apply(P, a.state, { k: "set", i: last, d: P.solution[last]! }, 0);
    expect(fixed).toMatchObject({ ok: true, end: "solved" });
  });

  test("a hint fills the open cell with the fewest candidates, from the solution, and locks it", () => {
    const s = nineLives.init(P);
    const h = nineLives.hint(P, s)!;
    expect(h.ok).toBe(true);
    if (!h.ok) return;
    const { i, d } = h.reveal as { i: number; d: number };
    expect(P.givens[i]).toBe(0);
    expect(d).toBe(P.solution[i]);
    expect(h.state.cells[i]).toBe(d);
    expect(h.state.hinted).toEqual([i]);
    expect(nineLives.apply(P, h.state, { k: "clear", i }, 0)).toEqual({ ok: false, reason: "illegal" });
    // It never picks a cell that is already filled.
    const h2 = nineLives.hint(P, h.state)!;
    expect(h2.ok && (h2.reveal as { i: number }).i).not.toBe(i);
  });

  test("a hint picks a cell with no candidate left last", () => {
    // Fill open peers of cell i with every digit its given peers lack: i has nothing left.
    const i = open[0]!;
    const cells = [...P.givens];
    const have = new Set(peers(i).map((p) => cells[p]));
    const lacking = [1, 2, 3, 4, 5, 6, 7, 8, 9].filter((d) => !have.has(d));
    const openPeers = peers(i).filter((p) => cells[p] === 0);
    lacking.forEach((d, k) => (cells[openPeers[k]!] = d));
    const h = nineLives.hint(P, { cells, hinted: [] })!;
    expect(h.ok).toBe(true);
    if (h.ok) expect((h.reveal as { i: number }).i).not.toBe(i);
  });

  test("a hint on a full wrong grid fixes the first wrong cell, and may finish it", () => {
    const s = almost();
    const last = open.at(-1)!;
    const wrong = (P.solution[last]! % 9) + 1;
    const a = nineLives.apply(P, s, { k: "set", i: last, d: wrong }, 0);
    if (!a.ok) throw new Error("refused");
    const h = nineLives.hint(P, a.state)!;
    expect(h).toMatchObject({ ok: true, reveal: { i: last, d: P.solution[last] }, end: "solved" });
  });

  test("publicState plus publicPuzzle rebuild the board", () => {
    const h = nineLives.hint(P, nineLives.init(P))!;
    if (!h.ok) throw new Error("no hint");
    const pub = nineLives.publicState(P, h.state) as NineLivesState;
    expect(pub).toEqual(h.state);
    expect(pub.cells).not.toBe(h.state.cells);
    expect(Object.keys(pub).sort()).toEqual(["cells", "hinted"]);
    expect((nineLives.publicPuzzle(P) as { givens: number[] }).givens).toHaveLength(N);
  });

  test("result: solved is all the way, other endings count cells placed", () => {
    const s = almost();
    expect(nineLives.result(P, s, "solved", 120_000, 1)).toEqual({
      outcome: "solved",
      timeMs: 120_000,
      hints: 1,
      progress: 1,
    });
    const gaveUp = nineLives.result(P, s, "gaveUp", 60_000, 0);
    expect(gaveUp.outcome).toBe("gaveUp");
    expect(gaveUp.progress).toBeCloseTo((open.length - 1) / open.length);
  });

  test("compare: solved first by time then hints; unsolved by progress then time", () => {
    const fast = result({ timeMs: 90_000 });
    const slow = result({ timeMs: 200_000 });
    const hinted = result({ timeMs: 90_000, hints: 1 });
    const far = result({ outcome: "gaveUp", progress: 0.9, timeMs: 500_000 });
    const near = result({ outcome: "closed", progress: 0.2, timeMs: 10_000 });
    const nearSlow = result({ outcome: "gaveUp", progress: 0.2, timeMs: 20_000 });
    const sorted = [near, slow, far, hinted, nearSlow, fast].sort(nineLives.compare);
    expect(sorted).toEqual([fast, hinted, slow, far, near, nearSlow]);
    expect(nineLives.compare(fast, { ...fast })).toBe(0);
  });

  test("floors and move spacing", () => {
    expect(nineLives.id).toBe("nine-lives");
    expect(nineLives.floorMs).toBe(FLOOR_MS);
    expect(FLOOR_MS).toEqual({ 1: 45_000, 2: 55_000, 3: 65_000, 4: 75_000, 5: 90_000, 6: 105_000, 7: 80_000 });
    expect(nineLives.minMoveGapMs).toBe(100);
  });
});
