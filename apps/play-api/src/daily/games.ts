import { testGame } from "./test-game";

import type { DailyGameId, DailyModule } from "./module";
import type { Env } from "../env";

/**
 * The daily games the server can referee. Each game session adds its own line here (map plan,
 * "The contracts"). `test` is listed only with `DAILY_TEST` on (`dailyModule`).
 */
export const DAILY_GAMES: Partial<Record<DailyGameId, DailyModule>> = {
  test: testGame as DailyModule,
};

/** The module for `id`, or null for an unknown or unlisted game. */
export function dailyModule(id: string, env: Pick<Env, "DAILY_TEST">): DailyModule | null {
  if (id === "test" && env.DAILY_TEST !== "on") return null;
  return Object.hasOwn(DAILY_GAMES, id) ? (DAILY_GAMES[id as DailyGameId] as DailyModule) : null;
}

/** The order the Dish lists its games in (and the reminder picks the first unplayed one by). */
export const DISH_ORDER: readonly DailyGameId[] = ["sniff", "nine-lives", "cat-nap", "box-fort", "test"];

/** The games this server referees now, in the Dish's order. */
export function listedGames(env: Pick<Env, "DAILY_TEST">): DailyModule[] {
  return DISH_ORDER.map((id) => dailyModule(id, env)).filter((m): m is DailyModule => m !== null);
}

/** Each game's name, for push copy (the names are placeholders until JD has seen them: spec §1). */
export const DAILY_TITLES: Record<DailyGameId, string> = {
  sniff: "Sniff",
  "nine-lives": "Nine Lives",
  "cat-nap": "Cat Nap",
  "box-fort": "Box Fort",
  test: "Test",
};
