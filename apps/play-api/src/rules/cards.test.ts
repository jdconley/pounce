import { describe, expect, test } from "vitest";

import { seedOf } from "../../tests/seeds";

import { ALL_CARD_IDS, COATS, card, cardPoints } from "./cards";
import { createRng, shuffle } from "./rng";

describe("cards", () => {
  test("deck has 108 cards: 96 numbers, 8 yarn, 4 cucumber", () => {
    const cards = ALL_CARD_IDS.map(card);
    expect(ALL_CARD_IDS).toHaveLength(108);
    expect(cards.filter((c) => c.kind === "number")).toHaveLength(96);
    expect(cards.filter((c) => c.kind === "yarn")).toHaveLength(8);
    expect(cards.filter((c) => c.kind === "cucumber")).toHaveLength(4);
  });

  test("each number 1-12 appears exactly twice per coat", () => {
    for (const coat of COATS)
      for (let v = 1; v <= 12; v++)
        expect(
          ALL_CARD_IDS.map(card).filter(
            (c) => c.kind === "number" && c.coat === coat && c.value === v,
          ),
        ).toHaveLength(2);
  });

  test("coats are in order and ids map to coat/value", () => {
    expect(COATS).toEqual(["tabby", "tuxedo", "calico", "gray"]);
    expect(card(0)).toEqual({ id: 0, kind: "number", value: 1, coat: "tabby" });
    expect(card(11)).toEqual({ id: 11, kind: "number", value: 12, coat: "tabby" });
    expect(card(12)).toEqual({ id: 12, kind: "number", value: 1, coat: "tabby" });
    expect(card(24)).toEqual({ id: 24, kind: "number", value: 1, coat: "tuxedo" });
    expect(card(95)).toEqual({ id: 95, kind: "number", value: 12, coat: "gray" });
    expect(card(96)).toEqual({ id: 96, kind: "yarn" });
    expect(card(103)).toEqual({ id: 103, kind: "yarn" });
    expect(card(104)).toEqual({ id: 104, kind: "cucumber" });
    expect(card(107)).toEqual({ id: 107, kind: "cucumber" });
  });

  test("card rejects ids outside 0-107", () => {
    expect(() => card(-1)).toThrow();
    expect(() => card(108)).toThrow();
    expect(() => card(1.5)).toThrow();
  });

  test("points", () => {
    expect(cardPoints(0)).toBe(5); // tabby 1
    expect(cardPoints(8)).toBe(5); // tabby 9
    expect(cardPoints(9)).toBe(10); // tabby 10
    expect(cardPoints(11)).toBe(10); // tabby 12
    expect(cardPoints(96)).toBe(25); // yarn
    expect(cardPoints(104)).toBe(15); // cucumber
  });
});

describe("shuffle", () => {
  test("shuffle is deterministic per seed and a permutation", () => {
    const a = shuffle(ALL_CARD_IDS, createRng(seedOf(42)));
    const b = shuffle(ALL_CARD_IDS, createRng(seedOf(42)));
    expect(a).toEqual(b);
    expect([...a].sort((x, y) => x - y)).toEqual([...ALL_CARD_IDS]);
    expect(shuffle(ALL_CARD_IDS, createRng(seedOf(43)))).not.toEqual(a);
  });
});
