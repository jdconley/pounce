import { describe, expect, test } from "vitest";

import { addDays, localToInstant, type Day } from "../streaks/clock";

import { recordPlay } from "./playtime";
import { SPACING_MS } from "./policy";
import { decide, dueSlots, emptyNotifyState, freshStartDay, nextWake, noteSent, noteTurn, type PairFacts, type ReminderInput } from "./reminders";
import { notifySettings } from "./settings";

const LA = "America/Los_Angeles";
const NY = "America/New_York";
const D: Day = "2026-11-04"; // a Wednesday
const at = (day: Day, hhmm: string, zone = LA) => {
  const [h, m] = hhmm.split(":").map(Number) as [number, number];
  return localToInstant(day, h * 60 + m, zone);
};

const facts = (over: Partial<PairFacts> = {}): PairFacts => ({
  pair: "pr_1",
  partner: "Mia",
  count: 12,
  me: false,
  kept: false,
  paused: false,
  myMove: ["GH2VD"],
  breakId: 0,
  brokeOn: null,
  pinned: false,
  lastTurnAt: 0,
  streak: { pair: "pr_1", count: 12, me: false, them: true, naps: 1, myMove: ["GH2VD"], theirMove: [] },
  ...over,
});

const input = (now: number, over: Partial<ReminderInput> = {}): ReminderInput => ({
  now,
  zone: LA,
  band: "adult",
  settings: notifySettings({}, "adult"),
  name: "JD",
  lastOpenAt: null,
  pairs: [facts()],
  tableNames: { GH2VD: "Couch Cats" },
  ...over,
});

/** A state whose player took a turn yesterday: no backoff. */
function fresh(day: Day = D) {
  const st = emptyNotifyState();
  noteTurn(st, at(addDays(day, -1), "20:00"), LA, false);
  return st;
}

describe("the daily reminder (§12.1, §12.3)", () => {
  test("at 19:30, when today isn't kept, you aren't in and it's your move", () => {
    const st = fresh();
    expect(dueSlots(st, input(at(D, "19:29")))).toEqual([]);
    const i = input(at(D, "19:30"));
    expect(dueSlots(st, i)).toEqual(["daily"]);
    const { push, level, retryAt } = decide(st, i, "daily");
    expect(retryAt).toBeNull();
    expect(level).toBe("active");
    expect(push).toMatchObject({
      kind: "reminder",
      title: "JD",
      code: "GH2VD",
      thread: "pair:pr_1",
      collapse: "reminder:pr_1",
      streak: { pair: "pr_1", count: 12 },
    });
    expect(push?.body).toBe("The cats are on the rug. Your move at Couch Cats.");
    expect(st.reminders).toBe(1);
    expect(st.spacedAt).toBe(at(D, "19:30"));
    // Decided once a day.
    expect(dueSlots(st, input(at(D, "19:45")))).toEqual([]);
    expect(decide(st, input(at(D, "19:45")), "daily").push).toBeNull();
  });

  test("the next day's line rotates", () => {
    const st = fresh();
    const first = decide(st, input(at(D, "19:30")), "daily").push?.body;
    noteTurn(st, at(D, "21:00"), LA, false);
    const second = decide(st, input(at(addDays(D, 1), "19:30")), "daily").push?.body;
    expect(second).not.toBe(first);
  });

  test.each([
    ["today is kept", { kept: true }],
    ["you're in", { me: true }],
    ["it isn't your move", { myMove: [] }],
  ])("nothing when %s", (_name, over) => {
    const st = fresh();
    expect(decide(st, input(at(D, "19:30"), { pairs: [facts(over)] }), "daily").push).toBeNull();
    expect(st.decided.daily).toBe(D);
  });

  test("nothing when you opened the app in the last 2 hours", () => {
    expect(decide(fresh(), input(at(D, "19:30"), { lastOpenAt: at(D, "18:00") }), "daily").push).toBeNull();
    expect(decide(fresh(), input(at(D, "19:30"), { lastOpenAt: at(D, "17:29") }), "daily").push).not.toBeNull();
  });

  test("nothing with reminders off, no pairs, or for a kitten", () => {
    const off = notifySettings({ "reminders.on": { v: false, at: 1 } }, "adult");
    expect(dueSlots(fresh(), input(at(D, "19:30"), { settings: off }))).toEqual([]);
    expect(decide(fresh(), input(at(D, "19:30"), { settings: off }), "daily").push).toBeNull();
    expect(decide(fresh(), input(at(D, "19:30"), { pairs: [] }), "daily").push).toBeNull();
    const kitten = input(at(D, "19:30"), { band: "kitten", settings: notifySettings({}, "kitten") });
    expect(dueSlots(fresh(), kitten)).toEqual([]);
    expect(nextWake(fresh(), kitten)).toBeNull();
  });

  test("a paused top pair gets no reminders; the next pair is the subject", () => {
    const paused = facts({ paused: true, pinned: true });
    const mom = facts({ pair: "pr_2", partner: "Mom", count: 3, myMove: ["MOMCD"], streak: { ...facts().streak, pair: "pr_2" } });
    const { push } = decide(fresh(), input(at(D, "19:30"), { pairs: [paused, mom], tableNames: { MOMCD: "Tea Time" } }), "daily");
    expect(push).toMatchObject({ thread: "pair:pr_2", code: "MOMCD" });
    expect(decide(fresh(), input(at(D, "19:30"), { pairs: [paused] }), "daily").push).toBeNull();
  });

  test("the top pair is the pinned one, else the longest streak, then the latest turn", () => {
    const a = facts({ pair: "pr_a", count: 2, lastTurnAt: 5 });
    const b = facts({ pair: "pr_b", count: 9, lastTurnAt: 1 });
    const c = facts({ pair: "pr_c", count: 9, lastTurnAt: 3 });
    expect(decide(fresh(), input(at(D, "19:30"), { pairs: [a, b, c] }), "daily").push?.thread).toBe("pair:pr_c");
    expect(decide(fresh(), input(at(D, "19:30"), { pairs: [a, b, { ...c, pinned: false }, { ...a, pair: "pr_p", pinned: true }] }), "daily").push?.thread).toBe(
      "pair:pr_p",
    );
  });

  test("the push opens the table its line names", () => {
    const pairs = [facts({ myMove: ["AAAAA", "GH2VD"] })];
    const { push } = decide(fresh(), input(at(D, "19:30"), { pairs, tableNames: { GH2VD: "Couch Cats" } }), "daily");
    expect(push).toMatchObject({ code: "GH2VD", body: "The cats are on the rug. Your move at Couch Cats." });
  });

  test("a table with no known name still gets a line that needs none", () => {
    const { push } = decide(fresh(), input(at(D, "19:30"), { tableNames: {}, pairs: [facts({ count: 0 })] }), "daily");
    expect(push?.body).not.toContain("undefined");
    expect(push?.body).toContain("Mia");
  });

  test("auto timing uses the learned time; a fixed time is used as set", () => {
    const st = fresh();
    for (const d of ["2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30"]) recordPlay(st.playtime, at(d, "18:10"), LA);
    expect(dueSlots(st, input(at(D, "17:59")))).toEqual([]);
    expect(dueSlots(st, input(at(D, "18:00")))).toEqual(["daily"]);
    const fixed = notifySettings({ "reminders.auto": { v: false, at: 1 }, "reminders.weekday": { v: { h: 12, m: 0 }, at: 1 } }, "adult");
    expect(dueSlots(fresh(), input(at(D, "12:00"), { settings: fixed }))).toEqual(["daily"]);
  });

  test("a slot more than an hour late is skipped, not sent late", () => {
    const st = fresh();
    expect(decide(st, input(at(D, "20:31")), "daily").push).toBeNull();
    expect(st.decided.daily).toBe(D);
  });

  test("a player with no time zone uses Los Angeles", () => {
    expect(dueSlots(fresh(), input(at(D, "19:30"), { zone: null }))).toEqual(["daily"]);
  });

  test("a teen gets nothing by default, and the fixed time once turned on", () => {
    const teen = input(at(D, "19:00"), { band: "teen", settings: notifySettings({}, "teen") });
    expect(dueSlots(fresh(), teen)).toEqual([]);
    const on = notifySettings({ "reminders.on": { v: true, at: 1 } }, "teen");
    // 19:30 clamps to 19:00, two hours before a teen's 21:00 quiet hours.
    const i = input(at(D, "19:00"), { band: "teen", settings: on });
    expect(dueSlots(fresh(), i)).toEqual(["daily"]);
    expect(decide(fresh(), i, "daily").push?.kind).toBe("reminder");
  });
});

describe("last chance", () => {
  test("90 minutes before quiet hours, with a streak of 3 or more, when you aren't in and it's your move", () => {
    const st = fresh();
    st.decided.daily = D;
    const i = input(at(D, "20:30"));
    expect(dueSlots(st, input(at(D, "20:29")))).toEqual([]);
    expect(dueSlots(st, i)).toEqual(["lastChance"]);
    const { push } = decide(st, i, "lastChance");
    expect(push).toMatchObject({ kind: "last_chance", title: "JD", collapse: "last_chance:pr_1" });
    expect(push?.body).toBe("One turn tonight keeps 12 days going.");
  });

  test("not under 3, not when in, not when it's their move, not when turned off", () => {
    for (const over of [{ count: 2 }, { me: true }, { myMove: [] }, { kept: true }]) {
      expect(decide(fresh(), input(at(D, "20:30"), { pairs: [facts(over)] }), "lastChance").push).toBeNull();
    }
    const off = notifySettings({ "lastChance.on": { v: false, at: 1 } }, "adult");
    expect(dueSlots(fresh(), input(at(D, "20:30"), { settings: off }))).toEqual(["daily"]);
    expect(decide(fresh(), input(at(D, "20:30"), { settings: off }), "lastChance").push).toBeNull();
  });

  test("two reminder-type pushes a day at most; spacing defers to the end of the 20 minutes", () => {
    const st = fresh();
    expect(decide(st, input(at(D, "19:30")), "daily").push).not.toBeNull();
    noteSent(st, "fresh_start", at(D, "19:55"), LA);
    expect(st.reminders).toBe(2);
    expect(decide(st, input(at(D, "20:30")), "lastChance").push).toBeNull();

    const spaced = fresh();
    noteSent(spaced, "milestone", at(D, "20:25"), LA);
    const deferred = decide(spaced, input(at(D, "20:30")), "lastChance");
    expect(deferred).toEqual({ push: null, level: null, retryAt: at(D, "20:25") + SPACING_MS });
    expect(spaced.decided.lastChance).toBeNull();
    expect(nextWake(spaced, input(at(D, "20:31")))).toBe(at(D, "20:45"));
    expect(decide(spaced, input(at(D, "20:45")), "lastChance").push?.kind).toBe("last_chance");
  });
});

describe("backoff (§12.3)", () => {
  const idle = (n: number) => {
    const st = emptyNotifyState();
    noteTurn(st, at(addDays(D, -(n + 1)), "20:00"), LA, false);
    return st;
  };

  test("after 2 days with no turn there's no last chance", () => {
    expect(decide(idle(1), input(at(D, "20:30")), "lastChance").push).not.toBeNull();
    expect(decide(idle(2), input(at(D, "20:30")), "lastChance").push).toBeNull();
  });

  test("after 4 days the daily reminder comes every other day", () => {
    const st = idle(4);
    expect(decide(st, input(at(D, "19:30")), "daily").push).not.toBeNull();
    expect(decide(st, input(at(addDays(D, 1), "19:30")), "daily").push).toBeNull();
    expect(decide(st, input(at(addDays(D, 2), "19:30")), "daily").push).not.toBeNull();
  });

  test("after 7 days one going-quiet push, then nothing; a turn resets it all", () => {
    const st = idle(7);
    const { push } = decide(st, input(at(D, "19:30")), "daily");
    expect(push).toMatchObject({ kind: "going_quiet", body: "The cats will keep your seat warm.", title: "JD" });
    expect(decide(st, input(at(addDays(D, 1), "19:30")), "daily").push).toBeNull();
    expect(decide(st, input(at(addDays(D, 2), "19:30")), "daily").push).toBeNull();
    noteTurn(st, at(addDays(D, 2), "21:00"), LA, false);
    expect(decide(st, input(at(addDays(D, 3), "19:30")), "daily").push?.kind).toBe("reminder");
    expect(decide(idle(7), input(at(D, "19:30"), { pairs: [] }), "daily").push).toBeNull();
  });

  test("a player with no turn yet starts with no backoff", () => {
    const st = emptyNotifyState();
    expect(decide(st, input(at(D, "19:30")), "daily").push).not.toBeNull();
    expect(st.lastTurnDay).toBe(D);
  });

  test("turns learn only when asked, and an older turn doesn't move the day back", () => {
    const st = emptyNotifyState();
    noteTurn(st, at(D, "19:00"), LA, true);
    expect(st.playtime.days.weekday).toBe(1);
    noteTurn(st, at(addDays(D, -3), "19:00"), LA, true);
    expect(st.lastTurnDay).toBe(D);
    noteTurn(st, at(addDays(D, 1), "19:00"), LA, false);
    expect(st.playtime.days.weekday).toBe(1);
  });
});

describe("the fresh start (§8.4)", () => {
  test("the first Monday or 1st after the break", () => {
    expect(freshStartDay("2026-11-04")).toBe("2026-11-09");
    expect(freshStartDay("2026-11-28")).toBe("2026-11-30");
    expect(freshStartDay("2026-11-30")).toBe("2026-12-01");
  });

  test("at the reminder time, once per break, only while the count is 0", () => {
    const broken = facts({ count: 0, breakId: 1, brokeOn: "2026-11-04", myMove: [] });
    const st = fresh("2026-11-09");
    expect(decide(fresh("2026-11-08"), input(at("2026-11-08", "19:30"), { pairs: [broken] }), "daily").push).toBeNull();
    const { push } = decide(st, input(at("2026-11-09", "19:30"), { pairs: [broken] }), "daily");
    expect(push).toMatchObject({ kind: "fresh_start", title: "JD", body: "New week, new deal. One turn starts a streak with Mia." });
    expect(push).not.toHaveProperty("code");
    st.decided.daily = null;
    expect(decide(st, input(at("2026-11-09", "19:40"), { pairs: [broken] }), "daily").push).toBeNull();
    expect(decide(fresh("2026-11-09"), input(at("2026-11-09", "19:30"), { pairs: [{ ...broken, count: 1 }] }), "daily").push).toBeNull();
    const month = decide(fresh("2026-12-01"), input(at("2026-12-01", "19:30"), { pairs: [{ ...broken, brokeOn: "2026-11-30" }] }), "daily");
    expect(month.push?.body).toBe("New month, new deal. One turn starts a streak with Mia.");
  });
});

describe("nextWake", () => {
  test("the next undecided slot today, then tomorrow's reminder", () => {
    const st = fresh();
    expect(nextWake(st, input(at(D, "12:00")))).toBe(at(D, "19:30"));
    st.decided.daily = D;
    expect(nextWake(st, input(at(D, "19:31")))).toBe(at(D, "20:30"));
    st.decided.lastChance = D;
    expect(nextWake(st, input(at(D, "20:31")))).toBe(at(addDays(D, 1), "19:30"));
  });

  test("after a westward trip, with today stale and tomorrow already decided, it looks a day further", () => {
    const st = fresh();
    // Both of 11-05's slots were decided in Tokyo that evening; at 03:50 in LA it's still 11-04.
    st.decided = { daily: "2026-11-05", lastChance: "2026-11-05" };
    const now = at("2026-11-05", "03:50");
    expect(nextWake(st, input(now))).toBe(at("2026-11-06", "19:30"));
    expect(Number.isFinite(nextWake(st, input(now)))).toBe(true);
  });

  test("a due slot wakes now; a slot an hour stale is skipped; zones are the player's", () => {
    const st = fresh();
    expect(nextWake(st, input(at(D, "19:40")))).toBe(at(D, "19:40"));
    expect(nextWake(st, input(at(D, "21:40")))).toBe(at(addDays(D, 1), "19:30"));
    expect(nextWake(fresh(), input(at(D, "12:00", NY), { zone: NY }))).toBe(at(D, "19:30", NY));
    const noLast = notifySettings({ "lastChance.on": { v: false, at: 1 } }, "adult");
    st.decided.daily = D;
    expect(nextWake(st, input(at(D, "19:31"), { settings: noLast }))).toBe(at(addDays(D, 1), "19:30"));
  });
});

describe("noteSent and noteTurn", () => {
  test("your move counts toward neither cap nor spacing; no zone means Los Angeles", () => {
    const st = emptyNotifyState();
    noteSent(st, "your_move", at(D, "12:00"), null);
    expect(st).toMatchObject({ day: D, reminders: 0, spacedAt: null });
    noteTurn(st, at(D, "03:00"), null, false);
    expect(st.lastTurnDay).toBe(addDays(D, -1));
  });
});
