import { describe, expect, it, test } from "vitest";

import { drawable, lockedFor, tablesFor, withoutUndrawable, type TableEntry } from "./tables";

const entry = (code: string, game?: string): TableEntry => ({
  code,
  status: "playing",
  yourTurn: false,
  updatedAt: 1,
  ...(game === undefined ? {} : { game }),
});

describe("which tables an app is shown", () => {
  it("every app draws Cat Tower: a table that names no game, or names Cat Tower", () => {
    expect(drawable(undefined, [])).toBe(true);
    expect(drawable("cat-tower", [])).toBe(true);
    expect(drawable(undefined, ["tiles"])).toBe(true);
  });

  it("a table of another game only for an app that lists it", () => {
    expect(drawable("tiles", [])).toBe(false);
    expect(drawable("tiles", ["cat-tower"])).toBe(false);
    expect(drawable("tiles", ["cat-tower", "tiles"])).toBe(true);
  });

  it("tablesFor leaves the others out and keeps the order", () => {
    const tables = [entry("AAAAA"), entry("BBBBB", "tiles"), entry("CCCCC", "cat-tower"), entry("DDDDD", "tiles")];
    expect(tablesFor(tables, []).map((t) => t.code)).toEqual(["AAAAA", "CCCCC"]);
    expect(tablesFor(tables, ["cat-tower"]).map((t) => t.code)).toEqual(["AAAAA", "CCCCC"]);
    expect(tablesFor(tables, ["tiles"]).map((t) => t.code)).toEqual(["AAAAA", "BBBBB", "CCCCC", "DDDDD"]);
  });
});

describe("a streak's table codes", () => {
  const tables = [entry("AAAAA"), entry("BBBBB", "tiles"), entry("CCCCC", "tiles")];
  const view = { pair: "x", count: 3, myMove: ["AAAAA", "BBBBB"], theirMove: ["CCCCC", "ZZZZZ"] };

  it("an app is told only of the tables it can draw", () => {
    expect(withoutUndrawable(view, tables, [])).toEqual({ pair: "x", count: 3, myMove: ["AAAAA"], theirMove: ["ZZZZZ"] });
  });

  it("an app that draws them all, or a player with none, gets the very same view", () => {
    expect(withoutUndrawable(view, tables, ["tiles"])).toBe(view);
    expect(withoutUndrawable(view, [entry("AAAAA"), entry("DDDDD", "cat-tower")], [])).toBe(view);
    expect(withoutUndrawable(view, [], [])).toBe(view);
  });

  it("does not change the view it is given", () => {
    withoutUndrawable(view, tables, []);
    expect(view.myMove).toEqual(["AAAAA", "BBBBB"]);
  });
});

describe("lockedFor", () => {
  const title = (game: string) => (game === "tiles" ? "Tuna Tiles" : "a newer game");
  const tower: TableEntry = { code: "BCDFG", name: "Couch Cats", status: "playing", yourTurn: true, updatedAt: 3 };
  const tiles: TableEntry = { code: "GH2VD", name: "Taco Night", status: "playing", yourTurn: false, updatedAt: 2, game: "tiles", seats: [{ kind: "bot" }], movedAt: 1 };

  test("is empty for a device with no table of another game", () => {
    expect(lockedFor([tower], [], title)).toEqual([]);
    expect(lockedFor([], [], title)).toEqual([]);
  });

  test("is the tables the app can't draw, each with its game's name and none of a turn's details", () => {
    expect(lockedFor([tower, tiles], [], title)).toEqual([
      { code: "GH2VD", name: "Taco Night", game: "tiles", title: "Tuna Tiles", updatedAt: 2, seats: [{ kind: "bot" }] },
    ]);
    expect(lockedFor([{ code: "KLMNP", status: "lobby", yourTurn: false, updatedAt: 1, game: "chess" }], ["tiles"], title)).toEqual([
      { code: "KLMNP", game: "chess", title: "a newer game", updatedAt: 1 },
    ]);
  });

  test("nothing is locked for an app that can draw it, and a finished table isn't worth an update", () => {
    expect(lockedFor([tower, tiles], ["tiles"], title)).toEqual([]);
    expect(lockedFor([{ ...tiles, status: "over" }], [], title)).toEqual([]);
  });

  test("at most ten", () => {
    const many = Array.from({ length: 14 }, (_, i) => ({ ...tiles, code: `T${i}` }));
    expect(lockedFor(many, [], title)).toHaveLength(10);
  });
});
