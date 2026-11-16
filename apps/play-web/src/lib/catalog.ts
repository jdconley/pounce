/**
 * The games on Home's shelf: their names, seats and posters. The names and seat counts are the
 * server's (`games/index.ts`), copied here only so Home doesn't load both games' rules before a
 * table opens; tests/catalog.test.ts fails the build if they ever differ.
 */
export type GameId = "cat-tower" | "tiles";

export const CATALOG: Record<GameId, { title: string; minSeats: number; maxSeats: number; tagline: string; art: string }> = {
  "cat-tower": { title: "Cat Tower", minSeats: 2, maxSeats: 6, tagline: "Rummy up a ten-shelf tower.", art: "game-cat-tower" },
  tiles: { title: "Tuna Tiles", minSeats: 2, maxSeats: 4, tagline: "Tile rummy. Yarn is wild.", art: "game-tiles" },
};

export const GAME_IDS = Object.keys(CATALOG) as GameId[];

export const titleOf = (id: string | undefined): string => (id && id in CATALOG ? CATALOG[id as GameId].title : "a newer game");
