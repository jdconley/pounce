import { DatabaseSync } from "node:sqlite";

import { describe, expect, it } from "vitest";

import { storage } from "../../tests/sqlite-storage";

import { createTables, listTables, upsertTable, type TableEntry } from "./tables";

/*
 * The tables list's SQL against a real SQLite (`tests/sqlite-storage.ts`). What matters here is a
 * list saved before tables had a game: it must load as it is, with no step that can fail.
 */

const entry = (code: string, over: Partial<TableEntry> = {}): TableEntry => ({
  code,
  name: "Couch Cats",
  status: "playing",
  yourTurn: true,
  updatedAt: 1_000,
  ...over,
});

describe("the tables list's storage", () => {
  it("a new list keeps a table's game, and none for a Cat Tower table", () => {
    const sql = storage(new DatabaseSync(":memory:"));
    createTables(sql);
    upsertTable(sql, entry("AAAAA"));
    upsertTable(sql, entry("BBBBB", { game: "tiles", updatedAt: 2_000 }));
    const [tiles, tower] = listTables(sql);
    expect(tiles).toEqual(entry("BBBBB", { game: "tiles", updatedAt: 2_000 }));
    expect(tower).toEqual(entry("AAAAA"));
    expect(Object.keys(tower as TableEntry)).not.toContain("game");
  });

  it("a list saved before tables had a game gains the column and reads exactly as it did", () => {
    const db = new DatabaseSync(":memory:");
    // The table as the release before this one made it.
    db.exec(
      "CREATE TABLE tables (code TEXT PRIMARY KEY, status TEXT, your_turn INTEGER, updated_at INTEGER, name TEXT, next TEXT, seats TEXT, moved_at INTEGER)",
    );
    db.prepare("INSERT INTO tables (code, status, your_turn, updated_at, name, moved_at) VALUES (?, ?, ?, ?, ?, ?)").run(
      "AAAAA", "playing", 1, 1_000, "Couch Cats", 900,
    );
    const sql = storage(db);
    createTables(sql);
    expect(listTables(sql)).toEqual([entry("AAAAA", { movedAt: 900 })]);
    // And from then on it takes a game.
    upsertTable(sql, entry("BBBBB", { game: "tiles", updatedAt: 2_000 }));
    expect(listTables(sql).map((t) => [t.code, t.game])).toEqual([["BBBBB", "tiles"], ["AAAAA", undefined]]);
  });

  it("creating the schema twice changes nothing: every start of the object runs it", () => {
    const sql = storage(new DatabaseSync(":memory:"));
    createTables(sql);
    upsertTable(sql, entry("BBBBB", { game: "tiles" }));
    createTables(sql);
    createTables(sql);
    expect(listTables(sql)).toEqual([entry("BBBBB", { game: "tiles" })]);
  });

  it("the very first schema, before names, seats or anything else, still loads", () => {
    const db = new DatabaseSync(":memory:");
    db.exec("CREATE TABLE tables (code TEXT PRIMARY KEY, status TEXT, your_turn INTEGER, updated_at INTEGER)");
    db.prepare("INSERT INTO tables (code, status, your_turn, updated_at) VALUES (?, ?, ?, ?)").run("AAAAA", "over", 0, 5);
    const sql = storage(db);
    createTables(sql);
    expect(listTables(sql)).toEqual([{ code: "AAAAA", status: "over", yourTurn: false, updatedAt: 5 }]);
  });

  it("an update keeps a table's game, and an older report never overwrites a newer one", () => {
    const sql = storage(new DatabaseSync(":memory:"));
    createTables(sql);
    upsertTable(sql, entry("BBBBB", { game: "tiles", updatedAt: 2_000 }));
    upsertTable(sql, entry("BBBBB", { game: "tiles", updatedAt: 3_000, status: "over", yourTurn: false }));
    upsertTable(sql, entry("BBBBB", { updatedAt: 1_000, status: "lobby" }));
    expect(listTables(sql)).toEqual([entry("BBBBB", { game: "tiles", updatedAt: 3_000, status: "over", yourTurn: false })]);
  });
});
