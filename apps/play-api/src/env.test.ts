import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { devSpeed } from "./env";
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
