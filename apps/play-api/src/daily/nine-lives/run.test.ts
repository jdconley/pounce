import { describe, expect, test } from "vitest";

import { seedOf } from "../../../tests/seeds";
import { createRng } from "../../rules/rng";
import { HINT_PENALTY_MS, moves, newRun, startView, useHint, type RunState } from "../run-core";

import { nineLives } from "./module";

import type { DailyModule } from "../module";

const m = nineLives as unknown as DailyModule;
const date = "2027-01-04"; // a Monday
const p = nineLives.make(createRng(seedOf(7)), 1, { date, key: seedOf(8) });
const open = p.givens.flatMap((d, i) => (d === 0 ? [i] : []));
const T0 = Date.UTC(2027, 0, 4, 18);

function run(): RunState {
  return newRun(m, p, { id: "r", playerId: "me", game: "nine-lives", date, zone: "America/Los_Angeles", now: T0 });
}

describe("Nine Lives refereed by the server's run core", () => {
  test("start shows the givens and never the solution", () => {
    const v = startView(m, p, run(), T0);
    expect(v.puzzle).toEqual({ givens: p.givens });
    expect(JSON.stringify(v)).not.toContain(JSON.stringify(p.solution));
  });

  test("one move per batch, a second apart, to solved: the server's time", () => {
    const r = run();
    open.forEach((i, k) => {
      const a = moves(m, p, r, k, [{ k: "set", i, d: p.solution[i] }], T0 + (k + 1) * 2_000);
      expect(a.ok, `move ${k}`).toBe(true);
    });
    expect(r.result).toMatchObject({ outcome: "solved", timeMs: open.length * 2_000, hints: 0, progress: 1, tooFast: false });
  });

  test("a batch of several moves made over a second is accepted", () => {
    const r = run();
    const batch = open.slice(0, 3).map((i) => ({ k: "set", i, d: p.solution[i] }));
    expect(moves(m, p, r, 0, batch, T0 + 5_000)).toMatchObject({ ok: true, seq: 3 });
  });

  test("sustained inhuman speed is refused: more moves than the time allows (S1's cumulative budget)", () => {
    // A second in, the budget is floor(1000 / 100) + 10 = 20 moves; a whole solve is far more.
    const r = run();
    const batch = open.map((i) => ({ k: "set", i, d: p.solution[i] }));
    expect(batch.length).toBeGreaterThan(20);
    expect(moves(m, p, r, 0, batch, T0 + 1_000)).toMatchObject({ ok: false, error: "too_soon" });
    expect(r.seq).toBe(0);
  });

  test("a hint fills a cell and costs 30 s", () => {
    const r = run();
    const a = useHint(m, p, r, T0 + 10_000);
    expect(a).toMatchObject({ ok: true, reveals: [{ i: expect.any(Number), d: expect.any(Number) }] });
    expect(r.hints).toBe(1);
    expect(HINT_PENALTY_MS).toBe(30_000);
  });
});
