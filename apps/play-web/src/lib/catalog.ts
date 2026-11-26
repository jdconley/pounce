/**
 * The games on Home's shelf: their names, seats and posters. The names and seat counts are the
 * server's (`games/index.ts`), copied here only so Home doesn't load both games' rules before a
 * table opens; tests/catalog.test.ts fails the build if they ever differ.
 */
import { TUMBLE_ON } from "./env";

export type GameId = "cat-tower" | "tiles" | "birdwatch" | "tumble";

export const CATALOG: Record<GameId, { title: string; minSeats: number; maxSeats: number; tagline: string; art: string }> = {
  "cat-tower": { title: "Cat Tower", minSeats: 2, maxSeats: 6, tagline: "Rummy up a ten-shelf tower.", art: "game-cat-tower" },
  tiles: { title: "Tuna Tiles", minSeats: 2, maxSeats: 4, tagline: "Tile rummy. Yarn is wild.", art: "game-tiles" },
  birdwatch: { title: "Birdwatch", minSeats: 4, maxSeats: 6, tagline: "Bid, call trump, take tricks.", art: "game-birdwatch" },
  tumble: { title: "Toy Tumble", minSeats: 2, maxSeats: 6, tagline: "Drop toys. Clear rows. Play tricks.", art: "game-tumble" },
};

/** Every game this player draws, at a table it joins. */
export const GAME_IDS = Object.keys(CATALOG) as GameId[];

/**
 * The games Home and the TV offer a new table of. Toy Tumble stays off the shelf until the server
 * deals it (`GAMES` lists `tumble`) and the build turns it on (`WEB_TUMBLE=on`); a table someone
 * else made still draws.
 */
export const SHELF: GameId[] = GAME_IDS.filter((id) => id !== "tumble" || TUMBLE_ON);

export const titleOf = (id: string | undefined): string => (id && id in CATALOG ? CATALOG[id as GameId].title : "a newer game");
