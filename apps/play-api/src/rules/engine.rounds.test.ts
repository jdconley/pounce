import { describe, expect, test } from "vitest";

import { seedOf } from "../../tests/seeds";

import { applyAction, newGame, type ApplyResult, type CatTowerState, type GameEvent } from "./engine";
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
