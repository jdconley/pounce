import { describe, expect, it, test } from "vitest";

import { birdwatch } from "./birdwatch";
import { catTower } from "./cat-tower";
import { purrtrait } from "./purrtrait";
import { tiles } from "./tiles";
import { tumble } from "./tumble";

import { DEFAULT_GAME, GAME_MIN_APP, GAMES, GAMES_HEADER, gameModule, gamesFor, gamesListed, gamesOn, gameTitle, isGameId } from "./index";

describe("the games a room can hold", () => {
  it("are Cat Tower, the tile game, Birdwatch, Purrtrait and Toy Tumble, each under its own id", () => {
    expect(Object.keys(GAMES)).toEqual(["cat-tower", "tiles", "birdwatch", "purrtrait", "tumble"]);
    expect(GAMES.tumble).toBe(tumble);
    expect(GAMES["cat-tower"]).toBe(catTower);
    expect(GAMES.tiles).toBe(tiles);
    expect(GAMES.birdwatch).toBe(birdwatch);
    expect(GAMES.purrtrait).toBe(purrtrait);
    for (const [id, module] of Object.entries(GAMES)) expect(module.id).toBe(id);
    expect(DEFAULT_GAME).toBe("cat-tower");
  });

  it("isGameId takes those ids and nothing else", () => {
    expect(isGameId("cat-tower")).toBe(true);
    expect(isGameId("tiles")).toBe(true);
    expect(isGameId("birdwatch")).toBe(true);
    for (const other of ["Tiles", "", "toString", "constructor", "__proto__", 1, null, undefined, ["tiles"]]) {
      expect(isGameId(other), String(other)).toBe(false);
    }
  });

  it("gameModule finds a room's module, and Cat Tower for a room that names none or one that is unknown", () => {
    expect(gameModule("tiles")).toBe(tiles);
    expect(gameModule("birdwatch")).toBe(birdwatch);
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
    expect(gamesListed("cat-tower,tiles,birdwatch")).toEqual(["cat-tower", "tiles", "birdwatch"]);
  });

  it("ignores what it doesn't know, and repeats", () => {
    expect(gamesListed("tiles,tiles,chess,,toString")).toEqual(["cat-tower", "tiles"]);
    expect(gamesListed("chess")).toEqual(["cat-tower"]);
  });
});

describe("the games an app is given, by its version", () => {
  const all = "cat-tower,tiles,birdwatch,tumble";
  const ios = (version: string) => `platform=ios; version=${version}; build=1; protocol=1`;
  const older = ["cat-tower", "tiles", "birdwatch"];

  it("Toy Tumble and Purrtrait need app 1.4", () => {
    expect(GAME_MIN_APP).toEqual({ purrtrait: "1.4", tumble: "1.4" });
  });

  it("an iOS or tvOS app below 1.4 never gets Toy Tumble, whatever it lists", () => {
    expect(gamesFor(all, ios("1.3"), false)).toEqual(older);
    expect(gamesFor(all, ios("1.3.9"), false)).toEqual(older);
    expect(gamesFor(all, "platform=tvos; version=1.2; protocol=1", false)).toEqual(older);
    // An app that doesn't say what it is is 1.0.
    expect(gamesFor(all, null, false)).toEqual(older);
    expect(gamesFor(all, "nonsense", false)).toEqual(older);
  });

  it("from 1.4 it does", () => {
    expect(gamesFor(all, ios("1.4"), false)).toEqual([...older, "tumble"]);
    expect(gamesFor(all, ios("2.0"), false)).toContain("tumble");
    expect(gamesFor(all, "platform=tvos; version=1.4; protocol=1", false)).toContain("tumble");
  });

  it("the web player always does: it ships with the server", () => {
    expect(gamesFor(all, "platform=web; version=500; protocol=1", false)).toContain("tumble");
  });

  it("a dev server skips the check", () => {
    expect(gamesFor(all, ios("1.3"), true)).toContain("tumble");
  });

  it("is still only what the app lists", () => {
    expect(gamesFor("tiles", ios("1.4"), true)).toEqual(["cat-tower", "tiles"]);
    expect(gamesFor(null, ios("1.4"), true)).toEqual(["cat-tower"]);
  });
});

describe("Purrtrait, by app version", () => {
  const all = "cat-tower,tiles,birdwatch,purrtrait";
  const older = ["cat-tower", "tiles", "birdwatch"];

  it("an iPhone or Apple TV below 1.4 never gets it, so a 1.3 TV can't host it either", () => {
    expect(gamesFor(all, "platform=ios; version=1.3; build=1; protocol=1", false)).toEqual(older);
    expect(gamesFor(all, "platform=tvos; version=1.3; protocol=1", false)).toEqual(older);
  });

  it("1.4 apps, the web player and dev servers do", () => {
    expect(gamesFor(all, "platform=ios; version=1.4; build=1; protocol=1", false)).toContain("purrtrait");
    expect(gamesFor(all, "platform=tvos; version=1.4; protocol=1", false)).toContain("purrtrait");
    expect(gamesFor(all, "platform=web; version=500; protocol=1", false)).toContain("purrtrait");
    expect(gamesFor(all, "platform=tvos; version=1.3; protocol=1", true)).toContain("purrtrait");
  });
});

describe("the GAMES flag", () => {
  it("leaves Toy Tumble off unless it lists it", () => {
    expect(gamesOn({ GAMES: "tiles,birdwatch" })).not.toContain("tumble");
    expect(gamesOn({ GAMES: "tiles,birdwatch,tumble" })).toContain("tumble");
  });

  it("off or unset: rooms are Cat Tower only", () => {
    expect(gamesOn({})).toEqual(["cat-tower"]);
    expect(gamesOn({ GAMES: "" })).toEqual(["cat-tower"]);
    expect(gamesOn({ GAMES: "off" })).toEqual(["cat-tower"]);
    expect(gamesOn({ GAMES: "on" })).toEqual(["cat-tower"]);
  });

  it("turns on the games it lists", () => {
    expect(gamesOn({ GAMES: "tiles" })).toEqual(["cat-tower", "tiles"]);
    expect(gamesOn({ GAMES: "cat-tower, tiles" })).toEqual(["cat-tower", "tiles"]);
    expect(gamesOn({ GAMES: "tiles,birdwatch" })).toEqual(["cat-tower", "tiles", "birdwatch"]);
  });
});

describe("a game's name, for an app that can't draw it", () => {
  test("is the one the app's shelf uses", () => {
    expect(gameTitle("cat-tower")).toBe("Cat Tower");
    expect(gameTitle("tiles")).toBe("Tuna Tiles");
    expect(gameTitle("birdwatch")).toBe("Birdwatch");
    expect(gameTitle("purrtrait")).toBe("Purrtrait");
    expect(gameTitle("tumble")).toBe("Toy Tumble");
  });

  test("a game this server has no name for is a newer game", () => {
    expect(gameTitle("chess")).toBe("a newer game");
    expect(gameTitle("toString")).toBe("a newer game");
  });
});
