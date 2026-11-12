import { describe, expect, test } from "vitest";

import { bell, feather, fish, makeState, mouse, piecesIn, YARN } from "../../tests/tiles-helpers";

import { eventFor, viewFor } from "./view";

import type { TilesEvent, TilesState } from "./engine";

const TABLE = [[fish(4), fish(5), fish(6)], [mouse(9), feather(9), YARN]];
const RACKS = [[fish(1), fish(2)], [mouse(1)], [bell(1), bell(2), bell(3)]];

const state = (over: Partial<TilesState> = {}): TilesState =>
  makeState({
    racks: RACKS,
    table: TABLE,
    pool: [bell(7), bell(8), bell(9), bell(10)],
    boxed: [feather(13)],
    opened: [true, false, true],
    passed: [false, true, false],
    turn: 1,
    turns: 9,
    ...over,
  });

describe("viewFor", () => {
  test("a seat sees its own rack and nobody else's", () => {
    const view = viewFor(state(), [1]);
    expect(view.racks).toEqual({ 1: [mouse(1)] });
    expect(Object.keys(view.racks)).toEqual(["1"]);
    expect(view.rackCounts).toEqual([2, 1, 3]);
  });

  test("a shared phone sees every rack it holds", () => {
    expect(viewFor(state(), [0, 2]).racks).toEqual({ 0: RACKS[0], 2: RACKS[2] });
  });

  test("a device with no seat sees no rack", () => {
    expect(viewFor(state(), []).racks).toEqual({});
  });

  test("ignores controlled seats that are not seats", () => {
    expect(Object.keys(viewFor(state(), [-1, 3, 1.5, 99, 1]).racks)).toEqual(["1"]);
  });

  test("shows the table, the counts and whose move it is", () => {
    expect(viewFor(state(), [1])).toEqual({
      status: "playing",
      turn: 1,
      turns: 9,
      table: TABLE,
      poolCount: 4,
      rackCounts: [2, 1, 3],
      racks: { 1: [mouse(1)] },
      opened: [true, false, true],
      passed: [false, true, false],
      winners: [],
      scores: [0, 0, 0],
      forfeited: [false, false, false],
    });
  });

  test("never carries the pool, the set-aside pieces or anything else of the state", () => {
    const view = viewFor(state(), [1]);
    expect(Object.keys(view).sort()).toEqual([
      "forfeited", "opened", "passed", "poolCount", "rackCounts", "racks", "scores", "status", "table", "turn",
      "turns", "winners",
    ]);
  });

  test("every piece in a view is on the table or on a rack the device holds", () => {
    const s = state();
    for (const controlled of [[], [0], [1], [2], [0, 2]]) {
      const allowed = new Set([...TABLE.flat(), ...controlled.flatMap((seat) => RACKS[seat] as number[])]);
      const seen = piecesIn(viewFor(s, controlled));
      expect(seen.every((id) => allowed.has(id)), `seats ${controlled.join()}`).toBe(true);
      expect(seen).toHaveLength(allowed.size);
    }
  });

  test("a finished game still shows no other rack, only what each was left with", () => {
    const over = state({ status: "gameOver", winners: [1], scores: [-3, 9, -6], endReason: "blocked" });
    const view = viewFor(over, [1]);
    expect(view.racks).toEqual({ 1: [mouse(1)] });
    expect(view.status).toBe("gameOver");
    expect(view.winners).toEqual([1]);
    expect(view.scores).toEqual([-3, 9, -6]);
    expect(view.endReason).toBe("blocked");
  });

  test("a seat that forfeited shows as out, with an empty rack", () => {
    const view = viewFor(state({ racks: [RACKS[0] as number[], [], RACKS[2] as number[]], forfeited: [false, true, false] }), [1]);
    expect(view.forfeited).toEqual([false, true, false]);
    expect(view.racks).toEqual({ 1: [] });
    expect(view.rackCounts).toEqual([2, 0, 3]);
  });

  test("every array is a copy: changing a view never changes the state", () => {
    const s = structuredClone(state());
    const view = viewFor(s, [0]);
    (view.table[0] as number[]).push(99);
    view.table.push([1]);
    (view.racks[0] as number[]).push(99);
    view.opened[1] = true;
    view.passed[0] = true;
    view.winners.push(2);
    view.scores[0] = 50;
    view.forfeited[0] = true;
    view.rackCounts[0] = 0;
    expect(s).toEqual(state());
  });
});

describe("eventFor", () => {
  const drew: TilesEvent = { kind: "drew", seat: 1, tile: bell(10), poolCount: 3 };

  test("the drawer sees the piece it drew", () => {
    expect(eventFor(drew, [1])).toEqual(drew);
    expect(eventFor(drew, [0, 1])).toEqual(drew);
  });

  test("nobody else does: they see only that a piece was drawn", () => {
    for (const controlled of [[0], [2], [0, 2], []]) {
      const seen = eventFor(drew, controlled);
      expect(seen).toEqual({ kind: "drew", seat: 1, poolCount: 3 });
      expect("tile" in seen).toBe(false);
      expect(piecesIn(seen)).toEqual([]);
    }
  });

  test("does not change the event it is given, and returns a copy", () => {
    const event: TilesEvent = { ...drew };
    eventFor(event, [0]);
    expect(event).toEqual(drew);
    const played: TilesEvent = { kind: "played", seat: 0, table: [[1, 2, 3]], placed: [3], opened: false };
    const copy = eventFor(played, [1]) as typeof played;
    expect(copy).toEqual(played);
    expect(copy).not.toBe(played);
    expect(copy.table).not.toBe(played.table);
  });

  test.each<TilesEvent>([
    { kind: "played", seat: 0, table: TABLE, placed: [fish(6)], opened: true },
    { kind: "passed", seat: 0 },
    { kind: "turn", seat: 2 },
    { kind: "forfeited", seat: 2 },
    { kind: "gameOver", winners: [0], reason: "out", scores: [7, -3, -4], left: [0, 3, 4] },
  ])("$kind is the same for everyone: it holds nothing hidden", (event) => {
    for (const controlled of [[0], [1], [2], []]) expect(eventFor(event, controlled)).toEqual(event);
    // Whatever pieces it names are on the table by the time it is sent.
    expect(piecesIn(event).every((id) => TABLE.flat().includes(id))).toBe(true);
  });
});
