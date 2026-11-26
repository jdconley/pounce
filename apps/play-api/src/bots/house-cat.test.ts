import { describe, expect, test } from "vitest";

import { seedOf } from "../../tests/seeds";
import { card, type CardId } from "../rules/cards";
import {
  applyAction,
  newGame,
  type Action,
  type CatTowerState,
  type DiscardLog,
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

/** A round-1 log in which each listed seat did these things with the discard pile, in order. */
function logOf(bySeat: Record<number, { card: CardId; took: boolean }[]>, seats = 3): DiscardLog {
  return { round: 1, seats: Array.from({ length: seats }, (_, seat) => bySeat[seat] ?? []) };
}
const took = (id: CardId) => ({ card: id, took: true });
const left = (id: CardId) => ({ card: id, took: false });

/** Every card the bot discards from `state` with `log`, over 40 rng seeds. */
function discards(state: CatTowerState, log: DiscardLog): Set<CardId> {
  const out = new Set<CardId>();
  for (let seed = 1; seed <= 40; seed++) {
    const action = chooseAction(viewFor(state, [0]), 0, createRng(seedOf(seed)), log);
    expect(action.type).toBe("discard");
    out.add((action as { card: CardId }).card);
  }
  return out;
}

describe("House Cat reads the table", () => {
  // Seat 0 holds pairs of 5s and 8s toward set(3)+set(3), and two spares worth 5 points each.
  const spares = (a: CardId, b: CardId, over: Partial<CatTowerState> = {}) =>
    makeState({
      hands: [[tabby(5), tuxedo(5), tabby(8), tuxedo(8), a, b], [tabby(1)], [tabby(2)]],
      ...over,
    });

  test("without a log, two equal spares are a coin flip", () => {
    expect(discards(spares(calico(7), gray(2)), logOf({}))).toEqual(new Set([calico(7), gray(2)]));
  });

  test("keeps the 7 when the next player took two 7s from the discard pile", () => {
    const log = logOf({ 1: [took(tabby(7)), took(tuxedo(7))] });
    expect(discards(spares(calico(7), gray(2)), log)).toEqual(new Set([gray(2)]));
  });

  test("keeps a card that fits the run the next player is collecting", () => {
    // Phase 2 is set(3)+run(4); a 4 and a 5 taken make a 6 fit and leave a 10 out.
    const log = logOf({ 1: [took(tabby(4)), took(tuxedo(5))] });
    const state = spares(calico(6), gray(10), { phase: [0, 1, 0] });
    // The 10 is worth more anyway, so check the other way round too: a 9 is just as safe.
    expect(discards(state, log)).toEqual(new Set([gray(10)]));
    expect(discards(spares(calico(6), gray(9), { phase: [0, 1, 0] }), log)).toEqual(new Set([gray(9)]));
  });

  test("keeps a card of the coat the next player is collecting", () => {
    // Phase 8 is seven of one coat.
    const log = logOf({ 1: [took(calico(3)), took(calico(10))] });
    const state = spares(calico(6), gray(9), { phase: [0, 7, 0] });
    expect(discards(state, log)).toEqual(new Set([gray(9)]));
  });

  test("keeps a card the next player could hit once they are laid down", () => {
    // A 10 is worth more, but it goes straight onto seat 1's set of 10s.
    const state = spares(gray(10), gray(3), {
      laid: [null, [setOf([tabby(10), tuxedo(10), calico(10)])], null],
    });
    expect(discards(state, logOf({}))).toEqual(new Set([gray(3)]));
  });

  test("still throws the 7 when every other card is part of its own phase", () => {
    const log = logOf({ 1: [took(tabby(7)), took(tuxedo(7))] });
    const state = makeState({
      hands: [[tabby(5), tuxedo(5), tabby(8), tuxedo(8), calico(7)], [tabby(1)], [tabby(2)]],
    });
    expect(discards(state, log)).toEqual(new Set([calico(7)]));
  });

  test("only the player who draws next matters", () => {
    // Seat 1 collects 7s, seat 2 collects 9s. Seat 1 draws next, unless it is skipped.
    const log = logOf({ 1: [took(tabby(7)), took(tuxedo(7))], 2: [took(tabby(9)), took(tuxedo(9))] });
    expect(discards(spares(calico(7), calico(9)), log)).toEqual(new Set([calico(9)]));
    const skipped = spares(calico(7), calico(9), { pendingSkip: [false, true, false] });
    expect(discards(skipped, log)).toEqual(new Set([calico(7)]));
  });

  test("a value the next player passed up or threw since taking one is the safest to give", () => {
    const passed = logOf({ 1: [took(tabby(7)), took(tuxedo(7)), left(gray(7))] });
    expect(discards(spares(calico(7), gray(2)), passed)).toEqual(new Set([calico(7)]));
    const threw = logOf({ 1: [took(tabby(7)), left(tabby(7))] });
    expect(discards(spares(calico(7), gray(2)), threw)).toEqual(new Set([calico(7)]));
    // Taking one again after passing it up counts again.
    const again = logOf({ 1: [left(gray(7)), took(tabby(7))] });
    expect(discards(spares(calico(7), gray(2)), again)).toEqual(new Set([gray(2)]));
  });

  test("a passed-up value is safe for a run, a passed-up coat for a coat phase", () => {
    const run = logOf({ 1: [took(tabby(4)), took(tuxedo(5)), left(gray(9))] });
    expect(discards(spares(calico(9), gray(11), { phase: [0, 1, 0] }), run)).toEqual(new Set([calico(9)]));
    const coat = logOf({ 1: [took(calico(3)), left(gray(4))] });
    expect(discards(spares(gray(9), tabby(9), { phase: [0, 7, 0] }), coat)).toEqual(new Set([gray(9)]));
  });

  test("a player who finished every phase wants nothing in particular", () => {
    const log = logOf({ 1: [took(tabby(7)), took(tuxedo(7))] });
    expect(discards(spares(calico(7), gray(2), { phase: [0, 10, 0] }), log)).toEqual(new Set([calico(7), gray(2)]));
  });

  test("a log from an earlier round is ignored", () => {
    const old = { ...logOf({ 1: [took(tabby(7)), took(tuxedo(7))] }), round: 0 };
    expect(discards(spares(calico(7), gray(2)), old)).toEqual(new Set([calico(7), gray(2)]));
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
