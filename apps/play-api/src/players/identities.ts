import { DurableObject } from "cloudflare:workers";

import type { Env } from "../env";

/** The single instance's name. It can be sharded by hash prefix if it ever needs to be. */
export const IDENTITIES_NAME = "global";

/**
 * The identities index: `(provider, subject_hash) → playerId`, plus the
 * hashed person keys that prove a `device` identity, and Apple nonces already
 * used. Raw provider subjects are never stored.
 */
export class Identities extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => {
      const { sql } = this.ctx.storage;
      sql.exec(
        `CREATE TABLE IF NOT EXISTS identities (provider TEXT, subject_hash TEXT, player_id TEXT, verifier TEXT,
           PRIMARY KEY (provider, subject_hash))`,
      );
      sql.exec("CREATE INDEX IF NOT EXISTS identities_player ON identities (player_id)");
      sql.exec("CREATE TABLE IF NOT EXISTS nonces (hash TEXT PRIMARY KEY, expires_at INTEGER)");
    });
  }

  /**
   * Claims an identity for `playerId` if nobody has it. Otherwise returns its
   * owner, or `mismatch` when a verifier is given and differs from the stored one.
   */
  bind(
    provider: string,
    subjectHash: string,
    playerId: string,
    verifier?: string,
  ): { playerId: string; created: boolean } | { mismatch: true } {
    const existing = this.lookup(provider, subjectHash);
    if (existing) {
      if (verifier !== undefined && existing.verifier !== verifier) return { mismatch: true };
      return { playerId: existing.playerId, created: false };
    }
    this.ctx.storage.sql.exec(
      "INSERT INTO identities (provider, subject_hash, player_id, verifier) VALUES (?, ?, ?, ?)",
      provider,
      subjectHash,
      playerId,
      verifier ?? null,
    );
    return { playerId, created: true };
  }

  lookup(provider: string, subjectHash: string): { playerId: string; verifier: string | null } | null {
    const row = this.ctx.storage.sql
      .exec<{ player_id: string; verifier: string | null }>(
        "SELECT player_id, verifier FROM identities WHERE provider = ? AND subject_hash = ?",
        provider,
        subjectHash,
      )
      .toArray()[0];
    return row ? { playerId: row.player_id, verifier: row.verifier } : null;
  }

  repoint(from: string, to: string): void {
    this.ctx.storage.sql.exec("UPDATE identities SET player_id = ? WHERE player_id = ?", to, from);
  }

  /** Removes one identity, only if it still belongs to `playerId`. */
  remove(provider: string, subjectHash: string, playerId: string): void {
    this.ctx.storage.sql.exec(
      "DELETE FROM identities WHERE provider = ? AND subject_hash = ? AND player_id = ?",
      provider,
      subjectHash,
      playerId,
    );
  }

  removePlayer(playerId: string): void {
    this.ctx.storage.sql.exec("DELETE FROM identities WHERE player_id = ?", playerId);
  }

  /** True the first time a nonce hash is seen. Expired ones are forgotten. */
  useNonce(hash: string, expiresAt: number, now: number): boolean {
    const { sql } = this.ctx.storage;
    sql.exec("DELETE FROM nonces WHERE expires_at <= ?", now);
    if (sql.exec("SELECT 1 FROM nonces WHERE hash = ?", hash).toArray().length > 0) return false;
    sql.exec("INSERT INTO nonces (hash, expires_at) VALUES (?, ?)", hash, expiresAt);
    return true;
  }
}
