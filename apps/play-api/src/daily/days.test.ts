import { describe, expect, it } from "vitest";

import { FALLBACK_ZONE } from "../streaks/clock";

import { closesAt, dailyDay, LAUNCH, levelFor, puzzleNumber } from "./days";

const LA = "America/Los_Angeles";
const KIRITIMATI = "Pacific/Kiritimati";
const utc = (y: number, mo: number, d: number, h: number, mi = 0) => Date.UTC(y, mo - 1, d, h, mi);

describe("levels and numbers", () => {
  it("levelFor maps Mon..Sun to 1..7", () => {
    const week = ["2026-11-23", "2026-11-24", "2026-11-25", "2026-11-26", "2026-11-27", "2026-11-28", "2026-11-29"];
    expect(week.map(levelFor)).toEqual([1, 2, 3, 4, 5, 6, 7]);
  });

  it("puzzleNumber is 1 on LAUNCH", () => {
    expect(puzzleNumber(LAUNCH)).toBe(1);
  });

  it("puzzleNumber counts up from LAUNCH", () => {
    expect(puzzleNumber("2099-01-12")).toBe(12);
  });

  it("closesAt is the end of the date's day: 04:00 the next morning", () => {
    expect(closesAt("2026-11-23", LA)).toBe(utc(2026, 11, 24, 12));
  });
});

describe("dailyDay", () => {
  const locked = { zone: LA, since: "2026-01-01" };

  it("dailyDay rolls at 04:00 local, DST included", () => {
    // 2026-03-08: clocks spring forward, so 04:00 PDT is 11:00 UTC.
    expect(dailyDay(utc(2026, 3, 8, 10, 59), locked, LA).day).toBe("2026-03-07");
    expect(dailyDay(utc(2026, 3, 8, 11, 0), locked, LA).day).toBe("2026-03-08");
    // 2026-11-01: clocks fall back, so 04:00 PST is 12:00 UTC.
    expect(dailyDay(utc(2026, 11, 1, 11, 59), locked, LA).day).toBe("2026-10-31");
    expect(dailyDay(utc(2026, 11, 1, 12, 0), locked, LA).day).toBe("2026-11-01");
  });

  it("keeps a locked zone the player still reports, or reports nothing for", () => {
    expect(dailyDay(utc(2026, 11, 23, 20), locked, LA)).toEqual({ day: "2026-11-23", zone: locked });
    expect(dailyDay(utc(2026, 11, 23, 20), locked, null)).toEqual({ day: "2026-11-23", zone: locked });
  });

  it("a zone hop east doesn't open tomorrow early", () => {
    // 20:00 in LA on the 23rd is 18:00 on the 24th in Kiritimati.
    const at = utc(2026, 11, 24, 4);
    const hop = dailyDay(at, locked, KIRITIMATI);
    expect(hop.day).toBe("2026-11-23");
    expect(hop.zone).toEqual({ zone: KIRITIMATI, since: "2026-11-24", before: LA });
    // Asked again just before LA's 04:00, still LA's day.
    expect(dailyDay(utc(2026, 11, 24, 11, 59), hop.zone, KIRITIMATI).day).toBe("2026-11-23");
  });

  it("the new zone applies after the next 04:00", () => {
    const hop = dailyDay(utc(2026, 11, 24, 4), locked, KIRITIMATI).zone;
    // LA's 04:00 on the 24th is 02:00 on the 25th in Kiritimati: its day is the 24th.
    const after = dailyDay(utc(2026, 11, 24, 12), hop, KIRITIMATI);
    expect(after).toEqual({ day: "2026-11-24", zone: { zone: KIRITIMATI, since: "2026-11-24" } });
    // And from then on, Kiritimati's own 04:00.
    expect(dailyDay(utc(2026, 11, 24, 14), after.zone, KIRITIMATI).day).toBe("2026-11-25");
  });

  it("a hop west never goes back a day", () => {
    const kiri = { zone: KIRITIMATI, since: "2026-01-01" };
    // 20:00 on the 23rd in Kiritimati is 22:00 on the 22nd in LA.
    const hop = dailyDay(utc(2026, 11, 23, 6), kiri, LA);
    expect(hop.day).toBe("2026-11-23");
    // Kiritimati's next 04:00 (14:00 UTC on the 23rd) is 06:00 in LA, on the 23rd: the same day.
    const after = dailyDay(utc(2026, 11, 23, 14), hop.zone, LA);
    expect(after.day).toBe("2026-11-23");
    expect(after.zone).toEqual({ zone: LA, since: "2026-11-24" });
  });

  it("a second hop before the first applies keeps the zone that rules today", () => {
    const hop = dailyDay(utc(2026, 11, 24, 4), locked, KIRITIMATI).zone;
    const again = dailyDay(utc(2026, 11, 24, 5), hop, "Asia/Tokyo");
    expect(again).toEqual({ day: "2026-11-23", zone: { zone: "Asia/Tokyo", since: "2026-11-24", before: LA } });
    // Hopping back home before the switch drops the pending change.
    expect(dailyDay(utc(2026, 11, 24, 6), again.zone, LA)).toEqual({ day: "2026-11-23", zone: { zone: LA, since: "2026-11-23" } });
  });

  it("locks the first zone a player reports", () => {
    expect(dailyDay(utc(2026, 11, 23, 20), null, LA)).toEqual({ day: "2026-11-23", zone: { zone: LA, since: "2026-11-23" } });
  });

  it("no zone uses FALLBACK_ZONE", () => {
    expect(dailyDay(utc(2026, 11, 23, 20), null, null)).toEqual({ day: "2026-11-23", zone: { zone: FALLBACK_ZONE, since: "2026-11-23" } });
    expect(dailyDay(utc(2026, 11, 23, 20), null, "Not/AZone")).toEqual({ day: "2026-11-23", zone: { zone: FALLBACK_ZONE, since: "2026-11-23" } });
  });

  it("ignores a reported zone that isn't one", () => {
    expect(dailyDay(utc(2026, 11, 23, 20), locked, "Not/AZone")).toEqual({ day: "2026-11-23", zone: locked });
  });
});
