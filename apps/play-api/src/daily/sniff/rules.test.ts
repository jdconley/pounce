import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { isAllowed } from "./allowed-check";
import { keyboardMarks } from "./keyboard";
import { markGuess } from "./marks";

import type { Guess, Mark } from "./types";

type Vector = { name: string; answer: string; guess: string; marks: Mark[] };
const vectors = (
  JSON.parse(readFileSync(new URL("../../../fixtures/daily/sniff/marks.json", import.meta.url), "utf8")) as {
    vectors: Vector[];
  }
).vectors;
const allowed = readFileSync(new URL("words/allowed.txt", import.meta.url), "utf8").trim().split("\n");

describe("markGuess", () => {
  it.each(vectors)("$name", (v) => {
    expect(markGuess(v.answer, v.guess)).toEqual(v.marks);
  });

  it("covers the repeated-letter cases", () => {
    expect(vectors.length).toBeGreaterThanOrEqual(12);
  });
});

describe("isAllowed", () => {
  it("every allowed word passes", () => {
    for (const w of allowed) expect(isAllowed(w), w).toBe(true);
  });

  it("words between the listed ones fail", () => {
    const set = new Set(allowed);
    for (const w of allowed.filter((_, i) => i % 50 === 0)) {
      for (const tail of ["a", "q", "z"]) {
        const near = w.slice(0, 4) + tail;
        expect(isAllowed(near), near).toBe(set.has(near));
      }
    }
    expect(isAllowed("zzzzz")).toBe(false);
    expect(isAllowed("aaaaa")).toBe(false);
  });

  it("uppercase, wrong length and non-letters fail", () => {
    expect(isAllowed("PLANT")).toBe(false);
    expect(isAllowed("plan")).toBe(false);
    expect(isAllowed("plants")).toBe(false);
    expect(isAllowed("pl@nt")).toBe(false);
    expect(isAllowed("")).toBe(false);
  });

  it("takes another list", () => {
    expect(isAllowed("bbbbb", "aaaaabbbbbccccc")).toBe(true);
    expect(isAllowed("plant", "aaaaabbbbbccccc")).toBe(false);
  });
});

describe("keyboardMarks", () => {
  const g = (word: string, marks: Mark[]): Guess => ({ word, marks });

  it("keeps the best mark each letter has had", () => {
    const keys = keyboardMarks([
      g("crate", ["none", "none", "near", "none", "near"]),
      g("plant", ["none", "none", "spot", "none", "none"]),
      g("slate", ["none", "none", "none", "none", "spot"]),
    ]);
    expect(keys.a).toBe("spot");
    expect(keys.e).toBe("spot");
    expect(keys.c).toBe("none");
    expect(keys.t).toBe("none");
    expect(keys.z).toBeUndefined();
  });

  it("a plain copy never hides a near or a spot of the same letter", () => {
    expect(keyboardMarks([g("tatty", ["near", "near", "none", "none", "none"])]).t).toBe("near");
    expect(keyboardMarks([g("nanny", ["none", "near", "none", "spot", "none"])]).n).toBe("spot");
  });

  it("is empty with no guesses", () => {
    expect(keyboardMarks([])).toEqual({});
  });
});

describe("client files", () => {
  it("never import the answers or the module", () => {
    for (const file of ["allowed-check.ts", "keyboard.ts", "types.ts"]) {
      const source = readFileSync(new URL(file, import.meta.url), "utf8");
      const imports = [...source.matchAll(/\bfrom\s+["']([^"']+)["']|\bimport\(\s*["']([^"']+)["']/g)].map((m) => m[1] ?? m[2]);
      for (const spec of imports) expect(spec, file).toMatch(/^\.\/(types|words\/allowed)$/);
    }
  });
});
