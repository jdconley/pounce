/** One row of a tables list, as a room last reported it. */
export type TableEntry = {
  code: string;
  /** Absent for tables last reported before tables had names. */
  name?: string;
  status: string;
  yourTurn: boolean;
  updatedAt: number;
};

const MAX_TABLES = 50;

/** The tables list in a Durable Object's SQLite: the same schema for devices and players. */
export function createTables(sql: SqlStorage): void {
  sql.exec("CREATE TABLE IF NOT EXISTS tables (code TEXT PRIMARY KEY, status TEXT, your_turn INTEGER, updated_at INTEGER)");
  const columns = sql.exec<{ name: string }>("PRAGMA table_info(tables)").toArray();
  if (!columns.some((c) => c.name === "name")) sql.exec("ALTER TABLE tables ADD COLUMN name TEXT");
}

/** An older report never overwrites a newer one. */
export function upsertTable(sql: SqlStorage, entry: TableEntry): void {
  sql.exec(
    `INSERT INTO tables (code, name, status, your_turn, updated_at) VALUES (?, ?, ?, ?, ?)
     ON CONFLICT (code) DO UPDATE SET name = excluded.name, status = excluded.status,
       your_turn = excluded.your_turn, updated_at = excluded.updated_at
     WHERE excluded.updated_at >= tables.updated_at`,
    entry.code,
    entry.name ?? null,
    entry.status,
    entry.yourTurn ? 1 : 0,
    entry.updatedAt,
  );
}

export function removeTable(sql: SqlStorage, code: string): void {
  sql.exec("DELETE FROM tables WHERE code = ?", code);
}

/** Newest first, at most 50. */
export function listTables(sql: SqlStorage): TableEntry[] {
  return sql
    .exec<{ code: string; name: string | null; status: string; your_turn: number; updated_at: number }>(
      "SELECT code, name, status, your_turn, updated_at FROM tables ORDER BY updated_at DESC LIMIT ?",
      MAX_TABLES,
    )
    .toArray()
    .map((row) => ({
      code: row.code,
      ...(row.name === null ? {} : { name: row.name }),
      status: row.status,
      yourTurn: row.your_turn === 1,
      updatedAt: row.updated_at,
    }));
}
