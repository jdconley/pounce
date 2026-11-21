import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { nameAllowed } from "../../../names/filter";

import { ALLOWED } from "./allowed";
import { ANSWERS } from "./answers";

const here = (file: string) => new URL(file, import.meta.url);
const text = (file: string | URL) => readFileSync(file, "utf8");
const listed = (file: string) => text(here(file)).trim().split("\n");
const rot13 = (s: string) => s.replace(/[a-z]/g, (c) => String.fromCharCode(((c.charCodeAt(0) - 97 + 13) % 26) + 97));
const entries = (file: string) =>
  listed(file)
    .map((l) => l.replace(/#.*/, "").trim())
    .filter(Boolean);

const allowed = listed("allowed.txt");
const allowedSet = new Set(allowed);

describe("Sniff's word lists", () => {
  it("allowed is about ten thousand sorted five-letter words", () => {
    expect(allowed.length).toBeGreaterThanOrEqual(9000);
    expect(allowed.length).toBeLessThanOrEqual(12000);
    for (const [i, w] of allowed.entries()) {
      expect(w).toMatch(/^[a-z]{5}$/);
      if (i > 0) expect(w > (allowed[i - 1] as string)).toBe(true);
    }
    expect(ALLOWED).toBe(allowed.join(""));
  });

  it("answers are about two thousand, all allowed, every tier present", () => {
    expect(ANSWERS.length).toBeGreaterThanOrEqual(1800);
    expect(ANSWERS.length).toBeLessThanOrEqual(2600);
    for (const [w] of ANSWERS) expect(allowedSet.has(w)).toBe(true);
    for (const tier of [1, 2, 3]) expect(ANSWERS.filter(([, t]) => t === tier).length).toBeGreaterThan(300);
    expect(listed("answers.txt")).toEqual(ANSWERS.map(([w, t]) => `${w} ${t}`));
    expect(new Set(ANSWERS.map(([w]) => w)).size).toBe(ANSWERS.length);
  });

  it("no answer is a plural made by adding s", () => {
    for (const [w] of ANSWERS) {
      if (w.endsWith("s") && !w.endsWith("ss")) expect(allowedSet.has(w.slice(0, 4)), w).toBe(false);
    }
  });

  it("no blocked word anywhere, and the name filter passes every word", () => {
    const blocked = entries("blocked.rot13.txt").map(rot13);
    expect(blocked.length).toBeGreaterThan(50);
    for (const w of blocked) expect(allowedSet.has(w), w).toBe(false);
    for (const w of allowed) expect(nameAllowed(w), w).toBe(true);
  });

  it("the hand pass holds: no cut word is an answer", () => {
    const answers = new Set(ANSWERS.map(([w]) => w));
    for (const w of entries("answers-cut.txt")) expect(answers.has(w), w).toBe(false);
    const rot = entries("answers-cut.rot13.txt").map(rot13);
    expect(rot.length).toBeGreaterThan(0);
    for (const w of rot) {
      expect(answers.has(w), w).toBe(false);
      expect(allowedSet.has(w), w).toBe(true);
    }
  });

  it("the app's copy is the same list", () => {
    const ios = here("../../../../../play-ios/Pounce/Daily/Sniff/sniff-allowed.txt");
    expect(text(ios)).toBe(text(here("allowed.txt")));
  });
});
