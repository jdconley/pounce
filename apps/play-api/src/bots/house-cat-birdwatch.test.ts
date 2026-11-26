import { describe, expect, test } from "vitest";

import { bell, feather, fish, game, inPlay, mouse } from "../../tests/birdwatch-helpers";
import { BIRD } from "../birdwatch/cards";
import { RULE_SETS } from "../birdwatch/rules";
import { viewFor } from "../birdwatch/view";
import { createRng } from "../rules/rng";

import { bestSuit, chooseAction, estimate, putBack } from "./house-cat-birdwatch";

import type { BirdState } from "../birdwatch/engine";

const rng = () => createRng([5, 6, 7, 8]);
const act = (s: BirdState, seat: number) => chooseAction(viewFor(s, [seat]), seat, rng());
const official = RULE_SETS.official;

describe("bidding", () => {
  const strong = [BIRD, fish(14), fish(13), fish(12), fish(11), fish(10), mouse(14), bell(14), feather(14)];
  const weak = [fish(5), fish(6), mouse(7), mouse(8), bell(6), bell(9), feather(7), feather(8), feather(11)];

  test("bids on a strong hand, never past its estimate, and passes a weak one", () => {
    expect(estimate(strong, official, 4)).toBeGreaterThan(estimate(weak, official, 4));
    const s = game(4, "official", { dealer: 3, turn: 0, hands: [strong, weak, weak, weak] });
    expect(act(s, 0)).toEqual({ type: "bid", amount: 70 });
    expect(act({ ...s, turn: 1 }, 1)).toEqual({ type: "pass" });
    const high = { ...s, high: { seat: 1, amount: estimate(strong, official, 4) + 20 } };
    expect(act(high, 0)).toEqual({ type: "pass" });
  });

  test("never bids against its own side", () => {
    const s = game(4, "official", { dealer: 3, turn: 2, hands: [weak, weak, strong, weak], high: { seat: 0, amount: 70 }, bids: [70, null, null, null] });
    expect(act(s, 2)).toEqual({ type: "pass" });
  });
});

describe("the nest and trump", () => {
  test("puts back short off-suits first, keeps trump and the Bird, and counters only when it must", () => {
    const hand = [BIRD, fish(6), fish(7), fish(8), fish(9), fish(11), mouse(6), mouse(14), bell(5), bell(7), bell(8), feather(6), feather(9), feather(12)];
    const back = putBack(hand, 5, official);
    expect(back).not.toContain(BIRD);
    expect(back.some((c) => [fish(6), fish(7), fish(8), fish(9), fish(11)].includes(c))).toBe(false);
    expect(back).not.toContain(mouse(14));
    expect(back).not.toContain(bell(5));
    expect(back).toContain(mouse(6));
    // Nothing but counters and trump left to put back: a counter goes.
    expect(putBack([fish(10), fish(14), mouse(5), mouse(10)], 1, official)).toEqual([mouse(5)]);
  });

  test("names its longest suit, ties going to the higher cards", () => {
    expect(bestSuit([bell(5), bell(6), mouse(13), mouse(14), fish(9)], official)).toBe("mouse");
    expect(bestSuit([bell(5), bell(6), bell(7), mouse(13), mouse(14)], official)).toBe("bell");
  });
});

describe("the partner call", () => {
  test("calls the highest trump it doesn't hold, else a top card, never one it put back", () => {
    const hands = [[fish(14), fish(13), mouse(5)], [BIRD], [fish(12)], [bell(14)], [mouse(6)]];
    const s = game(5, "official", { phase: "partner", turn: 0, high: { seat: 0, amount: 70 }, trump: "fish", hands, putBack: [] });
    expect(act(s, 0)).toEqual({ type: "partner", card: BIRD });
    expect(act({ ...s, putBack: [BIRD] }, 0)).toEqual({ type: "partner", card: fish(12) });
  });
});

describe("play", () => {
  const hands4 = (h1: number[]) => [[mouse(10), feather(6)], h1, [bell(9), bell(11)], [mouse(6), mouse(7)]];

  test("takes a trick with counters in it as cheaply as it can", () => {
    let s = inPlay({ hands: hands4([mouse(14), mouse(12), mouse(5)]), trump: "fish" });
    s = { ...s, trick: [{ seat: 0, card: mouse(10) }], turn: 1, hands: [[feather(6)], ...s.hands.slice(1)] };
    expect(act(s, 1)).toEqual({ type: "play", card: mouse(12) });
  });

  test("throws its lowest card when it can't win", () => {
    let s = inPlay({ hands: hands4([fish(5), bell(6), bell(10)]), trump: "bell" });
    s = { ...s, trick: [{ seat: 0, card: BIRD }], turn: 1 };
    expect(act(s, 1)).toEqual({ type: "play", card: bell(6) });
  });

  test("gives counters to a partner who is winning", () => {
    const s = inPlay({ hands: hands4([fish(5), bell(6)]), trump: "fish", bidder: 2 });
    const t = { ...s, trick: [{ seat: 3, card: bell(7) }, { seat: 0, card: BIRD }], turn: 1, leader: 3 };
    // Seat 1's partner is seat 3: the Bird is seat 0's, so no feeding there.
    expect(act(t, 1)).toEqual({ type: "play", card: bell(6) });
    const u = { ...s, trick: [{ seat: 3, card: BIRD }, { seat: 0, card: bell(7) }], turn: 1, leader: 3 };
    expect(act(u, 1)).toEqual({ type: "play", card: fish(5) });
  });

  test("leads the top trump on the bidding side", () => {
    const s = inPlay({ hands: [[BIRD, mouse(6)], [bell(5)], [bell(6)], [bell(7)]], trump: "fish" });
    expect(act(s, 0)).toEqual({ type: "play", card: BIRD });
    const t = inPlay({ hands: [[BIRD, mouse(6)], [bell(5)], [bell(6)], [bell(7)]], trump: "fish", bidder: 1, leader: 0 });
    expect(act(t, 0)).toEqual({ type: "play", card: mouse(6) });
  });

  test("between hands it deals the next", () => {
    expect(act(game(4, "official", { phase: "between" }), 0)).toEqual({ type: "nextHand" });
  });
});
