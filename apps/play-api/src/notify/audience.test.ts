import { describe, expect, test } from "vitest";

import { forDevice } from "./audience";
import { apnsBody } from "./payload";

import type { Outgoing } from "./types";
import type { TableEntry } from "../room/tables";

const TILES = "TTTTT";
const TOWER = "GH2VD";
const table = (code: string, game?: string): TableEntry => ({ code, status: "playing", yourTurn: true, updatedAt: 1, ...(game ? { game } : {}) });
const TABLES = [table(TILES, "tiles"), table(TOWER)];
/** An app that can draw the tile game, and one from before there was a second game. */
const NEWER = ["tiles"];
const OLDER: string[] = [];

const yourMove = (code: string): Outgoing => ({ kind: "your_move", title: "Mia", body: "JD played. Your move at Toy Box.", code, thread: code, collapse: code });
const streak = { pair: "pr_1", count: 12, me: false, them: true, naps: 1, myMove: [TILES, TOWER], theirMove: [] as string[] };
const reminder = (otherwise?: Outgoing["otherwise"]): Outgoing => ({
  kind: "reminder",
  title: "Mia",
  body: "The cats are on the rug. Your move at Toy Box.",
  code: TILES,
  thread: "pair:pr_1",
  collapse: "reminder:pr_1",
  streak,
  ...(otherwise ? { otherwise } : {}),
});

describe("forDevice: a push only about a table", () => {
  test("goes as it is to a device that can open the table", () => {
    expect(forDevice(yourMove(TILES), TABLES, NEWER)).toEqual(yourMove(TILES));
    expect(forDevice(yourMove(TOWER), TABLES, OLDER)).toEqual(yourMove(TOWER));
    expect(forDevice(yourMove(TOWER), TABLES, NEWER)).toEqual(yourMove(TOWER));
  });

  test("is not for a device that can't", () => {
    expect(forDevice(yourMove(TILES), TABLES, OLDER)).toBeNull();
    expect(forDevice(yourMove(TILES), TABLES, ["chess"])).toBeNull();
  });

  test("the sender's word on the table's game wins over a list that hasn't heard of the table yet", () => {
    expect(forDevice(yourMove("NEWWW"), TABLES, OLDER, "tiles")).toBeNull();
    expect(forDevice(yourMove("NEWWW"), TABLES, NEWER, "tiles")).toEqual(yourMove("NEWWW"));
    // A table nobody has listed, with no word on its game, is a Cat Tower table: every app opens it.
    expect(forDevice(yourMove("NEWWW"), TABLES, OLDER)).toEqual(yourMove("NEWWW"));
  });
});

describe("forDevice: a push with no table", () => {
  test("goes to every device", () => {
    const nap: Outgoing = { kind: "nap", title: "Mia", body: "A cat nap saved the streak.", thread: "pair:pr_1", collapse: "nap:pr_1" };
    expect(forDevice(nap, TABLES, OLDER)).toEqual(nap);
    expect(forDevice(nap, TABLES, NEWER)).toEqual(nap);
  });
});

describe("forDevice: a streak reminder that points at a table only a newer app can open", () => {
  const withTower = reminder({ body: "The cats are on the rug. Your move at Couch Cats.", code: TOWER });
  const withNone = reminder({ body: "Mia's cat is guarding the deck. Your move." });

  test("a newer app gets it as it was built, without the note for older ones", () => {
    const got = forDevice(withTower, TABLES, NEWER);
    expect(got).toEqual(reminder());
    expect(got && "otherwise" in got).toBe(false);
  });

  test("an older app gets the reminder too: its own words, a table it can open, and a streak block without the other", () => {
    expect(forDevice(withTower, TABLES, OLDER)).toEqual({
      kind: "reminder",
      title: "Mia",
      body: "The cats are on the rug. Your move at Couch Cats.",
      code: TOWER,
      thread: "pair:pr_1",
      collapse: "reminder:pr_1",
      streak: { ...streak, myMove: [TOWER] },
    });
  });

  test("with no table it can open, it gets the reminder with no table at all", () => {
    const got = forDevice(withNone, TABLES, OLDER);
    expect(got).toMatchObject({ kind: "reminder", body: "Mia's cat is guarding the deck. Your move." });
    expect(got && "code" in got).toBe(false);
    // Nothing of the tile game's table is left in what the device is sent.
    expect(JSON.stringify(apnsBody(got as Outgoing, "active", 0))).not.toContain(TILES);
  });

  test("with nothing said for older apps, a push about the table is dropped for them", () => {
    expect(forDevice(reminder(), TABLES, OLDER)).toBeNull();
  });

  test("the note for older apps never reaches a payload", () => {
    for (const games of [NEWER, OLDER]) {
      const body = JSON.stringify(apnsBody(forDevice(withTower, TABLES, games) as Outgoing, "active", 1));
      expect(body).not.toContain("otherwise");
    }
    // Even straight into the payload builder it is left out.
    expect(JSON.stringify(apnsBody(withTower, "active", 1))).not.toContain("otherwise");
  });
});

describe("forDevice: a player with no table of another game", () => {
  test("every push is the one it was given, key for key", () => {
    const tables = [table(TOWER), table("AAAAA")];
    const push: Outgoing = { ...reminder(), code: TOWER, streak: { ...streak, myMove: [TOWER] } };
    for (const games of [NEWER, OLDER]) {
      expect(forDevice(push, tables, games)).toEqual(push);
      expect(apnsBody(forDevice(push, tables, games) as Outgoing, "active", 2)).toEqual(apnsBody(push, "active", 2));
    }
  });
});
