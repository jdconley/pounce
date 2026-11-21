import { readdirSync, readFileSync } from "node:fs";

import { describe, expect, test } from "vitest";

import { boxFort } from "./module";
import { buildVectors, formatVector, rugOf, type VectorFile } from "./vectors";

import type { BoxFortPuzzle } from "./maker";

const DIR = new URL("../../../fixtures/daily/box-fort/", import.meta.url);
const REGENERATE = "pnpm --filter @pounce/play-api vectors:box-fort";
const built = buildVectors();

describe("the golden vectors on disk", () => {
  test("are exactly the files the rules write", () => {
    const onDisk = readdirSync(DIR).filter((f) => f.endsWith(".json")).sort();
    expect(onDisk, `stale vectors: run ${REGENERATE}`).toEqual(built.map((v) => `${v.name}.json`).sort());
  });

  test.each(built)("$name.json matches the rules", (v) => {
    const text = readFileSync(new URL(`${v.name}.json`, DIR), "utf8");
    expect(text, `stale vectors: run ${REGENERATE}`).toBe(`${formatVector(v)}\n`);
  });
});

describe("replaying each file through the module", () => {
  const files = readdirSync(DIR)
    .filter((f) => f.endsWith(".json"))
    .map((f) => JSON.parse(readFileSync(new URL(f, DIR), "utf8")) as VectorFile);

  test.each(files)("$name", (v) => {
    // The day as the server held it: the first set, then each set the vector saw dealt.
    const p: BoxFortPuzzle = {
      rug: v.start.rug,
      sets: [v.start.pieces, ...v.steps.flatMap((s) => (s.ok && s.reveal ? [s.reveal.pieces] : []))],
    };
    // A vector that never reached a later set still knows how many there were.
    while (p.sets.length < v.start.sets) p.sets.push(v.start.pieces);
    let s = boxFort.init(p);
    for (const step of v.steps) {
      const out = boxFort.apply(p, s, step.move, 0);
      if (!step.ok) {
        expect(out).toEqual({ ok: false, reason: step.reason });
      } else {
        if (!out.ok) throw new Error(`${v.name}: step refused`);
        expect(out.reveal ?? null).toEqual(step.reveal);
        expect(out.end ?? null).toBe(step.end);
        expect(out.state.points - s.points).toBe(step.gained);
        s = out.state;
      }
      expect(boxFort.publicState(p, s)).toEqual(step.state);
    }
  });

  test("covers every rule edge", () => {
    const steps = files.flatMap((f) => f.steps);
    const ok = steps.filter((s) => s.ok);
    expect(ok.some((s) => s.cleared.rows.length >= 3)).toBe(true);
    expect(ok.some((s) => s.cleared.rows.length > 0 && s.cleared.cols.length > 0)).toBe(true);
    expect(ok.some((s) => s.state.combo >= 3)).toBe(true);
    expect(ok.some((s) => s.state.over === "stuck" && s.reveal === null)).toBe(true);
    expect(ok.some((s) => s.state.over === "stuck" && s.reveal !== null)).toBe(true);
    expect(ok.some((s) => s.state.over === "full")).toBe(true);
    expect(steps.some((s) => !s.ok && s.reason === "illegal")).toBe(true);
    expect(steps.some((s) => !s.ok && s.reason === "over")).toBe(true);
  });
});

test("rugOf reads tints, starting boxes and gaps", () => {
  expect(rugOf(["3#."]).slice(0, 3)).toEqual([3, 7, 0]);
});

test("formatVector keeps number arrays on one line", () => {
  expect(formatVector({ a: [1, 2], b: [[0, 1]], c: [{ d: null }], e: "x" })).toBe(
    '{\n  "a": [1,2],\n  "b": [[0,1]],\n  "c": [\n    {\n      "d": null\n    }\n  ],\n  "e": "x"\n}',
  );
});
