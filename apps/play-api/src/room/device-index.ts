import { DurableObject } from "cloudflare:workers";

import { pushYourTurn } from "../push/apns";

import type { Env } from "../env";
import type { PushIntent } from "./core";

export type TableEntry = {
  code: string;
  status: string;
  yourTurn: boolean;
  updatedAt: number;
};

const MAX_TABLES = 50;

/**
 * One instance per device (named by deviceId): its APNs token and the rooms
 * it sits in, as reported by each room.
 */
export class DeviceIndex extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT)");
      this.ctx.storage.sql.exec(
        "CREATE TABLE IF NOT EXISTS tables (code TEXT PRIMARY KEY, status TEXT, your_turn INTEGER, updated_at INTEGER)",
      );
    });
  }

  setApnsToken(token: string): void {
    this.ctx.storage.sql.exec(
      "INSERT INTO meta (k, v) VALUES ('apns_token', ?) ON CONFLICT (k) DO UPDATE SET v = excluded.v",
      token,
    );
  }

  /** An older report never overwrites a newer one. */
  upsertTable(entry: TableEntry): void {
    this.ctx.storage.sql.exec(
      `INSERT INTO tables (code, status, your_turn, updated_at) VALUES (?, ?, ?, ?)
       ON CONFLICT (code) DO UPDATE SET status = excluded.status, your_turn = excluded.your_turn,
         updated_at = excluded.updated_at
       WHERE excluded.updated_at >= tables.updated_at`,
      entry.code,
      entry.status,
      entry.yourTurn ? 1 : 0,
      entry.updatedAt,
    );
  }

  removeTable(code: string): void {
    this.ctx.storage.sql.exec("DELETE FROM tables WHERE code = ?", code);
  }

  /** Newest first, at most 50. */
  listTables(): TableEntry[] {
    return this.ctx.storage.sql
      .exec<{ code: string; status: string; your_turn: number; updated_at: number }>(
        "SELECT code, status, your_turn, updated_at FROM tables ORDER BY updated_at DESC LIMIT ?",
        MAX_TABLES,
      )
      .toArray()
      .map((row) => ({
        code: row.code,
        status: row.status,
        yourTurn: row.your_turn === 1,
        updatedAt: row.updated_at,
      }));
  }

  /**
   * Sends the "your turn" push, and forgets a token APNs says is dead. Only
   * that token: the device may have registered a new one while the push was
   * in flight.
   */
  async push(intent: PushIntent): Promise<{ sent: boolean }> {
    const token =
      this.ctx.storage.sql.exec<{ v: string }>("SELECT v FROM meta WHERE k = 'apns_token'").toArray()[0]?.v ?? null;
    const { sent, unregistered } = await pushYourTurn(this.env, token, intent);
    if (unregistered) this.ctx.storage.sql.exec("DELETE FROM meta WHERE k = 'apns_token' AND v = ?", token);
    return { sent };
  }
}
