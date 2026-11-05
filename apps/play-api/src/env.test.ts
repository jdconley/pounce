import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { devSpeed } from "./env";
import { streaksOn } from "./streaks/profile";

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
