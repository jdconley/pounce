import { describe, expect, test } from "vitest";

import { LINK_TOKEN, parseAnswer, parsePounce, POUNCE_ID } from "./parse";

const PAIR = "pr_AAAAAAAAAAAAAAAAAAAAAA";

describe("parsePounce (§13.4)", () => {
  test("accepts a pair and each target, or no pair for a link", () => {
    expect(parsePounce({ to: PAIR, target: { table: "BCDFG" } })).toEqual({ to: PAIR, target: { table: "BCDFG" } });
    expect(parsePounce({ to: PAIR, target: "new" })).toEqual({ to: PAIR, target: "new" });
    expect(parsePounce({ target: "pick" })).toEqual({ to: null, target: "pick" });
  });

  test("rejects anything else", () => {
    for (const bad of [
      null,
      [],
      {},
      { target: "maybe" },
      { target: { table: "bad!" } },
      { target: { table: "BCDFG", extra: 1 } },
      { target: { code: "BCDFG" } },
      { target: null },
      { to: "p_someone", target: "new" },
      { to: PAIR, target: "new", extra: true },
    ]) {
      expect(parsePounce(bad), JSON.stringify(bad)).toBeNull();
    }
  });
});

describe("parseAnswer", () => {
  test("accepts each answer, a choice and a link token", () => {
    expect(parseAnswer({ answer: "later" })).toEqual({ answer: "later", choice: null, link: null });
    expect(parseAnswer({ answer: "play", choice: "new" })).toEqual({ answer: "play", choice: "new", link: null });
    expect(parseAnswer({ answer: "play", choice: "BCDFG", link: "A".repeat(22) })).toEqual({ answer: "play", choice: "BCDFG", link: "A".repeat(22) });
  });

  test("rejects a bad answer, a choice with anything but play, bad codes and tokens", () => {
    for (const bad of [null, {}, { answer: "yes" }, { answer: "no", choice: "new" }, { answer: "play", choice: "x" }, { answer: "play", link: "short" }, { answer: "play", x: 1 }]) {
      expect(parseAnswer(bad), JSON.stringify(bad)).toBeNull();
    }
  });

  test("ids and tokens", () => {
    expect(POUNCE_ID.test(`pc_${"A".repeat(22)}`)).toBe(true);
    expect(POUNCE_ID.test("pr_x")).toBe(false);
    expect(LINK_TOKEN.test("A".repeat(22))).toBe(true);
    expect(LINK_TOKEN.test("A".repeat(21))).toBe(false);
  });
});
