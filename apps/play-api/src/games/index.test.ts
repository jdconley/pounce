import { describe, expect, it, test } from "vitest";

import { catTower } from "./cat-tower";
import { tiles } from "./tiles";

import { DEFAULT_GAME, GAMES, GAMES_HEADER, gameModule, gamesListed, gamesOn, gameTitle, isGameId } from "./index";

describe("the games a room can hold", () => {
  it("are Cat Tower and the tile game, each under its own id", () => {
    expect(Object.keys(GAMES)).toEqual(["cat-tower", "tiles"]);
    expect(GAMES["cat-tower"]).toBe(catTower);
    expect(GAMES.tiles).toBe(tiles);
    for (const [id, module] of Object.entries(GAMES)) expect(module.id).toBe(id);
    expect(DEFAULT_GAME).toBe("cat-tower");
  });

  it("isGameId takes those ids and nothing else", () => {
    expect(isGameId("cat-tower")).toBe(true);
    expect(isGameId("tiles")).toBe(true);
    for (const other of ["Tiles", "", "toString", "constructor", "__proto__", 1, null, undefined, ["tiles"]]) {
      expect(isGameId(other), String(other)).toBe(false);
    }
  });

  it("gameModule finds a room's module, and Cat Tower for a room that names none or one that is unknown", () => {
    expect(gameModule("tiles")).toBe(tiles);
    expect(gameModule("cat-tower")).toBe(catTower);
    expect(gameModule(undefined)).toBe(catTower);
    expect(gameModule("chess")).toBe(catTower);
  });
});

describe("the games an app says it can draw", () => {
  it("the header is x-pounce-games", () => {
    expect(GAMES_HEADER).toBe("x-pounce-games");
  });

  it("no header: Cat Tower only, which is every app before there was a second game", () => {
    expect(gamesListed(null)).toEqual(["cat-tower"]);
    expect(gamesListed("")).toEqual(["cat-tower"]);
  });

  it("lists the games it names, always with Cat Tower first", () => {
    expect(gamesListed("cat-tower,tiles")).toEqual(["cat-tower", "tiles"]);
    expect(gamesListed("tiles")).toEqual(["cat-tower", "tiles"]);
    expect(gamesListed(" Tiles , cat-tower ")).toEqual(["cat-tower", "tiles"]);
  });

  it("ignores what it doesn't know, and repeats", () => {
    expect(gamesListed("tiles,tiles,chess,,toString")).toEqual(["cat-tower", "tiles"]);
    expect(gamesListed("chess")).toEqual(["cat-tower"]);
  });
});

describe("the GAMES flag", () => {
  it("off or unset: rooms are Cat Tower only", () => {
    expect(gamesOn({})).toEqual(["cat-tower"]);
    expect(gamesOn({ GAMES: "" })).toEqual(["cat-tower"]);
    expect(gamesOn({ GAMES: "off" })).toEqual(["cat-tower"]);
    expect(gamesOn({ GAMES: "on" })).toEqual(["cat-tower"]);
  });

  it("turns on the games it lists", () => {
    expect(gamesOn({ GAMES: "tiles" })).toEqual(["cat-tower", "tiles"]);
    expect(gamesOn({ GAMES: "cat-tower, tiles" })).toEqual(["cat-tower", "tiles"]);
  });
});

describe("a game's name, for an app that can't draw it", () => {
  test("is the one the app's shelf uses", () => {
    expect(gameTitle("cat-tower")).toBe("Cat Tower");
    expect(gameTitle("tiles")).toBe("Tuna Tiles");
  });

  test("a game this server has no name for is a newer game", () => {
    expect(gameTitle("chess")).toBe("a newer game");
    expect(gameTitle("toString")).toBe("a newer game");
  });
});
