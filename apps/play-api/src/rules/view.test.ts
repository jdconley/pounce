import { describe, expect, test } from "vitest";

import { eventFor, viewFor } from "./view";

import type { CatTowerState, GameEvent } from "./engine";

function makeState(over: Partial<CatTowerState> = {}): CatTowerState {
  return {
    seats: 3,
    phase: [0, 1, 2],
    scores: [10, 20, 30],
    round: 4,
    dealer: 2,
    deck: [0, 1, 2, 3],
    discard: [50, 60],
    hands: [
      [10, 11, 12],
      [20, 21],
      [30, 31, 32, 33],
    ],
    laid: [null, [{ kind: "set", cards: [5, 6, 7], value: 3 }], null],
    turn: 1,
    step: "play",
    pendingSkip: [false, true, false],
    status: "playing",
    winners: [],
    seed: [42, 43, 44, 45],
    rngCalls: 0,
    ...over,
  };
}

describe("viewFor", () => {
  test("view for seat 1 only includes hand 1", () => {
    const view = viewFor(makeState(), [1]);
    expect(view.hands).toEqual({ 1: [20, 21] });
    expect(Object.keys(view.hands)).toEqual(["1"]);
    expect(view.handCounts).toEqual([3, 2, 4]);
  });

  test("view for [0,2] (shared phone) includes both", () => {
    const view = viewFor(makeState(), [0, 2]);
    expect(view.hands).toEqual({ 0: [10, 11, 12], 2: [30, 31, 32, 33] });
  });

  test("view for [] (spectating device) has no hands", () => {
    expect(viewFor(makeState(), []).hands).toEqual({});
  });

  test("ignores controlled seats that are not valid indices", () => {
    const view = viewFor(makeState(), [-1, 3, 1.5, 99, 1]);
    expect(Object.keys(view.hands)).toEqual(["1"]);
  });

  test("exposes public table state without the deck contents", () => {
    const view = viewFor(makeState(), [1]);
    expect(view).toMatchObject({
      round: 4,
      dealer: 2,
      turn: 1,
      step: "play",
      status: "playing",
      deckCount: 4,
      discardTop: 60,
      discardCount: 2,
      phase: [0, 1, 2],
      scores: [10, 20, 30],
      laid: [null, [{ kind: "set", cards: [5, 6, 7], value: 3 }], null],
      pendingSkip: [false, true, false],
      winners: [],
    });
    expect(view).not.toHaveProperty("deck");
    expect(view).not.toHaveProperty("discard");
    expect(view).not.toHaveProperty("seed");
  });

  test("discardTop is null for an empty discard pile", () => {
    const view = viewFor(makeState({ discard: [] }), []);
    expect(view.discardTop).toBeNull();
    expect(view.discardCount).toBe(0);
  });

  test("has exactly the public keys plus hands", () => {
    expect(Object.keys(viewFor(makeState(), [1])).sort()).toEqual([
      "dealer",
      "deckCount",
      "discardCount",
      "discardTop",
      "handCounts",
      "hands",
      "laid",
      "pendingSkip",
      "phase",
      "round",
      "scores",
      "status",
      "step",
      "turn",
      "winners",
    ]);
  });

  test("carries endReason only on a game that ended early", () => {
    const over = makeState({ status: "gameOver", winners: [1], endReason: "decided" });
    expect(viewFor(over, []).endReason).toBe("decided");
    expect("endReason" in viewFor(makeState({ status: "gameOver", winners: [1] }), [])).toBe(false);
  });

  test("the whole serialized view never carries hidden values", () => {
    // Every hidden value is distinct from every number the view may show, so
    // finding one anywhere in the JSON can only mean a leak.
    const state = makeState({
      deck: [90, 91, 92, 93, 94],
      discard: [95, 96, 60],
      hands: [
        [70, 71, 72],
        [20, 21],
        [80, 81, 82, 83],
      ],
      seed: [987654321, 876543219, 765432198, 654321987],
      rngCalls: 107,
    });
    const shown = new Set([4, 2, 1, 5, 60, 3, 0, 10, 20, 30, 6, 7, 21]);
    const hidden = [
      ...state.hands[0]!,
      ...state.hands[2]!,
      ...state.deck,
      ...state.discard.slice(0, -1),
      ...state.seed,
      state.rngCalls,
    ];
    for (const value of hidden) expect(shown.has(value)).toBe(false);

    const numbers = (json: string) => new Set((json.match(/\d+/g) ?? []).map(Number));
    const seen = numbers(JSON.stringify(viewFor(state, [1])));
    expect([...seen].every((n) => shown.has(n))).toBe(true);
    for (const value of hidden) expect(seen.has(value)).toBe(false);
  });

  test("never leaks other seats' cards in the serialized hands section", () => {
    const state = makeState();
    const hands = JSON.parse(JSON.stringify(viewFor(state, [1]))).hands;
    expect(Object.keys(hands)).toEqual(["1"]);
    const serialized = JSON.stringify(hands);
    for (const id of [...state.hands[0]!, ...state.hands[2]!]) {
      expect(serialized).not.toMatch(new RegExp(`\\b${id}\\b`));
    }
  });

  test("returns fresh copies, not references into the state", () => {
    const state = makeState();
    const view = viewFor(state, [1]);
    expect(view.hands[1]).not.toBe(state.hands[1]);
    expect(view.phase).not.toBe(state.phase);
    expect(view.scores).not.toBe(state.scores);
    expect(view.pendingSkip).not.toBe(state.pendingSkip);
    expect(view.winners).not.toBe(state.winners);
    expect(view.laid).not.toBe(state.laid);
    expect(view.laid[1]).not.toBe(state.laid[1]);
    expect(view.laid[1]![0]!.cards).not.toBe(state.laid[1]![0]!.cards);

    view.hands[1]!.push(99);
    view.laid[1]![0]!.cards.push(99);
    view.scores[0] = 999;
    expect(state.hands[1]).toEqual([20, 21]);
    expect(state.laid[1]![0]!.cards).toEqual([5, 6, 7]);
    expect(state.scores[0]).toBe(10);
  });
});

describe("eventFor", () => {
  const deckDraw: GameEvent = { kind: "drew", seat: 1, from: "deck", card: 42 };

  test("deck draw event hides card from others, shows it to drawer", () => {
    const hidden = eventFor(deckDraw, [0, 2]);
    expect(hidden).toEqual({ kind: "drew", seat: 1, from: "deck" });
    expect("card" in hidden).toBe(false);

    expect(eventFor(deckDraw, [1])).toEqual(deckDraw);
    expect(eventFor(deckDraw, [0, 1])).toEqual(deckDraw);
    expect("card" in eventFor(deckDraw, [])).toBe(false);
  });

  test("discard draw event shows card to all", () => {
    const e: GameEvent = { kind: "drew", seat: 1, from: "discard", card: 7 };
    expect(eventFor(e, [0])).toEqual(e);
    expect(eventFor(e, [1])).toEqual(e);
    expect(eventFor(e, [])).toEqual(e);
  });

  test("passes other events through unchanged, as copies", () => {
    const events: GameEvent[] = [
      { kind: "roundStarted", round: 1, dealer: 0 },
      {
        kind: "laidDown",
        seat: 0,
        groups: [{ kind: "set", cards: [1, 2, 3], value: 2 }],
      },
      { kind: "discarded", seat: 0, card: 5, skipTarget: 2 },
      {
        kind: "roundOver",
        wentOut: null,
        points: [1, 2],
        advanced: [0],
        scores: [1, 2],
        phase: [1, 0],
      },
    ];
    for (const e of events) {
      const out = eventFor(e, [1]);
      expect(out).toEqual(e);
      expect(out).not.toBe(e);
    }
    const laid = events[1] as Extract<GameEvent, { kind: "laidDown" }>;
    const out = eventFor(laid, [1]) as typeof laid;
    expect(out.groups).not.toBe(laid.groups);
    expect(out.groups[0]!.cards).not.toBe(laid.groups[0]!.cards);
  });

  test("a deck draw without a card passes through", () => {
    const e: GameEvent = { kind: "drew", seat: 1, from: "deck" };
    const out = eventFor(e, []);
    expect(out).toEqual(e);
    expect("card" in out).toBe(false);
  });

  test("does not mutate the input event", () => {
    const e: GameEvent = { kind: "drew", seat: 1, from: "deck", card: 42 };
    eventFor(e, []);
    expect(e).toEqual({ kind: "drew", seat: 1, from: "deck", card: 42 });
  });
});
