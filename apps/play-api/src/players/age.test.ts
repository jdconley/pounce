import { describe, expect, it } from "vitest";

import { alertsBlocked, pushBlocked } from "./age";

// 2026-11-04 10:00 UTC is 02:00 in Los Angeles (PST, UTC-8).
const AT_2AM_PT = Date.UTC(2026, 10, 4, 10, 0);
const AT_6AM_PT = Date.UTC(2026, 10, 4, 14, 0);
const AT_559AM_PT = Date.UTC(2026, 10, 4, 13, 59);
const PT = "America/Los_Angeles";

describe("age-band push gates", () => {
  it("a kitten device gets no push at all", () => {
    expect(pushBlocked("kitten")).toBe(true);
    expect(pushBlocked("teen")).toBe(false);
    expect(pushBlocked("adult")).toBe(false);
    expect(pushBlocked(null)).toBe(false);
  });

  it("a teen gets no alerts from midnight to 6 a.m. local time", () => {
    expect(alertsBlocked("teen", PT, AT_2AM_PT)).toBe(true);
    expect(alertsBlocked("teen", PT, AT_559AM_PT)).toBe(true);
    expect(alertsBlocked("teen", PT, AT_6AM_PT)).toBe(false);
  });

  it("adults and unknown bands are never blocked by the clock", () => {
    expect(alertsBlocked("adult", PT, AT_2AM_PT)).toBe(false);
    expect(alertsBlocked(null, PT, AT_2AM_PT)).toBe(false);
  });

  it("a missing or unusable zone counts as UTC", () => {
    expect(alertsBlocked("teen", null, Date.UTC(2026, 10, 4, 3, 0))).toBe(true);
    expect(alertsBlocked("teen", "Mars/Base", Date.UTC(2026, 10, 4, 3, 0))).toBe(true);
    expect(alertsBlocked("teen", null, Date.UTC(2026, 10, 4, 12, 0))).toBe(false);
  });
});
