import { describe, expect, test } from "vitest";

import { localMinutes, localToInstant } from "../streaks/clock";

import { emptyPlaytime, recordPlay } from "./playtime";
import { clampReminder, lastChanceMinutes, reminderMinutes, slotAt } from "./schedule";
import { notifySettings } from "./settings";

const LA = "America/Los_Angeles";
const adult = notifySettings({}, "adult");
const fixed = notifySettings(
  {
    "reminders.auto": { v: false, at: 1 },
    "reminders.weekday": { v: { h: 18, m: 0 }, at: 1 },
    "reminders.weekend": { v: { h: 11, m: 0 }, at: 1 },
  },
  "adult",
);

describe("reminder times (§12.3)", () => {
  test("auto uses 19:30 until there's data, then the learned time", () => {
    expect(reminderMinutes("2026-11-04", adult, null)).toBe(1170);
    expect(reminderMinutes("2026-11-04", adult, emptyPlaytime())).toBe(1170);
    const p = emptyPlaytime();
    for (const d of ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"]) {
      recordPlay(p, localToInstant(d, 18 * 60 + 40, LA), LA);
    }
    expect(reminderMinutes("2026-11-09", adult, p)).toBe(18 * 60 + 30);
  });

  test("fixed times pick weekdays or weekends", () => {
    expect(reminderMinutes("2026-11-04", fixed, null)).toBe(18 * 60);
    expect(reminderMinutes("2026-11-07", fixed, null)).toBe(11 * 60);
  });

  test("clamped to at least 2 hours before quiet hours and never inside them", () => {
    expect(clampReminder(21 * 60 + 30, adult)).toBe(20 * 60);
    expect(clampReminder(6 * 60, adult)).toBe(8 * 60);
    expect(clampReminder(1 * 60, adult)).toBe(20 * 60);
    expect(clampReminder(12 * 60, adult)).toBe(12 * 60);
    expect(clampReminder(19 * 60 + 30, { ...adult, quietStart: 10 * 60, quietEnd: 12 * 60 })).toBe(8 * 60);
    expect(clampReminder(19 * 60 + 30, notifySettings({}, "teen"))).toBe(19 * 60);
  });

  test("last chance is 90 minutes before quiet hours", () => {
    expect(lastChanceMinutes(adult)).toBe(20 * 60 + 30);
    expect(lastChanceMinutes({ ...adult, quietStart: 30 })).toBe(23 * 60);
  });
});

describe("slotAt", () => {
  test("lands on the wall-clock time, DST days included", () => {
    for (const day of ["2026-03-08", "2026-11-01", "2026-11-04"]) {
      expect(localMinutes(slotAt(day, 1170, LA), LA)).toBe(1170);
    }
  });

  test("minutes before 04:00 run into the next date", () => {
    expect(slotAt("2026-11-04", 30, LA)).toBe(localToInstant("2026-11-05", 30, LA));
  });
});
