import { catTower } from "./cat-tower";
import { tiles } from "./tiles";

import type { GameModule } from "./module";
import type { Action, ApplyError, GameEvent } from "../rules/engine";
import type { TilesAction, TilesError, TilesEvent } from "../tiles/engine";

/** Every game a room can hold, by its stable id. */
export const GAMES = { "cat-tower": catTower, tiles } as const;

export type GameId = keyof typeof GAMES;

/** The game every room played before rooms had a choice, and the one a client that names none can draw. */
export const DEFAULT_GAME: GameId = "cat-tower";

export const isGameId = (v: unknown): v is GameId => typeof v === "string" && Object.hasOwn(GAMES, v);

export type GameAction = Action | TilesAction;
export type GameError = ApplyError | TilesError;
export type AnyGameEvent = GameEvent | TilesEvent;

/**
 * A game as a room holds it: the state is the room's to keep, and actions,
 * views and events pass through without the room looking inside them.
 */
export type RoomGame<S = unknown> = GameModule<S, unknown, unknown, unknown, GameError>;

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
