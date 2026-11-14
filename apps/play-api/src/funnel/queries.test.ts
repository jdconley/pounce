import { readFileSync } from "node:fs";

import { beforeAll, describe, expect, test } from "vitest";

import { d1, importSqlite } from "../../tests/d1-sqlite";

import { active, minted, pageView, reached, report, resetActivity, type Report } from "./funnel";
import { APP_MILESTONES, SERVER_MILESTONES } from "./milestones";

import type { DatabaseSync } from "node:sqlite";

// The saved queries (funnel/queries.sql) against sample devices: each one runs and says what it should.
const FILE = readFileSync(new URL("../../funnel/queries.sql", import.meta.url), "utf8");
const QUERIES = Object.fromEntries(
  FILE.split(/^-- name: /m)
    .slice(1)
    .map((chunk) => [chunk.slice(0, chunk.indexOf("\n")).trim(), chunk.slice(chunk.indexOf("\n") + 1)]),
);

const SECRET = "s".repeat(64);
const DAY = 86_400_000;
const IOS = { platform: "ios", version: "1.2", build: 70, protocol: 3 };
let sqlite: DatabaseSync;

const run = (name: string) => sqlite.prepare(QUERIES[name] as string).all() as Record<string, unknown>[];

beforeAll(async () => {
  const { DatabaseSync } = await importSqlite();
  sqlite = new DatabaseSync(":memory:");
  const env = { FUNNEL: d1(sqlite), TOKEN_SECRET: SECRET };
  resetActivity();
  const t0 = Date.now() - 20 * DAY;
  const say = (deviceId: string, at: number, steps: Report["reached"], source: Report["source"] = null) =>
    report(env, deviceId, { reached: steps, source, locale: "en-US" }, at, IOS);
  const seat = (deviceId: string, at: number, host: boolean, game = "tiles") =>
    reached(env, [{ deviceId, milestone: "seat_taken", game }, ...(host ? [] : [{ deviceId, milestone: "joined_table" as const, game }])], at);

  // Organic, plays alone with a House Cat, comes back the next day.
  await minted(env, "a", t0, IOS);
  await say("a", t0 + 70_000, [["age_done", 40], ["named", 10], ["home_seen", 0]], "organic");
  await reached(env, [{ deviceId: "a", milestone: "table_created", game: "tiles" }], t0 + 90_000);
  await seat("a", t0 + 100_000, true);
  await reached(env, [{ deviceId: "a", milestone: "first_move", game: "tiles" }], t0 + 150_000);
  await reached(env, [{ deviceId: "a", milestone: "game_finished", game: "tiles" }], t0 + 600_000);
  await say("a", t0 + 200_000, [["invite_sent", 0]]);
  await active(env, "a", t0 + DAY + 1000);

  // From a table link: joins Grandma's game and finishes it with her; back on day 1 and day 7.
  await minted(env, "b", t0 + 1000, IOS);
  await say("b", t0 + 61_000, [["age_done", 40], ["named", 20], ["link_opened", 15]], "join_link");
  await seat("b", t0 + 61_000, false, "cat-tower");
  await reached(env, [{ deviceId: "b", milestone: "first_move", game: "cat-tower" }], t0 + 91_000);
  for (const milestone of ["game_finished", "game_with_human", "game_with_device"] as const) {
    await reached(env, [{ deviceId: "b", milestone, game: "cat-tower" }], t0 + 501_000);
  }
  await say("b", t0 + 501_000, [["push_answered", 0], ["push_allowed", 0]]);
  await active(env, "b", t0 + DAY + 2000);
  await active(env, "b", t0 + 7 * DAY + 2000);

  // Organic, stops after the age check.
  await minted(env, "c", t0 + 2000, IOS);
  await say("c", t0 + 32_000, [["age_done", 0]], "organic");

  // A pasted invite: joins and moves.
  await minted(env, "d", t0 + 3000, IOS);
  await say("d", t0 + 63_000, [["age_done", 50], ["named", 30], ["home_seen", 20], ["invite_pasted", 10]], "paste");
  await seat("d", t0 + 63_000, false);
  await reached(env, [{ deviceId: "d", milestone: "first_move", game: "tiles" }], t0 + 123_000);

  // Minted before tracking began: never in the cohort.
  await say("old", t0, [["age_done", 0], ["named", 0]], "organic");

  await pageView(env, "j", "facebookexternalhit/1.1 Facebot Twitterbot/1.0", t0);
  await pageView(env, "j", "Mozilla/5.0 (iPhone)", t0 + 10);
  await pageView(env, "p", "Mozilla/5.0 (iPhone)", t0 + 10);
});

describe("saved funnel queries", () => {
  test("the file holds the queries docs/funnel.md names, and they name every step", () => {
    expect(Object.keys(QUERIES)).toEqual(["funnel", "side_steps", "median_times", "by_source", "retention", "by_game", "invite_pages"]);
    for (const step of [...SERVER_MILESTONES, ...APP_MILESTONES]) expect(FILE).toContain(`'${step}'`);
  });

  test("funnel: devices per step, as a share of installs and of the step before", () => {
    expect(run("funnel").map((r) => [r.milestone, r.devices, r.pct_of_installs, r.pct_of_previous])).toEqual([
      ["device_created", 4, 100, null],
      ["age_done", 4, 100, 100],
      ["named", 3, 75, 75],
      ["home_seen", 2, 50, 66.7],
      ["seat_taken", 3, 75, 150],
      ["first_move", 3, 75, 100],
      ["game_finished", 2, 50, 66.7],
      ["game_with_human", 1, 25, 50],
      ["game_with_device", 1, 25, 100],
    ]);
  });

  test("side steps", () => {
    expect(run("side_steps").map((r) => [r.milestone, r.devices])).toEqual([
      ["table_created", 1],
      ["invite_sent", 1],
      ["link_opened", 1],
      ["invite_pasted", 1],
      ["joined_table", 2],
      ["push_answered", 1],
      ["push_allowed", 1],
    ]);
  });

  test("median times between steps", () => {
    const medians = Object.fromEntries(run("median_times").map((r) => [`${r.from_step}>${r.to_step}`, [r.devices, r.median_seconds]]));
    // Age done 30, 20, 30 and 10 seconds after install: the middle two are 20 and 30.
    expect(medians["device_created>age_done"]).toEqual([4, 25]);
    expect(medians["device_created>first_move"]).toEqual([3, 120]);
    expect(medians["link_opened>joined_table"]).toEqual([1, 15]);
    expect(medians["joined_table>first_move"]).toEqual([2, 45]);
  });

  test("by source", () => {
    expect(run("by_source").map((r) => [r.source, r.installs, r.first_move, r.game_with_human])).toEqual([
      ["organic", 2, 1, 0],
      ["join_link", 1, 1, 1],
      ["paste", 1, 1, 0],
    ]);
  });

  test("retention: day 1 and day 7 return", () => {
    const weeks = run("retention");
    const installs = weeks.reduce((n, r) => n + (r.installs as number), 0);
    expect(installs).toBe(4);
    const all = weeks.find((r) => r.installs === 4) as Record<string, unknown>;
    expect([all.pct_day_1, all.pct_day_7, all.pct_any_1_to_7]).toEqual([50, 25, 50]);
  });

  test("by game", () => {
    expect(run("by_game").map((r) => [r.game, r.first_table, r.first_move, r.first_finish, r.first_with_human])).toEqual([
      ["tiles", 1, 2, 1, 0],
      ["cat-tower", 0, 1, 1, 1],
    ]);
  });

  test("invite pages", () => {
    const [day] = run("invite_pages");
    expect(day).toMatchObject({ table_link_opened: 1, table_link_previews: 1, play_link_opened: 1, play_link_previews: 0 });
  });
});
