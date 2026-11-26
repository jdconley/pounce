import { describe, expect, test } from "vitest";

import { bell, errorOf, feather, fish, game, inPlay, mouse, ok } from "../../tests/birdwatch-helpers";

import { BIRD } from "./cards";
import { actor, applyAction, type BirdState } from "./engine";

/**
 * Four players, official, trump fish, one trick left: seat 0 takes it with the 14 (35 in it), and
 * the put-back cards hold 40 more. 45 was taken before it, 25 by seat 0 and 20 by seat 1: 120 in all.
 */
function lastTrick(bid: number, scores = [0, 0]): BirdState {
  return inPlay({
    hands: [[fish(14)], [fish(5)], [fish(10)], [mouse(10)]],
    trump: "fish",
    bid,
    over: { points: [25, 20, 0, 0], scores, putBack: [bell(5), bell(10), feather(14), mouse(14), feather(5)].sort((a, b) => a - b) },
  });
}

function playOut(s: BirdState) {
  let state = s;
  const events = [];
  while (state.phase === "play") {
    const seat = actor(state) as number;
    const r = ok(applyAction(state, seat, { type: "play", card: (state.hands[seat] as number[])[0] as number }));
    state = r.state;
    events.push(...r.events);
  }
  return { state, events };
}

describe("scoring a hand", () => {
  test("the put-back cards go to the last trick, and a side that made its bid scores what it took", () => {
    const { state, events } = playOut(lastTrick(90));
    const result = { hand: 1, bidder: 0, bid: 90, partner: null, trump: "fish", made: true, taken: [100, 20], change: [100, 20], totals: [100, 20] };
    expect(events.at(-1)).toEqual({ kind: "handOver", result, putBack: [bell(5), bell(10), feather(5), feather(14), mouse(14)].sort((a, b) => a - b) });
    expect(state.history).toEqual([result]);
    expect([state.phase, actor(state)]).toEqual(["between", null]);
    // Every counter is counted once, by one side.
    expect(result.taken.reduce((a, b) => a + b)).toBe(120);
  });

  test("a side that missed loses its bid; the others still score what they took", () => {
    const { state } = playOut(lastTrick(105));
    expect(state.history[0]).toMatchObject({ made: false, taken: [100, 20], change: [-105, 20], totals: [-105, 20] });
  });

  test("the next hand deals itself left of the last dealer", () => {
    const { state } = playOut(lastTrick(90));
    expect(errorOf(applyAction(state, 0, { type: "pass" }))).toBe("not_your_turn");
    const { state: next, events } = ok(applyAction(state, 0, { type: "nextHand" }));
    expect([next.hand, next.dealer, next.phase, actor(next)]).toEqual([2, (state.dealer + 1) % 4, "bidding", (state.dealer + 2) % 4]);
    expect(events.map((e) => e.kind)).toEqual(["dealt", "turn"]);
    expect(next.scores).toEqual([100, 20]);
    expect(next.points).toEqual([0, 0, 0, 0]);
  });
});

describe("winning", () => {
  test("a side at the target wins, the highest one when both are", () => {
    const { state, events } = playOut(lastTrick(90, [250, 290]));
    expect([state.status, state.phase, state.winners, state.endReason]).toEqual(["over", "over", [0, 2], "target"]);
    expect(events.at(-1)).toEqual({ kind: "gameOver", winners: [0, 2], scores: [350, 310], reason: "target" });
    expect(errorOf(applyAction(state, 0, { type: "nextHand" }))).toBe("game_over");
  });

  test("a tie for the highest plays another hand", () => {
    expect(playOut(lastTrick(90, [250, 330])).state.phase).toBe("between");
  });

  test("a side that missed its bid can't win on that hand", () => {
    expect(playOut(lastTrick(105, [450, 250])).state.phase).toBe("between");
    const { state } = playOut(lastTrick(105, [450, 290]));
    expect([state.scores, state.winners]).toEqual([[345, 310], [1, 3]]);
  });
});

describe("five players", () => {
  /** Seat 0 won at 70; nothing left to take but the last trick, which seat 0 wins with no counters in it. */
  function fiveLast(holder: number | null): BirdState {
    return inPlay({
      seats: 5,
      hands: [[fish(13)], [fish(6)], [fish(7)], [fish(8)], [fish(9)]],
      trump: "fish",
      over: { points: [50, 30, 20, 10, 10], putBack: [bell(6), bell(7), bell(8)], called: BIRD, holder, partner: holder },
    });
  }

  test("the bid winner and the partner each score their side; everyone else scores what the other side took", () => {
    const { state } = playOut(fiveLast(2));
    expect(state.history[0]).toMatchObject({ partner: 2, made: true, taken: [70, 50, 70, 50, 50], change: [70, 50, 70, 50, 50] });
    expect(state.scores).toEqual([70, 50, 70, 50, 50]);
  });

  test("with the called card put back, the bid winner plays alone, which the hand's end reveals", () => {
    const { state, events } = playOut(fiveLast(null));
    expect(state.history[0]).toMatchObject({ partner: null, made: false, taken: [50, 70, 70, 70, 70], change: [-70, 70, 70, 70, 70] });
    expect(events.at(-1)).toMatchObject({ kind: "handOver", putBack: [bell(6), bell(7), bell(8)] });
  });

  test("a missed bid keeps the partner from winning too", () => {
    const s = fiveLast(2);
    const { state } = playOut({ ...s, high: { seat: 0, amount: 100 }, scores: [600, 50, 600, 480, 0] });
    // 0 and 2 missed; 3 reached 530 and wins alone.
    expect([state.scores, state.winners]).toEqual([[500, 100, 500, 530, 50], [3]]);
  });
});

test("the room ends a game nobody is left at", () => {
  const { state, events } = ok(applyAction(game(4), 2, { type: "forfeit" }));
  expect([state.status, state.phase, state.winners, state.endReason]).toEqual(["over", "over", [], "left"]);
  expect(events).toEqual([{ kind: "gameOver", winners: [], scores: [0, 0], reason: "left" }]);
});
