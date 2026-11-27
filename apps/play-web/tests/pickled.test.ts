import { describe, expect, test } from "vitest";

import { NO_PICKLES, pickledSeats, pickleWatch, type PickleWatch } from "../src/table/pickled";

import type { GameEvent } from "@pounce/play-api/rules/engine";

const play = (events: GameEvent[], from: PickleWatch = NO_PICKLES) => events.reduce(pickleWatch, from);
const pickled = (w: PickleWatch, pendingSkip = [false, false, false]) => pickledSeats(pendingSkip, w);

describe("pickled (a Cucumber's target, until the turn it cost them is over)", () => {
  test("waiting for the skip, the server's own word says so", () => {
    expect(pickled(NO_PICKLES, [false, true, false])).toEqual([false, true, false]);
  });

  test("skipped: still pickled through the turn played in its place, then not", () => {
    // Seat 0 pickles seat 1, who is next: the turn goes straight to seat 2.
    const w = play([
      { kind: "discarded", seat: 0, card: 104, skipTarget: 1 },
      { kind: "skipped", seat: 1 },
      { kind: "turn", seat: 2 },
    ]);
    expect(pickled(w)).toEqual([false, true, false]);
    expect(pickled(play([{ kind: "drew", seat: 2, from: "deck" }], w))).toEqual([false, true, false]);
    expect(pickled(play([{ kind: "turn", seat: 0 }], w))).toEqual([false, false, false]);
  });

  test("two players: the pickler's next turn stands in for the one skipped", () => {
    const w = play([{ kind: "skipped", seat: 1 }, { kind: "turn", seat: 0 }]);
    expect(pickledSeats([false, false], w)).toEqual([false, true]);
    expect(pickledSeats([false, false], play([{ kind: "turn", seat: 1 }], w))).toEqual([false, false]);
  });

  test("a new round, the round's end and leaving the game clear it", () => {
    const w = play([{ kind: "skipped", seat: 1 }, { kind: "turn", seat: 2 }]);
    expect(pickled(play([{ kind: "roundOver", wentOut: 2, points: [0, 0, 0], advanced: [], scores: [0, 0, 0], phase: [0, 0, 0] }], w))).toEqual([false, false, false]);
    expect(pickled(play([{ kind: "roundStarted", round: 2, dealer: 0 }], w))).toEqual([false, false, false]);
    expect(pickled(play([{ kind: "forfeited", seat: 1 }], w))).toEqual([false, false, false]);
  });

  test("a round that starts on a Cucumber pickles the first player through the next one's turn", () => {
    const w = play([{ kind: "roundStarted", round: 2, dealer: 0 }, { kind: "skipped", seat: 1 }, { kind: "turn", seat: 2 }]);
    expect(pickled(w)).toEqual([false, true, false]);
  });
});
