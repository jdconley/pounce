import { describe, expect, test } from "vitest";

import { seedOf } from "../../tests/seeds";
import { bell, expectSound, feather, fish, makeState, mouse, YARN, YARN2 } from "../../tests/tiles-helpers";
import { createRng } from "../rules/rng";
import { applyAction, type TilesAction, type TilesState } from "../tiles/engine";
import { ALL_TILE_IDS, type TileId } from "../tiles/pieces";
import { readSet } from "../tiles/sets";
import { viewFor } from "../tiles/view";

import { chooseAction } from "./house-cat-tiles";

const OTHER = [bell(1, true), bell(2, true), bell(3, true)];
const DRAW: TilesAction = { type: "draw" };
const PASS: TilesAction = { type: "pass" };

/** A two-seat state on seat 0's turn. */
const seated = (rack: TileId[], table: TileId[][] = [], over: Partial<TilesState> = {}) =>
  makeState({ racks: [rack, OTHER], table, ...over });
const opened = (rack: TileId[], table: TileId[][] = [], over: Partial<TilesState> = {}) =>
  seated(rack, table, { opened: [true, false], ...over });

const choose = (state: TilesState, seed = 1): TilesAction =>
  chooseAction(viewFor(state, [state.turn]), state.turn, createRng(seedOf(seed)));

/** The bot's action, applied: throws if the engine refuses it. */
function after(state: TilesState, seed = 1): TilesState {
  const action = choose(state, seed);
  const result = applyAction(state, state.turn, action);
  if (!result.ok) throw new Error(`rejected: ${JSON.stringify(action)} ${result.error}`);
  expectSound(result.state);
  return result.state;
}

const RUN_30 = [fish(9), fish(10), fish(11)];

describe("before opening", () => {
  test("lays down a set worth exactly 30", () => {
    expect(choose(seated([bell(2), ...RUN_30, mouse(6)]))).toEqual({ type: "play", table: [RUN_30] });
  });

  test("draws while its sets are worth less than 30", () => {
    expect(choose(seated([fish(8), fish(9), fish(10), bell(2), mouse(6)]))).toEqual(DRAW);
  });

  test("draws with no set at all", () => {
    expect(choose(seated([fish(1), mouse(5), bell(9), feather(13)]))).toEqual(DRAW);
  });

  test("passes instead once the pool is empty", () => {
    expect(choose(seated([fish(8), fish(9), fish(10), bell(2)], [], { pool: [] }))).toEqual(PASS);
  });

  test("lays down every set it holds, not just enough for 30", () => {
    const low = [mouse(1), mouse(2), mouse(3)];
    const s = after(seated([...RUN_30, ...low, bell(2)]));
    expect(s.racks[0]).toEqual([bell(2)]);
    expect(s.opened[0]).toBe(true);
  });

  test("adds small sets up to 30", () => {
    const s = after(seated([fish(4), fish(5), fish(6), mouse(5), feather(5), bell(5), bell(2)]));
    expect(s.opened[0]).toBe(true);
    expect(s.racks[0]).toEqual([bell(2)]);
  });

  test("keeps its Yarn when the number pieces reach 30 without it", () => {
    const s = after(seated([...RUN_30, YARN, mouse(6), mouse(7)]));
    expect(s.racks[0]).toEqual([YARN, mouse(6), mouse(7)]);
  });

  test("spends a Yarn on a pair when that is what reaches 30", () => {
    // 4-5-6 is 15; the two 11s with a Yarn add 33.
    const s = after(seated([fish(4), fish(5), fish(6), mouse(11), bell(11), YARN, bell(2)]));
    expect(s.opened[0]).toBe(true);
    expect(s.racks[0]).toEqual([bell(2)]);
  });

  test("stretches a set with a Yarn as a last resort", () => {
    // 8-9-10 is 27; with the Yarn as an 11 it is 38.
    const action = choose(seated([fish(8), fish(9), fish(10), YARN, bell(2)]));
    expect(action).toEqual({ type: "play", table: [[fish(8), fish(9), fish(10), YARN]] });
  });

  test("draws when even its Yarn cannot reach 30", () => {
    expect(choose(seated([fish(1), fish(2), fish(3), YARN, bell(9)]))).toEqual(DRAW);
    expect(choose(seated([fish(1), mouse(5), YARN, YARN2]))).toEqual(DRAW);
  });

  test("leaves every set on the table as it is, even one it could add to", () => {
    const there = [fish(6), fish(7), fish(8)];
    const group = [mouse(2), feather(2), bell(2)];
    const action = choose(seated([...RUN_30, fish(2), mouse(6)], [there, group]));
    // The run 6-7-8 and its own 9-10-11 would join, and the 2 fits the group: not before opening.
    expect(action).toEqual({ type: "play", table: [there, group, RUN_30] });
    const short = choose(seated([fish(9), fish(10), fish(2)], [there, group]));
    expect(short).toEqual(DRAW);
  });
});

describe("after opening", () => {
  const run = [mouse(5), mouse(6), mouse(7)];

  test("lays down a set of any size", () => {
    const low = [fish(1), fish(2), fish(3)];
    expect(choose(opened([...low, bell(9)], [run]))).toEqual({ type: "play", table: [run, low] });
  });

  test("adds single pieces to the sets on the table", () => {
    const nines = [fish(9), mouse(9), bell(9)];
    const s = after(opened([mouse(8), mouse(4), feather(9), bell(12)], [run, nines]));
    expect(s.racks[0]).toEqual([bell(12)]);
    expect(s.table).toEqual([[mouse(4), ...run, mouse(8)], [...nines, feather(9)]]);
  });

  test("adds to the sets it has just laid down, too", () => {
    const s = after(opened([fish(1), fish(2), fish(3), fish(4, true), bell(12)], [run]));
    expect(s.racks[0]).toEqual([bell(12)]);
  });

  test("splits a long run around a twin", () => {
    const long = [fish(3), fish(4), fish(5), fish(6), fish(7)];
    const s = after(opened([fish(5, true), bell(12)], [long]));
    expect(s.table).toEqual([[fish(3), fish(4), fish(5)], [fish(5, true), fish(6), fish(7)]]);
  });

  test("borrows a spare piece from the table to finish a pair", () => {
    const fours = [fish(4), mouse(4), feather(4), bell(4)];
    const s = after(opened([feather(5), feather(6), bell(12)], [fours]));
    expect(s.racks[0]).toEqual([bell(12)]);
    expect(s.table).toHaveLength(2);
  });

  test("spends a Yarn to finish a pair", () => {
    const s = after(opened([fish(11), bell(11), YARN, bell(2)], [run]));
    expect(s.racks[0]).toEqual([bell(2)]);
  });

  test("keeps a spare Yarn while it has other pieces and the pool has more", () => {
    const s = after(opened([mouse(8), YARN, bell(12)], [run]));
    expect(s.racks[0]).toEqual([YARN, bell(12)]);
  });

  test("plays the Yarn when it is all that is left, and wins", () => {
    const s = after(opened([mouse(8), YARN], [run]));
    expect(s.status).toBe("gameOver");
    expect(s.winners).toEqual([0]);
  });

  test("plays both Yarn to go out", () => {
    const s = after(opened([YARN, YARN2], [run, [fish(1), fish(2), fish(3)]]));
    expect(s.winners).toEqual([0]);
  });

  test("gets rid of a Yarn once the pool is empty, whatever else it holds", () => {
    const s = after(opened([YARN, bell(12)], [run], { pool: [] }));
    expect(s.racks[0]).toEqual([bell(12)]);
    expect(s.table).toEqual([[...run, YARN]]);
  });

  test("holds a Yarn that has nowhere to go", () => {
    const full = [fish(9), mouse(9), feather(9), bell(9)];
    expect(choose(opened([YARN], [full]))).toEqual(DRAW);
  });

  test("draws with nothing to put down, and passes once the pool is empty", () => {
    expect(choose(opened([bell(12), fish(1)], [run]))).toEqual(DRAW);
    expect(choose(opened([bell(12), fish(1)], [run], { pool: [] }))).toEqual(PASS);
  });

  test("works on an empty table", () => {
    expect(choose(opened([bell(12), fish(1)]))).toEqual(DRAW);
    expect(choose(opened([fish(1), fish(2), fish(3)]))).toEqual({ type: "play", table: [[fish(1), fish(2), fish(3)]] });
  });
});

describe("after opening: building the table again", () => {
  const fives = [fish(5), mouse(5), bell(5)];
  const sixes = [fish(6), mouse(6), bell(6)];
  const sevens = [fish(7), mouse(7), bell(7)];

  test("turns three groups into three runs to make room for pieces no group had room for", () => {
    // Neither the fish 8 nor the mouse 4 fits a group; they fit the runs 5-6-7 the groups can become.
    const s = after(opened([fish(8), mouse(4), bell(12)], [fives, sixes, sevens]));
    expect(s.racks[0]).toEqual([bell(12)]);
    expect(s.table).toHaveLength(3);
    expect(s.table.flat()).toHaveLength(11);
  });

  test("goes out that way, a spare Yarn included", () => {
    const s = after(opened([fish(8), mouse(4), YARN], [fives, sixes, sevens]));
    expect(s.winners).toEqual([0]);
  });

  test("still keeps a spare Yarn back while other pieces are left", () => {
    const s = after(opened([fish(8), mouse(4), bell(12), YARN], [fives, sixes, sevens]));
    expect(s.racks[0]).toEqual([bell(12), YARN]);
  });

  test("takes a Yarn on the table along", () => {
    const s = after(opened([fish(8), mouse(4), bell(12)], [[...fives, YARN], sixes, sevens]));
    expect(s.racks[0]).toEqual([bell(12)]);
    expect(s.table.flat()).toContain(YARN);
  });

  test("gives up when a piece from the table would be left over", () => {
    // Rebuilt runs first, 3-4-5 would use the group's fish 5 and strand its other two.
    expect(choose(opened([fish(3), fish(4)], [fives]))).toEqual(DRAW);
  });

  test("gives up when a Yarn from the table would be left over", () => {
    // Rebuilt, the four 9s leave the Yarn nowhere to go; the plain move still works.
    const s = after(opened([bell(9), mouse(2)], [[fish(9), mouse(9), feather(9), YARN], [fish(1), fish(2), fish(3)]]));
    expect(s.racks[0]).toEqual([mouse(2)]);
  });
});

describe("choosing between runs first and groups first", () => {
  test("takes runs first when that puts down more", () => {
    const s = after(opened([fish(3), fish(4), fish(5), fish(6), mouse(5), bell(5)]));
    expect(s.table).toEqual([[fish(3), fish(4), fish(5), fish(6)]]);
  });

  test("takes groups first when that puts down more", () => {
    const s = after(opened([fish(3), fish(4), fish(5), mouse(5), bell(5), mouse(3), bell(3)]));
    expect(s.racks[0]).toEqual([fish(4)]);
  });

  test("lets the rng settle a tie, and nothing else", () => {
    const state = opened([fish(3), fish(4), fish(5), mouse(5), bell(5)]);
    const view = viewFor(state, [0]);
    expect(chooseAction(view, 0, () => 0.1)).toEqual({ type: "play", table: [[fish(3), fish(4), fish(5)]] });
    expect(chooseAction(view, 0, () => 0.9)).toEqual({ type: "play", table: [[fish(5), mouse(5), bell(5)]] });
  });

  test("the same seed makes the same move", () => {
    const state = opened([fish(3), fish(4), fish(5), mouse(5), bell(5)]);
    for (const seed of [1, 2, 3, 4]) expect(choose(state, seed)).toEqual(choose(state, seed));
  });
});

describe("a House Cat sees only its own view", () => {
  test("it never changes the view it is given", () => {
    const state = opened([mouse(8), mouse(4), bell(12)], [[mouse(5), mouse(6), mouse(7)]]);
    const view = viewFor(state, [0]);
    const copy = structuredClone(view);
    chooseAction(view, 0, createRng(seedOf(1)));
    expect(view).toEqual(copy);
  });
});

describe("speed", () => {
  test("the biggest rack a game can hold, against a crowded table, takes a few milliseconds", () => {
    // Two seats: 14 dealt and all 78 from the pool is the most one rack can ever hold. Here: 53
    // pieces on the rack and every other piece on the table.
    const table: TileId[][] = [];
    for (let suit = 0; suit < 3; suit++) {
      for (const start of [1, 5, 9]) table.push([0, 1, 2, 3].map((i) => suit * 26 + start - 1 + i));
    }
    const rack = ALL_TILE_IDS.filter((id) => !table.flat().includes(id) && !OTHER.includes(id)).slice(0, 53);
    const state = opened(rack, table, { pool: [] });
    for (const set of table) expect(readSet(set)).not.toBeNull();
    const view = viewFor(state, [0]);
    let fastest = Infinity;
    for (let i = 0; i < 5; i++) {
      const start = performance.now();
      chooseAction(view, 0, createRng(seedOf(i + 1)));
      fastest = Math.min(fastest, performance.now() - start);
    }
    // A Worker request has far more than this; the budget for a bot move is 50 ms.
    expect(fastest).toBeLessThan(50);
    after(state);
  });
});
