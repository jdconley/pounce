import { describe, expect, test } from "vitest";

import { errorOf, fish, game, mouse, ok } from "../../tests/birdwatch-helpers";

import { BIRD } from "./cards";
import { actor, applyAction, minBid, newGame, teamsFor, type BirdState } from "./engine";
import { dealFor, RULE_SETS } from "./rules";

const left = (s: BirdState) => (s.dealer + 1) % s.seats;

describe("a new game", () => {
  test("deals every hand and the nest, and bidding starts left of the dealer", () => {
    const s = newGame(5, [1, 2, 3, 4], { rules: "tucker" });
    const { hand, nest } = dealFor(RULE_SETS.tucker, 5);
    expect(s.hands.map((h) => h.length)).toEqual([hand, hand, hand, hand, hand]);
    expect(s.nest).toHaveLength(nest);
    expect(new Set([...s.hands.flat(), ...s.nest]).size).toBe(57);
    expect(s.phase).toBe("bidding");
    expect(actor(s)).toBe(left(s));
    expect(s.teams).toEqual([[0], [1], [2], [3], [4]]);
  });

  test("is the same for the same seed, and the dealer comes from it", () => {
    expect(newGame(4, [9, 9, 9, 9])).toEqual(newGame(4, [9, 9, 9, 9]));
    const dealers = new Set([1, 2, 3, 4, 5, 6, 7, 8, 9].map((n) => newGame(6, [1, (n * 2654435761) >>> 0, 1, 1]).dealer));
    expect(dealers.size).toBeGreaterThan(1);
  });

  test("teams sit across the table", () => {
    expect(teamsFor(4)).toEqual([[0, 2], [1, 3]]);
    expect(teamsFor(6)).toEqual([[0, 3], [1, 4], [2, 5]]);
  });

  test("only 4 to 6 players, and only a known rule set", () => {
    expect(() => newGame(3, [1, 2, 3, 4])).toThrow(RangeError);
    expect(() => newGame(4, [1, 2, 3, 4], { rules: "other" as "official" })).toThrow(RangeError);
  });
});

describe("bidding", () => {
  const s0 = game(4, "official", { dealer: 3, turn: 0 });

  test("a bid is a multiple of 5 from 70, at least 5 over the high bid, at most the maximum", () => {
    expect(minBid(s0)).toBe(70);
    expect(errorOf(applyAction(s0, 0, { type: "bid", amount: 65 }))).toBe("bid_too_low");
    expect(errorOf(applyAction(s0, 0, { type: "bid", amount: 72 }))).toBe("bad_bid");
    expect(errorOf(applyAction(s0, 0, { type: "bid", amount: 125 }))).toBe("bid_too_high");
    const { state, events } = ok(applyAction(s0, 0, { type: "bid", amount: 80 }));
    expect(events).toEqual([{ kind: "bid", seat: 0, amount: 80 }, { kind: "turn", seat: 1 }]);
    expect(minBid(state)).toBe(85);
    expect(errorOf(applyAction(state, 1, { type: "bid", amount: 80 }))).toBe("bid_too_low");
    expect(state.high).toEqual({ seat: 0, amount: 80 });
    expect(state.bids).toEqual([80, null, null, null]);
  });

  test("only the seat on the move bids, and only while bidding", () => {
    expect(errorOf(applyAction(s0, 1, { type: "bid", amount: 70 }))).toBe("not_your_turn");
    expect(errorOf(applyAction(s0, 0, { type: "play", card: fish(5) }))).toBe("wrong_phase");
    expect(errorOf(applyAction(s0, 9, { type: "pass" }))).toBe("bad_seat");
    expect(errorOf(applyAction(s0, 0, { type: "nextHand" }))).toBe("wrong_phase");
    expect(errorOf(applyAction(s0, 0, { type: "other" } as never))).toBe("bad_action");
  });

  test("a seat that passed is skipped, and the last one in wins the bid and takes the nest", () => {
    let s = ok(applyAction(s0, 0, { type: "bid", amount: 70 })).state;
    s = ok(applyAction(s, 1, { type: "pass" })).state;
    s = ok(applyAction(s, 2, { type: "bid", amount: 75 })).state;
    s = ok(applyAction(s, 3, { type: "pass" })).state;
    expect(actor(s)).toBe(0);
    s = ok(applyAction(s, 0, { type: "bid", amount: 90 })).state;
    expect(actor(s)).toBe(2);
    const nest = [...s.nest];
    const handBefore = [...(s.hands[0] as number[])];
    const { state, events } = ok(applyAction(s, 2, { type: "pass" }));
    expect(events).toEqual([
      { kind: "passed", seat: 2 },
      { kind: "bidWon", seat: 0, amount: 90 },
      { kind: "nest", seat: 0, cards: nest },
      { kind: "turn", seat: 0 },
    ]);
    expect(state.phase).toBe("nest");
    expect(state.nest).toEqual([]);
    expect(state.hands[0]).toEqual([...handBefore, ...nest].sort((a, b) => a - b));
    expect(state.fromNest).toEqual(nest);
  });

  test("when every seat passes, the dealer takes the hand at the minimum", () => {
    let s = s0;
    for (const seat of [0, 1, 2]) s = ok(applyAction(s, seat, { type: "pass" })).state;
    expect(s.phase).toBe("nest");
    expect(s.high).toEqual({ seat: 3, amount: 70 });
    expect(actor(s)).toBe(3);
  });

  test("a bid of the maximum ends bidding at once", () => {
    const { state, events } = ok(applyAction(game(6, "tucker", { dealer: 5, turn: 0 }), 0, { type: "bid", amount: 180 }));
    expect(state.phase).toBe("nest");
    expect(events.map((e) => e.kind)).toEqual(["bid", "bidWon", "nest", "turn"]);
  });
});

describe("the nest, trump and the partner", () => {
  /** Seat 0 has won the bid at 4 players and holds the nest. */
  function withNest(seats = 4, rules: "official" | "tucker" = "official"): BirdState {
    let s = game(seats, rules, { dealer: seats - 1, turn: 0 });
    s = ok(applyAction(s, 0, { type: "bid", amount: 70 })).state;
    for (let seat = 1; seat < seats; seat++) s = ok(applyAction(s, seat, { type: "pass" })).state;
    return s;
  }

  test("the bid winner puts back exactly as many cards as the nest held, from their hand", () => {
    const s = withNest();
    const hand = s.hands[0] as number[];
    const notMine = s.hands[1]?.[0] as number;
    expect(errorOf(applyAction(s, 0, { type: "nest", discard: hand.slice(0, 4) }))).toBe("wrong_count");
    expect(errorOf(applyAction(s, 0, { type: "nest", discard: [...hand.slice(0, 4), notMine] }))).toBe("not_your_card");
    expect(errorOf(applyAction(s, 0, { type: "nest", discard: [hand[0], ...hand.slice(0, 4)] as number[] }))).toBe("duplicate_card");
    expect(errorOf(applyAction(s, 0, { type: "trump", suit: "fish" }))).toBe("wrong_phase");
    const discard = hand.slice(2, 7);
    const { state, events } = ok(applyAction(s, 0, { type: "nest", discard }));
    expect(events).toEqual([{ kind: "putBack", seat: 0, count: 5, cards: discard }, { kind: "turn", seat: 0 }]);
    expect(state.hands[0]).toHaveLength(9);
    expect(state.putBack).toEqual(discard);
    expect(state.fromNest).toEqual([]);
    expect(state.phase).toBe("trump");
  });

  test("with 4 players, trump starts play and the bid winner leads", () => {
    let s = withNest();
    s = ok(applyAction(s, 0, { type: "nest", discard: (s.hands[0] as number[]).slice(0, 5) })).state;
    const { state, events } = ok(applyAction(s, 0, { type: "trump", suit: "bell" }));
    expect(events).toEqual([{ kind: "trump", seat: 0, suit: "bell" }, { kind: "turn", seat: 0 }]);
    expect([state.phase, state.trump, state.leader]).toEqual(["play", "bell", 0]);
    expect(errorOf(applyAction(state, 0, { type: "partner", card: 1 }))).toBe("wrong_phase");
  });

  test("with 5 players the bid winner calls a card they don't hold, and nobody is told who has it", () => {
    let s = withNest(5, "tucker");
    s = ok(applyAction(s, 0, { type: "nest", discard: (s.hands[0] as number[]).slice(0, 7) })).state;
    s = ok(applyAction(s, 0, { type: "trump", suit: "mouse" })).state;
    expect(s.phase).toBe("partner");
    const mine = (s.hands[0] as number[])[0] as number;
    expect(errorOf(applyAction(s, 0, { type: "partner", card: mine }))).toBe("own_card");
    const theirs = (s.hands[3] as number[])[0] as number;
    const { state, events } = ok(applyAction(s, 0, { type: "partner", card: theirs }));
    expect(events).toEqual([{ kind: "called", seat: 0, card: theirs }, { kind: "turn", seat: 0 }]);
    expect([state.called, state.holder, state.partner, state.phase]).toEqual([theirs, 3, null, "play"]);
  });

  test("calling a card that was put back is playing alone", () => {
    let s = withNest(5, "tucker");
    const back = (s.hands[0] as number[]).slice(0, 7);
    s = ok(applyAction(s, 0, { type: "nest", discard: back })).state;
    s = ok(applyAction(s, 0, { type: "trump", suit: "mouse" })).state;
    expect(ok(applyAction(s, 0, { type: "partner", card: back[0] as number })).state.holder).toBeNull();
  });

  test("a called card must be in the deck", () => {
    let s = withNest(5, "official");
    s = ok(applyAction(s, 0, { type: "nest", discard: (s.hands[0] as number[]).slice(0, 3) })).state;
    s = ok(applyAction(s, 0, { type: "trump", suit: "mouse" })).state;
    // Official rules have no 1s.
    expect(errorOf(applyAction(s, 0, { type: "partner", card: mouse(1) }))).toBe("bad_card");
    expect(s.hands.flat().includes(BIRD) || s.putBack.includes(BIRD)).toBe(true);
  });
});
