import { describe, expect, it } from "vitest";

import { GROUPS, WORDS } from "./words";

describe("word list", () => {
  it("has at least 250 easy and 250 tricky words", () => {
    expect(WORDS.filter((w) => w.level === "easy").length).toBeGreaterThanOrEqual(250);
    expect(WORDS.filter((w) => w.level === "tricky").length).toBeGreaterThanOrEqual(250);
  });

  it("uses all eight groups at both levels", () => {
    expect(GROUPS).toHaveLength(8);
    for (const group of GROUPS) {
      for (const level of ["easy", "tricky"] as const) {
        expect(WORDS.filter((w) => w.group === group && w.level === level).length).toBeGreaterThan(20);
      }
    }
  });

  it("has no duplicate words", () => {
    const words = WORDS.map((w) => w.word);
    expect(new Set(words).size).toBe(words.length);
  });

  it("is plain lowercase", () => {
    for (const { word } of WORDS) expect(word).toMatch(/^[a-z][a-z ]{1,20}$/);
  });

  it("holds nothing from the deny list", () => {
    const deny = /\b(gun|blood|kill|dead|die|knife|bomb|beer|wine|god|church|butt|poop|naked)\b/;
    expect(WORDS.filter((w) => deny.test(w.word)).map((w) => w.word)).toEqual([]);
  });
});
