import { describe, expect, test } from "vitest";

import { seedOf } from "../../tests/seeds";

import { applyAction, type ApplyResult, type CatTowerState } from "./engine";
import { buildGroup, canHit, type Group, type Requirement } from "./groups";

/*
 * A Yarn in a run keeps the spot the player gave it (spec: "Yarn in a run" in
 * the Cat Tower design). `runStart` wins when sent; without it the cards'
 * order picks the start when that order is a valid run; otherwise the lowest
 * start that fits. Hits then use the run's real start and end.
 *
 * Card ids: tabby v = v - 1, tuxedo v = 23 + v, calico v = 47 + v, gray v = 71 + v.
 */
const tabby = (v: number) => v - 1;
const tuxedo = (v: number) => 23 + v;
const calico = (v: number) => 47 + v;
const gray = (v: number) => 71 + v;
const W = 96;
const W2 = 97;
const RUN4: Requirement = { kind: "run", size: 4 };
const RUN7: Requirement = { kind: "run", size: 7 };

const four = tabby(4);
const five = tuxedo(5);
const six = calico(6);

describe("a Yarn keeps its spot in a run", () => {
  test("at the start: W 4 5 6 stands for 3", () => {
    const want = { kind: "run", cards: [W, four, five, six], start: 3, end: 6 };
    expect(buildGroup(RUN4, [W, four, five, six], 3)).toEqual(want);
    expect(buildGroup(RUN4, [W, four, five, six])).toEqual(want);
  });

  test("at the end: 4 5 6 W stands for 7", () => {
    const want = { kind: "run", cards: [four, five, six, W], start: 4, end: 7 };
    expect(buildGroup(RUN4, [four, five, six, W], 4)).toEqual(want);
    expect(buildGroup(RUN4, [four, five, six, W])).toEqual(want);
  });

  test("in the middle: 4 W 6 7 stands for 5", () => {
    const seven = gray(7);
    const want = { kind: "run", cards: [four, W, six, seven], start: 4, end: 7 };
    expect(buildGroup(RUN4, [four, W, six, seven])).toEqual(want);
    expect(buildGroup(RUN4, [W, four, six, seven])).toEqual(want); // only 5 fits
  });

  test("two Yarns that could go either end keep the player's order", () => {
    expect(buildGroup(RUN4, [W, W2, five, six])).toMatchObject({ start: 3, cards: [W, W2, five, six] });
    expect(buildGroup(RUN4, [W, five, six, W2])).toMatchObject({ start: 4, cards: [W, five, six, W2] });
    expect(buildGroup(RUN4, [five, six, W2, W])).toMatchObject({ start: 5, cards: [five, six, W2, W] });
  });

  test("a long run keeps a Yarn at the end", () => {
    const cards = [tabby(2), tabby(3), tabby(4), tabby(5), tabby(6), tabby(7), W];
    expect(buildGroup(RUN7, cards)).toMatchObject({ start: 2, end: 8, cards });
  });

  test("runStart wins over the order", () => {
    expect(buildGroup(RUN4, [four, five, six, W], 3)).toEqual({
      kind: "run",
      cards: [W, four, five, six],
      start: 3,
      end: 6,
    });
  });

  test("an order that is no run falls back to the lowest start", () => {
    // A Yarn between 4 and 5 stands for nothing: the old default (3) applies.
    expect(buildGroup(RUN4, [four, W, five, six])).toMatchObject({ start: 3, cards: [W, four, five, six] });
    // Shuffled naturals: the old default too.
    expect(buildGroup(RUN4, [six, W, four, five])).toMatchObject({ start: 3, cards: [W, four, five, six] });
    // An order past 12 can't be used: 10 11 12 W must be 9 10 11 12.
    expect(buildGroup(RUN4, [tabby(10), tabby(11), tabby(12), W])).toMatchObject({ start: 9 });
  });
});

describe("hits use the Yarn's real rank", () => {
  const atStart = buildGroup(RUN4, [W, four, five, six]) as Group; // 3-6
  const atEnd = buildGroup(RUN4, [four, five, six, W]) as Group; // 4-7

  test("Yarn at the start (3-6): 2 goes below, 7 above, 3 nowhere", () => {
    expect(canHit(atStart, gray(2))).toEqual({
      ok: true,
      group: { kind: "run", cards: [gray(2), W, four, five, six], start: 2, end: 6 },
    });
    expect(canHit(atStart, gray(7))).toEqual({
      ok: true,
      group: { kind: "run", cards: [W, four, five, six, gray(7)], start: 3, end: 7 },
    });
    expect(canHit(atStart, gray(3))).toEqual({ ok: false });
  });

  test("Yarn at the end (4-7): 3 goes below, 8 above, 7 nowhere", () => {
    expect(canHit(atEnd, gray(3))).toMatchObject({ ok: true, group: { start: 3, end: 7 } });
    expect(canHit(atEnd, gray(8))).toMatchObject({ ok: true, group: { start: 4, end: 8 } });
    expect(canHit(atEnd, gray(7))).toEqual({ ok: false });
  });
});

describe("through the engine", () => {
  function state(over: Partial<CatTowerState> = {}): CatTowerState {
    return {
      seats: 2,
      phase: [1, 1],
      scores: [0, 0],
      round: 1,
      dealer: 1,
      deck: [tabby(1), tabby(2)],
      discard: [tuxedo(9)],
      hands: [
        [tabby(9), tuxedo(9), calico(9), W, four, five, six, gray(7), gray(3), tabby(11)],
        [tabby(12)],
      ],
      laid: [null, null],
      turn: 0,
      step: "play",
      pendingSkip: [false, false],
      status: "playing",
      winners: [],
      seed: seedOf(7),
      rngCalls: 0,
      ...over,
    };
  }
  const ok = (r: ApplyResult) => {
    if (!r.ok) throw new Error(r.error);
    return r.state;
  };
  const nines = { cards: [tabby(9), tuxedo(9), calico(9)] };

  test("a lay-down with the Yarn at the end keeps it there, and hits follow", () => {
    const laid = ok(applyAction(state(), 0, { type: "layDown", groups: [nines, { cards: [four, five, six, W] }] }));
    expect(laid.laid[0]?.[1]).toEqual({ kind: "run", cards: [four, five, six, W], start: 4, end: 7 });
    expect(applyAction(laid, 0, { type: "hit", card: gray(7), target: { seat: 0, group: 1 } })).toMatchObject({
      ok: false,
      error: "bad_target",
    });
    const low = ok(applyAction(laid, 0, { type: "hit", card: gray(3), target: { seat: 0, group: 1 } }));
    expect(low.laid[0]?.[1]).toEqual({ kind: "run", cards: [gray(3), four, five, six, W], start: 3, end: 7 });
  });

  test("a lay-down with the Yarn at the start (as builds in TestFlight send it) keeps it there", () => {
    const laid = ok(
      applyAction(state(), 0, { type: "layDown", groups: [nines, { cards: [W, four, five, six], runStart: 3 }] }),
    );
    expect(laid.laid[0]?.[1]).toEqual({ kind: "run", cards: [W, four, five, six], start: 3, end: 6 });
    const high = ok(applyAction(laid, 0, { type: "hit", card: gray(7), target: { seat: 0, group: 1 } }));
    expect(high.laid[0]?.[1]).toEqual({ kind: "run", cards: [W, four, five, six, gray(7)], start: 3, end: 7 });
  });

  test("a saved game with a run laid the old way still loads and plays", () => {
    // Stored before this change: the server's default put the Yarn low (3-6).
    const saved = JSON.stringify(
      state({
        laid: [
          [
            { kind: "set", cards: [tabby(9), tuxedo(9), calico(9)], value: 9 },
            { kind: "run", cards: [W, four, five, six], start: 3, end: 6 },
          ],
          null,
        ],
        hands: [[gray(7), gray(3), tabby(11)], [tabby(12)]],
      }),
    );
    const loaded = JSON.parse(saved) as CatTowerState;
    expect(applyAction(loaded, 0, { type: "hit", card: gray(3), target: { seat: 0, group: 1 } })).toMatchObject({
      ok: false,
      error: "bad_target",
    });
    const hit = ok(applyAction(loaded, 0, { type: "hit", card: gray(7), target: { seat: 0, group: 1 } }));
    expect(hit.laid[0]?.[1]).toEqual({ kind: "run", cards: [W, four, five, six, gray(7)], start: 3, end: 7 });
  });
});
