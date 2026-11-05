import { describe, expect, test } from "vitest";

import { notifySettings } from "./settings";

const e = (v: unknown) => ({ v: v as never, at: 1 });

describe("notifySettings", () => {
  test("an adult's defaults: reminders on, auto timing, 19:30, quiet 22:00-08:00, last chance on (§12.3)", () => {
    expect(notifySettings({}, "adult")).toEqual({
      reminders: true,
      auto: true,
      weekday: 1170,
      weekend: 1170,
      quietStart: 1320,
      quietEnd: 480,
      lastChance: true,
      liveTable: true,
    });
    expect(notifySettings({}, null)).toEqual(notifySettings({}, "adult"));
  });

  test("a teen's defaults: reminders, learned timing and last chance off, quiet from 21:00 (§14.1)", () => {
    expect(notifySettings({}, "teen")).toMatchObject({ reminders: false, auto: false, lastChance: false, quietStart: 1260, quietEnd: 480 });
    // The live table is the game, not a nudge: on for teens too (§11.3).
    expect(notifySettings({}, "teen").liveTable).toBe(true);
  });

  test("a kitten gets nothing from the server", () => {
    expect(notifySettings({ "reminders.on": e(true), "reminders.auto": e(true), "lastChance.on": e(true), "liveTable.on": e(true) }, "kitten")).toMatchObject({
      reminders: false,
      auto: false,
      lastChance: false,
      liveTable: false,
    });
  });

  test("synced values override the defaults", () => {
    const s = notifySettings(
      {
        "reminders.on": e(false),
        "reminders.auto": e(false),
        "reminders.weekday": e({ h: 18, m: 15 }),
        "reminders.weekend": e({ h: 10, m: 0 }),
        "quiet.start": e({ h: 23, m: 30 }),
        "quiet.end": e({ h: 7, m: 0 }),
        "lastChance.on": e(false),
        "liveTable.on": e(false),
      },
      "adult",
    );
    expect(s).toEqual({ reminders: false, auto: false, weekday: 1095, weekend: 600, quietStart: 1410, quietEnd: 420, lastChance: false, liveTable: false });
    expect(notifySettings({ "reminders.on": e(true), "reminders.auto": e(true), "lastChance.on": e(true) }, "teen")).toMatchObject({
      reminders: true,
      auto: true,
      lastChance: true,
    });
  });

  test("malformed values fall back to the defaults", () => {
    const s = notifySettings(
      {
        "reminders.on": e("yes"),
        "reminders.weekday": e({ h: 25, m: 0 }),
        "reminders.weekend": e([19, 30]),
        "quiet.end": e({ h: 7 }),
        "lastChance.on": e(null),
        "liveTable.on": e(0),
      },
      "adult",
    );
    expect(s).toEqual(notifySettings({}, "adult"));
  });
});
