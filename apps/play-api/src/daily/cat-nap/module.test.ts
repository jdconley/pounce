import { describe, expect, test } from "vitest";

import { createRng } from "../../rules/rng";

import { makeNap, type NapPuzzle } from "./maker";
import { catNap } from "./module";
import { clashes, complete, type NapMove, type NapState } from "./rules";

import type { DailyResult } from "./contract";

const P: NapPuzzle = makeNap(createRng([4, 4, 4, 4]), 1);
const at = (r: number, c: number) => r * P.n + c;
const cat = (cell: number): NapMove => ({ k: "mark", cells: [cell], to: "cat" });

function play(moves: NapMove[]): ReturnType<typeof catNap.apply> {
  let s = catNap.init(P);
  let last: ReturnType<typeof catNap.apply> = { ok: true, state: s };
  for (const m of moves) {
    last = catNap.apply(P, s, m, 1000);
    if (!last.ok) return last;
    s = last.state;
  }
  return last;
}

describe("catNap", () => {
  test("is cat-nap, with no move spacing and floors that grow with the quilt", () => {
    expect(catNap.id).toBe("cat-nap");
    expect(catNap.minMoveGapMs).toBe(0);
    expect(catNap.floorMs).toEqual({ 1: 6000, 2: 9000, 3: 12000, 4: 12000, 5: 16000, 6: 16000, 7: 20000 });
    expect(catNap.make(createRng([4, 4, 4, 4]), 1)).toEqual(P);
  });

  test("publicPuzzle carries only n and patches", () => {
    const pub = catNap.publicPuzzle(P) as Record<string, unknown>;
    expect(Object.keys(pub).sort()).toEqual(["n", "patches"]);
    expect(pub).toEqual({ n: P.n, patches: P.patches });
    expect(JSON.stringify(pub)).not.toContain("solution");
  });

  test("parseMove is the rules' exact shape", () => {
    expect(catNap.parseMove({ k: "mark", cells: [0], to: "x" })).toEqual({ k: "mark", cells: [0], to: "x" });
    expect(catNap.parseMove({ k: "mark", cells: [0], to: "x", solved: true })).toBeNull();
  });

  test("solving by marks ends solved, and only on the last cat", () => {
    const cats = P.solution.map((c, r) => cat(at(r, c)));
    const before = play(cats.slice(0, -1));
    expect(before.ok && before.end).toBeUndefined();
    const done = play([{ k: "mark", cells: [0, 1], to: "x" }, ...cats]);
    expect(done).toMatchObject({ ok: true, end: "solved" });
  });

  test("an illegal move is refused", () => {
    expect(play([cat(P.n * P.n)])).toEqual({ ok: false, reason: "illegal" });
  });

  test("a full quilt that breaks a rule is not solved", () => {
    // Every solution cat, one moved sideways into its neighbour: n cats, some clash.
    const cells = P.solution.map((c, r) => at(r, c));
    const r0 = P.solution[0]!;
    cells[0] = at(0, r0 === 0 ? 1 : r0 - 1);
    const out = play(cells.map(cat));
    expect(out.ok).toBe(true);
    expect(out.ok && out.end).toBeUndefined();
    expect(out.ok && complete(P, out.state)).toBe(false);
  });

  test("hint reveals one cell and can finish", () => {
    let s = catNap.init(P);
    for (let i = 0; i < P.n; i++) {
      const h = catNap.hint(P, s)!;
      expect(h.ok).toBe(true);
      if (!h.ok) return;
      expect(h.reveal).toEqual({ cell: at(i, P.solution[i]!) });
      expect(h.end).toBe(i === P.n - 1 ? "solved" : undefined);
      s = h.state;
    }
    expect(s.hinted).toHaveLength(P.n);
    expect(catNap.hint(P, s)).toEqual({ ok: false, reason: "over" });
  });

  test("progress counts cats that break no rule", () => {
    const s = catNap.init(P);
    expect(catNap.progress(P, s)).toBe(0);
    const one = play([cat(at(0, P.solution[0]!))]);
    expect(one.ok && catNap.progress(P, one.state)).toBe(1 / P.n);
  });

  test("result is the server's outcome, time, hints and progress", () => {
    const s = catNap.init(P);
    expect(catNap.result(P, s, "gaveUp", 61_000, 1)).toEqual({ outcome: "gaveUp", timeMs: 61_000, hints: 1, progress: 0 });
  });

  test("compare ranks solved by time, then unsolved by progress", () => {
    const r = (outcome: DailyResult["outcome"], timeMs: number, progress: number): DailyResult => ({
      game: "cat-nap", date: "2027-01-04", number: 1, outcome, timeMs, hints: 0, tooFast: false, progress,
    });
    const fast = r("solved", 60_000, 1);
    const slow = r("solved", 90_000, 1);
    const far = r("gaveUp", 30_000, 0.8);
    const near = r("closed", 20_000, 0.2);
    const nearSlow = r("gaveUp", 40_000, 0.2);
    const sorted = [near, slow, nearSlow, far, fast].sort(catNap.compare);
    expect(sorted).toEqual([fast, slow, far, near, nearSlow]);
    expect(catNap.compare(fast, { ...fast })).toBe(0);
  });

  test("publicState round-trips into the client rules", () => {
    const h = catNap.hint(P, catNap.init(P))!;
    if (!h.ok) throw new Error("hint");
    const out = catNap.apply(P, h.state, { k: "mark", cells: [at(P.n - 1, 0), at(P.n - 1, 1)], to: "x" }, 0);
    if (!out.ok) throw new Error("apply");
    const wire = JSON.parse(JSON.stringify(catNap.publicState(P, out.state))) as NapState;
    expect(wire).toEqual(out.state);
    expect(clashes(P, wire)).toEqual(clashes(P, out.state));
    expect(Object.keys(wire).sort()).toEqual(["cells", "hinted"]);
  });
});
