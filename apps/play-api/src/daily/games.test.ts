import { describe, expect, it } from "vitest";

import { DAILY_GAMES, DISH_ORDER, dailyModule, listedGames } from "./games";
import { testGame } from "./test-game";

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
