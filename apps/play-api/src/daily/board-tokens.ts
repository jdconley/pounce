import { DurableObject } from "cloudflare:workers";

import type { Env } from "../env";

type Row = { hash: string; player: string; device: string; expires: number };

/**
 * One TV board token, named by the token's SHA-256 (daily games design §8): whose board it
 * shows, the TV device it was given to, and until when (30 days). The token itself is random,
 * names no one, and is kept only on the TV. At expiry, or on revoke, the board's TV sockets close.
 */
export class BoardTokens extends DurableObject<Env> {
  /** Reads never make the table, so asking after a token that never was leaves nothing behind. */
  private row(): Row | null {
    const made = this.ctx.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'token'").toArray().length > 0;
    if (!made) return null;
    return this.ctx.storage.sql.exec<Row>("SELECT hash, player, device, expires FROM token WHERE id = 1").toArray()[0] ?? null;
  }

  /** A new token (this instance is named `hash`, its SHA-256): `player`'s board, for the TV `device`, until `expires`. */
  async open(hash: string, player: string, device: string, expires: number): Promise<void> {
    this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS token (id INTEGER PRIMARY KEY CHECK (id = 1), hash TEXT, player TEXT, device TEXT, expires INTEGER)");
    this.ctx.storage.sql.exec("INSERT OR REPLACE INTO token (id, hash, player, device, expires) VALUES (1, ?, ?, ?, ?)", hash, player, device, expires);
    await this.ctx.storage.setAlarm(expires);
  }

  /** The player whose board the token shows, for the TV it was given to while it lives; else null. */
  async resolve(device: string, now: number): Promise<string | null> {
    const row = this.row();
    return row && row.device === device && row.expires > now ? row.player : null;
  }

  /** Forgets the token. */
  async revoke(): Promise<void> {
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
  }

  /** Expiry: the board's sockets on this token close, and the token is forgotten. */
  async alarm(): Promise<void> {
    const row = this.row();
    if (row) {
      await this.env.PLAYERS.get(this.env.PLAYERS.idFromName(row.player))
        .boardTokenGone(row.hash)
        .catch(() => undefined);
    }
    await this.ctx.storage.deleteAll();
  }
}
