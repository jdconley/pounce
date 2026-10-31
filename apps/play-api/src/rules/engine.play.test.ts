import { describe, expect, test } from "vitest";

import { seedOf } from "../../tests/seeds";

import {
  applyAction,
  type Action,
  type ApplyResult,
  type CatTowerState,
  type GameEvent,
} from "./engine";
import { buildGroup, type Group } from "./groups";

/* Card ids: tabby v = v - 1, tuxedo v = 23 + v, calico v = 47 + v, gray v = 71 + v. */
const tabby = (v: number) => v - 1;
const tuxedo = (v: number) => 23 + v;
const calico = (v: number) => 47 + v;
const gray = (v: number) => 71 + v;
const YARN = 96;
const CUCUMBER = 104;

function deepFreeze<T>(value: T): T {
  if (typeof value === "object" && value !== null && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const v of Object.values(value)) deepFreeze(v);
  }
  return value;
}

/** A frozen 3-seat state in seat 0's play step. */
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
      [tabby(5), tuxedo(5), calico(5), tabby(8), tuxedo(8), calico(8), gray(2)],
      [tabby(7), tuxedo(7), calico(7)],
      [tabby(9), tuxedo(10), calico(11)],
    ],
    laid: [null, null, null],
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

const fails = (error: string) => ({ ok: false, error });

const PHASE1: Action = {
  type: "layDown",
  groups: [
    { cards: [tabby(5), tuxedo(5), calico(5)] },
    { cards: [tabby(8), tuxedo(8), calico(8)] },
  ],
};

const group = (g: Group | null): Group => g as Group;
const run4 = group(
  buildGroup({ kind: "run", size: 4 }, [tabby(3), tabby(4), tabby(5), tabby(6)]),
);
const set3 = group(buildGroup({ kind: "set", size: 3 }, [tabby(9), tuxedo(9), calico(9)]));

describe("layDown", () => {
  test("lay down phase 1 with two sets", () => {
    const s = makeState();
    const { state, events } = ok(applyAction(s, 0, PHASE1));
    const groups = [
      group(buildGroup({ kind: "set", size: 3 }, [tabby(5), tuxedo(5), calico(5)])),
      group(buildGroup({ kind: "set", size: 3 }, [tabby(8), tuxedo(8), calico(8)])),
    ];
    expect(state.laid[0]).toEqual(groups);
    expect(state.laid[1]).toBeNull();
    expect(state.hands[0]).toEqual([gray(2)]);
    expect(state.turn).toBe(0);
    expect(state.step).toBe("play");
    expect(state.status).toBe("playing");
    expect(events).toEqual([{ kind: "laidDown", seat: 0, groups }]);
    // The input state is untouched.
    expect(s.hands[0]).toHaveLength(7);
    expect(s.laid[0]).toBeNull();
  });

  test("a run with Yarn honours runStart", () => {
    const s = makeState({
      phase: [3, 0, 0],
      hands: [[tabby(3), tabby(4), YARN, tabby(6), tabby(7), tabby(8), tabby(9), gray(1)], [], []],
    });
    const { state } = ok(
      applyAction(s, 0, {
        type: "layDown",
        groups: [
          { cards: [tabby(3), tabby(4), YARN, tabby(6), tabby(7), tabby(8), tabby(9)], runStart: 3 },
        ],
      }),
    );
    expect(state.laid[0]).toMatchObject([{ kind: "run", start: 3, end: 9 }]);
    expect(state.hands[0]).toEqual([gray(1)]);
  });

  test("lay down wrong phase -> bad_groups", () => {
    const s = makeState();
    const snapshot = structuredClone(s);
    const wrong: Action = {
      type: "layDown",
      groups: [
        { cards: [tabby(5), tuxedo(5), calico(8)] },
        { cards: [tabby(8), tuxedo(8), calico(5)] },
      ],
    };
    expect(applyAction(s, 0, wrong)).toEqual(fails("bad_groups"));
    expect(applyAction(s, 0, { type: "layDown", groups: [] })).toEqual(fails("bad_groups"));
    // Too far along: the seat already finished all ten phases.
    expect(applyAction(makeState({ phase: [10, 0, 0] }), 0, PHASE1)).toEqual(
      fails("bad_groups"),
    );
    expect(s).toEqual(snapshot);
  });

  test("the same card in both groups -> bad_groups", () => {
    const s = makeState();
    const dup: Action = {
      type: "layDown",
      groups: [
        { cards: [tabby(5), tuxedo(5), calico(5)] },
        { cards: [tabby(5), tuxedo(5), calico(5)] },
      ],
    };
    expect(applyAction(s, 0, dup)).toEqual(fails("bad_groups"));
  });

  test("cards not in the hand -> bad_card", () => {
    const s = makeState();
    const foreign: Action = {
      type: "layDown",
      groups: [
        { cards: [tabby(5), tuxedo(5), calico(5)] },
        { cards: [tabby(7), tuxedo(7), calico(7)] }, // seat 1's cards
      ],
    };
    expect(applyAction(s, 0, foreign)).toEqual(fails("bad_card"));
    const unknown: Action = {
      type: "layDown",
      groups: [{ cards: [999] }, { cards: [] }],
    };
    expect(applyAction(s, 0, unknown)).toEqual(fails("bad_card"));
  });

  test("second layDown same round -> already_laid", () => {
    const first = ok(applyAction(makeState(), 0, PHASE1));
    const snapshot = structuredClone(first.state);
    deepFreeze(first.state);
    expect(applyAction(first.state, 0, PHASE1)).toEqual(fails("already_laid"));
    expect(first.state).toEqual(snapshot);
  });

  test("layDown in draw step -> bad_step", () => {
    expect(applyAction(makeState({ step: "draw" }), 0, PHASE1)).toEqual(fails("bad_step"));
  });

  test("layDown out of turn -> not_your_turn", () => {
    expect(applyAction(makeState(), 1, PHASE1)).toEqual(fails("not_your_turn"));
  });

  test("laying down every card goes out", () => {
    const s = makeState({
      hands: [
        [tabby(5), tuxedo(5), calico(5), tabby(8), tuxedo(8), calico(8)],
        [YARN, tabby(1)],
        [calico(12)],
      ],
      scores: [0, 10, 0],
    });
    const { state, events } = ok(applyAction(s, 0, PHASE1));
    expect(state.status).toBe("roundOver");
    expect(state.hands[0]).toEqual([]);
    expect(state.phase).toEqual([1, 0, 0]);
    expect(state.scores).toEqual([0, 40, 10]);
    expect(state.turn).toBe(0);
    expect(events.map((e) => e.kind)).toEqual(["laidDown", "roundOver"]);
    expect(events[1]).toMatchObject({ kind: "roundOver", wentOut: 0, advanced: [0] });
  });
});

describe("hit", () => {
  const laidState = (over: Partial<CatTowerState> = {}) =>
    makeState({
      laid: [[set3], [run4], null],
      hands: [
        [tabby(7), tuxedo(1), YARN],
        [tabby(1)],
        [tabby(2)],
      ],
      ...over,
    });

  test("hit before laying down -> not_laid", () => {
    const s = makeState({ laid: [null, [run4], null] });
    expect(
      applyAction(s, 0, { type: "hit", card: tabby(5), target: { seat: 1, group: 0 } }),
    ).toEqual(fails("not_laid"));
  });

  test("hit onto another player's run extends it", () => {
    const s = laidState();
    const snapshot = structuredClone(s);
    const { state, events } = ok(
      applyAction(s, 0, { type: "hit", card: tabby(7), target: { seat: 1, group: 0 } }),
    );
    const extended = { kind: "run", cards: [...run4.cards, tabby(7)], start: 3, end: 7 };
    expect(state.laid[1]).toEqual([extended]);
    expect(state.laid[0]).toEqual([set3]);
    expect(state.hands[0]).toEqual([tuxedo(1), YARN]);
    expect(state.turn).toBe(0);
    expect(state.step).toBe("play");
    expect(events).toEqual([
      {
        kind: "hit",
        seat: 0,
        card: tabby(7),
        target: { seat: 1, group: 0 },
        group: extended,
      },
    ]);
    expect(s).toEqual(snapshot);
  });

  test("hit invalid card -> bad_target", () => {
    const s = laidState();
    expect(
      applyAction(s, 0, { type: "hit", card: tuxedo(1), target: { seat: 1, group: 0 } }),
    ).toEqual(fails("bad_target"));
  });

  test("hit on a missing seat or group -> bad_target", () => {
    const s = laidState();
    const hitAt = (seat: number, grp: number): Action => ({
      type: "hit",
      card: YARN,
      target: { seat, group: grp },
    });
    expect(applyAction(s, 0, hitAt(2, 0))).toEqual(fails("bad_target")); // not laid
    expect(applyAction(s, 0, hitAt(7, 0))).toEqual(fails("bad_target")); // no such seat
    expect(applyAction(s, 0, hitAt(-1, 0))).toEqual(fails("bad_target"));
    expect(applyAction(s, 0, hitAt(1, 1))).toEqual(fails("bad_target")); // no such group
    expect(applyAction(s, 0, hitAt(1, -1))).toEqual(fails("bad_target"));
  });

  test("hit with a card not in hand -> bad_card", () => {
    const s = laidState();
    expect(
      applyAction(s, 0, { type: "hit", card: tabby(2), target: { seat: 1, group: 0 } }),
    ).toEqual(fails("bad_card"));
  });

  test("hit in the draw step -> bad_step", () => {
    const s = laidState({ step: "draw" });
    expect(
      applyAction(s, 0, { type: "hit", card: YARN, target: { seat: 1, group: 0 } }),
    ).toEqual(fails("bad_step"));
  });

  test("hit last card ends round (status roundOver, wentOut = seat)", () => {
    const s = laidState({
      hands: [[YARN], [tabby(1), calico(2)], [calico(12)]],
      scores: [1, 2, 3],
    });
    const { state, events } = ok(
      applyAction(s, 0, { type: "hit", card: YARN, target: { seat: 0, group: 0 } }),
    );
    expect(state.status).toBe("roundOver");
    expect(state.hands[0]).toEqual([]);
    expect(state.laid[0]).toEqual([{ ...set3, cards: [...set3.cards, YARN] }]);
    expect(state.scores).toEqual([1, 12, 13]);
    expect(events.map((e) => e.kind)).toEqual(["hit", "roundOver"]);
    expect(events[1]).toMatchObject({
      kind: "roundOver",
      wentOut: 0,
      points: [0, 10, 10],
      advanced: [0, 1],
    });
    expect(applyAction(state, 0, { type: "draw", from: "deck" })).toEqual(
      fails("bad_step"),
    );
  });
});

describe("hit after laying down in the same turn", () => {
  test("is allowed", () => {
    const s = makeState({
      hands: [
        [tabby(5), tuxedo(5), calico(5), tabby(8), tuxedo(8), calico(8), gray(5), gray(2)],
        [tabby(7)],
        [tabby(9)],
      ],
    });
    const laid = ok(applyAction(s, 0, PHASE1));
    deepFreeze(laid.state);
    const { state, events } = ok(
      applyAction(laid.state, 0, {
        type: "hit",
        card: gray(5),
        target: { seat: 0, group: 0 },
      }),
    );
    expect(state.laid[0]?.[0]?.cards).toEqual([tabby(5), tuxedo(5), calico(5), gray(5)]);
    expect(state.hands[0]).toEqual([gray(2)]);
    expect(events).toHaveLength(1);
  });
});

describe("discarding the last card", () => {
  test("discarding last card ends round", () => {
    const set7 = group(buildGroup({ kind: "set", size: 3 }, [tabby(7), tuxedo(7), YARN]));
    const s = makeState({
      step: "play",
      laid: [[set7], null, null],
      hands: [[gray(2)], [tabby(1), calico(12)], [YARN]],
    });
    const { state, events } = ok(applyAction(s, 0, { type: "discard", card: gray(2) }));
    expect(state.status).toBe("roundOver");
    expect(state.hands[0]).toEqual([]);
    expect(state.discard).toEqual([tuxedo(9), gray(2)]);
    expect(state.turn).toBe(0);
    expect(state.phase).toEqual([1, 0, 0]);
    expect(events.map((e) => e.kind)).toEqual(["discarded", "roundOver"]);
    expect(events[1]).toMatchObject({
      kind: "roundOver",
      wentOut: 0,
      points: [0, 15, 25],
      advanced: [0],
    });
  });

  test("a final Cucumber is validated but its skip never takes effect", () => {
    const s = makeState({
      hands: [[CUCUMBER], [tabby(1)], [tabby(2)]],
    });
    expect(applyAction(s, 0, { type: "discard", card: CUCUMBER })).toEqual(
      fails("bad_target"),
    );
    const { state, events } = ok(
      applyAction(s, 0, { type: "discard", card: CUCUMBER, skipTarget: 2 }),
    );
    expect(state.status).toBe("roundOver");
    expect(state.pendingSkip).toEqual([false, false, false]);
    expect(events.map((e) => e.kind)).toEqual(["discarded", "roundOver"]);
    expect(events[1]).toMatchObject({ wentOut: 0 });
  });
});
