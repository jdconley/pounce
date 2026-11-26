import { expect, test } from "vitest";

import { catTower } from "../src/games/cat-tower";
import { card } from "../src/rules/cards";
import { type CatTowerState } from "../src/rules/engine";
import { createRng } from "../src/rules/rng";

import { seedOf } from "./seeds";

const MAX_ROUNDS = 60;
const GAMES = 300;

/**
 * Play one all-bot game through the game module, as a room does (so the House
 * Cats keep their discard log), asserting every action is accepted. Counts the
 * number cards discarded mid-round and how many the next player took.
 */
function playGame(seed: number, seats: number): { state: CatTowerState; rounds: number; discards: number; taken: number } {
  const rng = createRng(seedOf(-seed));
  let state = catTower.create(seats, seedOf(seed));
  let discards = 0;
  let taken = 0;
  let offered = false;
  for (;;) {
    if (state.status === "gameOver" || state.round > MAX_ROUNDS) return { state, rounds: state.round, discards, taken };
    const seat = state.status === "roundOver" ? 0 : state.turn;
    const action =
      state.status === "roundOver"
        ? ({ type: "nextRound" } as const)
        : catTower.botAction(state, seat, rng);
    const result = catTower.apply(state, seat, action);
    if (!result.ok) {
      throw new Error(
        `seed ${seed}: ${JSON.stringify(action)} rejected with ${result.error}`,
      );
    }
    if (action.type === "draw") {
      if (offered && action.from === "discard") taken++;
      offered = false;
    } else if (action.type === "discard") {
      offered = card(action.card).kind === "number" && result.state.status === "playing";
      if (offered) discards++;
    }
    state = result.state;
  }
}

test("300 games of 2-6 House Cats finish with gameOver, no rejected action, under 60 rounds each", () => {
  const roundCounts: number[] = [];
  let discards = 0;
  let taken = 0;
  for (let seed = 1; seed <= GAMES; seed++) {
    const seats = 2 + ((seed - 1) % 5);
    const game = playGame(seed, seats);
    const { state, rounds } = game;
    expect(state.status, `seed ${seed} (${seats} seats) rounds ${rounds}`).toBe("gameOver");
    expect(rounds, `seed ${seed}`).toBeLessThanOrEqual(MAX_ROUNDS);
    expect(state.winners.length).toBeGreaterThan(0);
    roundCounts.push(rounds);
    discards += game.discards;
    taken += game.taken;
  }
  expect(roundCounts).toHaveLength(GAMES);
  // House Cats that ignored the discard log handed the next player a card they took on about
  // 17% of discards; reading the table brings it under 10%.
  expect(taken / discards).toBeLessThan(0.12);
}, 120_000);
