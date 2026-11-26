/**
 * The games on Home's shelf: their names, seats and posters. The names and seat counts are the
 * server's (`games/index.ts`), copied here only so Home doesn't load both games' rules before a
 * table opens; tests/catalog.test.ts fails the build if they ever differ.
 */
export type GameId = "cat-tower" | "tiles" | "birdwatch" | "purrtrait";

/** `tv`: only a TV makes this game's table (Purrtrait, played in one room on the TV's easel). */
export const CATALOG: Record<GameId, { title: string; minSeats: number; maxSeats: number; tagline: string; art: string; tv?: true }> = {
  "cat-tower": { title: "Cat Tower", minSeats: 2, maxSeats: 6, tagline: "Rummy up a ten-shelf tower.", art: "game-cat-tower" },
  tiles: { title: "Tuna Tiles", minSeats: 2, maxSeats: 4, tagline: "Tile rummy. Yarn is wild.", art: "game-tiles" },
  birdwatch: { title: "Birdwatch", minSeats: 4, maxSeats: 6, tagline: "Bid, call trump, take tricks.", art: "game-birdwatch" },
  purrtrait: { title: "Purrtrait", minSeats: 2, maxSeats: 10, tagline: "Draw it. The room guesses.", art: "game-purrtrait", tv: true },
};

export const GAME_IDS = Object.keys(CATALOG) as GameId[];

export const titleOf = (id: string | undefined): string => (id && id in CATALOG ? CATALOG[id as GameId].title : "a newer game");
