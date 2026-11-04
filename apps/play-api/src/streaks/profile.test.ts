import { describe, expect, it } from "vitest";

import { quietStartMinutes, streaksOn } from "./profile";

import type { Json } from "../players/parse";

describe("quietStartMinutes", () => {
  it("reads the synced quiet.start setting", () => {
    expect(quietStartMinutes({ "quiet.start": { v: { h: 23, m: 30 }, at: 1 } }, "adult")).toBe(23 * 60 + 30);
    expect(quietStartMinutes({ "quiet.start": { v: { h: 0, m: 0 }, at: 1 } }, "teen")).toBe(0);
  });

  it("falls back to the band's default when it's missing or malformed", () => {
    expect(quietStartMinutes({}, "adult")).toBe(22 * 60);
    expect(quietStartMinutes({}, null)).toBe(22 * 60);
    expect(quietStartMinutes({}, "teen")).toBe(21 * 60);
    const bad: Json[] = [null, "22:00", { h: 24, m: 0 }, { h: 3, m: 60 }, { h: 1.5, m: 0 }, { h: 3 }, [1, 2]];
    for (const v of bad) {
      expect(quietStartMinutes({ "quiet.start": { v, at: 1 } }, "adult")).toBe(22 * 60);
    }
  });
});

describe("streaksOn", () => {
  it("is off unless STREAKS says on", () => {
    expect(streaksOn({})).toBe(false);
    expect(streaksOn({ STREAKS: "" })).toBe(false);
    expect(streaksOn({ STREAKS: "off" })).toBe(false);
    expect(streaksOn({ STREAKS: "0" })).toBe(false);
    for (const on of ["on", "1", "true", "ON"]) expect(streaksOn({ STREAKS: on })).toBe(true);
  });
});
