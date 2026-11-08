import { describe, expect, test } from "vitest";

import { seedOf } from "../../tests/seeds";
import { chooseAction } from "../bots/house-cat";

import { ALL_CARD_IDS } from "./cards";
import { activeSeats, applyAction, newGame, type Action, type ApplyResult, type CatTowerState, type GameEvent } from "./engine";
import { buildGroup } from "./groups";
import { createRng } from "./rng";
import { viewFor } from "./view";

/* Card ids (see cards.ts): tabby v = v - 1, tuxedo v = 23 + v, calico v = 47 + v, 104-107 = Cucumber. */
const tabby = (v: number) => v - 1;
const tuxedo = (v: number) => 23 + v;
const calico = (v: number) => 47 + v;
const CUCUMBER = 104;

const FORFEIT: Action = { type: "forfeit" };
const DRAW: Action = { type: "draw", from: "deck" };

function deepFreeze<T>(value: T): T {
  if (typeof value === "object" && value !== null && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const v of Object.values(value)) deepFreeze(v);
  }
  return value;
}

/** A frozen state on seat 0's draw, `seats` seats with three cards each; no `forfeited` key, like an older saved game. */
function makeState(seats: number, over: Partial<CatTowerState> = {}): CatTowerState {
  return deepFreeze({
    seats,
    phase: new Array<number>(seats).fill(0),
    scores: new Array<number>(seats).fill(0),
    round: 1,
    dealer: seats - 1,
    deck: [tabby(1), tabby(2), tabby(3), tabby(4)],
    discard: [tuxedo(9)],
    hands: Array.from({ length: seats }, (_, i) => [tabby(5 + i), tuxedo(5 + i), calico(5 + i)]),
    laid: new Array<null>(seats).fill(null),
    turn: 0,
    step: "draw",
    pendingSkip: new Array<boolean>(seats).fill(false),
    status: "playing",
    winners: [],
    seed: seedOf(7),
    rngCalls: 0,
    ...over,
  });
}

function ok(result: ApplyResult): { state: CatTowerState; events: GameEvent[] } {
  if (!result.ok) throw new Error(`expected ok, got ${result.error}`);
  return result;
}

describe("forfeit with one other player", () => {
  test("on your own turn: the game is over and the other player wins", () => {
    const { state, events } = ok(applyAction(makeState(2), 0, FORFEIT));
    expect(events).toEqual([
      { kind: "forfeited", seat: 0 },
      { kind: "gameOver", winners: [1] },
    ]);
    expect(state.status).toBe("gameOver");
    expect(state.winners).toEqual([1]);
    expect(state.forfeited).toEqual([true, false]);
    expect(state.hands[0]).toEqual([]);
  });

  test("on the other player's turn, mid-turn: the same", () => {
    const drawn = ok(applyAction(makeState(2), 0, DRAW)).state;
    const { state, events } = ok(applyAction(drawn, 1, FORFEIT));
    expect(events).toEqual([
      { kind: "forfeited", seat: 1 },
      { kind: "gameOver", winners: [0] },
    ]);
    expect(state.winners).toEqual([0]);
  });

  test("between rounds: the same", () => {
    const { state } = ok(applyAction(makeState(2, { status: "roundOver" }), 1, FORFEIT));
    expect(state.status).toBe("gameOver");
    expect(state.winners).toEqual([0]);
  });

  test("the winner wins whatever the phases and scores say", () => {
    const { state } = ok(applyAction(makeState(2, { phase: [9, 2], scores: [10, 400] }), 0, FORFEIT));
    expect(state.winners).toEqual([1]);
  });
});

describe("forfeit with three or more players", () => {
  test("on your own turn: you're out, your cards leave play and the turn moves on", () => {
    const before = makeState(3);
    const { state, events } = ok(applyAction(before, 0, FORFEIT));
    expect(events).toEqual([
      { kind: "forfeited", seat: 0 },
      { kind: "turn", seat: 1 },
    ]);
    expect(state.status).toBe("playing");
    expect(state.forfeited).toEqual([true, false, false]);
    expect(state.turn).toBe(1);
    expect(state.step).toBe("draw");
    expect(state.hands[0]).toEqual([]);
    // Out of play: not to the discard, not to the deck.
    expect(state.discard).toEqual(before.discard);
    expect(state.deck).toEqual(before.deck);
    expect(activeSeats(state)).toEqual([1, 2]);
  });

  test("after drawing: the drawn card leaves play too", () => {
    const drawn = ok(applyAction(makeState(3), 0, DRAW)).state;
    const { state } = ok(applyAction(drawn, 0, FORFEIT));
    expect(state.hands[0]).toEqual([]);
    expect(state.turn).toBe(1);
    expect(state.step).toBe("draw");
  });

  test("on someone else's turn: their turn goes on, and the turn passes over you after", () => {
    const { state, events } = ok(applyAction(makeState(3), 1, FORFEIT));
    expect(events).toEqual([{ kind: "forfeited", seat: 1 }]);
    expect(state.turn).toBe(0);
    let s = ok(applyAction(state, 0, DRAW)).state;
    const turned = ok(applyAction(s, 0, { type: "discard", card: s.hands[0]?.[0] as number }));
    // Seat 1 is out: no turn and no "skipped".
    expect(turned.events.filter((e) => e.kind !== "discarded")).toEqual([{ kind: "turn", seat: 2 }]);
    s = turned.state;
    expect(s.turn).toBe(2);
  });

  test("a forfeited seat can't play, and can't forfeit again", () => {
    const { state } = ok(applyAction(makeState(3), 1, FORFEIT));
    expect(applyAction(state, 1, FORFEIT)).toEqual({ ok: false, error: "forfeited" });
    expect(applyAction(state, 1, DRAW)).toEqual({ ok: false, error: "not_your_turn" });
  });

  test("when that leaves one player, that player wins", () => {
    const one = ok(applyAction(makeState(3), 2, FORFEIT)).state;
    const { state, events } = ok(applyAction(one, 0, FORFEIT));
    expect(events).toEqual([
      { kind: "forfeited", seat: 0 },
      { kind: "gameOver", winners: [1] },
    ]);
    expect(state.forfeited).toEqual([true, false, true]);
    expect(state.winners).toEqual([1]);
  });

  test("a skip waiting on the forfeiter is dropped", () => {
    const { state } = ok(applyAction(makeState(3, { pendingSkip: [false, true, false] }), 1, FORFEIT));
    expect(state.pendingSkip).toEqual([false, false, false]);
  });

  test("a Cucumber can't skip a forfeited seat", () => {
    const out = ok(applyAction(makeState(3), 1, FORFEIT)).state;
    const drawn = ok(applyAction({ ...out, hands: [[CUCUMBER, tabby(5)], [], out.hands[2] as number[]] }, 0, DRAW)).state;
    expect(applyAction(drawn, 0, { type: "discard", card: CUCUMBER, skipTarget: 1 })).toEqual({
      ok: false,
      error: "bad_target",
    });
    const skipped = ok(applyAction(drawn, 0, { type: "discard", card: CUCUMBER, skipTarget: 2 }));
    // Seat 1 is out and seat 2 is skipped: seat 0 goes again.
    expect(skipped.events.filter((e) => e.kind !== "discarded")).toEqual([
      { kind: "skipped", seat: 2 },
      { kind: "turn", seat: 0 },
    ]);
  });

  test("a Cucumber with only forfeited or skipped seats left needs no target", () => {
    // Seat 2 is already skipped and seat 1 forfeits: nobody is left to aim at.
    const out = ok(applyAction(makeState(3, { pendingSkip: [false, false, true] }), 1, FORFEIT)).state;
    const s = { ...out, hands: [[CUCUMBER, tabby(5)], [], [tabby(9)]] } as CatTowerState;
    const drawn = ok(applyAction(s, 0, DRAW)).state;
    expect(applyAction(drawn, 0, { type: "discard", card: CUCUMBER, skipTarget: 1 })).toEqual({
      ok: false,
      error: "bad_target",
    });
    const { events } = ok(applyAction(drawn, 0, { type: "discard", card: CUCUMBER }));
    expect(events.filter((e) => e.kind !== "discarded")).toEqual([
      { kind: "skipped", seat: 2 },
      { kind: "turn", seat: 0 },
    ]);
  });

  test("their laid groups stay on the table to hit on, but they don't advance or score", () => {
    const set = buildGroup({ kind: "set", size: 3 }, [tabby(7), tuxedo(7), calico(7)]);
    if (!set) throw new Error("bad set");
    const SECOND_TABBY_7 = 7 + 11;
    // Seat 1 laid its phase, then forfeits; seat 0 goes out by hitting on seat 1's set.
    const s = makeState(3, {
      laid: [[set, set], [set, set], null],
      step: "play",
      hands: [[SECOND_TABBY_7], [tabby(12)], [tabby(11)]],
    });
    const out = ok(applyAction(s, 1, FORFEIT)).state;
    const { state, events } = ok(applyAction(out, 0, { type: "hit", card: SECOND_TABBY_7, target: { seat: 1, group: 0 } }));
    expect(state.laid[1]?.[0]?.cards).toContain(SECOND_TABBY_7);
    const roundOver = events.find((e) => e.kind === "roundOver");
    if (roundOver?.kind !== "roundOver") throw new Error("round should be over");
    expect(roundOver.wentOut).toBe(0);
    expect(roundOver.advanced).toEqual([0]);
    expect(roundOver.points[1]).toBe(0);
    expect(state.phase).toEqual([1, 0, 0]);
  });

  test("a forfeited seat on phase 10 can't win", () => {
    const set = buildGroup({ kind: "set", size: 3 }, [tabby(7), tuxedo(7), calico(7)]);
    if (!set) throw new Error("bad set");
    // Seat 1 laid its phase 10 before forfeiting; seat 0 goes out.
    const s = makeState(3, {
      phase: [3, 9, 0],
      laid: [[set, set], [set], null],
      step: "play",
      hands: [[tabby(4)], [tabby(12)], [tabby(11)]],
    });
    const out = ok(applyAction(s, 1, FORFEIT)).state;
    const { state, events } = ok(applyAction(out, 0, { type: "discard", card: tabby(4) }));
    expect(state.status).toBe("roundOver");
    expect(state.phase[1]).toBe(9);
    expect(events.some((e) => e.kind === "gameOver")).toBe(false);
  });

  test("between rounds: the next deal leaves the forfeiter out and the dealer moves to someone still in", () => {
    const over = makeState(3, { status: "roundOver", dealer: 0 });
    const out = ok(applyAction(over, 1, FORFEIT));
    expect(out.events).toEqual([{ kind: "forfeited", seat: 1 }]);
    expect(out.state.status).toBe("roundOver");
    const { state, events } = ok(applyAction(out.state, 0, { type: "nextRound" }));
    // Seat 1 would have dealt; it's out, so seat 2 deals and seat 0 starts.
    expect(state.dealer).toBe(2);
    expect(events[0]).toEqual({ kind: "roundStarted", round: 2, dealer: 2 });
    expect(state.hands.map((h) => h.length)).toEqual([10, 0, 10]);
    expect(state.deck.length + state.discard.length).toBe(ALL_CARD_IDS.length - 20);
    expect(state.turn === 0 || state.turn === 2).toBe(true);
  });

  test("house bots play a whole game around a forfeited seat", () => {
    const rng = createRng(seedOf(11));
    let s = newGame(4, seedOf(3));
    s = ok(applyAction(s, 2, FORFEIT)).state;
    let moves = 0;
    while (s.status !== "gameOver") {
      if (++moves > 20_000) throw new Error("game never ended");
      expect(s.hands[2]).toEqual([]);
      if (s.status === "roundOver") {
        s = ok(applyAction(s, 0, { type: "nextRound" })).state;
        continue;
      }
      expect(s.turn).not.toBe(2);
      s = ok(applyAction(s, s.turn, chooseAction(viewFor(s, [s.turn]), s.turn, rng))).state;
    }
    expect(s.round).toBeGreaterThan(1);
    expect(s.winners.length).toBeGreaterThan(0);
    expect(s.winners).not.toContain(2);
    expect(s.phase[2]).toBe(0);
  });
});

describe("forfeit refused", () => {
  test("once the game is over", () => {
    const { state } = ok(applyAction(makeState(2), 0, FORFEIT));
    expect(applyAction(state, 1, FORFEIT)).toEqual({ ok: false, error: "bad_step" });
  });

  test("from a seat that isn't at the table", () => {
    expect(applyAction(makeState(3), 3, FORFEIT)).toEqual({ ok: false, error: "bad_target" });
    expect(applyAction(makeState(3), -1, FORFEIT)).toEqual({ ok: false, error: "bad_target" });
  });
});

describe("the view", () => {
  test("shows every seat's forfeit, all false in a game saved before forfeits", () => {
    expect(viewFor(makeState(3), [0]).forfeited).toEqual([false, false, false]);
    const { state } = ok(applyAction(makeState(3), 1, FORFEIT));
    const view = viewFor(state, [1]);
    expect(view.forfeited).toEqual([false, true, false]);
    expect(view.hands[1]).toEqual([]);
    expect(view.handCounts[1]).toBe(0);
  });
});
