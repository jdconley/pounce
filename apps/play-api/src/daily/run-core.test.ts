import { describe, expect, it } from "vitest";

import { createRng } from "../rules/rng";

import { closesAt, puzzleNumber } from "./days";
import { close, countsForStreak, giveUp, HINT_PENALTY_MS, MAX_BATCH, MOVE_BURST, moves, newRun, startView, useHint, type RunState } from "./run-core";
import { testGame, type TestPuzzle } from "./test-game";

import type { DailyModule } from "./module";

const LA = "America/Los_Angeles";
const DATE = "2026-11-23"; // a Monday: the test game counts to 4
const T0 = Date.UTC(2026, 10, 23, 20); // 12:00 in LA
const m = testGame as DailyModule;
const p: TestPuzzle = testGame.make(createRng([1, 2, 3, 4]), 1, { date: DATE, key: [1, 0, 0, 0] });
const step = (n: number) => ({ k: "step", n });

function run(module: DailyModule = m): RunState {
  return newRun(module, p, { id: "r1", playerId: "p_1", game: "test", date: DATE, zone: LA, now: T0 });
}

describe("newRun", () => {
  it("starts at the server's clock with the module's first state", () => {
    expect(run()).toEqual({
      id: "r1",
      playerId: "p_1",
      game: "test",
      date: DATE,
      zone: LA,
      startedAt: T0,
      seq: 0,
      state: { n: 0 },
      hints: 0,
      lastMoveAt: 0,
      ended: null,
      result: null,
      tv: false,
      answers: {},
    });
  });
});

describe("moves", () => {
  it("a full solve gives solved with the server's time", () => {
    const r = run();
    expect(moves(m, p, r, 0, [step(1), step(2)], T0 + 20_000)).toEqual({ ok: true, seq: 2, reveals: [], progress: 0.5, result: null });
    const done = moves(m, p, r, 2, [step(3), step(4)], T0 + 95_000);
    const result = { game: "test", date: DATE, number: puzzleNumber(DATE), outcome: "solved", timeMs: 95_000, hints: 0, tooFast: false, progress: 1 };
    expect(done).toEqual({ ok: true, seq: 4, reveals: [], progress: 1, result });
    expect(r.ended).toEqual({ outcome: "solved", at: T0 + 95_000 });
    expect(r.result).toEqual(result);
    expect(r.lastMoveAt).toBe(T0 + 95_000);
  });

  it("a resent batch gets the same answer once", () => {
    const r = run();
    const first = moves(m, p, r, 0, [step(1), step(2)], T0 + 1000);
    const again = moves(m, p, r, 0, [step(1), step(2)], T0 + 2000);
    expect(again).toEqual(first);
    expect(r.seq).toBe(2);
    expect(r.state).toEqual({ n: 2 });
    // The batch that ended the run, resent, still gets its result.
    const end = moves(m, p, r, 2, [step(3), step(4)], T0 + 3000);
    expect(moves(m, p, r, 2, [step(3), step(4)], T0 + 4000)).toEqual(end);
  });

  it("an illegal move refuses the whole batch", () => {
    const r = run();
    expect(moves(m, p, r, 0, [step(1), step(3), step(4)], T0 + 1000)).toEqual({ ok: false, error: "illegal", at: 1, seq: 0 });
    expect(r.seq).toBe(0);
    expect(r.state).toEqual({ n: 0 });
    // A corrected batch from the same seq is played, not answered from memory.
    expect(moves(m, p, r, 0, [step(1), step(2)], T0 + 2000)).toMatchObject({ ok: true, seq: 2 });
  });

  it("a move the module can't read refuses the batch as bad_message", () => {
    const r = run();
    expect(moves(m, p, r, 0, [step(1), { k: "step", n: "2" }], T0 + 1000)).toEqual({ ok: false, error: "bad_message", at: 1, seq: 0 });
    expect(r.seq).toBe(0);
  });

  it("stale from is refused", () => {
    const r = run();
    expect(moves(m, p, r, 1, [step(2)], T0 + 1000)).toEqual({ ok: false, error: "stale", at: 0, seq: 0 });
    moves(m, p, r, 0, [step(1), step(2)], T0 + 1000);
    // Below seq with no stored answer for it: a batch that never was.
    expect(moves(m, p, r, 1, [step(2)], T0 + 2000)).toEqual({ ok: false, error: "stale", at: 0, seq: 2 });
  });

  it("an empty batch answers the state and stores nothing", () => {
    const r = run();
    expect(moves(m, p, r, 0, [], T0 + 1000)).toEqual({ ok: true, seq: 0, reveals: [], progress: 0, result: null });
    expect(r.answers).toEqual({});
    expect(r.lastMoveAt).toBe(0);
  });

  it("keeps only the last few answers", () => {
    const long = { ...m, make: () => ({ target: 100 }) } as DailyModule;
    const big = { target: 100 };
    const r = newRun(long, big, { id: "r1", playerId: "p_1", game: "test", date: DATE, zone: LA, now: T0 });
    for (let i = 0; i < 20; i++) moves(long, big, r, i, [step(i + 1)], T0 + 1000 * (i + 1));
    expect(Object.keys(r.answers).map(Number)).toEqual([12, 13, 14, 15, 16, 17, 18, 19]);
  });

  it("moves faster than the module's spacing allows, past a burst, are too_soon", () => {
    // A long puzzle, 100 ms apart at the fastest: the budget is 10 moves a second plus a burst of 10.
    const big = { target: 1000 };
    const spaced = { ...m, make: () => big, minMoveGapMs: 100 } as DailyModule;
    const r = newRun(spaced, big, { id: "r1", playerId: "p_1", game: "test", date: DATE, zone: LA, now: T0 });
    expect(MOVE_BURST).toBe(10);
    // 50 in the first second: the 21st breaks the budget, and the whole batch is refused.
    expect(moves(spaced, big, r, 0, Array.from({ length: 50 }, (_, i) => step(i + 1)), T0 + 1000)).toEqual({ ok: false, error: "too_soon", at: 20, seq: 0 });
    expect(r.seq).toBe(0);
    expect(r.state).toEqual({ n: 0 });
    // The first 20 fit.
    expect(moves(spaced, big, r, 0, Array.from({ length: 20 }, (_, i) => step(i + 1)), T0 + 1000)).toMatchObject({ ok: true, seq: 20 });
  });

  it("moves after the end answer over", () => {
    const r = run();
    moves(m, p, r, 0, [step(1), step(2), step(3), step(4)], T0 + 60_000);
    expect(moves(m, p, r, 4, [step(5)], T0 + 61_000)).toEqual({ ok: false, error: "over", at: 0, seq: 4 });
    expect(useHint(m, p, r, T0 + 61_000)).toEqual({ ok: false, error: "over", at: 0, seq: 4 });
    expect(giveUp(m, p, r, T0 + 61_000)).toEqual({ ok: false, error: "over", at: 0, seq: 4 });
  });

  it("a batch that runs past the end ends at the move that ended it", () => {
    const r = run();
    const batch = [step(1), step(2), step(3), step(4), step(5)];
    const a = moves(m, p, r, 0, batch, T0 + 60_000);
    expect(a).toMatchObject({ ok: true, seq: 4, result: { outcome: "solved", timeMs: 60_000 } });
    expect(r.seq).toBe(4);
    expect(r.ended).toEqual({ outcome: "solved", at: T0 + 60_000 });
    // Resent, it gets the same answer; anything after it is over.
    expect(moves(m, p, r, 0, batch, T0 + 61_000)).toEqual(a);
    expect(moves(m, p, r, 4, [step(5)], T0 + 61_000)).toEqual({ ok: false, error: "over", at: 0, seq: 4 });
  });

  it("an illegal move before the end still refuses the batch whole", () => {
    const r = run();
    expect(moves(m, p, r, 0, [step(1), step(3), step(4)], T0 + 60_000)).toEqual({ ok: false, error: "illegal", at: 1, seq: 0 });
    expect(r.ended).toBeNull();
  });

  it("a move after closesAt closes as closed", () => {
    const r = run();
    moves(m, p, r, 0, [step(1)], T0 + 1000);
    const end = closesAt(DATE, LA);
    expect(moves(m, p, r, 1, [step(2)], end)).toEqual({ ok: false, error: "over", at: 0, seq: 1 });
    expect(r.ended).toEqual({ outcome: "closed", at: end });
    expect(r.result).toMatchObject({ outcome: "closed", progress: 0.25, timeMs: end - T0 });
  });

  it("over 100 moves is bad_message", () => {
    const r = run();
    expect(MAX_BATCH).toBe(100);
    expect(moves(m, p, r, 0, Array.from({ length: 101 }, (_, i) => step(i + 1)), T0 + 1000)).toEqual({ ok: false, error: "bad_message", at: 0, seq: 0 });
    expect(moves(m, p, r, 0, "moves" as unknown as unknown[], T0 + 1000)).toEqual({ ok: false, error: "bad_message", at: 0, seq: 0 });
  });
});

describe("hints and giving up", () => {
  it("a hint adds 30 s and counts", () => {
    const r = run();
    moves(m, p, r, 0, [step(1), step(2)], T0 + 10_000);
    expect(useHint(m, p, r, T0 + 20_000)).toEqual({ ok: true, seq: 2, reveals: [{ n: 3 }], progress: 0.75, result: null });
    expect(r.hints).toBe(1);
    expect(r.seq).toBe(2);
    const done = moves(m, p, r, 2, [step(4)], T0 + 40_000);
    expect(HINT_PENALTY_MS).toBe(30_000);
    expect(done).toMatchObject({ ok: true, result: { outcome: "solved", timeMs: 40_000 + HINT_PENALTY_MS, hints: 1 } });
  });

  it("a hint that ends the run gives the result", () => {
    const r = run();
    moves(m, p, r, 0, [step(1), step(2), step(3)], T0 + 10_000);
    expect(useHint(m, p, r, T0 + 20_000)).toMatchObject({ ok: true, result: { outcome: "solved", timeMs: 20_000 + HINT_PENALTY_MS, hints: 1 } });
    expect(r.ended).toEqual({ outcome: "solved", at: T0 + 20_000 });
  });

  it("a move's reveal comes back in its answer, in order", () => {
    const marking = { ...m, apply: (pz: unknown, st: unknown, mv: unknown, ms: number) => ({ ...(m.apply(pz, st, mv, ms) as object), reveal: { mark: (mv as { n: number }).n } }) } as DailyModule;
    const r = run(marking);
    expect(moves(marking, p, r, 0, [step(1), step(2)], T0 + 1000)).toMatchObject({ ok: true, reveals: [{ mark: 1 }, { mark: 2 }] });
  });

  it("a hint with nothing to reveal answers no reveals", () => {
    const quiet = { ...m, hint: (_p: unknown, st: unknown) => ({ ok: true, state: { n: (st as { n: number }).n + 1 } }) } as DailyModule;
    expect(useHint(quiet, p, run(quiet), T0 + 1000)).toEqual({ ok: true, seq: 0, reveals: [], progress: 0.25, result: null });
  });

  it("a game with no hints refuses one as illegal", () => {
    const none = { ...m, hint: () => null } as DailyModule;
    const r = run(none);
    expect(useHint(none, p, r, T0 + 1000)).toEqual({ ok: false, error: "illegal", at: 0, seq: 0 });
    expect(r.hints).toBe(0);
  });

  it("a hint the module refuses keeps its reason", () => {
    const refused = { ...m, hint: () => ({ ok: false, reason: "too_soon" }) } as DailyModule;
    expect(useHint(refused, p, run(refused), T0 + 1000)).toEqual({ ok: false, error: "too_soon", at: 0, seq: 0 });
  });

  it("giving up ends the run unsolved, with its progress", () => {
    const r = run();
    moves(m, p, r, 0, [step(1)], T0 + 10_000);
    expect(giveUp(m, p, r, T0 + 50_000)).toEqual({
      ok: true,
      seq: 1,
      reveals: [],
      progress: 0.25,
      result: { game: "test", date: DATE, number: puzzleNumber(DATE), outcome: "gaveUp", timeMs: 50_000, hints: 0, tooFast: false, progress: 0.25 },
    });
  });

  it("a hint or give-up after closesAt closes the run instead", () => {
    const r = run();
    expect(useHint(m, p, r, closesAt(DATE, LA) + 5)).toMatchObject({ ok: false, error: "over" });
    expect(r.ended?.outcome).toBe("closed");
    const s = run();
    expect(giveUp(m, p, s, closesAt(DATE, LA))).toMatchObject({ ok: false, error: "over" });
    expect(s.ended?.outcome).toBe("closed");
  });
});

describe("the result", () => {
  it("too fast is kept and marked", () => {
    const floored = { ...m, floorMs: { 1: 60_000, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0 } } as DailyModule;
    const r = run(floored);
    const a = moves(floored, p, r, 0, [step(1), step(2), step(3), step(4)], T0 + 59_999);
    expect(a).toMatchObject({ ok: true, result: { outcome: "solved", timeMs: 59_999, tooFast: true } });
    const s = run(floored);
    expect(moves(floored, p, s, 0, [step(1), step(2), step(3), step(4)], T0 + 60_000)).toMatchObject({ result: { tooFast: false } });
  });

  it("the server's numbers win over the module's", () => {
    const lying = { ...m, result: () => ({ outcome: "solved", timeMs: 1, hints: 0, progress: 1 }) } as DailyModule;
    const r = run(lying);
    expect(giveUp(lying, p, r, T0 + 70_000)).toMatchObject({ ok: true, result: { outcome: "gaveUp", timeMs: 70_000 } });
  });

  it("close at day end gives closed with progress", () => {
    const r = run();
    moves(m, p, r, 0, [step(1), step(2)], T0 + 1000);
    expect(close(m, p, r, closesAt(DATE, LA) - 1)).toBeNull();
    expect(r.ended).toBeNull();
    // The alarm may run late: the run closed at 04:00 all the same.
    const result = close(m, p, r, closesAt(DATE, LA) + 5000);
    expect(result).toEqual({ game: "test", date: DATE, number: puzzleNumber(DATE), outcome: "closed", timeMs: closesAt(DATE, LA) - T0, hints: 0, tooFast: false, progress: 0.5 });
    expect(r.ended).toEqual({ outcome: "closed", at: closesAt(DATE, LA) });
    expect(close(m, p, r, closesAt(DATE, LA) + 9000)).toBeNull();
  });
});

describe("countsForStreak", () => {
  const ended = (outcome: "solved" | "missed" | "done" | "gaveUp" | "closed", seq: number): RunState => ({
    ...run(),
    seq,
    ended: { outcome, at: T0 + 1000 },
  });

  it("countsForStreak: solved, missed, done, gaveUp-with-moves yes; closed and gaveUp-without-moves no", () => {
    expect(countsForStreak(ended("solved", 4))).toBe(true);
    expect(countsForStreak(ended("missed", 6))).toBe(true);
    expect(countsForStreak(ended("done", 9))).toBe(true);
    expect(countsForStreak(ended("gaveUp", 1))).toBe(true);
    expect(countsForStreak(ended("gaveUp", 0))).toBe(false);
    expect(countsForStreak(ended("closed", 3))).toBe(false);
    expect(countsForStreak(run())).toBe(false);
  });

  it("giving up with no moves ends gaveUp but doesn't count", () => {
    const r = run();
    expect(giveUp(m, p, r, T0 + 1000)).toMatchObject({ ok: true, result: { outcome: "gaveUp" } });
    expect(countsForStreak(r)).toBe(false);
  });
});

describe("startView", () => {
  it("is what start answers: the public puzzle and state, never the whole puzzle", () => {
    const r = run();
    moves(m, p, r, 0, [step(1)], T0 + 1000);
    expect(startView(m, p, r, T0 + 2000)).toEqual({
      run: "r1",
      game: "test",
      date: DATE,
      number: puzzleNumber(DATE),
      level: 1,
      startedAt: T0,
      now: T0 + 2000,
      puzzle: { target: 4 },
      state: { n: 1 },
      seq: 1,
      hints: 0,
      result: null,
      closesAt: closesAt(DATE, LA),
      hintMs: HINT_PENALTY_MS,
    });
  });

  it("says what a hint costs, as the game sets it", () => {
    const free: DailyModule = { ...m, hintMs: () => 0 };
    const r = run(free);
    expect(startView(free, p, r, T0).hintMs).toBe(0);
    useHint(free, p, r, T0 + 1000);
    useHint(free, p, r, T0 + 2000);
    expect(moves(free, p, r, 0, [step(3), step(4)], T0 + 40_000)).toMatchObject({ ok: true, result: { outcome: "solved", timeMs: 40_000, hints: 2 } });
  });
});

describe("resends are matched by what they carry", () => {
  it("a different batch from an old from is stale, not the old answer", () => {
    const r = run();
    moves(m, p, r, 0, [step(1), step(2)], T0 + 1000);
    expect(moves(m, p, r, 0, [step(1)], T0 + 2000)).toEqual({ ok: false, error: "stale", at: 0, seq: 2 });
    expect(moves(m, p, r, 0, [step(1), step(2), step(3)], T0 + 2000)).toEqual({ ok: false, error: "stale", at: 0, seq: 2 });
    expect(moves(m, p, r, 0, [step(1), step(2)], T0 + 2000)).toMatchObject({ ok: true, seq: 2 });
  });
});

describe("a hint resent", () => {
  it("with the count it was asked at, gets the same answer once", () => {
    const r = run();
    const first = useHint(m, p, r, T0 + 1000, 0);
    expect(first).toMatchObject({ ok: true, reveals: [{ n: 1 }] });
    expect(useHint(m, p, r, T0 + 2000, 0)).toEqual(first);
    expect(r.hints).toBe(1);
    expect(useHint(m, p, r, T0 + 3000, 1)).toMatchObject({ ok: true, reveals: [{ n: 2 }] });
    expect(r.hints).toBe(2);
  });

  it("a count the run never had is stale", () => {
    const r = run();
    expect(useHint(m, p, r, T0 + 1000, 3)).toEqual({ ok: false, error: "stale", at: 0, seq: 0 });
    useHint(m, p, r, T0 + 1000, 0);
    r.hintAnswers = {};
    expect(useHint(m, p, r, T0 + 2000, 0)).toEqual({ ok: false, error: "stale", at: 0, seq: 0 });
  });

  it("without a count, every call is a new hint, as before", () => {
    const r = run();
    useHint(m, p, r, T0 + 1000);
    useHint(m, p, r, T0 + 2000);
    expect(r.hints).toBe(2);
  });
});

describe("what a result carries", () => {
  it("only the result's own fields: nothing else a game returns reaches the board", () => {
    const leaky = { ...m, result: () => ({ outcome: "solved", timeMs: 1, hints: 0, progress: 1, guesses: 3, points: 7, answer: "CRANE" }) } as unknown as DailyModule;
    const r = run(leaky);
    const a = giveUp(leaky, p, r, T0 + 5000);
    expect(a).toMatchObject({ ok: true, result: { guesses: 3, points: 7, progress: 1 } });
    expect(Object.keys(r.result as object).sort()).toEqual(["date", "game", "guesses", "hints", "number", "outcome", "points", "progress", "timeMs", "tooFast"]);
  });
});

describe("the move budget", () => {
  const big = { target: 1000 };
  const spaced = (gap: number) => ({ ...m, make: () => big, minMoveGapMs: gap }) as DailyModule;
  const fresh = (mod: DailyModule) => newRun(mod, big, { id: "r1", playerId: "p_1", game: "test", date: DATE, zone: LA, now: T0 });

  it("three quick moves in one batch are accepted", () => {
    const mod = spaced(100);
    const r = fresh(mod);
    expect(moves(mod, big, r, 0, [step(1), step(2), step(3)], T0 + 5000)).toMatchObject({ ok: true, seq: 3 });
  });

  it("1 s batches with 200 ms of jitter are accepted", () => {
    // Eight moves a second (125 ms apart, under the 100 ms limit), sent every second, arriving 200 ms early or late.
    const mod = spaced(100);
    const r = fresh(mod);
    let n = 0;
    for (let k = 1; k <= 30; k++) {
      const batch = Array.from({ length: 8 }, (_, i) => step(n + i + 1));
      const at = T0 + k * 1000 + (k % 2 === 0 ? 200 : -200);
      expect(moves(mod, big, r, n, batch, at), `batch ${k}`).toMatchObject({ ok: true });
      n += 8;
    }
    expect(r.seq).toBe(240);
  });

  it("a resent batch still gets its stored answer", () => {
    const mod = spaced(100);
    const r = fresh(mod);
    const first = moves(mod, big, r, 0, Array.from({ length: 20 }, (_, i) => step(i + 1)), T0 + 1000);
    expect(first).toMatchObject({ ok: true, seq: 20 });
    expect(moves(mod, big, r, 0, Array.from({ length: 20 }, (_, i) => step(i + 1)), T0 + 1001)).toEqual(first);
  });

  it("hints don't count toward it, and a game with no spacing has none", () => {
    const mod = spaced(100);
    const r = fresh(mod);
    for (let i = 0; i < 15; i++) useHint(mod, big, r, T0 + 10);
    expect(moves(mod, big, r, 0, Array.from({ length: 10 }, (_, i) => step(16 + i)), T0 + 10)).toMatchObject({ ok: true, seq: 10 });
    const free = spaced(0);
    const q = fresh(free);
    expect(moves(free, big, q, 0, Array.from({ length: 100 }, (_, i) => step(i + 1)), T0)).toMatchObject({ ok: true, seq: 100 });
  });
});
