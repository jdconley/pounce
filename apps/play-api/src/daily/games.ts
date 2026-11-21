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
