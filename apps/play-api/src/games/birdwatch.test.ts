import { expect, test } from "vitest";

import { game, ok } from "../../tests/birdwatch-helpers";
import { applyAction } from "../birdwatch/engine";

import { birdwatch } from "./birdwatch";

test("what a room asks of Birdwatch", () => {
  expect([birdwatch.id, birdwatch.minSeats, birdwatch.maxSeats, birdwatch.leaveTakeover]).toEqual(["birdwatch", 4, 6, true]);
  expect(birdwatch.defaultOptions).toEqual({ rules: "official" });
  expect(birdwatch.create(5, [1, 2, 3, 4], { rules: "friesen" }).rules).toBe("friesen");
  expect(birdwatch.create(4, [1, 2, 3, 4]).rules).toBe("official");
  expect(birdwatch.parseOptions?.({ rules: "tucker" })).toEqual({ rules: "tucker" });
  expect(birdwatch.parseAim({})).toBeNull();
  expect(birdwatch.aimAllowed(game(4), 0, { target: { seat: 0, group: 0 } })).toBe(false);
  expect([birdwatch.betweenAction, birdwatch.forfeitAction]).toEqual([{ type: "nextHand" }, { type: "forfeit" }]);
  expect(birdwatch.progressKind).toBe("score");

  const s = game(6, "official", { scores: [10, -20, 30] });
  expect(birdwatch.progress(s)).toEqual([10, -20, 30, 10, -20, 30]);
  expect(birdwatch.forfeited(s)).toEqual([false, false, false, false, false, false]);
  expect([birdwatch.phase(s), birdwatch.phase({ ...s, phase: "between" }), birdwatch.phase({ ...s, status: "over", phase: "over" })]).toEqual([
    "playing",
    "between",
    "over",
  ]);
  expect(birdwatch.turnKey(s)).toBe("1:0");
  const seat = birdwatch.currentActor(s) as number;
  const { state, events } = ok(applyAction(s, seat, { type: "pass" }));
  expect(birdwatch.turnKey(state)).toBe("1:1");
  expect(events.filter(birdwatch.startsTurn)).toEqual([{ kind: "turn", seat: (seat + 1) % 6 }]);
  expect(birdwatch.endsTurn({ type: "pass" }, events, seat)).toBe(true);
  expect(birdwatch.endsTurn({ type: "nextHand" }, [], 0)).toBe(false);
  expect(birdwatch.endsTurn({ type: "forfeit" }, [], 0)).toBe(false);
  expect(birdwatch.fallbackAction(s, seat)).toEqual({ type: "pass" });
});
