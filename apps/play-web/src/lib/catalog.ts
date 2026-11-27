/**
 * The games on Home's shelf: their names, seats and posters. The names and seat counts are the
 * server's (`games/index.ts`), copied here only so Home doesn't load both games' rules before a
 * table opens; tests/catalog.test.ts fails the build if they ever differ.
 */
import { PURRTRAIT_ON, TUMBLE_ON } from "./env";

export type GameId = "cat-tower" | "tiles" | "birdwatch" | "purrtrait" | "tumble";

/** `tv`: only a TV makes this game's table (Purrtrait, played in one room on the TV's easel). */
export const CATALOG: Record<GameId, { title: string; minSeats: number; maxSeats: number; tagline: string; art: string; tv?: true }> = {
  "cat-tower": { title: "Cat Tower", minSeats: 2, maxSeats: 6, tagline: "Rummy up a ten-shelf tower.", art: "game-cat-tower" },
  tiles: { title: "Tuna Tiles", minSeats: 2, maxSeats: 4, tagline: "Tile rummy. Yarn is wild.", art: "game-tiles" },
  birdwatch: { title: "Birdwatch", minSeats: 4, maxSeats: 6, tagline: "Bid, call trump, take tricks.", art: "game-birdwatch" },
  purrtrait: { title: "Purrtrait", minSeats: 2, maxSeats: 10, tagline: "Draw it. The room guesses.", art: "game-purrtrait", tv: true },
  tumble: { title: "Toy Tumble", minSeats: 2, maxSeats: 6, tagline: "Drop toys. Clear rows. Play tricks.", art: "game-tumble" },
};

/** Every game this player draws, at a table it joins. */
export const GAME_IDS = Object.keys(CATALOG) as GameId[];

/**
 * The games Home and the TV offer a new table of. Toy Tumble and Purrtrait stay off the shelf
 * until the server deals them (`GAMES` lists them) and the build turns them on (`WEB_TUMBLE=on`,
 * `WEB_PURRTRAIT=on`); a table someone else made still draws.
 */
export const SHELF: GameId[] = GAME_IDS.filter((id) => (id !== "tumble" || TUMBLE_ON) && (id !== "purrtrait" || PURRTRAIT_ON));

export const titleOf = (id: string | undefined): string => (id && id in CATALOG ? CATALOG[id as GameId].title : "a newer game");

/**
 * Birdwatch's rule sets by name, for Home's table cards ("Tucker rules"): the table's own copy is
 * `RULE_COPY` in `table/bw-model.ts`, kept out of Home so the card needs none of the game's code.
 * tests/catalog.test.ts holds the two to the same names.
 */
export const RULE_NAMES: Record<string, string> = { official: "Official", tucker: "Tucker", friesen: "Friesen" };

/** A tables-list entry's rule set as its card says it, or null for a game without one (or a rule set this player doesn't know). */
export function rulesLine(t: { game?: string; options?: { rules?: string } }): string | null {
  const name = t.game === "birdwatch" && t.options?.rules !== undefined ? RULE_NAMES[t.options.rules] : undefined;
  return name === undefined ? null : `${name} rules`;
}
