import { createRng } from "../rules/rng";

import { catNap } from "./cat-nap/module";
import { levelFor } from "./days";
import { nineLives } from "./nine-lives/module";
import { cycleKey, dailySeed } from "./seed";
import { sniff } from "./sniff/module";
import { testGame } from "./test-game";

import type { DailyGameId, DailyModule } from "./module";
import type { Env } from "../env";
import type { Day } from "../streaks/clock";

/**
 * The daily games the server can referee. Each game session adds its own line here (map plan,
 * "The contracts"). `test` is listed only with `DAILY_TEST` on (`dailyModule`).
 */
export const DAILY_GAMES: Partial<Record<DailyGameId, DailyModule>> = {
  "cat-nap": catNap as DailyModule,
  "nine-lives": nineLives as DailyModule,
  sniff: sniff as DailyModule,
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

/** The whole puzzle for `game` on `date`: made from the day's seed and level, with the game's cycle key. Server only. */
export async function makeDaily(m: DailyModule, secret: string, game: DailyGameId, date: Day): Promise<unknown> {
  const [seed, key] = await Promise.all([dailySeed(secret, game, date), cycleKey(secret, game)]);
  return m.make(createRng(seed), levelFor(date), { date, key });
}

/**
 * What an app that has the Daily Dish lists in its `X-Pounce-Games` header, beside the table games
 * it can draw (`"tiles,dish"`). Only such a device is told about the Dish by push.
 */
export const DISH_APP = "dish";

/** The app sending this `X-Pounce-Games` header has the Dish. */
export function dishListed(header: string | null): boolean {
  return (header ?? "").split(",").some((id) => id.trim().toLowerCase() === DISH_APP);
}
