import { describe, expect, it } from "vitest";

import {
  addDays,
  cutoffAt,
  dayEnd,
  dayKey,
  daysBetween,
  dayStart,
  FALLBACK_ZONE,
  isZone,
  localMinutes,
  localToInstant,
} from "./clock";

const LA = "America/Los_Angeles";
const NY = "America/New_York";
const HOUR = 3_600_000;
const utc = (y: number, mo: number, d: number, h: number, mi = 0) => Date.UTC(y, mo - 1, d, h, mi);

describe("dayKey", () => {
  it("rolls over at 04:00 local", () => {
    // 2026-11-04 is PST, UTC-8.
    expect(dayKey(utc(2026, 11, 4, 11, 59), LA)).toBe("2026-11-03");
    expect(dayKey(utc(2026, 11, 4, 12, 1), LA)).toBe("2026-11-04");
  });

  it("counts a turn at 1 a.m. as tonight", () => {
    expect(dayKey(utc(2026, 11, 5, 9), LA)).toBe("2026-11-04");
  });

  it("uses each person's own zone", () => {
    // 02:00 in LA is 05:00 in New York.
    const at = utc(2026, 11, 5, 10);
    expect(dayKey(at, LA)).toBe("2026-11-04");
    expect(dayKey(at, NY)).toBe("2026-11-05");
  });

  it("rolls over at 04:00 on the morning the clocks spring forward", () => {
    // 2026-03-08: 02:00 PST becomes 03:00 PDT, so 04:00 local is 11:00 UTC.
    expect(dayKey(utc(2026, 3, 8, 10, 59), LA)).toBe("2026-03-07");
    expect(dayKey(utc(2026, 3, 8, 11, 1), LA)).toBe("2026-03-08");
  });

  it("rolls over at 04:00 on the morning the clocks fall back", () => {
    // 2026-11-01: 02:00 PDT becomes 01:00 PST, so 04:00 local is 12:00 UTC.
    expect(dayKey(utc(2026, 11, 1, 11, 59), LA)).toBe("2026-10-31");
    expect(dayKey(utc(2026, 11, 1, 12, 1), LA)).toBe("2026-11-01");
  });
});

describe("day bounds", () => {
  it("are 04:00 to 04:00 local", () => {
    expect(dayStart("2026-11-04", LA)).toBe(utc(2026, 11, 4, 12));
    expect(dayEnd("2026-11-04", LA)).toBe(utc(2026, 11, 5, 12));
    expect(dayStart("2026-11-04", NY)).toBe(utc(2026, 11, 4, 9));
  });

  it("make a DST day 23 or 25 hours long", () => {
    expect(dayEnd("2026-03-07", LA) - dayStart("2026-03-07", LA)).toBe(23 * HOUR);
    expect(dayEnd("2026-10-31", LA) - dayStart("2026-10-31", LA)).toBe(25 * HOUR);
    expect(dayEnd("2026-03-08", LA) - dayStart("2026-03-08", LA)).toBe(24 * HOUR);
  });

  it("converts wall time past midnight to the next date", () => {
    expect(localToInstant("2026-11-04", 25 * 60, LA)).toBe(utc(2026, 11, 5, 9));
  });
});

describe("cutoffAt", () => {
  it("is two hours before quiet hours start", () => {
    expect(cutoffAt("2026-11-04", LA, 22 * 60)).toBe(utc(2026, 11, 5, 4));
    expect(localMinutes(cutoffAt("2026-11-04", LA, 21 * 60), LA)).toBe(19 * 60);
  });

  it("falls after midnight when quiet hours start after 02:00", () => {
    expect(cutoffAt("2026-11-04", LA, 60)).toBe(utc(2026, 11, 5, 7));
    expect(cutoffAt("2026-11-04", LA, 5 * 60)).toBe(utc(2026, 11, 5, 11));
  });

  it("never falls outside the day", () => {
    expect(cutoffAt("2026-11-04", LA, 5 * 60 + 30)).toBe(utc(2026, 11, 5, 11, 30));
    expect(cutoffAt("2026-11-04", LA, 6 * 60)).toBe(dayStart("2026-11-04", LA));
    expect(cutoffAt("2026-11-04", LA, 0)).toBe(utc(2026, 11, 5, 6));
  });
});

describe("calendar helpers", () => {
  it("adds and counts days", () => {
    expect(addDays("2026-12-31", 1)).toBe("2027-01-01");
    expect(addDays("2026-03-01", -1)).toBe("2026-02-28");
    expect(daysBetween("2026-11-01", "2026-11-08")).toBe(7);
    expect(daysBetween("2026-11-08", "2026-11-01")).toBe(-7);
  });

  it("knows a time zone", () => {
    expect(isZone(LA)).toBe(true);
    expect(isZone("Mars/Base")).toBe(false);
    expect(isZone(7)).toBe(false);
    expect(isZone("x".repeat(65))).toBe(false);
    expect(FALLBACK_ZONE).toBe(LA);
  });
});
