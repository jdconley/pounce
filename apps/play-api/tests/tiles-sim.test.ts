import { expect, test } from "vitest";

import { tiles } from "../src/games/tiles";
import { createRng } from "../src/rules/rng";
import { rackTotal } from "../src/tiles/pieces";

import { seedOf } from "./seeds";
import { expectSound, piecesIn } from "./tiles-helpers";

import type { TilesEvent, TilesState } from "../src/tiles/engine";

const GAMES = 300;
/**
 * No game can run longer: each turn is a draw (at most 78, the biggest pool), a play (at most 106,
 * one per piece) or a pass, and passes come at most seats - 1 in a row between plays before the
 * game is blocked. The bots finish far inside it.
 */
const MAX_TURNS = 78 + 106 * 4;

type Tally = { turns: number; moves: number; draws: number; ms: number; slowest: number; reason: string };

/** What a device holding `seat` may know of: the table and its own rack. */
function expectNoLeak(state: TilesState, events: readonly TilesEvent[], label: string): void {
  const onTable = new Set(state.table.flat());
  for (let seat = 0; seat < state.seats; seat++) {
    const allowed = new Set([...onTable, ...(state.racks[seat] as number[])]);
    const view = tiles.view(state, [seat]);
    expect(piecesIn(view).every((id) => allowed.has(id)), `${label}: view for seat ${seat}`).toBe(true);
    expect(view.rackCounts, label).toEqual(state.racks.map((rack) => rack.length));
    expect(view.poolCount, label).toBe(state.pool.length);
    for (const event of events) {
      const seen = piecesIn(tiles.filterEvent(event, [seat]));
      expect(seen.every((id) => allowed.has(id)), `${label}: ${event.kind} for seat ${seat}`).toBe(true);
    }
  }
  // A device with no seat sees the table only.
  expect(piecesIn(tiles.view(state, [])).every((id) => onTable.has(id)), `${label}: spectator`).toBe(true);
}

/** Play one all-bot game, checking every action and the state after it. */
function playGame(seed: number, seats: number): Tally {
  const rng = createRng(seedOf(-seed));
  let state = tiles.create(seats, seedOf(seed));
  const tally: Tally = { turns: 0, moves: 0, draws: 0, ms: 0, slowest: 0, reason: "" };
  expectSound(state, `seed ${seed} deal`);
  for (;;) {
    const seat = tiles.currentActor(state);
    if (seat === null) break;
    const label = `seed ${seed} turn ${state.turns}`;
    expect(state.turns, label).toBeLessThan(MAX_TURNS);
    expect(state.forfeited[seat], label).toBe(false);

    const started = performance.now();
    const action = tiles.botAction(state, seat, rng);
    const took = performance.now() - started;
    tally.moves++;
    tally.ms += took;
    tally.slowest = Math.max(tally.slowest, took);

    const result = tiles.apply(state, seat, action);
    if (!result.ok) throw new Error(`${label}: ${JSON.stringify(action)} rejected with ${result.error}`);
    // A bot only passes when it must, and a turn is always a whole turn.
    if (action.type === "pass") expect(state.pool, label).toHaveLength(0);
    if (action.type === "draw") tally.draws++;
    expect(tiles.endsTurn(action, result.events, seat), label).toBe(true);
    expect(result.state.turns, label).toBe(state.turns + 1);
    // Nothing ever returns to a rack: only a draw makes one grow, by one.
    for (let other = 0; other < seats; other++) {
      const grew = (result.state.racks[other] as number[]).length - (state.racks[other] as number[]).length;
      expect(grew, label).toBeLessThanOrEqual(other === seat && action.type === "draw" ? 1 : 0);
    }
    state = result.state;
    expectSound(state, label);
    expectNoLeak(state, result.events, label);
  }

  expect(state.status, `seed ${seed}`).toBe("gameOver");
  expect(state.winners.length, `seed ${seed}`).toBeGreaterThan(0);
  const left = state.racks.map(rackTotal);
  if (state.endReason === "out") {
    expect(state.winners, `seed ${seed}`).toHaveLength(1);
    expect(left[state.winners[0] as number], `seed ${seed}`).toBe(0);
  } else {
    expect(state.endReason, `seed ${seed}`).toBe("blocked");
    expect(state.pool, `seed ${seed}`).toHaveLength(0);
    const least = Math.min(...left);
    expect(state.winners, `seed ${seed}`).toEqual(left.flatMap((total, seat) => (total === least ? [seat] : [])));
  }
  // What the winners collect is exactly what the others lose.
  const lost = state.scores.reduce((sum, score, seat) => sum + (state.winners.includes(seat) ? 0 : -score), 0);
  for (const seat of state.winners) expect(state.scores[seat], `seed ${seed}`).toBe(lost - (left[seat] as number));
  return { ...tally, turns: state.turns, reason: state.endReason as string };
}

test(`${GAMES} games of 2-4 House Cats: every action accepted, every piece accounted for, nothing leaked, all finished`, () => {
  const tallies: Tally[] = [];
  const bySeats = new Map<number, number[]>();
  for (let seed = 1; seed <= GAMES; seed++) {
    const seats = 2 + ((seed - 1) % 3);
    const tally = playGame(seed, seats);
    tallies.push(tally);
    bySeats.set(seats, [...(bySeats.get(seats) ?? []), tally.turns]);
  }
  expect(tallies).toHaveLength(GAMES);
  for (const seats of [2, 3, 4]) expect(bySeats.get(seats)).toHaveLength(GAMES / 3);

  const total = (pick: (t: Tally) => number) => tallies.reduce((sum, t) => sum + pick(t), 0);
  const mean = (values: number[]) => values.reduce((sum, v) => sum + v, 0) / values.length;
  const moves = total((t) => t.moves);
  const report = {
    games: GAMES,
    turnsPerGame: Math.round(total((t) => t.turns) / GAMES),
    turnsPerGameBySeats: Object.fromEntries([...bySeats].map(([seats, turns]) => [seats, Math.round(mean(turns))])),
    longestGame: Math.max(...tallies.map((t) => t.turns)),
    wentOut: tallies.filter((t) => t.reason === "out").length,
    blocked: tallies.filter((t) => t.reason === "blocked").length,
    drawShare: Number((total((t) => t.draws) / moves).toFixed(2)),
    botMoves: moves,
    botMsPerMove: Number((total((t) => t.ms) / moves).toFixed(3)),
    botSlowestMs: Number(Math.max(...tallies.map((t) => t.slowest)).toFixed(2)),
  };
  console.info("tiles soak", JSON.stringify(report));

  // Most games should be won, not run dry; and a bot move must sit far inside a Worker request.
  expect(report.wentOut).toBeGreaterThan(GAMES / 2);
  expect(report.botMsPerMove).toBeLessThan(5);
}, 120_000);
