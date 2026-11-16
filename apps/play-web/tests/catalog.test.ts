import { GAMES, gameTitle } from "@pounce/play-api/games/index";
import { describe, expect, test } from "vitest";

import { CATALOG, GAME_IDS, titleOf } from "../src/lib/catalog";

describe("Home's game shelf", () => {
  test("names and seats every game the server has, exactly as the server does", () => {
    expect(GAME_IDS).toEqual(Object.keys(GAMES));
    for (const id of GAME_IDS) {
      expect(CATALOG[id].title).toBe(gameTitle(id));
      expect(CATALOG[id].minSeats).toBe(GAMES[id].minSeats);
      expect(CATALOG[id].maxSeats).toBe(GAMES[id].maxSeats);
    }
    expect(titleOf("chess")).toBe(gameTitle("chess"));
  });
});
