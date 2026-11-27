import { GAMES, gameTitle } from "@pounce/play-api/games/index";
import { describe, expect, test } from "vitest";

import { CATALOG, GAME_IDS, titleOf } from "../src/lib/catalog";

/** Games the server deals that this player doesn't draw yet: each leaves the list when its web table lands. */
const NOT_YET: readonly string[] = ["tumble"];

describe("Home's game shelf", () => {
  test("names and seats every game the server has, exactly as the server does", () => {
    expect(GAME_IDS).toEqual(Object.keys(GAMES).filter((id) => !NOT_YET.includes(id)));
    for (const id of GAME_IDS) {
      expect(CATALOG[id].title).toBe(gameTitle(id));
      expect(CATALOG[id].minSeats).toBe(GAMES[id].minSeats);
      expect(CATALOG[id].maxSeats).toBe(GAMES[id].maxSeats);
    }
    expect(titleOf("chess")).toBe(gameTitle("chess"));
  });
});
