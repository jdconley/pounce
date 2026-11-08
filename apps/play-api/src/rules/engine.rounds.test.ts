import { describe, expect, test } from "vitest";

import { seedOf } from "../../tests/seeds";

import { applyAction, newGame, outcomeDecided, type ApplyResult, type CatTowerState, type GameEvent } from "./engine";
import { buildGroup, type Group } from "./groups";

/* Card ids: tabby v = v - 1, tuxedo v = 23 + v, calico v = 47 + v, gray v = 71 + v. */
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

const set3 = buildGroup({ kind: "set", size: 3 }, [tabby(9), tuxedo(9), calico(9)]) as Group;

/**
 * A frozen 3-seat state in seat 0's play step with a single card left in
 * seat 0's hand, so discarding it goes out. Seat 0 has laid down.
 */
function makeState(over: Partial<CatTowerState> = {}): CatTowerState {
  return deepFreeze({
    seats: 3,
    phase: [0, 0, 0],
    scores: [0, 0, 0],
    round: 1,
    dealer: 2,
    deck: [tabby(1), tabby(2), tabby(3)],
    discard: [tuxedo(2)],
    hands: [[tabby(4)], [tabby(7), tuxedo(7), calico(8)], [tabby(10), tuxedo(11), calico(12)]],
    laid: [[set3], null, null],
    turn: 0,
    step: "play",
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

/** Seat 0 discards its last card and goes out. */
const goOut = (s: CatTowerState) => ok(applyAction(s, 0, { type: "discard", card: tabby(4) }));

describe("scoring", () => {
  test("points: hand [5,11,yarn,cucumber] = 5+10+25+15", () => {
    const s = makeState({
      hands: [[tabby(4)], [tabby(5), tuxedo(11), YARN, CUCUMBER], [calico(12)]],
      scores: [1, 100, 0],
    });
    const { state, events } = goOut(s);
    expect(events[1]).toMatchObject({ kind: "roundOver", points: [0, 55, 10] });
    expect(state.scores).toEqual([1, 155, 10]);
    expect(state.status).toBe("roundOver");
  });

  test("only seats that laid down advance", () => {
    const s = makeState({
      phase: [2, 4, 6],
      laid: [[set3], null, [set3]],
    });
    const { state, events } = goOut(s);
    expect(state.phase).toEqual([3, 4, 7]);
    expect(events[1]).toMatchObject({ advanced: [0, 2], phase: [3, 4, 7] });
    expect(state.status).toBe("roundOver");
    expect(state.winners).toEqual([]);
    expect(events.map((e) => e.kind)).toEqual(["discarded", "roundOver"]);
  });
});

describe("nextRound", () => {
  const over = (over: Partial<CatTowerState> = {}) => goOut(makeState(over)).state;

  test("rotates the dealer and redeals, keeping phases and scores", () => {
    const s = over({
      phase: [2, 4, 6],
      scores: [10, 20, 30],
      pendingSkip: [false, true, false],
      laid: [[set3], null, [set3]],
    });
    expect(s.status).toBe("roundOver");
    const { state, events } = ok(applyAction(s, 1, { type: "nextRound" }));
    expect(state.round).toBe(2);
    expect(state.dealer).toBe(0);
    expect(state.status).toBe("playing");
    expect(state.step).toBe("draw");
    expect(state.laid).toEqual([null, null, null]);
    expect(state.pendingSkip).toEqual([false, false, false]);
    expect(state.phase).toEqual(s.phase);
    expect(state.scores).toEqual(s.scores);
    expect(state.hands.map((h) => h.length)).toEqual([10, 10, 10]);
    expect(state.discard).toHaveLength(1);
    expect(state.deck).toHaveLength(108 - 30 - 1);
    expect(events[0]).toEqual({ kind: "roundStarted", round: 2, dealer: 0 });
    expect(events.at(-1)).toEqual({ kind: "turn", seat: state.turn });
  });

  test("dealer wraps around the table", () => {
    const { state } = ok(applyAction(over({ dealer: 2 }), 0, { type: "nextRound" }));
    expect(state.dealer).toBe(0);
    const { state: next } = ok(
      applyAction(
        // Play a trivial second round out to roundOver again.
        deepFreeze({ ...state, status: "roundOver" as const }),
        2,
        { type: "nextRound" },
      ),
    );
    expect(next.dealer).toBe(1);
    expect(next.round).toBe(3);
  });

  test("is allowed for a seat that is not on turn", () => {
    const s = over();
    expect(s.turn).toBe(0);
    expect(applyAction(s, 2, { type: "nextRound" }).ok).toBe(true);
  });

  test("nextRound while playing -> round_not_over", () => {
    expect(applyAction(makeState(), 0, { type: "nextRound" })).toEqual({
      ok: false,
      error: "round_not_over",
    });
    // Checked before turn order too.
    expect(applyAction(makeState(), 1, { type: "nextRound" })).toEqual({
      ok: false,
      error: "round_not_over",
    });
  });

  test("nextRound after the game is over -> round_not_over", () => {
    const s = over({ phase: [9, 0, 0] });
    expect(s.status).toBe("gameOver");
    expect(applyAction(s, 0, { type: "nextRound" })).toEqual({
      ok: false,
      error: "round_not_over",
    });
  });

  test("a second nextRound applied to the same state is a fresh deal, input untouched", () => {
    const s = over();
    const a = ok(applyAction(s, 0, { type: "nextRound" }));
    const b = ok(applyAction(s, 1, { type: "nextRound" }));
    expect(a.state).toEqual(b.state);
    expect(s.status).toBe("roundOver");
  });

  test("a full game state from newGame can round-trip into round 2", () => {
    const g = newGame(4, seedOf(7));
    const ended = { ...structuredClone(g), status: "roundOver" as const };
    const { state } = ok(applyAction(ended, 3, { type: "nextRound" }));
    expect(state.round).toBe(2);
    expect(state.dealer).toBe(1);
  });
});

describe("winning", () => {
  test("first to finish phase 10 wins", () => {
    const s = makeState({ phase: [9, 3, 4], scores: [200, 50, 60] });
    const { state, events } = goOut(s);
    expect(state.phase).toEqual([10, 3, 4]);
    expect(state.status).toBe("gameOver");
    expect(state.winners).toEqual([0]);
    expect(events.map((e) => e.kind)).toEqual(["discarded", "roundOver", "gameOver"]);
    expect(events[2]).toEqual({ kind: "gameOver", winners: [0] });
  });

  test("two finish phase 10 same round -> lower score wins", () => {
    const s = makeState({
      phase: [9, 9, 3],
      scores: [100, 90, 0],
      laid: [[set3], [set3], null],
      hands: [[tabby(4)], [tabby(5)], [calico(12)]],
    });
    const { state, events } = goOut(s);
    // Final scores: seat 0 = 100, seat 1 = 90 + 5, seat 2 = 10.
    expect(state.scores).toEqual([100, 95, 10]);
    expect(state.winners).toEqual([1]);
    expect(state.status).toBe("gameOver");
    expect(events.at(-1)).toEqual({ kind: "gameOver", winners: [1] });
  });

  test("a lower-scoring seat that has not finished phase 10 cannot win", () => {
    const s = makeState({ phase: [9, 5, 5], scores: [500, 0, 0] });
    const { state } = goOut(s);
    expect(state.winners).toEqual([0]);
  });

  test("equal scores share the win", () => {
    const s = makeState({
      phase: [9, 9, 3],
      scores: [95, 90, 0],
      laid: [[set3], [set3], null],
      hands: [[tabby(4)], [tabby(5)], [calico(12)]],
    });
    const { state, events } = goOut(s);
    expect(state.scores).toEqual([95, 95, 10]);
    expect(state.winners).toEqual([0, 1]);
    expect(events.at(-1)).toEqual({ kind: "gameOver", winners: [0, 1] });
  });

  test("a round that finishes no one on phase 10 keeps playing", () => {
    const { state, events } = goOut(makeState({ phase: [8, 0, 0] }));
    expect(state.status).toBe("roundOver");
    expect(state.winners).toEqual([]);
    expect(events.some((e) => e.kind === "gameOver")).toBe(false);
  });

  test("game ends via deck exhaustion too when a laid seat reaches phase 10", () => {
    const s = makeState({
      phase: [9, 0, 0],
      step: "draw",
      deck: [],
      discard: [tuxedo(2)],
    });
    const { state, events } = ok(applyAction(s, 0, { type: "draw", from: "deck" }));
    expect(state.status).toBe("gameOver");
    expect(state.winners).toEqual([0]);
    expect(events.map((e) => e.kind)).toEqual(["roundOver", "gameOver"]);
  });
});

describe("a decided game ends early", () => {
  /** Phase 10 (a set of 5 and a set of 3): five 7s and three 3s. */
  const PHASE_10 = [
    { cards: [tabby(7), tabby(7) + 12, tuxedo(7), calico(7), 78] },
    { cards: [tabby(3), tuxedo(3), calico(3)] },
  ];
  const PHASE_10_CARDS = PHASE_10.flatMap((g) => g.cards);
  /** Ten low cards worth 55: the second gray 1-10. */
  const TEN = Array.from({ length: 10 }, (_, i) => 84 + i);

  /** A frozen table in seat `turn`'s play step; every seat not given a hand holds TEN. */
  function table(seats: number, over: Partial<CatTowerState> = {}): CatTowerState {
    return deepFreeze({
      seats,
      phase: new Array<number>(seats).fill(0),
      scores: new Array<number>(seats).fill(0),
      round: 12,
      dealer: 0,
      deck: [tabby(1), tabby(2), tabby(3)],
      discard: [tuxedo(2)],
      hands: Array.from({ length: seats }, () => [...TEN]),
      laid: new Array<null>(seats).fill(null),
      turn: 1,
      step: "play",
      pendingSkip: new Array<boolean>(seats).fill(false),
      status: "playing",
      winners: [],
      seed: seedOf(42),
      rngCalls: 0,
      ...over,
    } as CatTowerState);
  }

  /** Seat 1 lays down phase 10, keeping a 12 and a Yarn (35 points). */
  const layTen = (s: CatTowerState) =>
    ok(applyAction(s, 1, { type: "layDown", groups: PHASE_10 }));
  const tenHand = [...PHASE_10_CARDS, tabby(12), YARN];

  test("two players: phase 10 down and the other can't reach it -> game over now", () => {
    const s = table(2, {
      phase: [6, 9],
      scores: [40, 120],
      hands: [[...TEN], tenHand],
    });
    const { state, events } = layTen(s);
    expect(events.map((e) => e.kind)).toEqual(["laidDown", "roundOver", "gameOver"]);
    // Scored as the hands stand: nobody went out, seat 1 advances.
    expect(events[1]).toMatchObject({ kind: "roundOver", wentOut: null, points: [55, 35] });
    expect(events[2]).toEqual({ kind: "gameOver", winners: [1], reason: "decided" });
    expect(state.status).toBe("gameOver");
    expect(state.endReason).toBe("decided");
    expect(state.phase).toEqual([6, 10]);
    expect(state.scores).toEqual([95, 155]);
    expect(state.winners).toEqual([1]);
  });

  test("two players: the other already down on phase 9 still can't reach 10", () => {
    const s = table(2, {
      phase: [8, 9],
      scores: [0, 400],
      laid: [[set3], null],
      hands: [[tabby(1)], tenHand],
    });
    const { state } = layTen(s);
    expect(state.status).toBe("gameOver");
    expect(state.phase).toEqual([9, 10]);
    expect(state.winners).toEqual([1]);
  });

  test("two players: the other is on phase 10 and not down -> keep playing", () => {
    const s = table(2, { phase: [9, 9], scores: [0, 500], hands: [[...TEN], tenHand] });
    const { state, events } = layTen(s);
    expect(state.status).toBe("playing");
    expect(state.endReason).toBeUndefined();
    expect(events.map((e) => e.kind)).toEqual(["laidDown"]);
  });

  test("same phase: a score the other can't catch -> game over, lowest score wins", () => {
    // Seat 0 is down on phase 10 at 300. Seat 1 at 0 can end at most 0 + 2 x 25.
    const s = table(2, {
      phase: [9, 9],
      scores: [300, 0],
      laid: [[set3], null],
      hands: [[tabby(1), tabby(2)], tenHand],
    });
    const { state, events } = layTen(s);
    expect(state.status).toBe("gameOver");
    expect(state.phase).toEqual([10, 10]);
    expect(state.scores).toEqual([310, 35]);
    expect(state.winners).toEqual([1]);
    expect(events.at(-1)).toEqual({ kind: "gameOver", winners: [1], reason: "decided" });
  });

  test("same phase: scores close enough to swap -> keep playing", () => {
    // Seat 1 could still hold 2 Yarn (50) against seat 0's 40.
    const s = table(2, {
      phase: [9, 9],
      scores: [40, 0],
      laid: [[set3], null],
      hands: [[tabby(1), tabby(2)], tenHand],
    });
    const { state } = layTen(s);
    expect(state.status).toBe("playing");
  });

  test("same phase: a discard that settles the scores ends it", () => {
    // Both down on phase 10. Seat 0 at 100 with 3 cards could reach 175, past
    // seat 1's 160; after the discard 2 cards cap it at 150.
    const s = table(2, {
      phase: [9, 9],
      scores: [100, 160],
      laid: [[set3], [set3]],
      turn: 0,
      hands: [[tabby(1), tabby(2), tabby(3)], [tabby(4), tabby(5)]],
    });
    expect(outcomeDecided(s)).toBe(false);

    const { state, events } = ok(applyAction(s, 0, { type: "discard", card: tabby(3) }));
    expect(events.map((e) => e.kind)).toEqual(["discarded", "turn", "roundOver", "gameOver"]);
    expect(state.scores).toEqual([110, 170]);
    expect(state.winners).toEqual([0]);
    expect(state.endReason).toBe("decided");
  });

  test("same phase: a hit that settles the scores ends it", () => {
    const s = table(2, {
      phase: [9, 9],
      scores: [100, 160],
      laid: [[set3], [set3]],
      turn: 0,
      hands: [[tabby(1), tabby(2), 71 + 9], [tabby(4), tabby(5)]],
    });
    const { state, events } = ok(
      applyAction(s, 0, { type: "hit", card: 71 + 9, target: { seat: 1, group: 0 } }),
    );
    expect(events.map((e) => e.kind)).toEqual(["hit", "roundOver", "gameOver"]);
    expect(state.winners).toEqual([0]);
    expect(state.scores).toEqual([110, 170]);
  });

  test("three players: phase 10 down but two others can still swap places -> keep playing", () => {
    const s = table(3, { phase: [3, 9, 3], hands: [[...TEN], tenHand, [...TEN]] });
    const { state } = layTen(s);
    expect(state.status).toBe("playing");
  });

  test("four players: every place already fixed by phase -> game over", () => {
    const s = table(4, { phase: [2, 9, 5, 8], hands: [[...TEN], tenHand, [...TEN], [...TEN]] });
    const { state, events } = layTen(s);
    expect(state.status).toBe("gameOver");
    expect(state.phase).toEqual([2, 10, 5, 8]);
    expect(state.winners).toEqual([1]);
    expect(events.at(-1)).toMatchObject({ reason: "decided" });
  });

  test("four players: two seats a phase apart can still meet -> keep playing", () => {
    // Seat 2 may lay down phase 7 and land level with seat 3, who is not down.
    const s = table(4, { phase: [2, 9, 5, 6], hands: [[...TEN], tenHand, [...TEN], [...TEN]] });
    const { state } = layTen(s);
    expect(state.status).toBe("playing");
  });

  test("nobody down on phase 10 yet -> never ends early", () => {
    // Seat 1 is on phase 10 far ahead, but this hand need not finish the game.
    const s = table(2, { phase: [0, 9], scores: [400, 0], turn: 1 });
    const { state } = ok(applyAction(s, 1, { type: "discard", card: TEN[0] as number }));
    expect(state.status).toBe("playing");
  });

  test("a game that ends by going out carries no reason", () => {
    const s = makeState({ phase: [9, 3, 4] });
    const { state, events } = goOut(s);
    expect(state.endReason).toBeUndefined();
    expect(events.at(-1)).toEqual({ kind: "gameOver", winners: [0] });
  });
});
