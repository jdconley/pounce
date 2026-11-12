import { describe, expect, test } from "vitest";

import { seedOf } from "../../tests/seeds";
import { bell, errorOf, expectSound, feather, fish, makeState, mouse, ok, YARN, YARN2 } from "../../tests/tiles-helpers";

import { activeSeats, applyAction, isOut, newGame, RACK_SIZE, type TilesAction, type TilesState } from "./engine";

const DRAW: TilesAction = { type: "draw" };
const PASS: TilesAction = { type: "pass" };
const play = (table: number[][]): TilesAction => ({ type: "play", table });

describe("newGame", () => {
  test.each([2, 3, 4])("%i seats: 14 pieces each, the rest in the pool, nothing on the table", (seats) => {
    const s = newGame(seats, seedOf(seats));
    expect(s.seats).toBe(seats);
    expect(s.racks).toHaveLength(seats);
    for (const rack of s.racks) expect(rack).toHaveLength(RACK_SIZE);
    expect(s.pool).toHaveLength(106 - 14 * seats);
    expect(s.table).toEqual([]);
    expect(s.boxed).toEqual([]);
    expect(s.status).toBe("playing");
    expect(s.opened).toEqual(new Array(seats).fill(false));
    expect(s.passed).toEqual(new Array(seats).fill(false));
    expect(s.forfeited).toEqual(new Array(seats).fill(false));
    expect(s.scores).toEqual(new Array(seats).fill(0));
    expect(s.winners).toEqual([]);
    expect(s.turns).toBe(0);
    expect(s.endReason).toBeUndefined();
    expect(activeSeats(s)).toHaveLength(seats);
    expect(isOut(s, 0)).toBe(false);
    expectSound(s);
  });

  test("the same seed deals the same game; another seed deals another", () => {
    expect(newGame(3, seedOf(11))).toEqual(newGame(3, seedOf(11)));
    expect(newGame(3, seedOf(11)).racks).not.toEqual(newGame(3, seedOf(12)).racks);
  });

  test("the seed picks who moves first, and every seat gets its share", () => {
    const first = new Set<number>();
    for (let seed = 1; seed <= 40; seed++) {
      const { turn } = newGame(4, seedOf(seed));
      expect([0, 1, 2, 3]).toContain(turn);
      first.add(turn);
    }
    expect(first.size).toBe(4);
  });

  test("the state is plain JSON and holds no seed", () => {
    const s = newGame(4, seedOf(5));
    expect(JSON.parse(JSON.stringify(s))).toEqual(s);
    expect(Object.keys(s)).not.toContain("seed");
  });

  test.each([1, 5, 0, 2.5, Number.NaN])("refuses %s seats", (seats) => {
    expect(() => newGame(seats, seedOf(1))).toThrow(RangeError);
  });

  test("refuses an all-zero seed", () => {
    expect(() => newGame(2, [0, 0, 0, 0])).toThrow(RangeError);
  });
});

describe("draw", () => {
  const state = makeState({ racks: [[fish(1)], [mouse(1)], [bell(1)]] });

  test("moves the pool's next piece to the rack and ends the turn", () => {
    const next = state.pool.at(-1) as number;
    const { state: after, events } = ok(applyAction(state, 0, DRAW));
    expect(after.racks[0]).toEqual([fish(1), next]);
    expect(after.pool).toEqual(state.pool.slice(0, -1));
    expect(after.turn).toBe(1);
    expect(after.turns).toBe(1);
    expect(after.opened[0]).toBe(false);
    expect(events).toEqual([
      { kind: "drew", seat: 0, tile: next, poolCount: state.pool.length - 1 },
      { kind: "turn", seat: 1 },
    ]);
    expectSound(after);
  });

  test("the move goes round the table and back to the first seat", () => {
    let s = state;
    const order: number[] = [];
    for (let i = 0; i < 7; i++) {
      order.push(s.turn);
      s = ok(applyAction(s, s.turn, DRAW)).state;
      expectSound(s);
    }
    expect(order).toEqual([0, 1, 2, 0, 1, 2, 0]);
    expect(s.turns).toBe(7);
  });

  test("only on your turn", () => {
    expect(errorOf(applyAction(state, 1, DRAW))).toBe("not_your_turn");
    expect(errorOf(applyAction(state, 2, DRAW))).toBe("not_your_turn");
    expect(errorOf(applyAction(state, 7, DRAW))).toBe("not_your_turn");
  });

  test("not from an empty pool", () => {
    const dry = makeState({ racks: [[fish(1)], [mouse(1)]], pool: [] });
    expect(errorOf(applyAction(dry, 0, DRAW))).toBe("pool_empty");
  });

  test("the last piece can be drawn, and then the pool is empty", () => {
    const last = makeState({ racks: [[fish(1)], [mouse(1)]], pool: [bell(4)] });
    const { state: after, events } = ok(applyAction(last, 0, DRAW));
    expect(after.pool).toEqual([]);
    expect(events[0]).toEqual({ kind: "drew", seat: 0, tile: bell(4), poolCount: 0 });
    expect(errorOf(applyAction(after, 1, DRAW))).toBe("pool_empty");
    expect(applyAction(after, 1, PASS).ok).toBe(true);
  });
});

describe("pass", () => {
  test("not while the pool has pieces, even one", () => {
    expect(errorOf(applyAction(makeState({ racks: [[fish(1)], [mouse(1)]] }), 0, PASS))).toBe("pool_not_empty");
    expect(errorOf(applyAction(makeState({ racks: [[fish(1)], [mouse(1)]], pool: [bell(4)] }), 0, PASS))).toBe("pool_not_empty");
  });

  test("only on your turn", () => {
    expect(errorOf(applyAction(makeState({ racks: [[fish(1)], [mouse(1)]], pool: [] }), 1, PASS))).toBe("not_your_turn");
  });

  test("with the pool empty: nothing moves, and the turn goes on", () => {
    const dry = makeState({ racks: [[fish(1)], [mouse(1)], [bell(1)]], pool: [] });
    const { state, events } = ok(applyAction(dry, 0, PASS));
    expect(events).toEqual([{ kind: "passed", seat: 0 }, { kind: "turn", seat: 1 }]);
    expect(state.passed).toEqual([true, false, false]);
    expect(state.racks).toEqual(dry.racks);
    expect(state.table).toEqual(dry.table);
    expect(state.turns).toBe(1);
    expect(state.status).toBe("playing");
    expectSound(state);
  });

  test("a player with a move may still pass", () => {
    const run = [fish(9), fish(10), fish(11)];
    const dry = makeState({ racks: [[...run, bell(2)], [mouse(1)]], pool: [] });
    expect(applyAction(dry, 0, PASS).ok).toBe(true);
  });
});

describe("going out", () => {
  const run = [fish(9), fish(10), fish(11)];

  test("the first empty rack wins; the others' racks count against them and for the winner", () => {
    // Seat 1 is left with 5 and a Yarn (35), seat 2 with 12 and 13 (25).
    const before = makeState({ racks: [run, [mouse(5), YARN], [bell(12), bell(13)]] });
    const { state, events } = ok(applyAction(before, 0, play([run])));
    expect(state.status).toBe("gameOver");
    expect(state.winners).toEqual([0]);
    expect(state.endReason).toBe("out");
    expect(state.scores).toEqual([60, -35, -25]);
    expect(events).toEqual([
      { kind: "played", seat: 0, table: [run], placed: run, opened: true },
      { kind: "gameOver", winners: [0], reason: "out", scores: [60, -35, -25], left: [0, 35, 25] },
    ]);
    expect(state.turns).toBe(1);
    expectSound(state);
  });

  test("the other racks stay where they are, hidden", () => {
    const before = makeState({ racks: [run, [mouse(5), YARN]] });
    const { state } = ok(applyAction(before, 0, play([run])));
    expect(state.racks).toEqual([[], [mouse(5), YARN]]);
  });

  test("nothing more can be done in a finished game", () => {
    const over = ok(applyAction(makeState({ racks: [run, [mouse(5)]] }), 0, play([run]))).state;
    for (const action of [DRAW, PASS, play([[1, 2, 3]]), { type: "forfeit" } as const]) {
      expect(errorOf(applyAction(over, 0, action))).toBe("game_over");
      expect(errorOf(applyAction(over, 1, action))).toBe("game_over");
    }
  });

  test("a rack emptied onto a table that already held sets still wins", () => {
    const there = [mouse(5), mouse(6), mouse(7)];
    const before = makeState({ racks: [[mouse(8)], [bell(2)]], table: [there], opened: [true, true] });
    const { state } = ok(applyAction(before, 0, play([[...there, mouse(8)]])));
    expect(state.winners).toEqual([0]);
    expect(state.scores).toEqual([2, -2]);
  });
});

describe("nobody can move: the pool is empty and everyone passes in a row", () => {
  const dry = (racks: number[][], over: Partial<TilesState> = {}) => makeState({ racks, pool: [], ...over });

  test("the lowest rack total wins and collects the others'", () => {
    // 1 + 9 = 10, 13, and a Yarn (30).
    let s = dry([[fish(1), fish(9)], [mouse(13)], [YARN]]);
    s = ok(applyAction(s, 0, PASS)).state;
    s = ok(applyAction(s, 1, PASS)).state;
    expect(s.status).toBe("playing");
    const { state, events } = ok(applyAction(s, 2, PASS));
    expect(events).toEqual([
      { kind: "passed", seat: 2 },
      { kind: "gameOver", winners: [0], reason: "blocked", scores: [33, -13, -30], left: [10, 13, 30] },
    ]);
    expect(state.status).toBe("gameOver");
    expect(state.winners).toEqual([0]);
    expect(state.endReason).toBe("blocked");
    expect(state.scores).toEqual([33, -13, -30]);
    expect(state.turns).toBe(3);
    expectSound(state);
  });

  test("a Yarn on a rack is 30, however low the rest", () => {
    let s = dry([[YARN, fish(1)], [mouse(13), bell(13), feather(4)]]);
    s = ok(applyAction(s, 0, PASS)).state;
    s = ok(applyAction(s, 1, PASS)).state;
    // 31 against 30.
    expect(s.winners).toEqual([1]);
    expect(s.scores).toEqual([-31, 1]);
  });

  test("equal lowest totals share the win, and each collects the rest", () => {
    let s = dry([[fish(7)], [mouse(3), mouse(4)], [bell(9)]]);
    for (const seat of [0, 1, 2]) s = ok(applyAction(s, seat, PASS)).state;
    expect(s.winners).toEqual([0, 1]);
    expect(s.scores).toEqual([2, 2, -9]);
  });

  test("everyone equal: everyone wins, and there is nothing to collect", () => {
    let s = dry([[fish(7)], [mouse(7)]]);
    for (const seat of [0, 1]) s = ok(applyAction(s, seat, PASS)).state;
    expect(s.winners).toEqual([0, 1]);
    expect(s.scores).toEqual([-7, -7]);
  });

  test("the passes must be in a row: a play starts the count again", () => {
    const run = [fish(9), fish(10), fish(11)];
    let s = dry([[mouse(13)], [...run, fish(1)], [bell(2), YARN2]]);
    s = ok(applyAction(s, 0, PASS)).state;
    expect(s.passed).toEqual([true, false, false]);
    s = ok(applyAction(s, 1, play([run]))).state;
    expect(s.passed).toEqual([false, false, false]);
    s = ok(applyAction(s, 2, PASS)).state;
    s = ok(applyAction(s, 0, PASS)).state;
    // Seat 0 has now passed twice, but seat 1 has not passed since its play.
    expect(s.status).toBe("playing");
    const { state } = ok(applyAction(s, 1, PASS));
    expect(state.status).toBe("gameOver");
    expect(state.endReason).toBe("blocked");
    // 1 against 13 and 32.
    expect(state.winners).toEqual([1]);
    expect(state.scores).toEqual([-13, 44, -32]);
    expectSound(state);
  });
});
