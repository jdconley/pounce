import { olderThan, parseApp, UNIDENTIFIED_VERSION, WEB_PLATFORM } from "../app/version";

import { birdwatch } from "./birdwatch";
import { catTower } from "./cat-tower";
import { purrtrait } from "./purrtrait";
import { tiles } from "./tiles";
import { tumble, type TumbleError, type TumbleOptions } from "./tumble";

import type { GameModule } from "./module";
import type { BirdAction, BirdError, BirdEvent, BirdOptions } from "../birdwatch/engine";
import type { PurrAction, PurrError, PurrEvent, PurrOptions } from "../purrtrait/engine";
import type { Action, ApplyError, GameEvent } from "../rules/engine";
import type { TilesAction, TilesError, TilesEvent } from "../tiles/engine";

/** Every game a room can hold, by its stable id. */
export const GAMES = { "cat-tower": catTower, tiles, birdwatch, purrtrait, tumble } as const;

export type GameId = keyof typeof GAMES;

/** The game every room played before rooms had a choice, and the one a client that names none can draw. */
export const DEFAULT_GAME: GameId = "cat-tower";

export const isGameId = (v: unknown): v is GameId => typeof v === "string" && Object.hasOwn(GAMES, v);

/**
 * Each game's name, as the app's shelf says it (`GameCatalog` in PounceKit): what an app that
 * can't draw a game is told the table is playing, in a card or a push. Names, so not translated.
 */
const TITLES: Record<GameId, string> = {
  "cat-tower": "Cat Tower",
  tiles: "Tuna Tiles",
  birdwatch: "Birdwatch",
  purrtrait: "Purrtrait",
  tumble: "Toy Tumble",
};

/** The name of a table's game. One this server has no name for (never stored today) is "a newer game". */
export const gameTitle = (id: string): string => (isGameId(id) ? TITLES[id] : "a newer game");

/**
 * A game's action, as the wire types it. Toy Tumble's two (Play without and Leave,
 * `TumbleAction` in `./tumble`) travel in the same `act` message, but stay out of this union for
 * now, so the clients that read it as cards and tiles keep compiling until they draw Toy Tumble.
 */
export type GameAction = Action | TilesAction | BirdAction | PurrAction;
export type GameError = ApplyError | TilesError | BirdError | PurrError | TumbleError;
export type AnyGameEvent = GameEvent | TilesEvent | BirdEvent | PurrEvent;
/** What a table may choose in its lobby, for the games that have a choice. */
export type GameOptions = BirdOptions;
/** Options of any game the wire types: Birdwatch's rule set or Purrtrait's. `GameOptions` stays Birdwatch's, which is all the web player draws. */
export type AnyGameOptions = BirdOptions | PurrOptions;
/**
 * What a room keeps of its lobby's choice, for every game that has one. Toy Tumble's (`{cats}`)
 * is sent in the same `options` field, outside the wire's `AnyGameOptions` for the reason above.
 */
export type RoomOptions = AnyGameOptions | TumbleOptions;

/**
 * A game as a room holds it: the state is the room's to keep, and actions,
 * views and events pass through without the room looking inside them.
 */
export type RoomGame<S = unknown> = GameModule<S, unknown, unknown, unknown, GameError, RoomOptions>;

/** The module for a stored room's `game`. A room saved before rooms had one is Cat Tower. */
export function gameModule(id: string | undefined): RoomGame {
  return (isGameId(id) ? GAMES[id] : GAMES[DEFAULT_GAME]) as RoomGame;
}

/** A game whose tables are same room only (Purrtrait): only a screen makes them, and only its near key lets a phone in. */
export const sameRoomGame = (id: string): boolean => isGameId(id) && gameModule(id).sameRoom === true;

/** The header an app lists the games it can draw in, comma separated. An app that sends none draws Cat Tower only. */
export const GAMES_HEADER = "x-pounce-games";

/**
 * The games a list names: always Cat Tower, plus whatever it lists that exists. An app's list
 * goes through `gamesFor`, which also asks its version.
 */
export function gamesListed(header: string | null): GameId[] {
  const listed = (header ?? "").split(",").map((id) => id.trim().toLowerCase());
  return [DEFAULT_GAME, ...listed.filter((id): id is GameId => isGameId(id) && id !== DEFAULT_GAME)].filter(
    (id, i, all) => all.indexOf(id) === i,
  );
}

/**
 * The oldest app version given a game, for a game that needs one newer than the first app to
 * list it: a test build may list a game before the version that has it is out.
 */
export const GAME_MIN_APP: Partial<Record<GameId, string>> = { tumble: "1.4" };

/**
 * The games a request's app can draw: what its `X-Pounce-Games` lists, less any game its
 * version (`X-Pounce-App`, `app`) is too old for (`GAME_MIN_APP`). The web player ships with
 * the server, so it is never too old. An app that doesn't say what it is is 1.0. `dev`: a dev
 * server, which skips the versions.
 */
export function gamesFor(header: string | null, app: string | null | undefined, dev: boolean): GameId[] {
  const listed = gamesListed(header);
  const identity = parseApp(app);
  if (dev || identity?.platform === WEB_PLATFORM) return listed;
  const version = identity?.version ?? UNIDENTIFIED_VERSION;
  return listed.filter((id) => {
    const min = GAME_MIN_APP[id];
    return min === undefined || !olderThan(version, min);
  });
}

/**
 * The games rooms may be created for (the `GAMES` flag, see `Env.GAMES`):
 * always Cat Tower, plus the ids it lists. Off or unset, only Cat Tower.
 */
export function gamesOn(env: { GAMES?: string }): GameId[] {
  return gamesListed(env.GAMES ?? null);
}
