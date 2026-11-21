import type { DayLevel } from "./days";
import type { Applied, DailyModule, DailyResult, Outcome } from "./module";
import type { Rng } from "../rules/rng";

/**
 * The server's test-only daily game, "count to N": listed only with `DAILY_TEST` on (Miniflare),
 * so the server core and the Dish's hosts are tested end to end before any real game lands.
 */
export type TestPuzzle = { target: number };
export type TestState = { n: number };
export type TestMove = { k: "step"; n: number };

const ZERO: Record<DayLevel, number> = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0 };

function take(p: TestPuzzle, s: TestState, n: number): Applied<TestState> {
  if (s.n >= p.target) return { ok: false, reason: "over" };
  if (n !== s.n + 1) return { ok: false, reason: "illegal" };
  const state = { n };
  return n === p.target ? { ok: true, state, end: "solved" } : { ok: true, state };
}

export const testGame: DailyModule<TestPuzzle, TestState, TestMove> = {
  id: "test",
  make: (_rng: Rng, level: DayLevel) => ({ target: 3 + level }),
  publicPuzzle: (p) => ({ target: p.target }),
  init: () => ({ n: 0 }),
  parseMove(raw) {
    if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return null;
    const keys = Object.keys(raw);
    const m = raw as Record<string, unknown>;
    if (keys.length !== 2 || m.k !== "step" || !Number.isInteger(m.n)) return null;
    return { k: "step", n: m.n as number };
  },
  apply: (p, s, m) => take(p, s, m.n),
  hint(p, s) {
    const a = take(p, s, s.n + 1);
    return a.ok ? { ...a, reveal: { n: a.state.n } } : a;
  },
  progress: (p, s) => s.n / p.target,
  publicState: (_p, s) => ({ n: s.n }),
  result: (p, s, outcome: Outcome, timeMs: number, hints: number) => ({ outcome, timeMs, hints, progress: s.n / p.target }),
  compare(a: DailyResult, b: DailyResult) {
    const solved = Number(b.outcome === "solved") - Number(a.outcome === "solved");
    if (solved !== 0) return solved;
    if (a.outcome !== "solved" && a.progress !== b.progress) return b.progress - a.progress;
    return a.timeMs - b.timeMs;
  },
  floorMs: ZERO,
  minMoveGapMs: 0,
};
