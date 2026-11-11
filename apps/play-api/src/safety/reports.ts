import { DurableObject } from "cloudflare:workers";

import type { ReportReason } from "./parse";
import type { Env } from "../env";

/** The single instance's name. */
export const REPORTS_NAME = "reports";

/** One report, as the owner reads it. */
export type Report = {
  id: number;
  at: number;
  reason: ReportReason;
  /** The table, and its name when the report was made. */
  code: string;
  table: string;
  /** Who was reported: the name they showed at the time, and what the server knows them by. */
  name: string;
  person: string;
  player: string | null;
  device: string | null;
  /** Who reported. */
  byPlayer: string | null;
  byDevice: string;
};

type Row = {
  id: number;
  at: number;
  reason: string;
  code: string;
  table_name: string;
  name: string;
  person: string;
  player: string | null;
  device: string | null;
  by_player: string | null;
  by_device: string;
};

const MAX_PAGE = 200;
/** Reports are kept a year. */
const KEEP_MS = 365 * 24 * 60 * 60 * 1000;

/**
 * One instance: every player report (App Store guideline 1.2), in SQLite. The owner reads them
 * with `GET /v1/admin/reports` (see `REPORTS_KEY`), or in the Cloudflare dashboard's storage
 * viewer for this object.
 */
export class Reports extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(
        `CREATE TABLE IF NOT EXISTS reports (id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER, reason TEXT, code TEXT,
           table_name TEXT, name TEXT, person TEXT, player TEXT, device TEXT, by_player TEXT, by_device TEXT)`,
      );
      this.ctx.storage.sql.exec("CREATE UNIQUE INDEX IF NOT EXISTS once ON reports (by_device, person, code, reason)");
    });
  }

  /** Stores a report and returns its id. The same device reporting the same person at the same table for the same reason again changes nothing. */
  add(r: Omit<Report, "id">): number {
    const { sql } = this.ctx.storage;
    sql.exec("DELETE FROM reports WHERE at < ?", r.at - KEEP_MS);
    sql.exec(
      `INSERT OR IGNORE INTO reports (at, reason, code, table_name, name, person, player, device, by_player, by_device)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      r.at, r.reason, r.code, r.table, r.name, r.person, r.player, r.device, r.byPlayer, r.byDevice,
    );
    const row = sql
      .exec<{ id: number }>(
        "SELECT id FROM reports WHERE by_device = ? AND person = ? AND code = ? AND reason = ?",
        r.byDevice, r.person, r.code, r.reason,
      )
      .toArray()[0];
    return row?.id ?? 0;
  }

  /** Reports with an id above `after`, oldest first, at most 200. */
  list(after: number): Report[] {
    return this.ctx.storage.sql
      .exec<Row>("SELECT * FROM reports WHERE id > ? ORDER BY id LIMIT ?", after, MAX_PAGE)
      .toArray()
      .map((r) => ({
        id: r.id,
        at: r.at,
        reason: r.reason as ReportReason,
        code: r.code,
        table: r.table_name,
        name: r.name,
        person: r.person,
        player: r.player,
        device: r.device,
        byPlayer: r.by_player,
        byDevice: r.by_device,
      }));
  }
}
