import type { DatabaseSync } from "node:sqlite";

/**
 * A real SQLite (Node's own) behind the one method of a Durable Object's `SqlStorage` the tables
 * list uses, so its SQL can run outside a Durable Object.
 */
export function storage(db: DatabaseSync): SqlStorage {
  return {
    exec(query: string, ...params: unknown[]) {
      const statement = db.prepare(query);
      const reads = /^\s*(SELECT|PRAGMA)/i.test(query);
      const rows = reads ? statement.all(...(params as never[])) : (statement.run(...(params as never[])), []);
      return { toArray: () => rows };
    },
  } as unknown as SqlStorage;
}
