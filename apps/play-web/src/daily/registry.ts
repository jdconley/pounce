/**
 * The daily games the web player can host. Each game adds one line: where its play screen and its
 * TV watch view load from, each in its own chunk, so a TV never downloads a play screen. The Dish
 * shows a game only when the server lists it too (a game the server doesn't referee stays hidden).
 *
 *   "sniff": { play: () => import("./sniff/dish"), watch: () => import("./sniff/watch") },
 *
 * `dish.tsx` default-exports a `DailyGame`; `watch.tsx` default-exports a `DailyWatchView`.
 */
import type { DailyGame, DailyWatchView } from "./host";
import type { DailyGameId } from "@pounce/play-api/daily/module";

/* eslint-disable @typescript-eslint/no-explicit-any */
export type DailyEntry = {
  play: () => Promise<{ default: DailyGame<any, any, any, any> }>;
  watch: () => Promise<{ default: DailyWatchView<any, any> }>;
};
/* eslint-enable @typescript-eslint/no-explicit-any */

export const DAILY_WEB_GAMES: Partial<Record<DailyGameId, DailyEntry>> = {
  test: { play: () => import("./test-game"), watch: () => import("./test-watch") },
};
