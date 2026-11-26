import { describe, expect, test } from "vitest";

import { ALL_CARDS, BIRD, cardFor, isBird, isCardId, isSuit, rankOf, suitIn, suitOf } from "./cards";
import { counterOf, dealFor, deckFor, isRuleSetId, powerOf, RULE_SET_IDS, RULE_SETS } from "./rules";

const SIZES = {
  official: { 4: [41, 9, 5], 5: [53, 10, 3], 6: [53, 8, 5] },
  tucker: { 4: [45, 10, 5], 5: [57, 10, 7], 6: [57, 9, 3] },
  friesen: { 4: [45, 10, 5], 5: [57, 10, 7], 6: [57, 9, 3] },
} as const;

describe("cards", () => {
  test("ids name a suit and a rank, and 56 is the Bird", () => {
    expect(ALL_CARDS).toHaveLength(57);
    expect([suitOf(0), rankOf(0)]).toEqual(["fish", 1]);
    expect([suitOf(13), rankOf(13)]).toEqual(["fish", 14]);
    expect([suitOf(55), rankOf(55)]).toEqual(["bell", 14]);
    expect(cardFor("feather", 10)).toBe(37);
    expect(isBird(BIRD)).toBe(true);
    expect(suitIn(BIRD, "mouse")).toBe("mouse");
    expect(suitIn(cardFor("bell", 5), "mouse")).toBe("bell");
    expect([isCardId(56), isCardId(57), isCardId(-1), isCardId(1.5), isCardId("3")]).toEqual([true, false, false, false, false]);
    expect([isSuit("fish"), isSuit("bird"), isSuit(0)]).toEqual([true, false, false]);
  });
});

describe.each(RULE_SET_IDS)("the %s rule set", (id) => {
  const rules = RULE_SETS[id];
  test.each([4, 5, 6] as const)("deals every card at %i players", (seats) => {
    const [deck, hand, nest] = SIZES[id][seats];
    expect(deckFor(rules, seats)).toHaveLength(deck);
    expect(dealFor(rules, seats)).toMatchObject({ hand, nest });
    expect(hand * seats + nest).toBe(deck);
    expect(deckFor(rules, seats)).toContain(BIRD);
  });

  test.each([4, 5, 6] as const)("its counters add up to the hand's worth at %i players", (seats) => {
    const total = deckFor(rules, seats).reduce((sum, c) => sum + counterOf(rules, c), 0);
    expect(total).toBe(id === "official" ? 120 : 180);
    expect(rules.total).toBe(total);
  });

  test("bids, target and the Bird", () => {
    expect([rules.minBid, rules.maxBid, rules.bidStep]).toEqual([70, id === "official" ? 120 : 180, 5]);
    expect(rules.target).toBe(id === "official" ? 300 : 500);
    expect(rules.birdWild).toBe(id !== "friesen");
    expect(counterOf(rules, BIRD)).toBe(20);
    expect([5, 10, 14, 13].map((r) => counterOf(rules, cardFor("fish", r)))).toEqual([5, 10, 10, 0]);
  });

  test("2s, 3s and 4s are in only with 5 or 6 players, and 1s never in official", () => {
    const has = (seats: number, rank: number) => deckFor(rules, seats).some((c) => !isBird(c) && rankOf(c) === rank);
    expect([has(4, 2), has(4, 4), has(5, 2), has(6, 4)]).toEqual([false, false, true, true]);
    expect([4, 5, 6].map((seats) => has(seats, 1))).toEqual(id === "official" ? [false, false, false] : [true, true, true]);
  });

  test("ranks run low to high, with 1 on top where it is in", () => {
    const power = (rank: number) => powerOf(rules, cardFor("bell", rank));
    expect(power(14)).toBeGreaterThan(power(13));
    expect(power(5)).toBeGreaterThan(power(4));
    if (id !== "official") {
      expect(power(1)).toBeGreaterThan(power(14));
      expect(counterOf(rules, cardFor("bell", 1))).toBe(15);
    }
  });
});

test("rule set ids, and only 4 to 6 players", () => {
  expect([isRuleSetId("tucker"), isRuleSetId("house"), isRuleSetId(1)]).toEqual([true, false, false]);
  expect(() => dealFor(RULE_SETS.official, 3)).toThrow(RangeError);
  expect(() => deckFor(RULE_SETS.tucker, 7)).toThrow(RangeError);
});
