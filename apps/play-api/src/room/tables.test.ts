import { describe, expect, it } from "vitest";

import { drawable, tablesFor, withoutUndrawable, type TableEntry } from "./tables";

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
