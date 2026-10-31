import { expect, test } from "vitest";

import { chooseAction } from "../src/bots/house-cat";
import { applyAction, newGame, type CatTowerState } from "../src/rules/engine";
import { createRng } from "../src/rules/rng";
import { viewFor } from "../src/rules/view";

import { seedOf } from "./seeds";

const MAX_ROUNDS = 60;
const GAMES = 300;

/** Play one all-bot game, asserting every action is accepted. */
function playGame(seed: number, seats: number): { state: CatTowerState; rounds: number } {
  const rng = createRng(seedOf(-seed));
  let state = newGame(seats, seedOf(seed));
  for (;;) {
    if (state.status === "gameOver") return { state, rounds: state.round };
    if (state.round > MAX_ROUNDS) return { state, rounds: state.round };
    const seat = state.status === "roundOver" ? 0 : state.turn;
    const action =
      state.status === "roundOver"
        ? ({ type: "nextRound" } as const)
        : chooseAction(viewFor(state, [seat]), seat, rng);
    const result = applyAction(state, seat, action);
    if (!result.ok) {
      throw new Error(
        `seed ${seed}: ${JSON.stringify(action)} rejected with ${result.error}`,
      );
    }
    state = result.state;
  }
}

test("300 games of 2-6 House Cats finish with gameOver, no rejected action, under 60 rounds each", () => {
  const roundCounts: number[] = [];
  for (let seed = 1; seed <= GAMES; seed++) {
    const seats = 2 + ((seed - 1) % 5);
    const { state, rounds } = playGame(seed, seats);
    expect(state.status, `seed ${seed} (${seats} seats) rounds ${rounds}`).toBe("gameOver");
    expect(rounds, `seed ${seed}`).toBeLessThanOrEqual(MAX_ROUNDS);
    expect(state.winners.length).toBeGreaterThan(0);
    roundCounts.push(rounds);
  }
  expect(roundCounts).toHaveLength(GAMES);
}, 120_000);
