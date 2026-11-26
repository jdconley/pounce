import { birdwatch } from "./birdwatch";
import { catTower } from "./cat-tower";
import { purrtrait } from "./purrtrait";
import { tiles } from "./tiles";

import type { GameModule } from "./module";
import type { BirdAction, BirdError, BirdEvent, BirdOptions } from "../birdwatch/engine";
import type { PurrAction, PurrError, PurrEvent, PurrOptions } from "../purrtrait/engine";
import type { Action, ApplyError, GameEvent } from "../rules/engine";
import type { TilesAction, TilesError, TilesEvent } from "../tiles/engine";

/** Every game a room can hold, by its stable id. */
export const GAMES = { "cat-tower": catTower, tiles, birdwatch, purrtrait } as const;

export type GameId = keyof typeof GAMES;

/** The game every room played before rooms had a choice, and the one a client that names none can draw. */
export const DEFAULT_GAME: GameId = "cat-tower";

export const isGameId = (v: unknown): v is GameId => typeof v === "string" && Object.hasOwn(GAMES, v);

/**
 * Each game's name, as the app's shelf says it (`GameCatalog` in PounceKit): what an app that
 * can't draw a game is told the table is playing, in a card or a push. Names, so not translated.
 */
const TITLES: Record<GameId, string> = { "cat-tower": "Cat Tower", tiles: "Tuna Tiles", birdwatch: "Birdwatch", purrtrait: "Purrtrait" };

/** The name of a table's game. One this server has no name for (never stored today) is "a newer game". */
export const gameTitle = (id: string): string => (isGameId(id) ? TITLES[id] : "a newer game");

export type GameAction = Action | TilesAction | BirdAction | PurrAction;
export type GameError = ApplyError | TilesError | BirdError | PurrError;
export type AnyGameEvent = GameEvent | TilesEvent | BirdEvent | PurrEvent;
/** What a table may choose in its lobby, for the games that have a choice. */
export type GameOptions = BirdOptions;
/** Options of any game, as a room holds them. `GameOptions` stays Birdwatch's, which is all the web player draws. */
export type AnyGameOptions = BirdOptions | PurrOptions;

/**
 * A game as a room holds it: the state is the room's to keep, and actions,
 * views and events pass through without the room looking inside them.
 */
export type RoomGame<S = unknown> = GameModule<S, unknown, unknown, unknown, GameError, AnyGameOptions>;

/** The module for a stored room's `game`. A room saved before rooms had one is Cat Tower. */
export function gameModule(id: string | undefined): RoomGame {
  return (isGameId(id) ? GAMES[id] : GAMES[DEFAULT_GAME]) as RoomGame;
}

/** The header an app lists the games it can draw in, comma separated. An app that sends none draws Cat Tower only. */
export const GAMES_HEADER = "x-pounce-games";

/** The games a request's app can draw: always Cat Tower, plus whatever its header lists that exists. */
export function gamesListed(header: string | null): GameId[] {
  const listed = (header ?? "").split(",").map((id) => id.trim().toLowerCase());
  return [DEFAULT_GAME, ...listed.filter((id): id is GameId => isGameId(id) && id !== DEFAULT_GAME)].filter(
    (id, i, all) => all.indexOf(id) === i,
  );
}

/**
 * The games rooms may be created for (the `GAMES` flag, see `Env.GAMES`):
 * always Cat Tower, plus the ids it lists. Off or unset, only Cat Tower.
 */
export function gamesOn(env: { GAMES?: string }): GameId[] {
  return gamesListed(env.GAMES ?? null);
}
