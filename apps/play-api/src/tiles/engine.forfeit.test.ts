import { describe, expect, test } from "vitest";

import { bell, errorOf, expectSound, feather, fish, makeState, mouse, ok, YARN } from "../../tests/tiles-helpers";

import { activeSeats, applyAction, isOut, type TilesAction, type TilesState } from "./engine";
import { viewFor } from "./view";

const FORFEIT: TilesAction = { type: "forfeit" };
const DRAW: TilesAction = { type: "draw" };
const PASS: TilesAction = { type: "pass" };
const play = (table: number[][]): TilesAction => ({ type: "play", table });

const RACKS = [
  [fish(9), fish(10), fish(11), fish(1)],
  [mouse(5), mouse(6), YARN],
  [bell(12), bell(13)],
  [feather(2), feather(4)],
];
const seats = (n: number, over: Partial<TilesState> = {}) => makeState({ racks: RACKS.slice(0, n), ...over });

describe("forfeit with one other player", () => {
  test("on your own turn: the game is over and the other player wins", () => {
    const { state, events } = ok(applyAction(seats(2), 0, FORFEIT));
    expect(events).toEqual([
      { kind: "forfeited", seat: 0 },
      { kind: "gameOver", winners: [1], reason: "forfeit", scores: [0, 0], left: [0, 41] },
    ]);
    expect(state.status).toBe("gameOver");
    expect(state.winners).toEqual([1]);
    expect(state.endReason).toBe("forfeit");
    expect(state.forfeited).toEqual([true, false]);
    expect(viewFor(state, [1]).endReason).toBe("forfeit");
  });

  test("on the other player's turn: the same", () => {
    const { state } = ok(applyAction(seats(2), 1, FORFEIT));
    expect(state.winners).toEqual([0]);
    expect(state.endReason).toBe("forfeit");
  });

  test("nobody scores: the winner did not go out", () => {
    const { state } = ok(applyAction(seats(2), 0, FORFEIT));
    expect(state.scores).toEqual([0, 0]);
  });

  test("the forfeited rack is set aside, not returned to the pool or left on the rack", () => {
    const before = seats(2);
    const { state } = ok(applyAction(before, 0, FORFEIT));
    expect(state.racks[0]).toEqual([]);
    expect(state.boxed).toEqual(RACKS[0]);
    expect(state.pool).toEqual(before.pool);
    expectSound(state);
  });
});

describe("forfeit with two or more other players", () => {
  test("on someone else's turn: the seat is out, the game goes on and the move stays put", () => {
    const { state, events } = ok(applyAction(seats(3), 2, FORFEIT));
    expect(events).toEqual([{ kind: "forfeited", seat: 2 }]);
    expect(state.status).toBe("playing");
    expect(state.turn).toBe(0);
    expect(state.turns).toBe(0);
    expect(state.forfeited).toEqual([false, false, true]);
    expect(isOut(state, 2)).toBe(true);
    expect(activeSeats(state)).toEqual([0, 1]);
    expect(state.racks[2]).toEqual([]);
    expect(state.boxed).toEqual(RACKS[2]);
    expectSound(state);
  });

  test("on your own turn: the move goes to the next seat, and it was not a turn", () => {
    const { state, events } = ok(applyAction(seats(3), 0, FORFEIT));
    expect(events).toEqual([{ kind: "forfeited", seat: 0 }, { kind: "turn", seat: 1 }]);
    expect(state.turn).toBe(1);
    expect(state.turns).toBe(0);
  });

  test("the move skips a seat that is out, every time round", () => {
    let s = ok(applyAction(seats(4), 2, FORFEIT)).state;
    const order: number[] = [];
    for (let i = 0; i < 6; i++) {
      order.push(s.turn);
      s = ok(applyAction(s, s.turn, DRAW)).state;
      expectSound(s);
    }
    expect(order).toEqual([0, 1, 3, 0, 1, 3]);
  });

  test("the move skips two seats that are out, and wraps past the last seat", () => {
    let s = seats(4, { turn: 1 });
    s = ok(applyAction(s, 2, FORFEIT)).state;
    s = ok(applyAction(s, 3, FORFEIT)).state;
    expect(s.status).toBe("playing");
    s = ok(applyAction(s, 1, DRAW)).state;
    expect(s.turn).toBe(0);
    s = ok(applyAction(s, 0, DRAW)).state;
    expect(s.turn).toBe(1);
  });

  test("when that leaves one seat in, that seat wins", () => {
    let s = ok(applyAction(seats(3), 2, FORFEIT)).state;
    const { state, events } = ok(applyAction(s, 0, FORFEIT));
    s = state;
    expect(events).toEqual([
      { kind: "forfeited", seat: 0 },
      { kind: "gameOver", winners: [1], reason: "forfeit", scores: [0, 0, 0], left: [0, 41, 0] },
    ]);
    expect(s.winners).toEqual([1]);
    expect(s.boxed).toEqual([...(RACKS[2] as number[]), ...(RACKS[0] as number[])]);
    expectSound(s);
  });

  test("the pieces a seat already played stay on the table for the others", () => {
    const run = [fish(9), fish(10), fish(11)];
    let s = ok(applyAction(seats(3), 0, play([run]))).state;
    s = ok(applyAction(s, 0, FORFEIT)).state;
    expect(s.table).toEqual([run]);
    expect(s.boxed).toEqual([fish(1)]);
    expect(s.turn).toBe(1);
    expectSound(s);
  });

  test("a seat that is out is not charged and its pieces count for nobody", () => {
    const run = [fish(9), fish(10), fish(11)];
    // Seat 1 (41 on its rack) forfeits; seat 0 then goes out; seat 2 holds 25.
    let s = seats(3, { racks: [run, RACKS[1] as number[], RACKS[2] as number[]] });
    s = ok(applyAction(s, 1, FORFEIT)).state;
    const { state, events } = ok(applyAction(s, 0, play([run])));
    expect(state.winners).toEqual([0]);
    expect(state.scores).toEqual([25, 0, -25]);
    expect(events.at(-1)).toEqual({ kind: "gameOver", winners: [0], reason: "out", scores: [25, 0, -25], left: [0, 0, 25] });
  });

  test("a seat that is out never wins a blocked game, though its empty rack is the lowest", () => {
    let s = seats(3, { pool: [] });
    s = ok(applyAction(s, 2, FORFEIT)).state;
    s = ok(applyAction(s, 0, PASS)).state;
    s = ok(applyAction(s, 1, PASS)).state;
    expect(s.status).toBe("gameOver");
    expect(s.endReason).toBe("blocked");
    // 31 against 41.
    expect(s.winners).toEqual([0]);
    expect(s.scores).toEqual([10, -41, 0]);
  });
});

describe("forfeit while everyone is passing", () => {
  test("the last seat yet to pass forfeits on its turn: everyone left has passed, so the game ends", () => {
    let s = seats(3, { pool: [] });
    s = ok(applyAction(s, 0, PASS)).state;
    s = ok(applyAction(s, 1, PASS)).state;
    const { state, events } = ok(applyAction(s, 2, FORFEIT));
    expect(events).toEqual([
      { kind: "forfeited", seat: 2 },
      { kind: "gameOver", winners: [0], reason: "blocked", scores: [10, -41, 0], left: [31, 41, 0] },
    ]);
    expect(state.status).toBe("gameOver");
  });

  test("a seat that passed and then forfeits does not stand in for the one still to move", () => {
    let s = seats(3, { pool: [] });
    s = ok(applyAction(s, 0, PASS)).state;
    s = ok(applyAction(s, 1, PASS)).state;
    s = ok(applyAction(s, 0, FORFEIT)).state;
    expect(s.status).toBe("playing");
    expect(s.turn).toBe(2);
    expect(s.passed).toEqual([false, true, false]);
    s = ok(applyAction(s, 2, PASS)).state;
    expect(s.status).toBe("gameOver");
    // 41 against 25.
    expect(s.winners).toEqual([2]);
  });
});

describe("who may forfeit", () => {
  test("not a seat that already did", () => {
    const s = ok(applyAction(seats(3), 2, FORFEIT)).state;
    expect(errorOf(applyAction(s, 2, FORFEIT))).toBe("forfeited");
  });

  test("a seat that is out can do nothing else either: it is never its turn", () => {
    const s = ok(applyAction(seats(3), 2, FORFEIT)).state;
    expect(errorOf(applyAction(s, 2, DRAW))).toBe("not_your_turn");
    expect(errorOf(applyAction(s, 2, play([[1, 2, 3]])))).toBe("not_your_turn");
  });

  test.each([-1, 3, 1.5, Number.NaN])("not seat %s of three", (seat) => {
    expect(errorOf(applyAction(seats(3), seat, FORFEIT))).toBe("bad_seat");
  });

  test("not once the game is over", () => {
    const over = ok(applyAction(seats(2), 0, FORFEIT)).state;
    expect(errorOf(applyAction(over, 1, FORFEIT))).toBe("game_over");
  });

  test("never mutates the state it is given", () => {
    const before = seats(3);
    ok(applyAction(before, 0, FORFEIT));
    expect(before.forfeited).toEqual([false, false, false]);
    expect(before.racks[0]).toEqual(RACKS[0]);
  });
});
