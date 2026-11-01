import { describe, expect, test } from "vitest";

import { seedOf } from "../../tests/seeds";
import { card, type CardId } from "../rules/cards";
import {
  applyAction,
  newGame,
  type Action,
  type CatTowerState,
} from "../rules/engine";
import { buildGroup, type Group } from "../rules/groups";
import { createRng } from "../rules/rng";
import { viewFor } from "../rules/view";

import { chooseAction } from "./house-cat";

/* Card ids: tabby v = v - 1, tuxedo v = 23 + v, calico v = 47 + v, gray v = 71 + v. */
const tabby = (v: number) => v - 1;
const tuxedo = (v: number) => 23 + v;
const calico = (v: number) => 47 + v;
const gray = (v: number) => 71 + v;
const YARN = 96;
const CUCUMBER = 104;

/** A 3-seat state in seat 0's play step; override anything. */
function makeState(over: Partial<CatTowerState> = {}): CatTowerState {
  return {
    seats: 3,
    phase: [0, 0, 0],
    scores: [0, 0, 0],
    round: 1,
    dealer: 2,
    deck: [tabby(1), tabby(2), tabby(3)],
    discard: [tuxedo(9)],
    hands: [
      [tabby(5), tuxedo(5), calico(5), tabby(8), tuxedo(8), calico(8), gray(2), gray(12)],
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
  };
}

const choose = (state: CatTowerState, seat = state.turn, seed = 1): Action =>
  chooseAction(viewFor(state, [seat]), seat, createRng(seedOf(seed)));

function accepted(state: CatTowerState, action: Action): CatTowerState {
  const result = applyAction(state, state.turn, action);
  if (!result.ok) throw new Error(`rejected: ${result.error}`);
  return result.state;
}

const setOf = (ids: CardId[]) => buildGroup({ kind: "set", size: ids.length }, ids) as Group;
const runOf = (start: number, ids: CardId[]) =>
  buildGroup({ kind: "run", size: ids.length }, ids, start) as Group;

describe("House Cat draw step", () => {
  const drawState = (over: Partial<CatTowerState>) =>
    makeState({
      step: "draw",
      // Three 5s and two 8s: five of the six cards phase 1 needs.
      hands: [
        [tabby(5), tuxedo(5), calico(5), tabby(8), tuxedo(8), gray(2), gray(12)],
        [tabby(7)],
        [tabby(9)],
      ],
      ...over,
    });

  test("takes the discard when it raises phase progress", () => {
    // A third 8 on the discard completes the second set.
    const state = drawState({ discard: [gray(8)] });
    expect(choose(state)).toEqual({ type: "draw", from: "discard" });
  });

  test("draws from the deck when the discard does not help", () => {
    const state = drawState({ discard: [gray(3)] });
    expect(choose(state)).toEqual({ type: "draw", from: "deck" });
  });

  test("never takes a Cucumber from the discard", () => {
    const state = drawState({ discard: [CUCUMBER] });
    expect(choose(state)).toEqual({ type: "draw", from: "deck" });
  });

  test("draws from the deck when the discard is empty", () => {
    const view = viewFor(drawState({ discard: [] }), [0]);
    expect(chooseAction(view, 0, createRng(seedOf(1)))).toEqual({ type: "draw", from: "deck" });
  });

  test("once laid, takes the discard only when it can be hit", () => {
    const laidGroups = { laid: [[setOf([tabby(5), tuxedo(5), calico(5)])], null, null] };
    // A fourth 5 fits the laid set; a 3 would only look like progress.
    expect(choose(drawState({ ...laidGroups, discard: [gray(5)] }))).toEqual({
      type: "draw",
      from: "discard",
    });
    expect(choose(drawState({ ...laidGroups, discard: [gray(3)] }))).toEqual({
      type: "draw",
      from: "deck",
    });
  });

  test("takes a Yarn from the discard while it still fills a gap", () => {
    const state = drawState({ discard: [YARN] });
    expect(choose(state)).toEqual({ type: "draw", from: "discard" });
  });
});

describe("House Cat play step", () => {
  test("bot lays down when possible", () => {
    const state = makeState({
      hands: [
        [tabby(5), tuxedo(5), calico(5), tabby(8), tuxedo(8), YARN, gray(2), gray(12)],
        [tabby(7)],
        [tabby(9)],
      ],
    });
    const action = choose(state);
    expect(action.type).toBe("layDown");
    const after = accepted(state, action);
    expect(after.laid[0]).not.toBeNull();
  });

  test("bot discards cucumber at leader", () => {
    const state = makeState({
      phase: [0, 2, 5],
      hands: [[tabby(1), CUCUMBER, tabby(7), gray(12)], [tabby(2)], [tabby(3)]],
    });
    expect(choose(state)).toEqual({ type: "discard", card: CUCUMBER, skipTarget: 2 });
  });

  test("a Cucumber target tie goes to the seat with fewest cards", () => {
    const state = makeState({
      phase: [0, 3, 3],
      hands: [[tabby(1), CUCUMBER], [tabby(2), tabby(3), tabby(4)], [tabby(3)]],
    });
    expect(choose(state)).toMatchObject({ skipTarget: 2 });
  });

  test("a full Cucumber target tie is broken by the rng", () => {
    const state = makeState({
      phase: [0, 3, 3],
      hands: [[tabby(1), CUCUMBER], [tabby(2)], [tabby(3)]],
    });
    const targets = new Set<unknown>();
    for (let seed = 1; seed <= 40; seed++) {
      const action = choose(state, 0, seed);
      targets.add((action as { skipTarget?: number }).skipTarget);
      expect(choose(state, 0, seed)).toEqual(action);
    }
    expect(targets).toEqual(new Set([1, 2]));
  });

  test("skips seats that are already skipped", () => {
    const state = makeState({
      phase: [0, 5, 1],
      pendingSkip: [false, true, false],
      hands: [[tabby(1), CUCUMBER], [tabby(2)], [tabby(3)]],
    });
    expect(choose(state)).toEqual({ type: "discard", card: CUCUMBER, skipTarget: 2 });
  });

  test("discards a Cucumber with no target when everyone is already skipped", () => {
    const state = makeState({
      pendingSkip: [false, true, true],
      hands: [[tabby(1), CUCUMBER], [tabby(2)], [tabby(3)]],
    });
    const action = choose(state);
    expect(action).toEqual({ type: "discard", card: CUCUMBER });
    accepted(state, action);
  });

  test("discards the card whose removal costs the least progress, then highest points", () => {
    // Pairs of 5s and 8s feed set(3)+set(3); the lone 2, 12 and 1 do not.
    // The 12 is worth more points than the 2 or the 1.
    const state = makeState({
      hands: [
        [tabby(5), tuxedo(5), tabby(8), tuxedo(8), gray(2), gray(12), tabby(1)],
        [tabby(7)],
        [tabby(9)],
      ],
    });
    expect(choose(state)).toEqual({ type: "discard", card: gray(12) });
  });

  test("a points tie among equal discards is broken by the rng", () => {
    const state = makeState({
      hands: [
        [tabby(5), tuxedo(5), tabby(8), tuxedo(8), gray(2), gray(3)],
        [tabby(7)],
        [tabby(9)],
      ],
    });
    const picked = new Set<unknown>();
    for (let seed = 1; seed <= 40; seed++) {
      picked.add((choose(state, 0, seed) as { card: CardId }).card);
    }
    expect(picked).toEqual(new Set([gray(2), gray(3)]));
  });

  test("never discards Yarn while another card is in hand", () => {
    const state = makeState({
      hands: [[YARN, 97, tabby(2), tabby(9)], [tabby(7)], [tabby(9)]],
    });
    const action = choose(state) as { card: CardId };
    expect(card(action.card).kind).toBe("number");
  });

  test("discards Yarn when the hand is all Yarn", () => {
    const state = makeState({
      hands: [[YARN, 97, 98], [tabby(7)], [tabby(9)]],
    });
    const action = choose(state);
    expect(card((action as { card: CardId }).card).kind).toBe("yarn");
    accepted(state, action);
  });

  test("once laid, takes the first hit and a number before Yarn", () => {
    const state = makeState({
      laid: [[setOf([tabby(5), tuxedo(5), calico(5)]), setOf([tabby(8), tuxedo(8), calico(8)])], null, null],
      hands: [[YARN, gray(8), gray(2)], [tabby(7)], [tabby(9)]],
    });
    expect(choose(state)).toEqual({
      type: "hit",
      card: gray(8),
      target: { seat: 0, group: 1 },
    });
  });

  test("once laid, hits an opponent's run", () => {
    const state = makeState({
      laid: [
        [setOf([tabby(5), tuxedo(5), calico(5)])],
        [runOf(3, [tabby(3), tabby(4), tabby(5), tabby(6)])],
        null,
      ],
      hands: [[tuxedo(7), gray(12)], [tabby(7)], [tabby(9)]],
    });
    expect(choose(state)).toEqual({
      type: "hit",
      card: tuxedo(7),
      target: { seat: 1, group: 0 },
    });
  });

  test("once laid with no hits, discards the highest-pointed card", () => {
    const state = makeState({
      laid: [[setOf([tabby(5), tuxedo(5), calico(5)])], null, null],
      hands: [[gray(2), gray(12), tabby(9)], [tabby(7)], [tabby(9)]],
    });
    expect(choose(state)).toEqual({ type: "discard", card: gray(12) });
  });

  test("going out on a hit leaves nothing to discard", () => {
    const state = makeState({
      laid: [[setOf([tabby(5), tuxedo(5), calico(5)])], null, null],
      hands: [[gray(5)], [tabby(7)], [tabby(9)]],
    });
    const action = choose(state);
    expect(action.type).toBe("hit");
    expect(accepted(state, action).status).toBe("roundOver");
  });
});

describe("House Cat is always legal", () => {
  test("bot never returns an action applyAction rejects", () => {
    for (let i = 0; i < 200; i++) {
      const seats = 2 + (i % 5);
      let state = newGame(seats, seedOf(1000 + i));
      const rng = createRng(seedOf(77 + i));
      // Play a pseudo-random number of bot actions to reach a mid-game state.
      const steps = Math.floor(rng() * 400);
      for (let n = 0; n < steps; n++) {
        if (state.status === "gameOver") break;
        if (state.status === "roundOver") {
          state = accepted(state, { type: "nextRound" });
          continue;
        }
        state = accepted(state, choose(state, state.turn, 5 + n));
      }
      if (state.status !== "playing") continue;
      const action = choose(state, state.turn, 9000 + i);
      const result = applyAction(state, state.turn, action);
      expect(result.ok, `game ${i}: ${JSON.stringify(action)}`).toBe(true);
    }
  }, 30_000); // 200 games; the 5 s default is tight under coverage on CI runners
});
