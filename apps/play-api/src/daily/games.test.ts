import { describe, expect, it } from "vitest";

import { DAILY_GAMES, DAILY_TITLES, DISH_APP, DISH_ORDER, dailyModule, dishListed, listedGames, makeDaily } from "./games";
import { cycleKey, dailySeed } from "./seed";
import { testGame } from "./test-game";

import type { DailyModule } from "./module";
import type { Rng } from "../rules/rng";

describe("the daily game registry", () => {
  it("dailyModule hides test unless DAILY_TEST", () => {
    expect(dailyModule("test", {})).toBeNull();
    expect(dailyModule("test", { DAILY_TEST: "off" })).toBeNull();
    expect(dailyModule("test", { DAILY_TEST: "on" })).toBe(testGame);
  });

  it("knows only listed games", () => {
    expect(dailyModule("sniff", { DAILY_TEST: "on" })).toBe(DAILY_GAMES.sniff ?? null);
    expect(dailyModule("chess", { DAILY_TEST: "on" })).toBeNull();
    expect(dailyModule("constructor", { DAILY_TEST: "on" })).toBeNull();
    expect(dailyModule("__proto__", { DAILY_TEST: "on" })).toBeNull();
  });

  it("each module's id is its key", () => {
    for (const [id, module] of Object.entries(DAILY_GAMES)) expect(module?.id).toBe(id);
  });
});

describe("listedGames", () => {
  it("lists the games with a module, in the Dish's order", () => {
    expect(listedGames({ DAILY_TEST: "on" }).map((m) => m.id)).toEqual(DISH_ORDER.filter((id) => dailyModule(id, { DAILY_TEST: "on" })));
    expect(listedGames({}).map((m) => m.id)).not.toContain("test");
  });

  it("orders the four games as the reminder names them, test last", () => {
    expect(DISH_ORDER).toEqual(["sniff", "nine-lives", "cat-nap", "box-fort", "test"]);
  });
});

describe("DAILY_TITLES", () => {
  it("names every game in plain words, as push copy and the board say them", () => {
    expect(DAILY_TITLES).toEqual({ sniff: "Sniff", "nine-lives": "Nine Lives", "cat-nap": "Cat Nap", "box-fort": "Box Fort", test: "Test" });
  });
});

describe("makeDaily", () => {
  it("makes the day's puzzle from its seed and level, and hands the game its date and cycle key", async () => {
    const secret = "s".repeat(64);
    const calls: { first: number; level: number; day: unknown }[] = [];
    const spy = { ...testGame, make: (rng: Rng, level: number, day: unknown) => (calls.push({ first: rng(), level, day }), { target: 1 }) } as unknown as DailyModule;
    expect(await makeDaily(spy, secret, "sniff", "2026-11-24")).toEqual({ target: 1 });
    const { createRng } = await import("../rules/rng");
    expect(calls).toEqual([
      { first: createRng(await dailySeed(secret, "sniff", "2026-11-24"))(), level: 2, day: { date: "2026-11-24", key: await cycleKey(secret, "sniff") } },
    ]);
  });
});

describe("dishListed (X-Pounce-Games)", () => {
  it("is true when the app lists dish among its games, in any case and spacing", () => {
    expect(DISH_APP).toBe("dish");
    expect(dishListed("tiles,dish")).toBe(true);
    expect(dishListed(" Dish ")).toBe(true);
    expect(dishListed("tiles")).toBe(false);
    expect(dishListed("dishes")).toBe(false);
    expect(dishListed(null)).toBe(false);
  });
});
