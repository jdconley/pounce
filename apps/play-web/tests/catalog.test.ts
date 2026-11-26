import { GAMES, gameTitle } from "@pounce/play-api/games/index";
import { describe, expect, test } from "vitest";

import { CATALOG, GAME_IDS, SHELF, titleOf } from "../src/lib/catalog";

/** Games the server deals that this player doesn't draw yet: each leaves the list when its web table lands. */
const NOT_YET: readonly string[] = [];
/**
 * Games this player draws before the server has their module: Toy Tumble, whose room is being
 * built. Each leaves the list when its server module lands, and is then held to the server's names.
 */
const AHEAD: Record<string, { title: string; minSeats: number; maxSeats: number }> = { tumble: { title: "Toy Tumble", minSeats: 2, maxSeats: 6 } };

describe("Home's game shelf", () => {
  test("names and seats every game the server has, exactly as the server does", () => {
    const server = Object.keys(GAMES).filter((id) => !NOT_YET.includes(id));
    expect(GAME_IDS.filter((id) => !(id in AHEAD) || server.includes(id))).toEqual(server);
    for (const id of GAME_IDS) {
      const theirs = id in GAMES ? { title: gameTitle(id), ...GAMES[id as keyof typeof GAMES] } : AHEAD[id];
      expect(theirs, id).toBeDefined();
      expect(CATALOG[id].title).toBe(theirs!.title);
      expect(CATALOG[id].minSeats).toBe(theirs!.minSeats);
      expect(CATALOG[id].maxSeats).toBe(theirs!.maxSeats);
    }
    expect(titleOf("chess")).toBe(gameTitle("chess"));
  });

  test("keeps Toy Tumble off the shelf until the build turns it on", () => {
    expect(SHELF).toEqual(["cat-tower", "tiles", "birdwatch"]);
    expect(GAME_IDS).toContain("tumble");
  });
});
