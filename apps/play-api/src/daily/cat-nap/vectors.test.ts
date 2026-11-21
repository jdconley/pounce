/**
 * Cat Nap's golden vectors (`fixtures/daily/cat-nap/vectors.json`): a quilt, a start, and steps,
 * each with the board, clashes, completeness and progress after it. The Swift rules
 * (`PounceKit/Daily/CatNap/CatNapRules.swift`) must give the same for every step
 * (`CatNapRulesTests`). A rule change changes these, and both sides fail until both match.
 * Regenerate with
 * `UPDATE_FIXTURES=1 pnpm --filter @pounce/play-api exec vitest run src/daily/cat-nap/vectors.test.ts`.
 */
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";

import { expect, test } from "vitest";

import { createRng } from "../../rules/rng";

import { makeNap } from "./maker";
import {
  applyHint,
  applyMark,
  catsPlaced,
  clashes,
  complete,
  dragMove,
  dragPaint,
  emptyState,
  parseNapMove,
  tapMove,
  type Clashes,
  type NapMove,
  type NapState,
  type Quilt,
} from "./rules";

type Input = { move: unknown } | { hint: number } | { tap: number } | { drag: number[] };
type Step = Input & { made?: NapMove | null; ok: boolean; state: NapState; clashes: Clashes; complete: boolean; placed: number };
type Vector = { name: string; quilt: Quilt; start: NapState; steps: Step[] };

const write = process.env.UPDATE_FIXTURES === "1";
const FILE = new URL("../../../fixtures/daily/cat-nap/vectors.json", import.meta.url);

/** The 5 by 5 quilt from the rules tests: one solution, cats at (0,1) (1,3) (2,0) (3,2) (4,4). */
const Q5: Quilt = { n: 5, patches: [0, 0, 1, 1, 1, 0, 2, 2, 1, 1, 3, 2, 2, 2, 1, 3, 3, 2, 4, 4, 3, 3, 4, 4, 4] };
const SOL5 = [1, 3, 0, 2, 4];
const at = (r: number, c: number) => r * 5 + c;
const P9 = makeNap(createRng([2027, 1, 10, 7]), 7);
const Q9: Quilt = { n: P9.n, patches: P9.patches };

function run(q: Quilt, s: NapState, input: Input): { ok: boolean; state: NapState; made?: NapMove | null } {
  if ("hint" in input) return { ok: true, state: applyHint(q, s, input.hint) };
  let made: NapMove | null;
  if ("move" in input) made = parseNapMove(input.move);
  else if ("tap" in input) made = tapMove(s, input.tap);
  else {
    const paint = dragPaint(s, input.drag[0]!);
    made = paint && dragMove(s, paint, input.drag);
  }
  const next = made && applyMark(q, s, made);
  const out = { ok: next !== null, state: next ?? s };
  return "move" in input ? out : { ...out, made };
}

function vector(name: string, quilt: Quilt, inputs: Input[], start: NapState = emptyState(quilt)): Vector {
  let s = start;
  const steps = inputs.map((input) => {
    const out = run(quilt, s, input);
    s = out.state;
    return { ...input, ...("made" in out ? { made: out.made } : {}), ok: out.ok, state: s, clashes: clashes(quilt, s), complete: complete(quilt, s), placed: catsPlaced(quilt, s) };
  });
  return { name, quilt, start, steps };
}

const mark = (cells: number[], to: string) => ({ move: { k: "mark", cells, to } });

function vectors(): Vector[] {
  const hinted: NapState = { cells: emptyState(Q5).cells.map((_, i) => (i === at(0, 1) ? 2 : 0)), hinted: [at(0, 1)] };
  return [
    vector("tap-cycle", Q5, [{ tap: 7 }, { tap: 7 }, { tap: 7 }, { tap: 7 }]),
    vector("drag-x", Q5, [mark([at(2, 2)], "cat"), { drag: [0, 1, 2, 3, 4, 9, 14] }, { drag: [12, 13, 14] }]),
    vector("drag-clear", Q5, [{ drag: [0, 1, 2, 3, 4] }, { drag: [1, 2, 3, 7] }]),
    vector("row-clash", Q5, [mark([at(0, 0)], "cat"), mark([at(0, 4)], "cat"), mark([at(0, 4)], "clear")]),
    vector("column-clash", Q5, [mark([at(0, 3)], "cat"), mark([at(3, 3)], "cat")]),
    vector("patch-clash", Q5, [mark([at(1, 1)], "cat"), mark([at(3, 2)], "cat")]),
    vector("touching-diagonal", Q5, [mark([at(1, 1)], "cat"), mark([at(2, 2)], "cat"), mark([at(4, 4)], "cat")]),
    vector("touching-side", Q5, [mark([at(2, 3)], "cat"), mark([at(3, 3)], "cat")]),
    vector("touching-edges", Q5, [mark([at(1, 4)], "cat"), mark([at(2, 0)], "cat")]),
    vector("full-but-touching", Q5, [at(0, 0), at(1, 1), at(2, 3), at(3, 2), at(4, 4)].map((c) => mark([c], "cat"))),
    vector("finish-5x5", Q5, [mark([0, 2, 3, 4], "x"), ...SOL5.map((c, r) => mark([at(r, c)], "cat"))]),
    vector("finish-9x9", Q9, [
      mark([0, 1, 2], "x"),
      ...P9.solution.map((c, r) => mark([r * 9 + c], "cat")),
      mark([80], "clear"),
    ]),
    vector("hint-locks", Q5, [{ hint: at(0, 1) }, mark([at(0, 1)], "clear"), { tap: at(0, 1) }, { hint: at(0, 1) }]),
    vector("hint-clears-clashes", Q5, [mark([at(0, 0)], "cat"), mark([at(1, 2)], "cat"), mark([at(4, 4)], "cat"), mark([at(0, 1)], "x"), { hint: at(0, 1) }]),
    vector("hinted-is-locked", Q5, [mark([at(0, 1)], "x"), mark([at(0, 0), at(0, 1)], "x"), mark([at(0, 0)], "x")], hinted),
    vector("drag-skips-hinted", Q5, [mark([at(1, 0)], "cat"), { drag: [at(0, 0), at(0, 1), at(0, 2), at(1, 0), at(1, 1)] }, { drag: [at(0, 1), at(0, 2)] }, { drag: [at(1, 0), at(1, 1)] }], hinted),
    vector("bad-shapes", Q5, [
      { move: { k: "mark", cells: [3], to: "cat", extra: 1 } },
      { move: { k: "mark", cells: [3], to: "dog" } },
      { move: { k: "mark", cells: [1.5], to: "x" } },
      { move: { k: "mark", cells: [-1], to: "x" } },
      { move: { k: "mark", cells: ["1"], to: "x" } },
      { move: { k: "mark", cells: [1, 1], to: "x" } },
      { move: { k: "mark", cells: [], to: "x" } },
      { move: { k: "mark", cells: Array.from({ length: 82 }, (_, i) => i), to: "x" } },
      { move: { k: "mark", cells: [1, 2], to: "cat" } },
      { move: { k: "mark", cells: 3, to: "x" } },
      { move: { k: "step", cells: [3], to: "x" } },
      { move: { cells: [3], to: "x" } },
      { move: null },
      { move: [1] },
      { move: "mark" },
      { move: { k: "mark", cells: [25], to: "x" } },
      mark([24], "x"),
    ]),
  ];
}

test("the golden vectors are what the rules say", () => {
  const built = vectors();
  if (write) {
    mkdirSync(new URL(".", FILE), { recursive: true });
    writeFileSync(FILE, `${JSON.stringify(built, null, 1)}\n`);
  }
  expect(JSON.parse(readFileSync(FILE, "utf8"))).toEqual(JSON.parse(JSON.stringify(built)));
});

test("the vectors cover every rule edge", () => {
  const all = vectors();
  const steps = all.flatMap((v) => v.steps);
  expect(steps.some((s) => s.complete)).toBe(true);
  expect(steps.some((s) => !s.ok)).toBe(true);
  expect(steps.some((s) => s.clashes.rows.length && s.clashes.cols.length === 0)).toBe(true);
  expect(steps.some((s) => s.clashes.cols.length)).toBe(true);
  expect(steps.some((s) => s.clashes.patches.length)).toBe(true);
  expect(steps.some((s) => s.clashes.touching.length)).toBe(true);
  expect(all.find((v) => v.name === "full-but-touching")!.steps.at(-1)).toMatchObject({ complete: false, placed: 1 });
  expect(all.find((v) => v.name === "finish-9x9")!.steps.at(-2)!.complete).toBe(true);
  expect(all.find((v) => v.name === "bad-shapes")!.steps.slice(0, -1).every((s) => !s.ok)).toBe(true);
});
