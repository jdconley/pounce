import { DurableObject } from "cloudflare:workers";

import type { Env } from "../env";

/** The single instance's name. */
export const LINKS_NAME = "links";

/**
 * Deleting or merging away a player forgets its pounce ids and link tokens
 * (§14). Links only exist with streaks on; never fatal.
 */
export async function forgetLinks(env: Env, playerId: string): Promise<void> {
  if (!["on", "1", "true"].includes((env.STREAKS ?? "").toLowerCase())) return;
  try {
    await env.LINKS.get(env.LINKS.idFromName(LINKS_NAME)).removePlayer(playerId);
  } catch {
    console.error("links_forget_failed");
  }
}

/** `pounce`: a pounce id → its sender. `link`: a Messages link token → its sender and pounce (§12.4). */
export type LinkKind = "pounce" | "link";
export type LinkRow = { kind: LinkKind; playerId: string; pounceId: string; expires: number };

/**
 * One instance (§13.2): finds a pounce's sender from its id or its link
 * token, so neither carries a player id. Rows are deleted when used or when
 * they expire: links after 24 hours, pounce ids after 7 days (§14).
 */
export class Links extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(
        "CREATE TABLE IF NOT EXISTS links (key TEXT PRIMARY KEY, kind TEXT, player_id TEXT, pounce_id TEXT, expires INTEGER)",
      );
    });
  }

  private async arm(): Promise<void> {
    const next = this.ctx.storage.sql.exec<{ t: number | null }>("SELECT MIN(expires) AS t FROM links").toArray()[0]?.t ?? null;
    if (next === null) await this.ctx.storage.deleteAlarm();
    else await this.ctx.storage.setAlarm(next);
  }

  async put(key: string, row: LinkRow): Promise<void> {
    this.ctx.storage.sql.exec(
      `INSERT INTO links (key, kind, player_id, pounce_id, expires) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT (key) DO UPDATE SET kind = excluded.kind, player_id = excluded.player_id,
         pounce_id = excluded.pounce_id, expires = excluded.expires`,
      key,
      row.kind,
      row.playerId,
      row.pounceId,
      row.expires,
    );
    await this.arm();
  }

  /** The row for `key`, or null when there's none or it has expired. */
  get(key: string, now: number): LinkRow | null {
    const r = this.ctx.storage.sql
      .exec<{ kind: string; player_id: string; pounce_id: string; expires: number }>(
        "SELECT kind, player_id, pounce_id, expires FROM links WHERE key = ?",
        key,
      )
      .toArray()[0];
    if (!r || r.expires <= now) return null;
    return { kind: r.kind as LinkKind, playerId: r.player_id, pounceId: r.pounce_id, expires: r.expires };
  }

  /** Single use: returns the row and deletes it. */
  async take(key: string, now: number): Promise<LinkRow | null> {
    const row = this.get(key, now);
    this.ctx.storage.sql.exec("DELETE FROM links WHERE key = ?", key);
    await this.arm();
    return row;
  }

  /** A deleted or merged-away player's links go (§14). */
  async removePlayer(playerId: string): Promise<void> {
    this.ctx.storage.sql.exec("DELETE FROM links WHERE player_id = ?", playerId);
    await this.arm();
  }

  async prune(now: number): Promise<void> {
    this.ctx.storage.sql.exec("DELETE FROM links WHERE expires <= ?", now);
    await this.arm();
  }

  async alarm(): Promise<void> {
    await this.prune(Date.now());
  }
}
