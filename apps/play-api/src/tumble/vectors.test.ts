import { readdirSync, readFileSync } from "node:fs";

import { describe, expect, test } from "vitest";

import { newBox } from "./box";
import { toyAt } from "./queue";
import { boxFromExpect, buildVectors, formatVector, runStep, type VectorFile } from "./vectors";

const DIR = new URL("../../fixtures/tumble/", import.meta.url);
const REGENERATE = "pnpm --filter @pounce/play-api vectors:tumble";
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

  test("cover every kind of step, every hit and every refusal", () => {
    const steps = built.flatMap((v) => v.steps);
    const kinds = new Set(steps.map((s) => s.do[0]));
    expect([...kinds].sort()).toEqual(["hit", "junk", "setDown", "turn", "use"]);
    const hits = new Set(steps.flatMap((s) => (s.do[0] === "hit" ? [s.do[1].k] : [])));
    expect([...hits].sort()).toEqual(["bath", "catnip", "hairball", "nap", "scoop", "settle", "swap", "swipe"]);
    const errors = new Set(steps.flatMap((s) => ("error" in s.expect ? [s.expect.error] : [])));
    expect([...errors].sort()).toEqual(["bad_landed", "box_out", "no_trick", "not_next", "not_resting"].filter((e) => errors.has(e)).sort());
    for (const e of ["bad_landed", "box_out", "no_trick", "not_next", "not_resting"]) expect(errors.has(e), e).toBe(true);
    expect(steps.some((s) => "out" in s.expect && s.expect.out)).toBe(true);
    expect(steps.some((s) => s.do[0] === "setDown" && s.do[5].length > 0 && !("error" in s.expect))).toBe(true);
    expect(steps.some((s) => "blocked" in s.expect && s.expect.blocked.length > 0)).toBe(true);
  });
});

describe("replaying each file from disk", () => {
  const files = readdirSync(DIR)
    .filter((f) => f.endsWith(".json"))
    .map((f) => JSON.parse(readFileSync(new URL(f, DIR), "utf8")) as VectorFile);

  test.each(files)("$name", (v) => {
    v.queue.forEach((toy, n) => expect(toy).toBe(toyAt(v.roundSeed, n)));
    let box = v.start ? boxFromExpect(v.start) : newBox(v.trickSeed);
    for (const step of v.steps) {
      const r = runStep(box, v.roundSeed, step.do);
      expect(r.expect).toEqual(step.expect);
      box = r.box;
    }
  });
});
