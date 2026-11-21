import { describe, expect, it } from "vitest";

import { createRng } from "../rules/rng";

import { testGame, type TestMove, type TestPuzzle, type TestState } from "./test-game";

import type { DailyResult } from "./module";

const puzzle = (level: 1 | 2 | 3 | 4 | 5 | 6 | 7 = 1): TestPuzzle => testGame.make(createRng([1, 2, 3, 4]), level);
const step = (n: number): TestMove => ({ k: "step", n });

/** Plays moves from the start, failing on any refusal. */
function play(p: TestPuzzle, moves: number[]): { state: TestState; end?: string } {
  let state = testGame.init(p);
  let end: string | undefined;
  for (const n of moves) {
    const a = testGame.apply(p, state, step(n), 0);
    if (!a.ok) throw new Error(a.reason);
    state = a.state;
    end = a.end;
  }
  return end === undefined ? { state } : { state, end };
}

const result = (r: Partial<DailyResult>): DailyResult => ({
  game: "test",
  date: "2026-11-23",
  number: 1,
  outcome: "solved",
  timeMs: 60_000,
  hints: 0,
  tooFast: false,
  progress: 1,
  ...r,
});

describe("the test game: count to 3 + level", () => {
  it("makes a target of 3 plus the level", () => {
    expect(puzzle(1)).toEqual({ target: 4 });
    expect(puzzle(7)).toEqual({ target: 10 });
  });

  it("test game solves at target", () => {
    const p = puzzle(1);
    expect(play(p, [1, 2, 3]).end).toBeUndefined();
    const done = play(p, [1, 2, 3, 4]);
    expect(done.end).toBe("solved");
    expect(testGame.progress(p, done.state)).toBe(1);
    expect(testGame.result(p, done.state, "solved", 61_000, 1)).toEqual({ outcome: "solved", timeMs: 61_000, hints: 1, progress: 1 });
  });

  it("parseMove rejects extra keys and wrong types", () => {
    expect(testGame.parseMove({ k: "step", n: 1 })).toEqual(step(1));
    for (const bad of [null, 1, "step", [], {}, { k: "step" }, { k: "jump", n: 1 }, { k: "step", n: "1" }, { k: "step", n: 1.5 }, { k: "step", n: 1, extra: true }]) {
      expect(testGame.parseMove(bad), JSON.stringify(bad)).toBeNull();
    }
  });

  it("apply refuses the wrong number as illegal", () => {
    const p = puzzle();
    expect(testGame.apply(p, testGame.init(p), step(2), 0)).toEqual({ ok: false, reason: "illegal" });
    expect(testGame.apply(p, play(p, [1]).state, step(1), 0)).toEqual({ ok: false, reason: "illegal" });
  });

  it("apply and hint at the target answer over", () => {
    const p = puzzle();
    const { state } = play(p, [1, 2, 3, 4]);
    expect(testGame.apply(p, state, step(5), 0)).toEqual({ ok: false, reason: "over" });
    expect(testGame.hint(p, state)).toEqual({ ok: false, reason: "over" });
  });

  it("a hint takes one step and reveals it", () => {
    const p = puzzle();
    expect(testGame.hint(p, play(p, [1, 2]).state)).toEqual({ ok: true, state: { n: 3 }, reveal: { n: 3 } });
    expect(testGame.hint(p, play(p, [1, 2, 3]).state)).toEqual({ ok: true, state: { n: 4 }, reveal: { n: 4 }, end: "solved" });
  });

  it("publicPuzzle carries nothing apply doesn't need", () => {
    // The pattern each game copies for its own secret fields: name every key start may send.
    expect(Object.keys(testGame.publicPuzzle(puzzle()) as object)).toEqual(["target"]);
  });

  it("publicState and progress follow the count", () => {
    const p = puzzle(2);
    const { state } = play(p, [1, 2]);
    expect(testGame.publicState(p, state)).toEqual({ n: 2 });
    expect(testGame.progress(p, state)).toBe(0.4);
  });

  it("compare ranks solved by time, then unsolved by progress", () => {
    const fast = result({ timeMs: 50_000 });
    const slow = result({ timeMs: 70_000 });
    const far = result({ outcome: "gaveUp", progress: 0.8, timeMs: 10_000 });
    const near = result({ outcome: "closed", progress: 0.2 });
    const sorted = [near, slow, far, fast].sort(testGame.compare);
    expect(sorted).toEqual([fast, slow, far, near]);
    expect(testGame.compare(result({ outcome: "missed", progress: 0.5, timeMs: 1 }), result({ outcome: "gaveUp", progress: 0.5, timeMs: 2 }))).toBeLessThan(0);
  });

  it("has no floors and no move spacing", () => {
    expect(Object.values(testGame.floorMs)).toEqual([0, 0, 0, 0, 0, 0, 0]);
    expect(testGame.minMoveGapMs).toBe(0);
  });
});
