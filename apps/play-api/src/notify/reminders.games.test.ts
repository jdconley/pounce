import { describe, expect, test } from "vitest";

import { addDays, localToInstant, type Day } from "../streaks/clock";

import { decide, emptyNotifyState, noteTurn, type PairFacts, type ReminderInput } from "./reminders";
import { notifySettings } from "./settings";

/* A streak reminder when one of the pair's tables is of a game only a newer app can open. */

const LA = "America/Los_Angeles";
const D: Day = "2026-11-04";
const at = (day: Day, hhmm: string) => {
  const [h, m] = hhmm.split(":").map(Number) as [number, number];
  return localToInstant(day, h * 60 + m, LA);
};
/** The tile game's table, and the pair's Cat Tower table. */
const TILES = "TTTTT";
const TOWER = "GH2VD";

const facts = (myMove: string[], over: Partial<PairFacts> = {}): PairFacts => ({
  pair: "pr_1",
  partner: "Mia",
  count: 12,
  me: false,
  kept: false,
  paused: false,
  myMove,
  breakId: 0,
  brokeOn: null,
  pinned: false,
  lastTurnAt: 0,
  streak: { pair: "pr_1", count: 12, me: false, them: true, naps: 1, myMove, theirMove: [] },
  ...over,
});

const input = (hhmm: string, myMove: string[], over: Partial<ReminderInput> = {}): ReminderInput => ({
  now: at(D, hhmm),
  zone: LA,
  band: "adult",
  settings: notifySettings({}, "adult"),
  name: "JD",
  lastOpenAt: null,
  pairs: [facts(myMove)],
  tableNames: { [TILES]: "Toy Box", [TOWER]: "Couch Cats" },
  newerOnly: [TILES],
  ...over,
});

function fresh() {
  const st = emptyNotifyState();
  noteTurn(st, at(addDays(D, -1), "20:00"), LA, false);
  return st;
}

describe("the daily reminder with a table only a newer app can open", () => {
  test("points at that table, and says what an older app gets: the pair's Cat Tower table", () => {
    const { push } = decide(fresh(), input("19:30", [TILES, TOWER]), "daily");
    expect(push).toMatchObject({ kind: "reminder", code: TILES, body: "The cats are on the rug. Your move at Toy Box." });
    expect(push?.otherwise).toEqual({ body: "The cats are on the rug. Your move at Couch Cats.", code: TOWER });
  });

  test("with no table an older app can open, it still gets the reminder: a line that names no table, and no table to open", () => {
    const { push } = decide(fresh(), input("19:30", [TILES]), "daily");
    expect(push?.code).toBe(TILES);
    expect(push?.otherwise).toBeDefined();
    expect(push?.otherwise?.body).not.toContain("Toy Box");
    expect(push?.otherwise?.body).not.toContain("undefined");
    expect(push?.otherwise?.body).toMatch(/Mia|Day 13/);
    expect("code" in (push?.otherwise ?? {})).toBe(false);
  });

  test("an older app's table need not have a name the line can use", () => {
    const { push } = decide(fresh(), input("19:30", [TILES, TOWER], { tableNames: { [TILES]: "Toy Box" } }), "daily");
    expect(push?.otherwise?.code).toBe(TOWER);
    expect(push?.otherwise?.body).not.toContain("Toy Box");
  });

  test("the older app's line is not the one counted as used: only what the newer app got rotates", () => {
    const st = fresh();
    decide(st, input("19:30", [TILES, TOWER]), "daily");
    expect(Object.keys(st.lines)).toEqual(["d-rug"]);
    expect(st.cursor.daily).toBe(1);
  });

  test("a reminder that points at a Cat Tower table says nothing more, whatever else the pair shares", () => {
    const { push } = decide(fresh(), input("19:30", [TOWER, TILES]), "daily");
    expect(push?.code).toBe(TOWER);
    expect(push && "otherwise" in push).toBe(false);
  });

  test("a player with no such table gets exactly the push they always did", () => {
    const withList = decide(fresh(), input("19:30", [TOWER], { newerOnly: [] }), "daily").push;
    const without = decide(fresh(), { ...input("19:30", [TOWER]), newerOnly: undefined }, "daily").push;
    expect(withList).toEqual(without);
    expect(Object.keys(without ?? {})).toEqual(["kind", "title", "body", "code", "thread", "collapse", "streak"]);
  });
});

describe("last chance with a table only a newer app can open", () => {
  test("says what an older app gets, the same way", () => {
    const both = decide(fresh(), input("21:15", [TILES, TOWER]), "lastChance").push;
    expect(both).toMatchObject({ kind: "last_chance", code: TILES });
    expect(both?.otherwise).toMatchObject({ code: TOWER });
    const only = decide(fresh(), input("21:15", [TILES]), "lastChance").push;
    expect(only?.otherwise).toBeDefined();
    expect("code" in (only?.otherwise ?? {})).toBe(false);
    expect(only?.otherwise?.body).not.toContain("Toy Box");
  });
});
