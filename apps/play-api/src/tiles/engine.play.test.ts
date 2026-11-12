import { describe, expect, test } from "vitest";

import { bell, errorOf, expectSound, feather, fish, makeState, mouse, ok, YARN, YARN2 } from "../../tests/tiles-helpers";

import { applyAction, checkPlay, type TilesAction, type TilesState } from "./engine";

import type { TileId } from "./pieces";

/** Seat 1's rack in every two-seat state here: nothing seat 0's plays need. */
const OTHER = [bell(1, true), bell(2, true), bell(3, true)];

const play = (state: TilesState, table: unknown, seat = state.turn) =>
  applyAction(state, seat, { type: "play", table } as TilesAction);

/** A two-seat state on seat 0's turn with `rack`, and `table` already down. */
const seated = (rack: TileId[], table: TileId[][] = [], over: Partial<TilesState> = {}) =>
  makeState({ racks: [rack, OTHER], table, ...over });

const RUN_30 = [fish(9), fish(10), fish(11)];

describe("a play", () => {
  test("puts the submitted table down, takes the pieces off the rack and passes the move on", () => {
    const before = seated([...RUN_30, bell(2)]);
    const { state, events } = ok(play(before, [RUN_30]));
    expect(state.table).toEqual([RUN_30]);
    expect(state.racks[0]).toEqual([bell(2)]);
    expect(state.racks[1]).toEqual(OTHER);
    expect(state.pool).toEqual(before.pool);
    expect(state.turn).toBe(1);
    expect(state.turns).toBe(1);
    expect(events).toEqual([
      { kind: "played", seat: 0, table: [RUN_30], placed: RUN_30, opened: true },
      { kind: "turn", seat: 1 },
    ]);
    expectSound(state);
  });

  test("never mutates the state it is given, nor shares arrays with the action", () => {
    const before = seated([...RUN_30, bell(2)]);
    const table = [[...RUN_30]];
    const { state, events } = ok(play(before, table));
    (table[0] as TileId[]).push(99);
    expect(state.table).toEqual([RUN_30]);
    const played = events[0] as { table: TileId[][] };
    (played.table[0] as TileId[]).push(98);
    expect(state.table).toEqual([RUN_30]);
    expect(before.table).toEqual([]);
  });

  test("clears the passes: someone moved", () => {
    const before = seated([...RUN_30, bell(2)], [], { pool: [], passed: [false, true] });
    expect(ok(play(before, [RUN_30])).state.passed).toEqual([false, false]);
  });
});

describe("the opening: 30 points of new sets from the rack", () => {
  test("exactly 30 opens", () => {
    const { state } = ok(play(seated([...RUN_30, bell(2)]), [RUN_30]));
    expect(state.opened).toEqual([true, false]);
  });

  test("29 does not", () => {
    // Three 3s (9) and 2-3-4-5-6 (20).
    const threes = [mouse(3), feather(3), bell(3)];
    const run = [fish(2), fish(3), fish(4), fish(5), fish(6)];
    const before = seated([...threes, ...run, bell(2)]);
    expect(errorOf(play(before, [threes, run]))).toBe("opening_too_low");
  });

  test("several sets add up", () => {
    // 1-2-3 (6) and three 8s (24).
    const low = [fish(1), fish(2), fish(3)];
    const eights = [mouse(8), feather(8), bell(8)];
    const { state } = ok(play(seated([...low, ...eights, bell(2)]), [low, eights]));
    expect(state.opened[0]).toBe(true);
    expect(state.racks[0]).toEqual([bell(2)]);
  });

  test("a Yarn counts as the piece it stands for, not as 30", () => {
    // 9, Yarn, 11: the Yarn is a 10.
    expect(ok(play(seated([fish(9), YARN, fish(11), bell(2)]), [[fish(9), YARN, fish(11)]])).state.opened[0]).toBe(true);
    // 1, 2, Yarn: the Yarn is a 3, and the set is worth 6.
    expect(errorOf(play(seated([fish(1), fish(2), YARN, bell(2)]), [[fish(1), fish(2), YARN]]))).toBe("opening_too_low");
  });

  test("where a Yarn sits in a run decides what it is worth", () => {
    const rack = [fish(9), fish(10), YARN, bell(2)];
    // 9, 10, Yarn is 9-10-11 (30); Yarn, 9, 10 is 8-9-10 (27).
    expect(play(seated(rack), [[fish(9), fish(10), YARN]]).ok).toBe(true);
    expect(errorOf(play(seated(rack), [[YARN, fish(9), fish(10)]]))).toBe("opening_too_low");
  });

  test("a Yarn in a group counts as the group's number", () => {
    expect(play(seated([mouse(10), bell(10), YARN, bell(2)]), [[mouse(10), bell(10), YARN]]).ok).toBe(true);
    expect(errorOf(play(seated([mouse(9), bell(9), YARN, bell(2)]), [[mouse(9), bell(9), YARN]]))).toBe("opening_too_low");
  });

  test("one piece with two Yarn counts as its better reading", () => {
    // Yarn, Yarn, 10: three 10s (30) beat 8-9-10 (27).
    expect(play(seated([YARN, YARN2, fish(10), bell(2)]), [[YARN, YARN2, fish(10)]]).ok).toBe(true);
    // Yarn, Yarn, 9: three 9s (27) is the better reading, and still short.
    expect(errorOf(play(seated([YARN, YARN2, fish(9), bell(2)]), [[YARN, YARN2, fish(9)]]))).toBe("opening_too_low");
    // 9, Yarn, Yarn: the run 9-10-11 (30) beats three 9s (27).
    expect(play(seated([YARN, YARN2, fish(9), bell(2)]), [[fish(9), YARN, YARN2]]).ok).toBe(true);
  });

  test("sets already on the table count for nothing", () => {
    const there = [mouse(10), mouse(11), mouse(12)];
    const low = [fish(1), fish(2), fish(3)];
    expect(errorOf(play(seated([...low, bell(2)], [there]), [there, low]))).toBe("opening_too_low");
  });

  test("the sets already there may be listed in another order", () => {
    const a = [mouse(5), mouse(6), mouse(7)];
    const b = [fish(4), mouse(4), bell(4)];
    const { state } = ok(play(seated([...RUN_30, bell(2)], [a, b]), [RUN_30, b, a]));
    expect(state.table).toEqual([RUN_30, b, a]);
    expect(state.opened[0]).toBe(true);
  });

  describe("every set already there must be left as it is", () => {
    test("no adding to one, even with 30 points of new sets beside it", () => {
      const there = [mouse(5), mouse(6), mouse(7)];
      const before = seated([mouse(8), ...RUN_30, bell(2)], [there]);
      expect(errorOf(play(before, [[...there, mouse(8)], RUN_30]))).toBe("table_touched");
    });

    test("no adding 30 points to one", () => {
      const there = [mouse(5), mouse(6), mouse(7)];
      const more = [mouse(8), mouse(9), mouse(10), mouse(11)];
      expect(errorOf(play(seated([...more, bell(2)], [there]), [[...there, ...more]]))).toBe("table_touched");
    });

    test("no splitting one", () => {
      const there = [mouse(3), mouse(4), mouse(5), mouse(6), mouse(7), mouse(8)];
      const before = seated([...RUN_30, bell(2)], [there]);
      expect(errorOf(play(before, [there.slice(0, 3), there.slice(3), RUN_30]))).toBe("table_touched");
    });

    test("no reordering one", () => {
      const there = [fish(4), mouse(4), bell(4)];
      const before = seated([...RUN_30, bell(2)], [there]);
      expect(errorOf(play(before, [[mouse(4), fish(4), bell(4)], RUN_30]))).toBe("table_touched");
    });

    test("no moving a Yarn that is on the table", () => {
      const there = [mouse(5), YARN, mouse(7)];
      const before = seated([mouse(6), fish(10), fish(11), bell(2)], [there]);
      const after = [[mouse(5), mouse(6), mouse(7)], [YARN, fish(10), fish(11)]];
      expect(errorOf(play(before, after))).toBe("table_touched");
    });

    test("no building a new set out of table pieces", () => {
      const fours = [fish(4), mouse(4), feather(4), bell(4)];
      const before = seated([fish(5), fish(6), ...RUN_30, bell(2)], [fours]);
      const after = [[mouse(4), feather(4), bell(4)], [fish(4), fish(5), fish(6)], RUN_30];
      expect(errorOf(play(before, after))).toBe("table_touched");
    });
  });

  test("an opening play can empty the rack and win", () => {
    const { state } = ok(play(seated(RUN_30), [RUN_30]));
    expect(state.status).toBe("gameOver");
    expect(state.winners).toEqual([0]);
  });
});

describe("after opening: the whole table is free to rearrange", () => {
  const opened = (rack: TileId[], table: TileId[][]) => seated(rack, table, { opened: [true, false] });

  test("one piece is enough, on either end of a run or as a group's fourth", () => {
    const run = [mouse(5), mouse(6), mouse(7)];
    const fours = [fish(4), mouse(4), bell(4)];
    const before = opened([mouse(4, true), mouse(8), feather(4), bell(2)], [run, fours]);
    expect(play(before, [[mouse(4, true), ...run], fours]).ok).toBe(true);
    expect(play(before, [[...run, mouse(8)], fours]).ok).toBe(true);
    expect(play(before, [run, [...fours, feather(4)]]).ok).toBe(true);
    const all = ok(play(before, [[mouse(4, true), ...run, mouse(8)], [...fours, feather(4)]]));
    expect(all.state.racks[0]).toEqual([bell(2)]);
    expect(all.events[0]).toMatchObject({ opened: false, placed: [mouse(4, true), mouse(8), feather(4)] });
    expectSound(all.state);
  });

  test("a run can be split around a new piece", () => {
    const run = [fish(3), fish(4), fish(5), fish(6), fish(7)];
    const before = opened([fish(5, true), bell(2)], [run]);
    const after = [[fish(3), fish(4), fish(5)], [fish(5, true), fish(6), fish(7)]];
    expect(ok(play(before, after)).state.table).toEqual(after);
  });

  test("a group can give up a piece to a new run", () => {
    const fours = [fish(4), mouse(4), feather(4), bell(4)];
    const before = opened([fish(5), fish(6), bell(2)], [fours]);
    const after = [[mouse(4), feather(4), bell(4)], [fish(4), fish(5), fish(6)]];
    expect(ok(play(before, after)).state.table).toEqual(after);
  });

  test("a Yarn on the table can move to another set", () => {
    const before = opened([mouse(6), bell(9)], [[mouse(5), YARN, mouse(7)], [feather(1), feather(2), feather(3)]]);
    const after = [[mouse(5), mouse(6), mouse(7)], [feather(1), feather(2), feather(3), YARN]];
    const { state } = ok(play(before, after));
    expect(state.table).toEqual(after);
    expectSound(state);
  });

  test("but it cannot leave the table", () => {
    const before = opened([mouse(6), bell(9)], [[mouse(5), YARN, mouse(7)], [feather(1), feather(2), feather(3)]]);
    const after = [[mouse(5), mouse(6), mouse(7)], [feather(1), feather(2), feather(3)]];
    expect(errorOf(play(before, after))).toBe("missing_piece");
  });

  test("rearranging without adding a piece is not a turn", () => {
    const run = [mouse(3), mouse(4), mouse(5), mouse(6), mouse(7), mouse(8)];
    const before = opened([bell(9)], [run]);
    expect(errorOf(play(before, [run]))).toBe("nothing_played");
    expect(errorOf(play(before, [run.slice(0, 3), run.slice(3)]))).toBe("nothing_played");
  });

  test("every set must still be a set when the turn is over", () => {
    const run = [mouse(5), mouse(6), mouse(7)];
    const before = opened([mouse(9), fish(1), fish(2), bell(9)], [run]);
    expect(errorOf(play(before, [[...run, mouse(9)]]))).toBe("bad_set");
    expect(errorOf(play(before, [run, [fish(1), fish(2)]]))).toBe("bad_set");
    expect(errorOf(play(before, [run, [mouse(9)], []]))).toBe("bad_set");
    // Taking the 5 for a new set would leave 6-7 behind.
    expect(errorOf(play(before, [[mouse(6), mouse(7)], [mouse(5), fish(1), fish(2)]]))).toBe("bad_set");
  });

  test("the opening stays made: later plays need no 30", () => {
    const first = ok(play(seated([...RUN_30, fish(12), bell(2)]), [RUN_30])).state;
    const back = ok(applyAction(first, 1, { type: "draw" })).state;
    const { state, events } = ok(play(back, [[...RUN_30, fish(12)]]));
    expect(state.opened).toEqual([true, false]);
    expect(events[0]).toMatchObject({ kind: "played", opened: false, placed: [fish(12)] });
  });
});

describe("where every piece comes from", () => {
  const run = [mouse(5), mouse(6), mouse(7)];
  const before = seated([...RUN_30, mouse(8), bell(2)], [run], { opened: [true, false] });

  test("a piece from another rack", () => {
    expect(errorOf(play(before, [run, OTHER]))).toBe("not_your_piece");
  });

  test("a piece from the pool", () => {
    expect(before.pool).toContain(fish(12));
    expect(errorOf(play(before, [run, [...RUN_30, fish(12)]]))).toBe("not_your_piece");
  });

  test("a piece set aside by a forfeit", () => {
    const boxed = seated([...RUN_30, bell(2)], [run], { opened: [true, false], boxed: [fish(12)] });
    expect(errorOf(play(boxed, [run, [...RUN_30, fish(12)]]))).toBe("not_your_piece");
  });

  test("a piece used twice: in one set, in two sets, or a table piece again", () => {
    expect(errorOf(play(before, [run, [...RUN_30, fish(11)]]))).toBe("duplicate_piece");
    expect(errorOf(play(before, [run, RUN_30, RUN_30]))).toBe("duplicate_piece");
    expect(errorOf(play(before, [run, [...run, mouse(8)]]))).toBe("duplicate_piece");
  });

  test("a piece missing from the table", () => {
    expect(errorOf(play(before, [RUN_30]))).toBe("missing_piece");
    expect(errorOf(play(before, [[mouse(6), mouse(7), mouse(8)], RUN_30]))).toBe("missing_piece");
    expect(errorOf(play(before, []))).toBe("missing_piece");
  });

  test("no piece from the rack", () => {
    expect(errorOf(play(before, [run]))).toBe("nothing_played");
    expect(errorOf(play(seated([bell(2)]), []))).toBe("nothing_played");
  });

  test.each([
    ["not a list", "table"],
    ["nothing", null],
    ["a set that is not a list", [run, "567"]],
    ["a set that is an object", [run, { 0: 1 }]],
    ["a piece that does not exist", [run, [fish(9), fish(10), 106]]],
    ["a negative piece", [run, [fish(9), fish(10), -1]]],
    ["a fraction of a piece", [run, [fish(9), fish(10), 10.5]]],
    ["a piece as text", [run, [fish(9), fish(10), "10"]]],
    ["a nested set", [run, [RUN_30]]],
  ])("a malformed table: %s", (_, table) => {
    expect(errorOf(play(before, table))).toBe("bad_piece");
  });
});

describe("which error wins when several apply", () => {
  const run = [mouse(5), mouse(6), mouse(7)];
  const before = seated([...RUN_30, bell(2)], [run]);

  test("shape, then duplicates, then the table's pieces, then the rack's, then the sets, then the opening", () => {
    // Malformed and duplicated: malformed.
    expect(errorOf(play(before, [RUN_30, RUN_30, [106]]))).toBe("bad_piece");
    // Duplicated and missing a table piece: duplicated.
    expect(errorOf(play(before, [RUN_30, RUN_30]))).toBe("duplicate_piece");
    // Missing a table piece and using someone else's: missing.
    expect(errorOf(play(before, [OTHER]))).toBe("missing_piece");
    // Someone else's piece in a set that is not a set: not yours.
    expect(errorOf(play(before, [run, [OTHER[0], fish(9)]]))).toBe("not_your_piece");
    // Not a set, and it touches the table before opening: not a set.
    expect(errorOf(play(before, [[...run, fish(9)]]))).toBe("bad_set");
    // Touches the table and is short of 30: the table.
    expect(errorOf(play(seated([mouse(8), bell(2)], [run]), [[...run, mouse(8)]]))).toBe("table_touched");
  });

  test("out of turn comes before everything about the play", () => {
    expect(errorOf(play(before, "nonsense", 1))).toBe("not_your_turn");
  });

  test("a finished game comes before everything", () => {
    const over = seated(RUN_30, [], { status: "gameOver", winners: [1] });
    expect(errorOf(play(over, [RUN_30]))).toBe("game_over");
    expect(errorOf(play(over, [RUN_30], 1))).toBe("game_over");
  });

  test("an action the game does not have is refused, not taken as a turn", () => {
    expect(errorOf(applyAction(before, 0, { type: "shuffle" } as unknown as TilesAction))).toBe("bad_action");
  });
});

describe("checkPlay", () => {
  const run = [mouse(5), mouse(6), mouse(7)];

  test("says which rack pieces a play puts down and what its new sets are worth", () => {
    const check = checkPlay([run], [...RUN_30, mouse(8)], true, [[...run, mouse(8)], RUN_30]);
    // The run 5-8 is new as a set (26) and so is 9-10-11 (30).
    expect(check).toEqual({ ok: true, placed: [mouse(8), ...RUN_30], points: 56 });
  });

  test("counts only the new sets", () => {
    expect(checkPlay([run], RUN_30, false, [run, RUN_30])).toEqual({ ok: true, placed: RUN_30, points: 30 });
  });

  test("gives the reason a play is refused", () => {
    expect(checkPlay([run], RUN_30, false, [run])).toEqual({ ok: false, error: "nothing_played" });
  });
});
