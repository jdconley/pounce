import { expect, test } from "vitest";

import { RULE_SET_IDS, RULE_SETS, type RuleSetId } from "../src/birdwatch/rules";
import { birdwatch } from "../src/games/birdwatch";
import { createRng } from "../src/rules/rng";

import type { BirdState } from "../src/birdwatch/engine";

/**
 * House Cats only, through the module as a room drives it: every rule set at 4, 5 and 6 seats.
 * Every bot action must be accepted (the room's fallback never needed), every game must end, and
 * every hand must count each counter once. `BIRDWATCH_SOAK=<games>` plays more per combination.
 */
const GAMES_EACH = Number(process.env.BIRDWATCH_SOAK ?? 150);
const MAX_HANDS = 300;

function playOut(rules: RuleSetId, seats: number, seed: number): { hands: number; moves: number; slowest: number } {
  const rng = createRng([seed, seats, 77, 1]);
  let s: BirdState = birdwatch.create(seats, [seed, (seed * 2654435761) >>> 0, seats, 9], { rules });
  let moves = 0;
  let slowest = 0;
  while (birdwatch.phase(s) !== "over") {
    if (s.hand > MAX_HANDS) throw new Error(`${rules} ${seats} seed ${seed}: no end after ${MAX_HANDS} hands`);
    const seat = birdwatch.currentActor(s);
    const started = performance.now();
    const action = seat === null ? birdwatch.betweenAction : birdwatch.botAction(s, seat, rng);
    slowest = Math.max(slowest, performance.now() - started);
    const result = birdwatch.apply(s, seat ?? 0, action as NonNullable<typeof action>);
    if (!result.ok) throw new Error(`${rules} ${seats} seed ${seed}: ${JSON.stringify(action)} refused: ${result.error}`);
    for (const e of result.events) {
      if (e.kind !== "handOver") continue;
      const { taken, bidder, partner } = e.result;
      const sides = seats === 5 ? [taken[bidder] as number, taken.find((_, i) => i !== bidder && i !== partner) as number] : taken;
      expect(sides.reduce((a, b) => a + b), `${rules} ${seats} seed ${seed} hand ${e.result.hand}`).toBe(RULE_SETS[rules].total);
    }
    s = result.state;
    moves++;
  }
  expect(s.endReason).toBe("target");
  expect(s.winners.length).toBeGreaterThan(0);
  return { hands: s.hand, moves, slowest };
}

test.each(RULE_SET_IDS.flatMap((rules) => [4, 5, 6].map((seats) => [rules, seats] as const)))(
  "%s at %i seats: House Cats play legal moves to the end of every game",
  (rules, seats) => {
    let hands = 0;
    let slowest = 0;
    for (let seed = 1; seed <= GAMES_EACH; seed++) {
      const r = playOut(rules, seats, seed);
      hands += r.hands;
      slowest = Math.max(slowest, r.slowest);
    }
    // Games last a sensible while: neither a hand or two nor hundreds.
    expect(hands / GAMES_EACH).toBeGreaterThan(2);
    expect(hands / GAMES_EACH).toBeLessThan(40);
    expect(slowest).toBeLessThan(50);
  },
  60_000,
);
