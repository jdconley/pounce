import { beforeEach, describe, expect, test } from "vitest";

import { d1, importSqlite } from "../../tests/d1-sqlite";

import { active, forget, funnelId, minted, pageView, parseReport, reached, report, resetActivity, SCHEMA } from "./funnel";
import { APP_MILESTONES, isAppMilestone, isSource, SERVER_MILESTONES } from "./milestones";

import type { FunnelEnv } from "./funnel";
import type { DatabaseSync } from "node:sqlite";

const SECRET = "s".repeat(64);
const DAY = 86_400_000;
const T0 = Date.UTC(2026, 10, 13, 12);
const IOS = { platform: "ios", version: "1.2", build: 70, protocol: 3 };

let sqlite: DatabaseSync;
let env: FunnelEnv;

beforeEach(async () => {
  const { DatabaseSync } = await importSqlite();
  sqlite = new DatabaseSync(":memory:");
  env = { FUNNEL: d1(sqlite), TOKEN_SECRET: SECRET };
  resetActivity();
});

const rows = (sql: string, ...params: (string | number)[]) => sqlite.prepare(sql).all(...params);
const idOf = (deviceId: string) => funnelId(SECRET, deviceId);

describe("milestones", () => {
  test("app and server steps don't overlap, and only app steps and known sources pass", () => {
    expect(APP_MILESTONES.filter((m) => (SERVER_MILESTONES as readonly string[]).includes(m))).toEqual([]);
    expect(isAppMilestone("age_done")).toBe(true);
    expect(isAppMilestone("first_move")).toBe(false);
    expect(isAppMilestone(3)).toBe(false);
    expect(isSource("paste")).toBe(true);
    expect(isSource("ad")).toBe(false);
  });
});

describe("funnel ids", () => {
  test("are a stable keyed hash, never the device id", async () => {
    const a = await idOf("device-a");
    expect(a).toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect(await idOf("device-a")).toBe(a);
    expect(await idOf("device-b")).not.toBe(a);
    expect(await funnelId("t".repeat(64), "device-a")).not.toBe(a);
  });
});

describe("minted", () => {
  test("keeps the device, its platform and version, its first step and day 0", async () => {
    await minted(env, "dev1", T0, IOS);
    const id = await idOf("dev1");
    expect(rows("SELECT * FROM devices")).toEqual([
      { id, created_at: T0, first_seen: T0, last_seen: T0, platform: "ios", app_version: "1.2", locale: null, source: null },
    ]);
    expect(rows("SELECT id, milestone, at, game, app_version FROM milestones")).toEqual([
      { id, milestone: "device_created", at: T0, game: null, app_version: "1.2" },
    ]);
    expect(rows("SELECT day FROM device_days")).toEqual([{ day: 0 }]);
  });

  test("an app that didn't say what it is (1.0) is kept without a platform or version", async () => {
    await minted(env, "dev1", T0, null);
    expect(rows("SELECT platform, app_version FROM devices")).toEqual([{ platform: null, app_version: null }]);
  });

  test("nothing happens without the database or the secret", async () => {
    await minted({ TOKEN_SECRET: SECRET }, "dev1", T0, IOS);
    await minted({ FUNNEL: env.FUNNEL }, "dev1", T0, IOS);
    await reached({ TOKEN_SECRET: SECRET }, [{ deviceId: "dev1", milestone: "seat_taken" }], T0);
    await report({ TOKEN_SECRET: SECRET }, "dev1", { reached: [], source: null, locale: null }, T0, null);
    await active({ TOKEN_SECRET: SECRET }, "dev1", T0);
    await pageView({ TOKEN_SECRET: SECRET }, "j", null, T0);
    await forget({ TOKEN_SECRET: SECRET }, "dev1");
    expect(rows("SELECT name FROM sqlite_master WHERE type = 'table'")).toEqual([]);
  });

  test("tables are created once, and again after a failure", async () => {
    let calls = 0;
    const real = d1(sqlite);
    const flaky = {
      prepare: real.prepare.bind(real),
      batch: async (statements: D1PreparedStatement[]) => {
        calls++;
        if (calls === 1) throw new Error("down");
        return real.batch(statements);
      },
    } as unknown as D1Database;
    const flakyEnv = { FUNNEL: flaky, TOKEN_SECRET: SECRET };
    await expect(minted(flakyEnv, "dev1", T0, IOS)).rejects.toThrow("down");
    await minted(flakyEnv, "dev1", T0, IOS);
    await minted(flakyEnv, "dev2", T0, IOS);
    // The schema, then each minting's own batch: the schema isn't sent again once it worked.
    expect(calls).toBe(4);
    expect(rows("SELECT COUNT(*) AS n FROM devices")).toEqual([{ n: 2 }]);
    expect(SCHEMA.length).toBe(5);
  });
});

describe("reached", () => {
  test("keeps each device's first time and the game", async () => {
    await reached(env, [{ deviceId: "dev1", milestone: "seat_taken", game: "tiles" }], T0);
    await reached(env, [{ deviceId: "dev1", milestone: "seat_taken", game: "cat-tower" }], T0 + 5000);
    await reached(env, [], T0);
    expect(rows("SELECT milestone, at, game FROM milestones")).toEqual([{ milestone: "seat_taken", at: T0, game: "tiles" }]);
  });

  test("a game id that isn't plain is left out", async () => {
    await reached(env, [{ deviceId: "dev1", milestone: "first_move", game: "Robert'); DROP TABLE" }], T0);
    expect(rows("SELECT game FROM milestones")).toEqual([{ game: null }]);
  });
});

describe("parseReport", () => {
  test("reads steps, source and locale", () => {
    expect(parseReport({ reached: { age_done: 12, named: 0 }, source: "join_link", locale: "en-US" })).toEqual({
      reached: [
        ["age_done", 12],
        ["named", 0],
      ],
      source: "join_link",
      locale: "en-US",
    });
    expect(parseReport({ reached: {} })).toEqual({ reached: [], source: null, locale: null });
    expect(parseReport({ reached: { home_seen: 1 }, locale: "pt" })).toEqual({ reached: [["home_seen", 1]], source: null, locale: "pt" });
  });

  test("leaves out steps it doesn't know or can't use", () => {
    const parsed = parseReport({
      reached: { first_move: 1, someday_step: 1, named: -1, age_done: 1.5, home_seen: 31 * 86_400, link_opened: "3", invite_sent: 30 * 86_400 },
    });
    expect(parsed?.reached).toEqual([["invite_sent", 30 * 86_400]]);
  });

  test("refuses anything that isn't a report", () => {
    expect(parseReport(null)).toBeNull();
    expect(parseReport({})).toBeNull();
    expect(parseReport({ reached: [] })).toBeNull();
    expect(parseReport({ reached: null })).toBeNull();
    expect(parseReport({ reached: "age_done" })).toBeNull();
    expect(parseReport({ reached: {}, name: "Grandma" })).toBeNull();
    expect(parseReport({ reached: {}, source: "facebook" })).toBeNull();
    expect(parseReport({ reached: {}, locale: "English" })).toBeNull();
    expect(parseReport({ reached: {}, locale: 7 })).toBeNull();
    const many = Object.fromEntries(Array.from({ length: 21 }, (_, i) => [`step${i}`, 0]));
    expect(parseReport({ reached: many })).toBeNull();
  });
});

describe("report", () => {
  test("keeps the app's steps at the time they happened, its locale and its first source", async () => {
    await minted(env, "dev1", T0, IOS);
    await report(env, "dev1", { reached: [["age_done", 30]], source: null, locale: "en-US" }, T0 + 60_000, IOS);
    await report(env, "dev1", { reached: [["named", 0]], source: "join_link", locale: null }, T0 + 120_000, { ...IOS, version: "1.3" });
    await report(env, "dev1", { reached: [["home_seen", 0]], source: "organic", locale: "fr-FR" }, T0 + DAY + 1, IOS);
    const id = await idOf("dev1");
    expect(rows("SELECT * FROM devices")).toEqual([
      { id, created_at: T0, first_seen: T0, last_seen: T0 + DAY + 1, platform: "ios", app_version: "1.2", locale: "fr-FR", source: "join_link" },
    ]);
    expect(rows("SELECT milestone, at, app_version FROM milestones ORDER BY at")).toEqual([
      { milestone: "device_created", at: T0, app_version: "1.2" },
      { milestone: "age_done", at: T0 + 30_000, app_version: "1.2" },
      { milestone: "named", at: T0 + 120_000, app_version: "1.3" },
      { milestone: "home_seen", at: T0 + DAY + 1, app_version: "1.2" },
    ]);
    expect(rows("SELECT day FROM device_days ORDER BY day")).toEqual([{ day: 0 }, { day: 1 }]);
  });

  test("an invite before the first table replaces organic; nothing replaces an invite", async () => {
    await report(env, "dev1", { reached: [], source: "organic", locale: null }, T0, IOS);
    await report(env, "dev1", { reached: [], source: null, locale: null }, T0, IOS);
    expect(rows("SELECT source FROM devices")).toEqual([{ source: "organic" }]);
    await report(env, "dev1", { reached: [], source: "paste", locale: null }, T0, IOS);
    await report(env, "dev1", { reached: [], source: "join_link", locale: null }, T0, IOS);
    await report(env, "dev1", { reached: [], source: "organic", locale: null }, T0, IOS);
    expect(rows("SELECT source FROM devices")).toEqual([{ source: "paste" }]);
  });

  test("a step sent again keeps the earliest time, even when the earlier one arrives last", async () => {
    await report(env, "dev1", { reached: [["named", 0]], source: null, locale: null }, T0 + 10_000, IOS);
    await report(env, "dev1", { reached: [["named", 0]], source: null, locale: null }, T0 + 20_000, IOS);
    await report(env, "dev1", { reached: [["named", 5]], source: null, locale: null }, T0 + 6_000, IOS);
    expect(rows("SELECT at FROM milestones")).toEqual([{ at: T0 + 1_000 }]);
  });

  test("a device minted before tracking began has no created_at, so no days of life", async () => {
    await report(env, "old", { reached: [["home_seen", 0]], source: null, locale: null }, T0, null);
    expect(rows("SELECT created_at, platform FROM devices")).toEqual([{ created_at: null, platform: null }]);
    expect(rows("SELECT * FROM device_days")).toEqual([]);
  });
});

describe("active", () => {
  test("marks the days a device was in use, at most once an hour, up to day 90", async () => {
    await minted(env, "dev1", T0, IOS);
    await active(env, "dev1", T0 + DAY);
    await active(env, "dev1", T0 + DAY + 60_000);
    await active(env, "dev1", T0 + 7 * DAY);
    await active(env, "dev1", T0 + 91 * DAY);
    expect(rows("SELECT day FROM device_days ORDER BY day")).toEqual([{ day: 0 }, { day: 1 }, { day: 7 }]);
    expect(rows("SELECT last_seen FROM devices")).toEqual([{ last_seen: T0 + 91 * DAY }]);
  });

  test("a call within the hour writes nothing", async () => {
    await minted(env, "dev1", T0, IOS);
    await active(env, "dev1", T0 + 1000);
    sqlite.exec("DELETE FROM device_days");
    await active(env, "dev1", T0 + 2000);
    expect(rows("SELECT * FROM device_days")).toEqual([]);
  });

  test("forgets what it wrote once it remembers too many devices", async () => {
    for (let i = 0; i < 10_001; i++) await active({}, `d${i}`, T0);
    await minted(env, "d0", T0, IOS);
    sqlite.exec("DELETE FROM device_days");
    await active(env, "d0", T0 + 1000);
    expect(rows("SELECT day FROM device_days")).toEqual([{ day: 0 }]);
  });
});

describe("pageView", () => {
  test("counts views per day and page, previews apart", async () => {
    await pageView(env, "j", "Mozilla/5.0 (iPhone) Safari", T0);
    await pageView(env, "j", null, T0);
    await pageView(env, "j", "facebookexternalhit/1.1 Facebot Twitterbot/1.0", T0);
    await pageView(env, "p", "Mozilla/5.0", T0 + DAY);
    expect(rows("SELECT * FROM page_views ORDER BY day, page")).toEqual([
      { day: "2026-11-13", page: "j", views: 2 },
      { day: "2026-11-13", page: "j_preview", views: 1 },
      { day: "2026-11-14", page: "p", views: 1 },
    ]);
  });
});

describe("forget", () => {
  test("deletes the device's row, steps and days, and nobody else's", async () => {
    await minted(env, "dev1", T0, IOS);
    await minted(env, "dev2", T0, IOS);
    await forget(env, "dev1");
    const id = await idOf("dev2");
    expect(rows("SELECT id FROM devices")).toEqual([{ id }]);
    expect(rows("SELECT id FROM milestones")).toEqual([{ id }]);
    expect(rows("SELECT id FROM device_days")).toEqual([{ id }]);
  });
});
