import { describe, expect, test } from "vitest";

import { parseAction } from "./parse";

describe("parseAction", () => {
  test.each(["draw", "pass", "forfeit"] as const)("%s is its type and nothing else", (type) => {
    expect(parseAction({ type })).toEqual({ type });
    expect(parseAction({ type, seat: 1 })).toBeNull();
    expect(parseAction({ type, table: [] })).toBeNull();
  });

  test("a play carries the whole table", () => {
    expect(parseAction({ type: "play", table: [[3, 4, 5], [104, 6, 32]] })).toEqual({
      type: "play",
      table: [[3, 4, 5], [104, 6, 32]],
    });
  });

  test("the table is copied: the message can't change the action afterwards", () => {
    const table = [[3, 4, 5]];
    const action = parseAction({ type: "play", table });
    (table[0] as number[]).push(6);
    table.push([7, 8, 9]);
    expect(action).toEqual({ type: "play", table: [[3, 4, 5]] });
  });

  test("it does not judge the play: an empty table, a short set and a repeated piece all parse", () => {
    expect(parseAction({ type: "play", table: [] })).toEqual({ type: "play", table: [] });
    expect(parseAction({ type: "play", table: [[], [3]] })).toEqual({ type: "play", table: [[], [3]] });
    expect(parseAction({ type: "play", table: [[3, 3, 3]] })).toEqual({ type: "play", table: [[3, 3, 3]] });
  });

  test.each([
    ["no table", { type: "play" }],
    ["an extra key", { type: "play", table: [], seat: 0 }],
    ["a table that is not a list", { type: "play", table: "3,4,5" }],
    ["a table that is an object", { type: "play", table: { 0: [3, 4, 5] } }],
    ["a set that is not a list", { type: "play", table: [[3, 4, 5], 6] }],
    ["a nested set", { type: "play", table: [[[3, 4, 5]]] }],
    ["a piece that does not exist", { type: "play", table: [[3, 4, 106]] }],
    ["a negative piece", { type: "play", table: [[3, 4, -1]] }],
    ["a fraction of a piece", { type: "play", table: [[3, 4, 4.5]] }],
    ["a piece as text", { type: "play", table: [[3, 4, "5"]] }],
    ["nothing where a piece should be", { type: "play", table: [[3, 4, null]] }],
    ["a set longer than any run", { type: "play", table: [Array.from({ length: 14 }, (_, i) => i)] }],
    ["more sets than the pieces can make", { type: "play", table: Array.from({ length: 36 }, () => [1, 2, 3]) }],
    ["more pieces than there are", { type: "play", table: Array.from({ length: 9 }, () => Array.from({ length: 12 }, (_, i) => i)) }],
  ])("refuses %s", (_, raw) => {
    expect(parseAction(raw)).toBeNull();
  });

  test("takes the largest table there can be", () => {
    // 35 sets of three and one piece over is 106.
    const table = [...Array.from({ length: 34 }, (_, i) => [3 * i, 3 * i + 1, 3 * i + 2]), [102, 103, 104, 105]];
    expect(parseAction({ type: "play", table })).toEqual({ type: "play", table });
  });

  test.each([null, undefined, "draw", 7, [], ["draw"], {}, { type: "shuffle" }, { type: 1 }, { type: "nextRound" }, { type: "discard", card: 3 }])(
    "refuses %j",
    (raw) => {
      expect(parseAction(raw)).toBeNull();
    },
  );
});
