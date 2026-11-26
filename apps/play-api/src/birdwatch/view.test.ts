import { describe, expect, test } from "vitest";

import { game, ok, randomAction } from "../../tests/birdwatch-helpers";
import { createRng } from "../rules/rng";

import { applyAction, newGame, plainAction, actor, type BirdEvent, type BirdState } from "./engine";
import { RULE_SET_IDS } from "./rules";
import { eventFor, viewFor, type BirdView } from "./view";

import type { CardId } from "./cards";

/** Plays `s` forward with random legal actions until `stop` says so. */
function until(s0: BirdState, stop: (s: BirdState) => boolean, seed = 1): BirdState {
  const rng = createRng([seed, 7, 7, 7]);
  let s = s0;
  while (!stop(s)) {
    const { seat, action } = randomAction(s, rng);
    s = ok(applyAction(s, seat, action)).state;
  }
  return s;
}

describe("what a device sees", () => {
  test("its own hands only, and the counts of every hand", () => {
    const s = game(4);
    const v = viewFor(s, [1]);
    expect(Object.keys(v.hands)).toEqual(["1"]);
    expect(v.hands[1]).toEqual(s.hands[1]);
    expect(v.handCounts).toEqual([9, 9, 9, 9]);
    expect(viewFor(s, []).hands).toEqual({});
    expect([v.target, v.minBid, v.maxBid, v.nestSize, v.teams]).toEqual([300, 70, 120, 5, [[0, 2], [1, 3]]]);
  });

  test("the bid range only on its own move while bidding", () => {
    const s = game(4, "tucker");
    const seat = actor(s) as number;
    expect(viewFor(s, [seat]).bidRange).toEqual({ min: 70, max: 180, step: 5 });
    expect(viewFor(s, [(seat + 1) % 4]).bidRange).toBeUndefined();
  });

  test("the nest only to the bid winner, the put-back cards only to them until the hand is scored", () => {
    const nest = until(game(4), (s) => s.phase === "nest");
    const bidder = actor(nest) as number;
    const other = (bidder + 1) % 4;
    expect(viewFor(nest, [bidder]).fromNest).toEqual(nest.fromNest);
    expect(viewFor(nest, [other]).fromNest).toBeUndefined();
    const playing = until(nest, (s) => s.phase === "play");
    expect(viewFor(playing, [bidder]).putBack).toEqual(playing.putBack);
    expect(viewFor(playing, [other]).putBack).toBeUndefined();
    const between = until(playing, (s) => s.phase !== "play");
    expect(viewFor(between, [other]).putBack).toEqual(between.putBack);
  });

  test("the playable cards only on its own move in play", () => {
    const s = until(game(6), (x) => x.phase === "play");
    const seat = actor(s) as number;
    expect(viewFor(s, [seat]).playable).toEqual(s.hands[seat]);
    expect(viewFor(s, [(seat + 1) % 6]).playable).toBeUndefined();
  });

  test("five players: the partner choices to the bid winner, the partner mark to its holder alone", () => {
    const calling = until(game(5, "friesen"), (s) => s.phase === "partner");
    const bidder = actor(calling) as number;
    const choices = viewFor(calling, [bidder]).partnerChoices as CardId[];
    expect(choices).toHaveLength(57 - 10);
    expect(choices.some((c) => calling.hands[bidder]?.includes(c))).toBe(false);
    expect(viewFor(calling, [(bidder + 1) % 5]).partnerChoices).toBeUndefined();

    const s = ok(applyAction(calling, bidder, { type: "partner", card: calling.hands[(bidder + 2) % 5]?.[0] as number })).state;
    const holder = (bidder + 2) % 5;
    expect(viewFor(s, [holder]).youArePartner).toBe(holder);
    for (const seat of [0, 1, 2, 3, 4].filter((x) => x !== holder)) {
      expect(viewFor(s, [seat]).youArePartner).toBeUndefined();
      expect(viewFor(s, [seat]).partner).toBeNull();
    }
    expect(JSON.stringify(viewFor(s, [bidder]))).not.toContain("holder");
  });
});

/** Every key of a view, sorted by whether it can carry a hidden card. Throws on one it doesn't know. */
const OPEN_KEYS = new Set([
  "rules", "seats", "target", "minBid", "maxBid", "nestSize", "teams", "scores", "history", "status", "phase", "hand",
  "dealer", "turn", "handCounts", "bids", "passed", "high", "trump", "called", "partner", "trick", "leader", "lastTrick",
  "played", "points", "tricks", "winners", "bidRange", "endReason", "youArePartner", "partnerChoices",
]);
const CARD_KEYS = new Set(["hands", "playable", "fromNest", "putBack"]);

/** The cards in a view's hidden-capable fields. */
function hiddenCards(v: BirdView): CardId[] {
  const out: CardId[] = [];
  for (const [key, value] of Object.entries(v)) {
    if (key === "hands") out.push(...Object.values(value as Record<string, CardId[]>).flat());
    else if (CARD_KEYS.has(key)) out.push(...(value as CardId[]));
    else if (!OPEN_KEYS.has(key)) throw new Error(`unclassified key: ${key}`);
  }
  return out;
}

describe.each(RULE_SET_IDS)("no leaks, %s", (rules) => {
  test.each([4, 5, 6])("%i players: no view or event shows a card or a partner it may not", (seats) => {
    for (let seed = 1; seed <= 6; seed++) {
      const rng = createRng([seed, 3, 5, 7]);
      let s = newGame(seats, [seed, 9, 9, 9], { rules });
      for (let moves = 0; s.status === "playing" && moves < 400; moves++) {
        const { seat, action } = randomAction(s, rng);
        const before = s;
        const { state, events } = ok(applyAction(s, seat, action));
        s = state;
        for (let device = -1; device < seats; device++) {
          const controlled = device < 0 ? [] : [device];
          const v = viewFor(s, controlled);
          const bidder = s.high?.seat;
          const allowed = new Set<CardId>([
            ...controlled.flatMap((c) => s.hands[c] as CardId[]),
            ...(bidder !== undefined && controlled.includes(bidder) ? [...s.fromNest, ...s.putBack] : []),
            ...(s.history.length >= s.hand ? s.putBack : []),
          ]);
          for (const card of hiddenCards(v)) expect(allowed.has(card), `${rules} ${seats} seat ${device} card ${card}`).toBe(true);
          if (v.partner !== null) expect(s.played.includes(s.called as number) || s.history.length >= s.hand).toBe(true);
          if (v.youArePartner !== undefined) expect(controlled).toContain(s.holder);
          for (const e of events) checkEvent(eventFor(e, controlled), controlled, before);
        }
      }
    }
  });
});

function checkEvent(e: BirdEvent, controlled: number[], before: BirdState): void {
  if (e.kind === "dealt") expect(Object.keys(e.hands).map(Number).every((seat) => controlled.includes(seat))).toBe(true);
  if ((e.kind === "nest" || e.kind === "putBack") && !controlled.includes(e.seat)) expect(e.cards).toBeUndefined();
  if (e.kind === "partner") expect(before.holder).toBe(e.seat);
}

test("a plain action is always legal", () => {
  for (const rules of RULE_SET_IDS) {
    for (const seats of [4, 5, 6]) {
      let s = newGame(seats, [seats, 1, 2, 3], { rules });
      for (let moves = 0; s.status === "playing" && moves < 300; moves++) {
        s = ok(applyAction(s, actor(s) ?? 0, plainAction(s, actor(s) ?? 0))).state;
      }
    }
  }
});

test("events are copies", () => {
  const e: BirdEvent = { kind: "dealt", hand: 1, dealer: 0, handCounts: [1], hands: { 0: [1], 1: [2] } };
  const copy = eventFor(e, [0]);
  expect(copy).toEqual({ ...e, hands: { 0: [1] } });
  expect(eventFor({ kind: "nest", seat: 0, cards: [1] }, [0])).toEqual({ kind: "nest", seat: 0, cards: [1] });
  expect(eventFor({ kind: "putBack", seat: 0, count: 1, cards: [1] }, [1])).toEqual({ kind: "putBack", seat: 0, count: 1 });
});
