import type { Person, SeatKind } from "../protocol";

/**
 * One seat as a tables list shows it: who sits there, for Home's "who you're playing with".
 * `yours` marks the list owner's own seats: on a device's list the seats that device controls,
 * on a player's list that player's seat. The same faces every phone at the table already sees.
 */
export type TableSeat = { kind: SeatKind; person?: Person; yours?: true };

/** One row of a tables list, as a room last reported it. */
export type TableEntry = {
  code: string;
  /** Absent for tables last reported before tables had names. */
  name?: string;
  status: string;
  yourTurn: boolean;
  updatedAt: number;
  /** The table "Play again" dealt from this one (§10.4). */
  next?: string;
  /** Absent for tables last reported before lists carried seats. */
  seats?: TableSeat[];
  /** While a game is mid-round: when the current turn began (epoch ms), so Home can say how long it has waited. */
  movedAt?: number;
  /**
   * The table's game, for a table of any game but Cat Tower. Absent: Cat Tower, as every table was
   * before there was a second game. A list only shows such a table to an app that can draw it.
   */
  game?: string;
};

/** The game a table without a `game` plays. */
const DEFAULT_GAME = "cat-tower";

/** Whether an app that lists `games` can draw a table of `game`. Every app draws Cat Tower (and a table that names no game is one). */
export function drawable(game: string | undefined, games: readonly string[]): boolean {
  return game === undefined || game === DEFAULT_GAME || games.includes(game);
}

/**
 * `lists` (a streak's `myMove` and `theirMove`: table codes) less the tables an app that lists
 * `games` can't draw. The same object when there is nothing to leave out, which is always so for
 * a player with no table of another game.
 */
export function withoutUndrawable<T extends { myMove: string[]; theirMove: string[] }>(
  lists: T,
  tables: readonly TableEntry[],
  games: readonly string[],
): T {
  const hidden = new Set(tables.filter((t) => !drawable(t.game, games)).map((t) => t.code));
  if (hidden.size === 0) return lists;
  const shown = (codes: string[]) => codes.filter((code) => !hidden.has(code));
  return { ...lists, myMove: shown(lists.myMove), theirMove: shown(lists.theirMove) };
}

/** The tables an app that lists `games` can draw: every other table is left out. */
export function tablesFor(tables: readonly TableEntry[], games: readonly string[]): TableEntry[] {
  return tables.filter((t) => drawable(t.game, games));
}

const MAX_TABLES = 50;

/** The tables list in a Durable Object's SQLite: the same schema for devices and players. */
export function createTables(sql: SqlStorage): void {
  sql.exec("CREATE TABLE IF NOT EXISTS tables (code TEXT PRIMARY KEY, status TEXT, your_turn INTEGER, updated_at INTEGER)");
  const columns = sql.exec<{ name: string }>("PRAGMA table_info(tables)").toArray();
  if (!columns.some((c) => c.name === "name")) sql.exec("ALTER TABLE tables ADD COLUMN name TEXT");
  if (!columns.some((c) => c.name === "next")) sql.exec("ALTER TABLE tables ADD COLUMN next TEXT");
  if (!columns.some((c) => c.name === "seats")) sql.exec("ALTER TABLE tables ADD COLUMN seats TEXT");
  if (!columns.some((c) => c.name === "moved_at")) sql.exec("ALTER TABLE tables ADD COLUMN moved_at INTEGER");
  // Null for every row there already is, and for every Cat Tower table from here on.
  if (!columns.some((c) => c.name === "game")) sql.exec("ALTER TABLE tables ADD COLUMN game TEXT");
}

/** An older report never overwrites a newer one. */
export function upsertTable(sql: SqlStorage, entry: TableEntry): void {
  sql.exec(
    `INSERT INTO tables (code, name, status, your_turn, updated_at, next, seats, moved_at, game) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT (code) DO UPDATE SET name = excluded.name, status = excluded.status,
       your_turn = excluded.your_turn, updated_at = excluded.updated_at, next = excluded.next,
       seats = excluded.seats, moved_at = excluded.moved_at, game = excluded.game
     WHERE excluded.updated_at >= tables.updated_at`,
    entry.code,
    entry.name ?? null,
    entry.status,
    entry.yourTurn ? 1 : 0,
    entry.updatedAt,
    entry.next ?? null,
    entry.seats ? JSON.stringify(entry.seats) : null,
    entry.movedAt ?? null,
    entry.game ?? null,
  );
}

export function removeTable(sql: SqlStorage, code: string): void {
  sql.exec("DELETE FROM tables WHERE code = ?", code);
}

/** Newest first, at most 50. */
export function listTables(sql: SqlStorage): TableEntry[] {
  return sql
    .exec<{
      code: string;
      name: string | null;
      status: string;
      your_turn: number;
      updated_at: number;
      next: string | null;
      seats: string | null;
      moved_at: number | null;
      game: string | null;
    }>(
      "SELECT code, name, status, your_turn, updated_at, next, seats, moved_at, game FROM tables ORDER BY updated_at DESC LIMIT ?",
      MAX_TABLES,
    )
    .toArray()
    .map((row) => ({
      code: row.code,
      ...(row.name === null ? {} : { name: row.name }),
      status: row.status,
      yourTurn: row.your_turn === 1,
      updatedAt: row.updated_at,
      ...(row.next === null ? {} : { next: row.next }),
      ...(row.seats === null ? {} : { seats: JSON.parse(row.seats) as TableSeat[] }),
      ...(row.moved_at === null ? {} : { movedAt: row.moved_at }),
      ...(row.game === null ? {} : { game: row.game }),
    }));
}
