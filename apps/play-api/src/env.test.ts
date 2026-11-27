import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { dailyOn, devSpeed, purrtraitAppLinksOn, tvAppLinksOn, tvOn } from "./env";
import { gamesOn } from "./games";
import { liveOn, notifyOn, streaksOn, trophyOn } from "./streaks/profile";

describe("devSpeed", () => {
  it("is 1 unless DEV_SPEED is a number above 1", () => {
    expect(devSpeed({})).toBe(1);
    expect(devSpeed({ DEV_SPEED: "" })).toBe(1);
    expect(devSpeed({ DEV_SPEED: "fast" })).toBe(1);
    expect(devSpeed({ DEV_SPEED: "0.5" })).toBe(1);
    expect(devSpeed({ DEV_SPEED: "-10" })).toBe(1);
    expect(devSpeed({ DEV_SPEED: "Infinity" })).toBe(1);
  });

  it("speeds up to at most 100", () => {
    expect(devSpeed({ DEV_SPEED: "10" })).toBe(10);
    expect(devSpeed({ DEV_SPEED: "2.5" })).toBe(2.5);
    expect(devSpeed({ DEV_SPEED: "5000" })).toBe(100);
  });

  it("is never configured for deploys", () => {
    const config = readFileSync(new URL("../wrangler.jsonc", import.meta.url), "utf8");
    expect(config).not.toMatch(/DEV_SPEED/);
  });
});

describe("GAMES in production", () => {
  it("is listed in wrangler.jsonc and deals Cat Tower, the tile game, Birdwatch, Toy Tumble and Purrtrait", () => {
    const config = readFileSync(new URL("../wrangler.jsonc", import.meta.url), "utf8");
    const read = (key: string) => new RegExp(`"${key}"\\s*:\\s*"([^"]*)"`).exec(config)?.[1];
    const value = read("GAMES");
    expect(value).toBe("tiles,birdwatch,tumble,purrtrait");
    expect(gamesOn({ GAMES: value })).toEqual(["cat-tower", "tiles", "birdwatch", "tumble", "purrtrait"]);
    // Only a TV makes a Purrtrait table, so TV is on too. The TV's QR opens the app since 1.4 went
    // to App Review, so the reviewers see it; without the app it opens the web player.
    expect(tvOn({ TV: read("TV") })).toBe(true);
    expect(purrtraitAppLinksOn({ PURRTRAIT_APPLINKS: read("PURRTRAIT_APPLINKS") })).toBe(true);
  });

  it("is on for local dev, in the example .dev.vars, as in production", () => {
    const vars = readFileSync(new URL("../.dev.vars.example", import.meta.url), "utf8");
    const value = /^GAMES=(.*)$/m.exec(vars)?.[1];
    expect(gamesOn({ GAMES: value })).toEqual(["cat-tower", "tiles", "birdwatch", "tumble", "purrtrait"]);
  });
});

describe("STREAKS in production", () => {
  it("is on in wrangler.jsonc, with a value streaksOn accepts (the app's streak screens shipped)", () => {
    const config = readFileSync(new URL("../wrangler.jsonc", import.meta.url), "utf8");
    const value = /"STREAKS"\s*:\s*"([^"]*)"/.exec(config)?.[1];
    expect(value).toBeDefined();
    expect(streaksOn({ STREAKS: value })).toBe(true);
  });
});

describe("NOTIFY in production", () => {
  it("is on in wrangler.jsonc, with STREAKS, so notifyOn accepts it (the app's settings and Pounce shipped)", () => {
    const config = readFileSync(new URL("../wrangler.jsonc", import.meta.url), "utf8");
    const streaks = /"STREAKS"\s*:\s*"([^"]*)"/.exec(config)?.[1];
    const notify = /"NOTIFY"\s*:\s*"([^"]*)"/.exec(config)?.[1];
    expect(notify).toBeDefined();
    expect(notifyOn({ STREAKS: streaks, NOTIFY: notify })).toBe(true);
  });
});

describe("LIVE in production", () => {
  it("is on in wrangler.jsonc, with NOTIFY and STREAKS, so liveOn accepts it (the app half ships with it)", () => {
    const config = readFileSync(new URL("../wrangler.jsonc", import.meta.url), "utf8");
    const read = (key: string) => new RegExp(`"${key}"\\s*:\\s*"([^"]*)"`).exec(config)?.[1];
    expect(read("LIVE")).toBeDefined();
    expect(liveOn({ STREAKS: read("STREAKS"), NOTIFY: read("NOTIFY"), LIVE: read("LIVE") })).toBe(true);
  });
});

describe("TROPHY in production", () => {
  it("is on in wrangler.jsonc, with STREAKS, so trophyOn accepts it (the app half ships with it)", () => {
    const config = readFileSync(new URL("../wrangler.jsonc", import.meta.url), "utf8");
    const read = (key: string) => new RegExp(`"${key}"\\s*:\\s*"([^"]*)"`).exec(config)?.[1];
    expect(read("TROPHY")).toBeDefined();
    expect(trophyOn({ STREAKS: read("STREAKS"), TROPHY: read("TROPHY") })).toBe(true);
  });
});

describe("tvOn", () => {
  it("is on for the same words as the other flags, and off otherwise", () => {
    expect(tvOn({ TV: "on" })).toBe(true);
    expect(tvOn({ TV: "ON" })).toBe(true);
    expect(tvOn({})).toBe(false);
    expect(tvOn({ TV: "off" })).toBe(false);
  });
});

describe("tvAppLinksOn", () => {
  it("needs TV and TV_APPLINKS both on", () => {
    expect(tvAppLinksOn({ TV: "on", TV_APPLINKS: "on" })).toBe(true);
    expect(tvAppLinksOn({ TV: "on", TV_APPLINKS: "off" })).toBe(false);
    expect(tvAppLinksOn({ TV: "on" })).toBe(false);
    expect(tvAppLinksOn({ TV: "off", TV_APPLINKS: "on" })).toBe(false);
    expect(tvAppLinksOn({ TV_APPLINKS: "on" })).toBe(false);
  });
});

describe("DAILY", () => {
  it("is on in wrangler.jsonc since all four games launched together (spec §11)", () => {
    const config = readFileSync(new URL("../wrangler.jsonc", import.meta.url), "utf8");
    const value = /"DAILY"\s*:\s*"([^"]*)"/.exec(config)?.[1];
    expect(value).toBeDefined();
    expect(dailyOn({ DAILY: value })).toBe(true);
  });

  it("never lists the test-only game for deploys (DAILY_TEST)", () => {
    const config = readFileSync(new URL("../wrangler.jsonc", import.meta.url), "utf8");
    expect(config).not.toMatch(/DAILY_TEST/);
  });

  it("is on for the same words as the other flags, and off otherwise", () => {
    expect(dailyOn({ DAILY: "on" })).toBe(true);
    expect(dailyOn({ DAILY: "1" })).toBe(true);
    expect(dailyOn({ DAILY: "TRUE" })).toBe(true);
    expect(dailyOn({})).toBe(false);
    expect(dailyOn({ DAILY: "off" })).toBe(false);
  });
});
