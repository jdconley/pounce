import type { Dish, GameBoard } from "./board";
import type { DailyResult } from "./module";
import type { Day } from "../streaks/clock";

/**
 * What the board socket says (docs/daily-protocol.md), pure. A row's `player` is "me" for the
 * board's owner and the pair id for a connection: never a player id.
 */
export type BoardAnswer = { date: Day; games: GameBoard[]; dish: Dish };

/**
 * What a run tells its player's boards as it goes (`DailyRun`): its progress, and with Show on
 * TV on, the offer, each frame of its public state, and its end.
 */
export type DailyEvent =
  | { k: "progress"; game: string; date: Day; progress: number }
  | { k: "watchOffer"; game: string }
  | { k: "watch"; game: string; state: unknown }
  | { k: "watchEnd"; game: string; result: DailyResult | null };

export type BoardMessage =
  | { t: "board"; board: BoardAnswer }
  | { t: "result"; player: string; result: DailyResult }
  | { t: "progress"; player: string; game: string; progress: number }
  | { t: "watchOffer"; player: string; name: string; cat: number; game: string }
  | { t: "watch"; player: string; game: string; state: unknown }
  | { t: "watchEnd"; player: string; game: string; result: DailyResult | null };

/** A run ended: its result, then the board as it now stands. */
export function resultMessages(player: string, result: DailyResult, board: BoardAnswer): BoardMessage[] {
  return [
    { t: "result", player, result },
    { t: "board", board },
  ];
}

/** A live event as a message, and who hears it: progress every board socket, watching TVs only. */
export function liveMessage(player: string, face: { name: string; cat: number }, e: DailyEvent): { to: "all" | "tv"; message: BoardMessage } {
  if (e.k === "progress") return { to: "all", message: { t: "progress", player, game: e.game, progress: e.progress } };
  if (e.k === "watchOffer") return { to: "tv", message: { t: "watchOffer", player, name: face.name, cat: face.cat, game: e.game } };
  if (e.k === "watch") return { to: "tv", message: { t: "watch", player, game: e.game, state: e.state } };
  return { to: "tv", message: { t: "watchEnd", player, game: e.game, result: e.result } };
}
