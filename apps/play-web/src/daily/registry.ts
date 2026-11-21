/**
 * The daily games the web player can host. Each game adds one line: its `dish.tsx`, loaded in its
 * own chunk when it's played or watched. The Dish shows a game only when the server lists it too
 * (a game the server doesn't referee answers 404 and stays hidden).
 */
import type { DailyGame } from "./host";
import type { DailyGameId } from "@pounce/play-api/daily/module";

export type DailyGameLoader = () => Promise<{ default: DailyGame<any, any, any, any> }>; // eslint-disable-line @typescript-eslint/no-explicit-any

export const DAILY_WEB_GAMES: Partial<Record<DailyGameId, DailyGameLoader>> = {
  test: () => import("./test-game"),
};
