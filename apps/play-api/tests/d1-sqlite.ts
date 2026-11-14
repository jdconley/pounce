import type { DatabaseSync, SQLInputValue } from "node:sqlite";

/**
 * A real SQLite (Node's own) behind the parts of D1's binding the funnel uses (`prepare`, `bind`,
 * `run`, `all`, `first`, `batch`), so its SQL runs, and is checked, outside the Workers runtime.
 * A batch is one transaction, as on D1.
 */
export function d1(db: DatabaseSync): D1Database {
  type Statement = D1PreparedStatement & { exec(): void };
  const statement = (sql: string, params: SQLInputValue[] = []): Statement => {
    const it = {
      bind: (...values: unknown[]) => statement(sql, values as SQLInputValue[]),
      exec: () => void db.prepare(sql).run(...params),
      run: async () => {
        db.prepare(sql).run(...params);
        return { success: true, results: [], meta: {} };
      },
      all: async () => ({ success: true, results: db.prepare(sql).all(...params), meta: {} }),
      first: async () => db.prepare(sql).get(...params) ?? null,
    };
    return it as unknown as Statement;
  };
  return {
    prepare: (sql: string) => statement(sql),
    batch: async (statements: D1PreparedStatement[]) => {
      db.exec("BEGIN");
      try {
        for (const s of statements) (s as Statement).exec();
        db.exec("COMMIT");
      } catch (error) {
        db.exec("ROLLBACK");
        throw error;
      }
      return [];
    },
  } as unknown as D1Database;
}

/** node:sqlite, without its one-time ExperimentalWarning on stderr. */
export async function importSqlite(): Promise<typeof import("node:sqlite")> {
  const emit = process.emitWarning;
  process.emitWarning = ((warning: string | Error, ...rest: unknown[]) => {
    if (String(warning).includes("SQLite")) return;
    (emit as (...args: unknown[]) => void).call(process, warning, ...rest);
  }) as typeof process.emitWarning;
  try {
    return await import("node:sqlite");
  } finally {
    process.emitWarning = emit;
  }
}
