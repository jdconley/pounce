import { describe, expect, test } from "vitest";

import { localToInstant } from "../streaks/clock";

import { dayType, emptyPlaytime, learnedMinutes, recordPlay } from "./playtime";

const LA = "America/Los_Angeles";
const at = (day: string, hhmm: string) => {
  const [h, m] = hhmm.split(":").map(Number) as [number, number];
  return localToInstant(day, h * 60 + m, LA);
};

describe("dayType", () => {
  test("Saturday and Sunday are the weekend", () => {
    expect(dayType("2026-11-06")).toBe("weekday");
    expect(dayType("2026-11-07")).toBe("weekend");
    expect(dayType("2026-11-08")).toBe("weekend");
    expect(dayType("2026-11-09")).toBe("weekday");
  });
});

describe("the playtime histogram (§12.3)", () => {
  test("five weekdays at 20:10 learn 20:00, 15 minutes before the bucket's middle", () => {
    const p = emptyPlaytime();
    for (const d of ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"]) recordPlay(p, at(d, "20:10"), LA);
    expect(learnedMinutes(p, "weekday")).toBe(20 * 60);
  });

  test("fewer than five days of data learns nothing", () => {
    const p = emptyPlaytime();
    for (const d of ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05"]) recordPlay(p, at(d, "20:10"), LA);
    expect(learnedMinutes(p, "weekday")).toBeNull();
  });

  test("only the first turn of each day counts", () => {
    const p = emptyPlaytime();
    recordPlay(p, at("2026-11-02", "09:00"), LA);
    recordPlay(p, at("2026-11-02", "21:00"), LA);
    expect(p.days.weekday).toBe(1);
    expect(p.weekday[18]).toBe(1);
    expect(p.weekday[42]).toBe(0);
    // A late report for an earlier day changes nothing.
    recordPlay(p, at("2026-11-01", "21:00"), LA);
    expect(p.days).toEqual({ weekday: 1, weekend: 0 });
  });

  test("the median runs in day order from 04:00, so late-night turns sit after the evening", () => {
    const p = emptyPlaytime();
    recordPlay(p, at("2026-11-02", "20:00"), LA);
    recordPlay(p, at("2026-11-04", "00:30"), LA); // tonight for 11-03
    recordPlay(p, at("2026-11-05", "00:30"), LA); // tonight for 11-04
    recordPlay(p, at("2026-11-05", "23:30"), LA);
    recordPlay(p, at("2026-11-06", "20:00"), LA);
    expect(learnedMinutes(p, "weekday")).toBe(23 * 60 + 30);
  });

  test("old weights decay by 0.85 a day, so recent habits win", () => {
    const p = emptyPlaytime();
    for (const d of ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"]) recordPlay(p, at(d, "08:00"), LA);
    for (const d of ["2026-11-16", "2026-11-17", "2026-11-18"]) recordPlay(p, at(d, "21:00"), LA);
    expect(learnedMinutes(p, "weekday")).toBe(21 * 60);
  });

  test("a day type with no data uses the other's median", () => {
    const p = emptyPlaytime();
    for (const d of ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"]) recordPlay(p, at(d, "19:00"), LA);
    expect(learnedMinutes(p, "weekend")).toBe(19 * 60);
    recordPlay(p, at("2026-11-07", "10:00"), LA);
    expect(learnedMinutes(p, "weekend")).toBe(10 * 60);
    const weekends = emptyPlaytime();
    for (const d of ["2026-11-07", "2026-11-08", "2026-11-14", "2026-11-15", "2026-11-21"]) recordPlay(weekends, at(d, "11:00"), LA);
    expect(learnedMinutes(weekends, "weekday")).toBe(11 * 60);
  });
});
