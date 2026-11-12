import { describe, expect, test } from "vitest";

import { localToInstant } from "../streaks/clock";

import { gate, inQuiet, isReminder, isSpaced, SPACING_MS, type NotifyKind } from "./policy";
import { notifySettings } from "./settings";

const LA = "America/Los_Angeles";
const at = (hhmm: string, day = "2026-11-04") => {
  const [h, m] = hhmm.split(":").map(Number) as [number, number];
  return localToInstant(day, h * 60 + m, LA);
};
const adult = notifySettings({}, "adult");
const base = { band: "adult" as const, zone: LA, settings: adult, spacedAt: null, remindersToday: 0 };

describe("inQuiet", () => {
  const q = { quietStart: 22 * 60, quietEnd: 8 * 60 };
  test("wraps midnight: [start, end)", () => {
    expect(inQuiet(23 * 60, q)).toBe(true);
    expect(inQuiet(7 * 60 + 59, q)).toBe(true);
    expect(inQuiet(8 * 60, q)).toBe(false);
    expect(inQuiet(21 * 60 + 59, q)).toBe(false);
    expect(inQuiet(22 * 60, q)).toBe(true);
  });
  test("a daytime window doesn't wrap", () => {
    const day = { quietStart: 10 * 60, quietEnd: 12 * 60 };
    expect(inQuiet(11 * 60, day)).toBe(true);
    expect(inQuiet(9 * 60, day)).toBe(false);
    expect(inQuiet(13 * 60, day)).toBe(false);
  });
  test("start equal to end means no quiet hours", () => {
    expect(inQuiet(3 * 60, { quietStart: 600, quietEnd: 600 })).toBe(false);
  });
});

describe("kinds", () => {
  test("reminder-type pushes are capped; your move and pounces aren't spaced", () => {
    const kinds: NotifyKind[] = ["reminder", "last_chance", "fresh_start", "going_quiet"];
    for (const k of kinds) expect(isReminder(k)).toBe(true);
    expect(isReminder("nap")).toBe(false);
    for (const k of ["your_move", "pounce", "pounce_answered", "nudge", "retire_soon", "retired", "update"] as NotifyKind[]) expect(isSpaced(k)).toBe(false);
    for (const k of ["reminder", "nap", "milestone", "play_again", "paused", "winback"] as NotifyKind[]) expect(isSpaced(k)).toBe(true);
  });
});

describe("gate", () => {
  test("a kitten player gets no reminders; delivery to a kitten's own device is the device's call (§14.1)", () => {
    const kitten = { ...base, band: "kitten" as const, settings: notifySettings({}, "kitten") };
    for (const kind of ["reminder", "last_chance", "fresh_start", "going_quiet"] as NotifyKind[]) {
      expect(gate({ ...kitten, kind, now: at("12:00") })).toEqual({ send: false, retryAt: null });
    }
    // A household kitten on a parent's phone still gets the game's pushes there.
    for (const kind of ["your_move", "pounce", "nap", "play_again"] as NotifyKind[]) {
      expect(gate({ ...kitten, kind, now: at("12:00") }).send).toBe(true);
    }
  });

  test("a teen gets nothing between 00:00 and 06:00; status waits for 06:00, reminders are dropped", () => {
    const teen = { ...base, band: "teen" as const, settings: notifySettings({ "reminders.on": { v: true, at: 1 } }, "teen") };
    expect(gate({ ...teen, kind: "your_move", now: at("02:00", "2026-11-05") })).toEqual({ send: false, retryAt: null });
    expect(gate({ ...teen, kind: "nap", now: at("04:10", "2026-11-05") })).toEqual({ send: false, retryAt: at("06:00", "2026-11-05") });
    expect(gate({ ...teen, kind: "nap", now: at("00:30", "2026-11-05") })).toEqual({ send: false, retryAt: at("06:00", "2026-11-05") });
    expect(gate({ ...teen, kind: "reminder", now: at("05:00", "2026-11-05") })).toEqual({ send: false, retryAt: null });
    expect(gate({ ...teen, kind: "nap", now: at("06:00", "2026-11-05") })).toEqual({ send: true, level: "passive" });
  });

  test("reminders: off, quiet hours and the daily cap drop them", () => {
    expect(gate({ ...base, kind: "reminder", now: at("19:30") })).toEqual({ send: true, level: "active" });
    const off = notifySettings({ "reminders.on": { v: false, at: 1 } }, "adult");
    expect(gate({ ...base, settings: off, kind: "last_chance", now: at("19:30") })).toEqual({ send: false, retryAt: null });
    expect(gate({ ...base, kind: "reminder", now: at("22:30") })).toEqual({ send: false, retryAt: null });
    expect(gate({ ...base, kind: "fresh_start", now: at("19:30"), remindersToday: 2 })).toEqual({ send: false, retryAt: null });
    expect(gate({ ...base, kind: "fresh_start", now: at("19:30"), remindersToday: 1 }).send).toBe(true);
  });

  test("spacing: one push every 20 minutes, except your move and pounces", () => {
    const spacedAt = at("19:20");
    expect(gate({ ...base, kind: "reminder", now: at("19:30"), spacedAt })).toEqual({ send: false, retryAt: spacedAt + SPACING_MS });
    expect(gate({ ...base, kind: "milestone", now: at("19:30"), spacedAt })).toEqual({ send: false, retryAt: spacedAt + SPACING_MS });
    expect(gate({ ...base, kind: "milestone", now: at("19:40"), spacedAt }).send).toBe(true);
    expect(gate({ ...base, kind: "your_move", now: at("19:30"), spacedAt })).toEqual({ send: true, level: "active" });
    expect(gate({ ...base, kind: "pounce", now: at("19:30"), spacedAt })).toEqual({ send: true, level: "active" });
  });

  test("levels: status is passive; everything is passive in quiet hours", () => {
    expect(gate({ ...base, kind: "nap", now: at("12:00") })).toEqual({ send: true, level: "passive" });
    expect(gate({ ...base, kind: "pounce_answered", now: at("12:00") })).toEqual({ send: true, level: "passive" });
    expect(gate({ ...base, kind: "your_move", now: at("23:00") })).toEqual({ send: true, level: "passive" });
    expect(gate({ ...base, kind: "pounce", now: at("23:00") })).toEqual({ send: true, level: "passive" });
    expect(gate({ ...base, kind: "milestone", now: at("12:00") })).toEqual({ send: true, level: "active" });
  });
});
