import { describe, expect, test } from "vitest";

import { seedOf } from "../../../tests/seeds";
import { createRng } from "../../rules/rng";
import { addToStats, rankGame, dish, type BoardRow } from "../board";
import { countsForStreak, giveUp, HINT_PENALTY_MS, moves, newRun, restart, startView, useHint, type RunState } from "../run-core";

import { HINTS, LIVES, LIVES_RULES, nineLives } from "./module";

import type { NineLivesState } from "./grid";
import type { DailyModule, DailyResult } from "../module";

/**
 * The `"lives"` rules (spec, "Nine Lives: lives and hints"): a number is checked against the
 * solution as it comes, three wrong ones end the run `missed`, and three hints cost nothing.
 * Runs that don't ask keep the first rules.
 */
const m = nineLives as unknown as DailyModule;
const date = "2027-01-04"; // a Monday
const p = nineLives.make(createRng(seedOf(7)), 1, { date, key: seedOf(8) });
const open = p.givens.flatMap((d, i) => (d === 0 ? [i] : []));
const T0 = Date.UTC(2027, 0, 4, 18);
const wrongDigit = (i: number) => (p.solution[i]! % 9) + 1;
const right = (i: number) => ({ k: "set", i, d: p.solution[i]! });
const wrong = (i: number) => ({ k: "set", i, d: wrongDigit(i) });

function run(rules?: string): RunState {
  return newRun(m, p, { id: "r", playerId: "me", game: "nine-lives", date, zone: "America/Los_Angeles", now: T0, ...(rules ? { rules } : {}) });
}

/** Plays `list` one move per batch, ten seconds apart, from the run's seq. */
function play(r: RunState, list: unknown[], at = T0) {
  return list.map((mv, k) => moves(m, p, r, r.seq, [mv], at + (k + 1) * 10_000));
}

describe("Nine Lives with lives: what start says", () => {
  test("a run that asks starts with three lives, three hints and free hints", () => {
    const v = startView(m, p, run(LIVES_RULES), T0);
    expect(v.state).toEqual({ cells: p.givens, hinted: [], rules: "lives", lives: LIVES, hintsLeft: HINTS, wrong: [] });
    expect(v.hintMs).toBe(0);
    expect(JSON.stringify(v)).not.toContain(JSON.stringify(p.solution));
  });

  test("a run that doesn't ask, or asks for rules Nine Lives doesn't have, plays the first rules", () => {
    for (const r of [run(), run("hearts")]) {
      const v = startView(m, p, r, T0);
      expect(v.state).toEqual({ cells: p.givens, hinted: [] });
      expect(v.hintMs).toBe(HINT_PENALTY_MS);
    }
  });
});

describe("Nine Lives with lives: entries are checked as they come", () => {
  test("a right number is placed, reveals nothing, and locks", () => {
    const r = run(LIVES_RULES);
    const i = open[0]!;
    expect(play(r, [right(i)])[0]).toMatchObject({ ok: true, seq: 1, reveals: [] });
    expect((r.state as NineLivesState).cells[i]).toBe(p.solution[i]);
    // It can't be changed or cleared: a right cell is as fixed as a given.
    expect(moves(m, p, r, 1, [wrong(i)], T0 + 60_000)).toMatchObject({ ok: false, error: "illegal" });
    expect(moves(m, p, r, 1, [{ k: "clear", i }], T0 + 60_000)).toMatchObject({ ok: false, error: "illegal" });
    expect((r.state as NineLivesState).lives).toBe(3);
  });

  test("a wrong number costs a life, reveals itself, and never reaches the board", () => {
    const r = run(LIVES_RULES);
    const i = open[0]!;
    const [a] = play(r, [wrong(i)]);
    expect(a).toEqual({ ok: true, seq: 1, reveals: [{ k: "wrong", i, d: wrongDigit(i), lives: 2 }], progress: 0, result: null });
    const s = r.state as NineLivesState;
    expect(s.cells[i]).toBe(0);
    expect(s.wrong).toEqual([{ i, d: wrongDigit(i) }]);
    expect(startView(m, p, r, T0 + 20_000).state).toMatchObject({ lives: 2, wrong: [{ i, d: wrongDigit(i) }] });
    // The cell is still open: the right number goes in after.
    expect(play(r, [right(i)], T0 + 20_000)[0]).toMatchObject({ ok: true, reveals: [] });
  });

  test("the same wrong number twice costs two lives", () => {
    const r = run(LIVES_RULES);
    play(r, [wrong(open[0]!), wrong(open[0]!)]);
    expect((r.state as NineLivesState).lives).toBe(1);
  });

  test("a given is illegal and costs nothing", () => {
    const r = run(LIVES_RULES);
    const given = p.givens.findIndex((d) => d !== 0);
    expect(moves(m, p, r, 0, [{ k: "set", i: given, d: (p.givens[given]! % 9) + 1 }], T0 + 10_000)).toMatchObject({ ok: false, error: "illegal" });
    expect((r.state as NineLivesState).lives).toBe(3);
  });

  test("a board out of lives takes nothing more, even asked directly", () => {
    const s: NineLivesState = { cells: [...p.givens], hinted: [], lives: 0, wrong: [] };
    expect(nineLives.apply(p, s, { k: "set", i: open[0]!, d: p.solution[open[0]!]! }, 0)).toEqual({ ok: false, reason: "over" });
  });

  test("clear is illegal under lives: the board holds no wrong number to clear", () => {
    const r = run(LIVES_RULES);
    expect(moves(m, p, r, 0, [{ k: "clear", i: open[0]! }], T0 + 10_000)).toMatchObject({ ok: false, error: "illegal", at: 0, seq: 0 });
  });
});

describe("Nine Lives with lives: out of lives", () => {
  test("the third wrong number ends the run missed and hands over the solution", () => {
    const r = run(LIVES_RULES);
    const [, , last] = play(r, [wrong(open[0]!), wrong(open[2]!), wrong(open[3]!)]);
    expect(last).toMatchObject({
      ok: true,
      reveals: [{ k: "wrong", i: open[3], d: wrongDigit(open[3]!), lives: 0, solution: p.solution }],
      result: { game: "nine-lives", outcome: "missed", hints: 0, timeMs: 30_000, progress: 0 },
    });
    expect(r.ended).toEqual({ outcome: "missed", at: T0 + 30_000 });
    expect(startView(m, p, r, T0 + 40_000).state).toMatchObject({ lives: 0, solution: p.solution });
    expect(countsForStreak(r)).toBe(true);
  });

  test("its progress is the right numbers placed", () => {
    const r = run(LIVES_RULES);
    play(r, [right(open[0]!), right(open[1]!), wrong(open[2]!), wrong(open[2]!), wrong(open[2]!)]);
    expect(r.result).toMatchObject({ outcome: "missed", progress: 2 / open.length });
  });

  test("nothing goes in after: moves, hints and giving up are over", () => {
    const r = run(LIVES_RULES);
    play(r, [wrong(open[0]!), wrong(open[0]!), wrong(open[0]!)]);
    expect(moves(m, p, r, 3, [right(open[0]!)], T0 + 60_000)).toMatchObject({ ok: false, error: "over" });
    expect(useHint(m, p, r, T0 + 60_000)).toMatchObject({ ok: false, error: "over" });
    expect(giveUp(m, p, r, T0 + 60_000)).toMatchObject({ ok: false, error: "over" });
  });

  test("a batch that runs out of lives mid-way ends at that move", () => {
    const r = run(LIVES_RULES);
    const a = moves(m, p, r, 0, [wrong(open[0]!), wrong(open[1]!), wrong(open[2]!), right(open[3]!)], T0 + 10_000);
    expect(a).toMatchObject({ ok: true, seq: 3, result: { outcome: "missed" } });
    expect((r.state as NineLivesState).cells[open[3]!]).toBe(0);
  });

  test("the solution is never in the state before the run ended out of lives", () => {
    const r = run(LIVES_RULES);
    play(r, [wrong(open[0]!), wrong(open[0]!)]);
    expect(JSON.stringify(startView(m, p, r, T0 + 30_000))).not.toContain(JSON.stringify(p.solution));
    giveUp(m, p, r, T0 + 40_000);
    expect(JSON.stringify(startView(m, p, r, T0 + 50_000))).not.toContain(JSON.stringify(p.solution));
  });
});

describe("Nine Lives with lives: three hints, separate from lives", () => {
  test("hints are free, never cost a life, and stop at three", () => {
    const r = run(LIVES_RULES);
    for (let k = 0; k < HINTS; k++) {
      expect(useHint(m, p, r, T0 + (k + 1) * 1_000, k)).toMatchObject({ ok: true, reveals: [{ i: expect.any(Number), d: expect.any(Number) }] });
    }
    expect(startView(m, p, r, T0 + 5_000).state).toMatchObject({ lives: 3, hintsLeft: 0 });
    expect(useHint(m, p, r, T0 + 6_000, 3)).toMatchObject({ ok: false, error: "illegal" });
    expect(r.hints).toBe(3);
    // A resent third hint still gets its own answer.
    expect(useHint(m, p, r, T0 + 7_000, 2)).toMatchObject({ ok: true });
  });

  test("a hinted solve's time has no penalty", () => {
    const r = run(LIVES_RULES);
    useHint(m, p, r, T0 + 1_000, 0);
    const rest = open.filter((i) => !(r.state as NineLivesState).hinted.includes(i));
    play(r, rest.map(right));
    expect(r.result).toMatchObject({ outcome: "solved", hints: 1, timeMs: rest.length * 10_000 });
  });

  test("lives don't limit hints: with one life left, all three hints still come", () => {
    const r = run(LIVES_RULES);
    play(r, [wrong(open[0]!), wrong(open[0]!)]);
    for (let k = 0; k < HINTS; k++) expect(useHint(m, p, r, T0 + 60_000 + k * 1_000, k)).toMatchObject({ ok: true });
    expect((r.state as NineLivesState).lives).toBe(1);
  });
});

describe("an app that can't show lives never plays by them (spec, \"Older apps keep their rules\")", () => {
  test("a start without the rules puts an open lives run back on the first rules, for good", () => {
    const r = run(LIVES_RULES);
    play(r, [wrong(open[0]!), wrong(open[0]!)]);
    useHint(m, p, r, T0 + 30_000, 0);
    expect(restart(m, p, r, LIVES_RULES)).toBe(false);
    expect(restart(m, p, r, undefined)).toBe(true);
    const v = startView(m, p, r, T0 + 40_000);
    expect(Object.keys(v.state as object).sort()).toEqual(["cells", "hinted"]);
    expect(v.hintMs).toBe(HINT_PENALTY_MS);
    // A third wrong number is just a number now; asking for lives again doesn't bring them back.
    expect(play(r, [wrong(open[1]!)], T0 + 40_000)[0]).toMatchObject({ ok: true, result: null });
    expect(restart(m, p, r, LIVES_RULES)).toBe(false);
  });

  test("hints taken under lives stay free; hints after cost 30 s", () => {
    const r = run(LIVES_RULES);
    useHint(m, p, r, T0 + 1_000, 0);
    restart(m, p, r, undefined);
    useHint(m, p, r, T0 + 2_000, 1);
    expect(giveUp(m, p, r, T0 + 10_000, 9_000)).toMatchObject({ result: { hints: 2, timeMs: 9_000 + HINT_PENALTY_MS } });
  });

  test("an ended run, and a run on the first rules, are left as they are", () => {
    const done = run(LIVES_RULES);
    play(done, [wrong(open[0]!), wrong(open[0]!), wrong(open[0]!)]);
    expect(restart(m, p, done, undefined)).toBe(false);
    expect(startView(m, p, done, T0 + 60_000).state).toMatchObject({ lives: 0 });
    expect(restart(m, p, run(), undefined)).toBe(false);
  });
});

describe("Nine Lives on the first rules: unchanged", () => {
  test("a wrong number is placed, costs nothing, and can be cleared; hints cost 30 s and never run out", () => {
    const r = run();
    const i = open[0]!;
    expect(play(r, [wrong(i), { k: "clear", i }])).toEqual([
      expect.objectContaining({ ok: true, reveals: [] }),
      expect.objectContaining({ ok: true, reveals: [] }),
    ]);
    for (let k = 0; k < 5; k++) expect(useHint(m, p, r, T0 + 30_000 + k * 1_000, k)).toMatchObject({ ok: true });
    const rest = open.filter((c) => !(r.state as NineLivesState).hinted.includes(c));
    play(r, rest.map(right), T0 + 40_000);
    expect(r.result).toMatchObject({ outcome: "solved", hints: 5, timeMs: 40_000 + rest.length * 10_000 + 5 * HINT_PENALTY_MS });
  });
});

describe("a failed run counts as Sniff's miss does (spec ruling)", () => {
  const res = (player: string, over: Partial<DailyResult>): BoardRow => ({
    player,
    name: player,
    cat: 0,
    rank: null,
    playing: null,
    result: { game: "nine-lives", date, number: 1, outcome: "solved", timeMs: 300_000, hints: 0, tooFast: false, progress: 1, ...over },
  });

  test("after every solver, by progress; 1 Dish point for ending it; played, not solved", () => {
    const rows = rankGame(m, [
      res("failed", { outcome: "missed", progress: 0.6, timeMs: 100_000 }),
      res("slow", { timeMs: 900_000 }),
      res("quit", { outcome: "gaveUp", progress: 0.2, timeMs: 50_000 }),
    ]);
    expect(rows.map((r) => [r.player, r.rank])).toEqual([["slow", 1], ["failed", 2], ["quit", 3]]);
    const points = Object.fromEntries(dish([{ game: "nine-lives", number: 1, rows }]).rows.map((r) => [r.player, r.points]));
    expect(points).toEqual({ slow: 4, failed: 3, quit: 2 });
    const stats = addToStats(null, rows[1]!.result!);
    expect(stats).toMatchObject({ played: 1, solved: 0, streak: 1 });
  });
});
