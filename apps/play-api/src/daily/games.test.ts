import { describe, expect, it } from "vitest";

import { DAILY_GAMES, dailyModule } from "./games";
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
