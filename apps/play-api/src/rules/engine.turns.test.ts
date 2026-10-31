import { describe, expect, test } from "vitest";

import { seedOf } from "../../tests/seeds";

import { ALL_CARD_IDS, card, cardPoints } from "./cards";
import {
  applyAction,
  dealRound,
  newGame,
  type Action,
  type ApplyResult,
  type CatTowerState,
  type GameEvent,
} from "./engine";
import { buildGroup } from "./groups";

/*
 * Card ids (see cards.ts): tabby v = v - 1 (or v + 11 for the second copy),
 * tuxedo v = 23 + v, calico v = 47 + v, gray v = 71 + v, 96-103 = Yarn,
 * 104-107 = Cucumber.
 */
const tabby = (v: number) => v - 1;
const tuxedo = (v: number) => 23 + v;
const calico = (v: number) => 47 + v;
const YARN = 96;
const CUCUMBER = 104;

function deepFreeze<T>(value: T): T {
  if (typeof value === "object" && value !== null && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const v of Object.values(value)) deepFreeze(v);
  }
  return value;
}

/**
 * A frozen 3-seat state in the draw step on seat 0's turn. Frozen so that any
 * mutation of the input by applyAction throws.
 */
function makeState(over: Partial<CatTowerState> = {}): CatTowerState {
  return deepFreeze({
    seats: 3,
    phase: [0, 0, 0],
    scores: [0, 0, 0],
    round: 1,
    dealer: 2,
    deck: [tabby(1), tabby(2), tabby(3)],
    discard: [tuxedo(9)],
    hands: [
      [tabby(5), tuxedo(5), calico(6)],
      [tabby(7), tuxedo(7), calico(8)],
      [tabby(9), tuxedo(10), calico(11)],
    ],
    laid: [null, null, null],
    turn: 0,
    step: "draw",
    pendingSkip: [false, false, false],
    status: "playing",
    winners: [],
    seed: seedOf(42),
    rngCalls: 0,
    ...over,
  });
}

function ok(result: ApplyResult): { state: CatTowerState; events: GameEvent[] } {
  if (!result.ok) throw new Error(`expected ok, got ${result.error}`);
  return result;
}

const DRAW_DECK: Action = { type: "draw", from: "deck" };
const discard = (cardId: number, skipTarget?: number): Action =>
  skipTarget === undefined
    ? { type: "discard", card: cardId }
    : { type: "discard", card: cardId, skipTarget };

/** Find a seed whose first flip has (or has not) a Cucumber on top. */
function seedWhere(seats: number, cucumber: boolean): number {
  for (let seed = 1; seed < 1000; seed++) {
    const s = newGame(seats, seedOf(seed));
    if ((card(s.discard[0] as number).kind === "cucumber") === cucumber) {
      return seed;
    }
  }
  throw new Error("no seed found");
}

describe("newGame", () => {
  test("deals 10 each, flips one card, and starts on dealer + 1", () => {
    const seed = seedWhere(4, false);
    const s = newGame(4, seedOf(seed));
    expect(s.seats).toBe(4);
    expect(s.hands.map((h) => h.length)).toEqual([10, 10, 10, 10]);
    expect(s.discard).toHaveLength(1);
    expect(s.deck).toHaveLength(108 - 41);
    expect(s.step).toBe("draw");
    expect(s.status).toBe("playing");
    expect(s.round).toBe(1);
    expect(s.dealer).toBe(0);
    expect(s.turn).toBe(1);
    expect(s.phase).toEqual([0, 0, 0, 0]);
    expect(s.scores).toEqual([0, 0, 0, 0]);
    expect(s.laid).toEqual([null, null, null, null]);
    expect(s.pendingSkip).toEqual([false, false, false, false]);
    expect(s.winners).toEqual([]);
    expect(s.seed).toEqual(seedOf(seed));
    const all = [...s.deck, ...s.discard, ...s.hands.flat()];
    expect([...all].sort((a, b) => a - b)).toEqual([...ALL_CARD_IDS]);
  });

  test("is deterministic for a seed, differs across seeds, and survives JSON", () => {
    expect(newGame(4, seedOf(1))).toEqual(newGame(4, seedOf(1)));
    expect(newGame(4, seedOf(1)).hands).not.toEqual(newGame(4, seedOf(2)).hands);
    const s = newGame(3, seedOf(5));
    expect(JSON.parse(JSON.stringify(s))).toEqual(s);
    expect(s.rngCalls).toBe(107);
  });

  test("a Cucumber on the first flip skips the first seat", () => {
    const seed = seedWhere(4, true);
    const s = newGame(4, seedOf(seed));
    expect(card(s.discard[0] as number).kind).toBe("cucumber");
    expect(s.turn).toBe(2);
    expect(s.pendingSkip).toEqual([false, false, false, false]);
  });

  test("rejects seat counts outside 2-6", () => {
    expect(() => newGame(1, seedOf(1))).toThrow(RangeError);
    expect(() => newGame(7, seedOf(1))).toThrow(RangeError);
    expect(() => newGame(2.5, seedOf(1))).toThrow(RangeError);
    expect(newGame(2, seedOf(1)).hands).toHaveLength(2);
    expect(newGame(6, seedOf(1)).hands).toHaveLength(6);
  });
});

describe("dealRound", () => {
  test("emits roundStarted then turn when the flip is a plain card", () => {
    const base = newGame(4, seedOf(seedWhere(4, false)));
    const { state, events } = dealRound(base, 1, 2);
    expect(state.round).toBe(2);
    expect(state.dealer).toBe(1);
    expect(state.turn).toBe(2);
    expect(events).toEqual([
      { kind: "roundStarted", round: 2, dealer: 1 },
      { kind: "turn", seat: 2 },
    ]);
  });

  test("emits skipped for the first seat when the flip is a Cucumber", () => {
    const base = newGame(4, seedOf(seedWhere(4, false)));
    // Keep dealing from the advancing rng until the flip is a Cucumber.
    let found: ReturnType<typeof dealRound> | null = null;
    let cur = base;
    for (let i = 0; i < 200 && found === null; i++) {
      const next = dealRound(cur, 0, 2);
      if (card(next.state.discard[0] as number).kind === "cucumber") found = next;
      cur = next.state;
    }
    expect(found).not.toBeNull();
    expect(found?.events).toEqual([
      { kind: "roundStarted", round: 2, dealer: 0 },
      { kind: "skipped", seat: 1 },
      { kind: "turn", seat: 2 },
    ]);
  });

  test("a 2-player Cucumber flip skips the first seat back to the dealer", () => {
    let cur = newGame(2, seedOf(1));
    let found: ReturnType<typeof dealRound> | null = null;
    for (let i = 0; i < 200 && found === null; i++) {
      const next = dealRound(cur, 0, 2);
      if (card(next.state.discard[0] as number).kind === "cucumber") found = next;
      cur = next.state;
    }
    expect(found?.state.turn).toBe(0);
  });

  test("resets per-round state but keeps phases and scores", () => {
    const dirty = makeState({
      phase: [2, 1, 0],
      scores: [10, 20, 30],
      status: "roundOver",
      pendingSkip: [true, false, true],
      laid: [[buildGroup({ kind: "set", size: 3 }, [tabby(7), tuxedo(7), YARN])!], null, null],
      rngCalls: 7,
    });
    const { state } = dealRound(dirty, 0, 2);
    expect(state.status).toBe("playing");
    expect(state.phase).toEqual([2, 1, 0]);
    expect(state.scores).toEqual([10, 20, 30]);
    expect(state.laid).toEqual([null, null, null]);
    expect(state.pendingSkip).toEqual([false, false, false]);
    expect(state.hands.map((h) => h.length)).toEqual([10, 10, 10]);
    expect(state.rngCalls).toBeGreaterThan(7);
  });
});

describe("draw", () => {
  test("from the deck moves the top card to the hand and sets step play", () => {
    const s = makeState();
    const { state, events } = ok(applyAction(s, 0, DRAW_DECK));
    expect(state.hands[0]).toEqual([...s.hands[0]!, tabby(3)]);
    expect(state.deck).toEqual([tabby(1), tabby(2)]);
    expect(state.step).toBe("play");
    expect(state.turn).toBe(0);
    expect(events).toEqual([
      { kind: "drew", seat: 0, from: "deck", card: tabby(3) },
    ]);
  });

  test("from the discard takes the top card", () => {
    const s = makeState({ discard: [tabby(4), tuxedo(9)] });
    const { state, events } = ok(applyAction(s, 0, { type: "draw", from: "discard" }));
    expect(state.hands[0]).toEqual([...s.hands[0]!, tuxedo(9)]);
    expect(state.discard).toEqual([tabby(4)]);
    expect(state.step).toBe("play");
    expect(events).toEqual([
      { kind: "drew", seat: 0, from: "discard", card: tuxedo(9) },
    ]);
  });

  test("cannot take a Cucumber from the discard", () => {
    const s = makeState({ discard: [tabby(4), CUCUMBER] });
    expect(applyAction(s, 0, { type: "draw", from: "discard" })).toEqual({
      ok: false,
      error: "cucumber_from_discard",
    });
  });

  test("an empty discard cannot be drawn from", () => {
    const s = makeState({ discard: [] });
    expect(applyAction(s, 0, { type: "draw", from: "discard" })).toEqual({
      ok: false,
      error: "empty_discard",
    });
  });

  test("drawing in the play step is bad_step", () => {
    const s = makeState({ step: "play" });
    expect(applyAction(s, 0, DRAW_DECK)).toEqual({ ok: false, error: "bad_step" });
  });

  test("the same draw applied twice: the second is bad_step and state is unchanged", () => {
    const first = ok(applyAction(makeState(), 0, DRAW_DECK));
    const snapshot = structuredClone(first.state);
    deepFreeze(first.state);
    expect(applyAction(first.state, 0, DRAW_DECK)).toEqual({
      ok: false,
      error: "bad_step",
    });
    expect(first.state).toEqual(snapshot);
  });

  test("nothing can be drawn once the round is over", () => {
    const s = makeState({ status: "roundOver" });
    expect(applyAction(s, 0, DRAW_DECK)).toEqual({ ok: false, error: "bad_step" });
  });
});

describe("turn ownership", () => {
  test("an action by the wrong seat is not_your_turn and changes nothing", () => {
    const s = makeState();
    const snapshot = structuredClone(s);
    for (const action of [DRAW_DECK, discard(tabby(5))]) {
      expect(applyAction(s, 1, action)).toEqual({ ok: false, error: "not_your_turn" });
    }
    expect(applyAction(s, 9, DRAW_DECK)).toEqual({ ok: false, error: "not_your_turn" });
    expect(s).toEqual(snapshot);
  });
});

describe("discard", () => {
  test("a card not in the hand is bad_card", () => {
    const s = makeState({ step: "play" });
    expect(applyAction(s, 0, discard(tabby(12)))).toEqual({
      ok: false,
      error: "bad_card",
    });
    expect(applyAction(s, 0, discard(500))).toEqual({ ok: false, error: "bad_card" });
  });

  test("in the draw step is bad_step", () => {
    expect(applyAction(makeState(), 0, discard(tabby(5)))).toEqual({
      ok: false,
      error: "bad_step",
    });
  });

  test("moves the card to the discard, advances the turn, and resets step to draw", () => {
    const s = makeState({ step: "play" });
    const { state, events } = ok(applyAction(s, 0, discard(tuxedo(5))));
    expect(state.hands[0]).toEqual([tabby(5), calico(6)]);
    expect(state.discard).toEqual([tuxedo(9), tuxedo(5)]);
    expect(state.turn).toBe(1);
    expect(state.step).toBe("draw");
    expect(events).toEqual([
      { kind: "discarded", seat: 0, card: tuxedo(5) },
      { kind: "turn", seat: 1 },
    ]);
  });

  test("the turn wraps around the table", () => {
    const s = makeState({ step: "play", turn: 2 });
    const { state } = ok(applyAction(s, 2, discard(tabby(9))));
    expect(state.turn).toBe(0);
  });

  test("a skipTarget on a plain card is ignored", () => {
    const s = makeState({ step: "play" });
    const { state, events } = ok(applyAction(s, 0, discard(tabby(5), 1)));
    expect(state.pendingSkip).toEqual([false, false, false]);
    expect(events[0]).toEqual({ kind: "discarded", seat: 0, card: tabby(5) });
  });

  test("every pending seat is skipped in turn, each with a skipped event", () => {
    const s = makeState({
      seats: 4,
      phase: [0, 0, 0, 0],
      scores: [0, 0, 0, 0],
      hands: [[tabby(5), tabby(4)], [tabby(6)], [tabby(7)], [tabby(8)]],
      laid: [null, null, null, null],
      pendingSkip: [false, true, true, false],
      step: "play",
    });
    const { state, events } = ok(applyAction(s, 0, discard(tabby(5))));
    expect(state.turn).toBe(3);
    expect(state.pendingSkip).toEqual([false, false, false, false]);
    expect(events).toEqual([
      { kind: "discarded", seat: 0, card: tabby(5) },
      { kind: "skipped", seat: 1 },
      { kind: "skipped", seat: 2 },
      { kind: "turn", seat: 3 },
    ]);
  });
});

describe("cucumber discards", () => {
  const playing = (over: Partial<CatTowerState> = {}) =>
    makeState({
      step: "play",
      hands: [
        [CUCUMBER, tabby(5)],
        [tabby(7), tuxedo(7)],
        [tabby(9), tuxedo(10)],
      ],
      ...over,
    });

  test("sets pendingSkip on the target and the target's turn is skipped once", () => {
    // 3 seats: 0 skips 2, so the order is 0, 1, 0, ...
    const afterDiscard = ok(applyAction(playing(), 0, discard(CUCUMBER, 2)));
    expect(afterDiscard.state.pendingSkip).toEqual([false, false, true]);
    expect(afterDiscard.state.turn).toBe(1);
    expect(afterDiscard.events).toEqual([
      { kind: "discarded", seat: 0, card: CUCUMBER, skipTarget: 2 },
      { kind: "turn", seat: 1 },
    ]);

    const s1 = ok(applyAction(afterDiscard.state, 1, DRAW_DECK));
    const s2 = ok(applyAction(s1.state, 1, discard(tabby(7))));
    expect(s2.state.turn).toBe(0);
    expect(s2.state.pendingSkip).toEqual([false, false, false]);
    expect(s2.events).toEqual([
      { kind: "discarded", seat: 1, card: tabby(7) },
      { kind: "skipped", seat: 2 },
      { kind: "turn", seat: 0 },
    ]);

    // The skip was used up: after seat 0 plays, seat 1 and then 2 get turns.
    const s3 = ok(applyAction(s2.state, 0, DRAW_DECK));
    const s4 = ok(applyAction(s3.state, 0, discard(tabby(5))));
    expect(s4.state.turn).toBe(1);
    const s5 = ok(applyAction(s4.state, 1, DRAW_DECK));
    const s6 = ok(applyAction(s5.state, 1, discard(tuxedo(7))));
    expect(s6.state.turn).toBe(2);
  });

  test("two players: the discarder gets two turns in a row", () => {
    const s = makeState({
      seats: 2,
      phase: [0, 0],
      scores: [0, 0],
      hands: [[CUCUMBER, tabby(5)], [tabby(7)]],
      laid: [null, null],
      pendingSkip: [false, false],
      step: "play",
    });
    const { state, events } = ok(applyAction(s, 0, discard(CUCUMBER, 1)));
    expect(state.turn).toBe(0);
    expect(state.step).toBe("draw");
    expect(state.pendingSkip).toEqual([false, false]);
    expect(events).toEqual([
      { kind: "discarded", seat: 0, card: CUCUMBER, skipTarget: 1 },
      { kind: "skipped", seat: 1 },
      { kind: "turn", seat: 0 },
    ]);
  });

  test("a missing skipTarget is bad_target when someone can be skipped", () => {
    expect(applyAction(playing(), 0, discard(CUCUMBER))).toEqual({
      ok: false,
      error: "bad_target",
    });
  });

  test("the target must be another seat that is not already pending", () => {
    const s = playing({ pendingSkip: [false, true, false] });
    for (const target of [0, 1, 3, -1, 1.5]) {
      expect(applyAction(s, 0, discard(CUCUMBER, target))).toEqual({
        ok: false,
        error: "bad_target",
      });
    }
    // Seat 2 is a valid target; seat 1 was already pending, so both are
    // skipped as the turn comes back around to seat 0.
    const accepted = ok(applyAction(s, 0, discard(CUCUMBER, 2)));
    expect(accepted.events[0]).toEqual({
      kind: "discarded",
      seat: 0,
      card: CUCUMBER,
      skipTarget: 2,
    });
    expect(accepted.state.turn).toBe(0);
  });

  test("with every other seat pending, it is discarded with no target", () => {
    const s = playing({ pendingSkip: [false, true, true] });
    const { state, events } = ok(applyAction(s, 0, discard(CUCUMBER)));
    expect(state.discard.at(-1)).toBe(CUCUMBER);
    expect(events[0]).toEqual({ kind: "discarded", seat: 0, card: CUCUMBER });
    // Both pending seats are skipped by the normal turn advance.
    expect(state.turn).toBe(0);
    expect(state.pendingSkip).toEqual([false, false, false]);
  });

  test("with every other seat pending, giving a target is bad_target", () => {
    const s = playing({ pendingSkip: [false, true, true] });
    expect(applyAction(s, 0, discard(CUCUMBER, 1))).toEqual({
      ok: false,
      error: "bad_target",
    });
  });
});

describe("deck exhaustion", () => {
  test("an empty deck reshuffles the discard except its top card", () => {
    const rest = [tabby(1), tabby(2), tuxedo(3), calico(4)];
    const s = makeState({ deck: [], discard: [...rest, tuxedo(9)], rngCalls: 3 });
    const { state, events } = ok(applyAction(s, 0, DRAW_DECK));
    expect(events).toHaveLength(2);
    expect(events[0]).toEqual({ kind: "reshuffled", deckCount: 4 });
    const drawn = state.hands[0]!.at(-1) as number;
    expect(events[1]).toEqual({ kind: "drew", seat: 0, from: "deck", card: drawn });
    expect(rest).toContain(drawn);
    expect([...state.deck, drawn].sort((a, b) => a - b)).toEqual(
      [...rest].sort((a, b) => a - b),
    );
    expect(state.discard).toEqual([tuxedo(9)]);
    expect(state.step).toBe("play");
    expect(state.rngCalls).toBeGreaterThan(3);
  });

  test("the reshuffle is deterministic and continues the rng stream", () => {
    const rest = [tabby(1), tabby(2), tuxedo(3), calico(4), calico(5)];
    const make = () =>
      makeState({ deck: [], discard: [...rest, tuxedo(9)], rngCalls: 3 });
    const a = ok(applyAction(make(), 0, DRAW_DECK)).state;
    const b = ok(applyAction(make(), 0, DRAW_DECK)).state;
    expect(a).toEqual(b);
    const c = ok(
      applyAction(
        makeState({ deck: [], discard: [...rest, tuxedo(9)], rngCalls: 40 }),
        0,
        DRAW_DECK,
      ),
    ).state;
    expect(c.rngCalls).toBe(40 + (a.rngCalls - 3));
  });

  test("an empty deck and an empty discard also end the round", () => {
    const s = makeState({ deck: [], discard: [] });
    const { state, events } = ok(applyAction(s, 0, DRAW_DECK));
    expect(state.status).toBe("roundOver");
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ kind: "roundOver", wentOut: null });
  });

  test("an empty deck with a one-card discard ends the round with nobody out", () => {
    const set7 = buildGroup({ kind: "set", size: 3 }, [tabby(7), tuxedo(7), YARN])!;
    const s = makeState({
      deck: [],
      discard: [tuxedo(9)],
      phase: [0, 3, 9],
      scores: [5, 100, 0],
      hands: [
        [CUCUMBER, tabby(5), tuxedo(11)], // 15 + 5 + 10
        [YARN, tabby(1)], // 25 + 5
        [calico(12)], // 10
      ],
      laid: [[set7], null, null],
    });
    const { state, events } = ok(applyAction(s, 0, DRAW_DECK));
    expect(state.status).toBe("roundOver");
    expect(state.scores).toEqual([35, 130, 10]);
    expect(state.phase).toEqual([1, 3, 9]);
    expect(state.hands).toEqual(s.hands);
    expect(state.deck).toEqual([]);
    expect(state.discard).toEqual([tuxedo(9)]);
    expect(events).toEqual([
      {
        kind: "roundOver",
        wentOut: null,
        points: [30, 30, 10],
        advanced: [0],
        scores: [35, 130, 10],
        phase: [1, 3, 9],
      },
    ]);
    // Nothing more can be played until the next round.
    expect(applyAction(state, 0, DRAW_DECK)).toEqual({ ok: false, error: "bad_step" });
    expect(cardPoints(YARN)).toBe(25);
  });
});

describe("nextRound outside a finished round", () => {
  test("nextRound while playing is round_not_over", () => {
    const s = makeState({ step: "play" });
    const action: Action = { type: "nextRound" };
    expect(applyAction(s, 0, action)).toEqual({ ok: false, error: "round_not_over" });
  });
});
