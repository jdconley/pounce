import { DurableObject } from "cloudflare:workers";

import { attemptAllowed, LINK_CODE_MS, newKid, newLinkCode } from "../consent/rules";

import type { Env } from "../env";

/** The single instance's name. */
export const KITTENS_NAME = "kittens";

export type TokenKind = "confirm" | "revoke";
export type TokenRow = { kitten: string; kind: TokenKind };

const cryptoRng = (): number => (crypto.getRandomValues(new Uint32Array(1))[0] as number) / 2 ** 32;
const CODE_ATTEMPTS = 8;

/**
 * One instance (plan decisions 1, 13–15, 26): six-digit link codes and each
 * parent's failed tries; the public `k_` id of each kitten; which parents
 * link which kittens; the texts' link tokens; phone hashes (for STOP); and
 * app transaction ids (for `RESCIND_CONSENT`). No phone number is kept here,
 * only its hash.
 */
export class KittenIndex extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => {
      const { sql } = this.ctx.storage;
      sql.exec("CREATE TABLE IF NOT EXISTS codes (code TEXT PRIMARY KEY, kitten TEXT, tx TEXT, expires INTEGER)");
      sql.exec("CREATE TABLE IF NOT EXISTS fails (parent TEXT, at INTEGER)");
      sql.exec("CREATE TABLE IF NOT EXISTS kids (kid TEXT PRIMARY KEY, kitten TEXT UNIQUE)");
      sql.exec("CREATE TABLE IF NOT EXISTS parents (parent TEXT, kitten TEXT, PRIMARY KEY (parent, kitten))");
      sql.exec("CREATE TABLE IF NOT EXISTS tokens (token TEXT PRIMARY KEY, kitten TEXT, kind TEXT, expires INTEGER)");
      sql.exec("CREATE TABLE IF NOT EXISTS phones (hash TEXT, kitten TEXT, PRIMARY KEY (hash, kitten))");
      sql.exec("CREATE TABLE IF NOT EXISTS transactions (tx TEXT PRIMARY KEY, kitten TEXT)");
    });
  }

  private async arm(): Promise<void> {
    const t = this.ctx.storage.sql
      .exec<{ t: number | null }>(
        "SELECT MIN(t) AS t FROM (SELECT MIN(expires) AS t FROM codes UNION ALL SELECT MIN(expires) FROM tokens UNION ALL SELECT MIN(at) + 600000 FROM fails)",
      )
      .toArray()[0]?.t ?? null;
    if (t === null) await this.ctx.storage.deleteAlarm();
    else await this.ctx.storage.setAlarm(t);
  }

  async alarm(): Promise<void> {
    await this.prune(Date.now());
  }

  async prune(now: number): Promise<void> {
    const { sql } = this.ctx.storage;
    sql.exec("DELETE FROM codes WHERE expires <= ?", now);
    sql.exec("DELETE FROM tokens WHERE expires <= ?", now);
    sql.exec("DELETE FROM fails WHERE at <= ?", now - LINK_CODE_MS);
    await this.arm();
  }

  /** A fresh code for the kitten; any older one stops working. */
  async putCode(kitten: string, tx: string | null, now: number): Promise<{ code: string; expiresAt: number }> {
    const { sql } = this.ctx.storage;
    sql.exec("DELETE FROM codes WHERE kitten = ? OR expires <= ?", kitten, now);
    for (let i = 0; i < CODE_ATTEMPTS; i++) {
      const code = newLinkCode(cryptoRng);
      if (sql.exec("SELECT 1 FROM codes WHERE code = ?", code).toArray().length > 0) continue;
      const expiresAt = now + LINK_CODE_MS;
      sql.exec("INSERT INTO codes (code, kitten, tx, expires) VALUES (?, ?, ?, ?)", code, kitten, tx, expiresAt);
      await this.arm();
      return { code, expiresAt };
    }
    throw new Error("no_link_code");
  }

  /**
   * A parent's try. Single use; a wrong or expired code counts against the
   * parent, and past 5 in 10 minutes every try is refused (decision 14).
   */
  async takeCode(parent: string, code: string, now: number): Promise<{ kitten: string; tx: string | null } | { limited: true } | { bad: true }> {
    const { sql } = this.ctx.storage;
    const fails = sql.exec<{ at: number }>("SELECT at FROM fails WHERE parent = ?", parent).toArray().map((r) => r.at);
    if (!attemptAllowed(fails, now)) return { limited: true };
    const row = sql.exec<{ kitten: string; tx: string | null; expires: number }>("SELECT kitten, tx, expires FROM codes WHERE code = ?", code).toArray()[0];
    if (!row || row.expires <= now) {
      sql.exec("INSERT INTO fails (parent, at) VALUES (?, ?)", parent, now);
      await this.arm();
      return { bad: true };
    }
    sql.exec("DELETE FROM codes WHERE code = ?", code);
    await this.arm();
    return { kitten: row.kitten, tx: row.tx };
  }

  /** The kitten's public id, made on first use. */
  kidFor(kitten: string): string {
    const { sql } = this.ctx.storage;
    const found = sql.exec<{ kid: string }>("SELECT kid FROM kids WHERE kitten = ?", kitten).toArray()[0]?.kid;
    if (found) return found;
    const kid = newKid();
    sql.exec("INSERT INTO kids (kid, kitten) VALUES (?, ?)", kid, kitten);
    return kid;
  }

  kittenOf(kid: string): string | null {
    return this.ctx.storage.sql.exec<{ kitten: string }>("SELECT kitten FROM kids WHERE kid = ?", kid).toArray()[0]?.kitten ?? null;
  }

  addParent(parent: string, kitten: string): void {
    this.ctx.storage.sql.exec("INSERT OR IGNORE INTO parents (parent, kitten) VALUES (?, ?)", parent, kitten);
  }

  removeParent(parent: string, kitten: string): void {
    this.ctx.storage.sql.exec("DELETE FROM parents WHERE parent = ? AND kitten = ?", parent, kitten);
  }

  kittensOf(parent: string): string[] {
    return this.ctx.storage.sql
      .exec<{ kitten: string }>("SELECT kitten FROM parents WHERE parent = ? ORDER BY rowid", parent)
      .toArray()
      .map((r) => r.kitten);
  }

  /** After a merge: `from`'s links are `to`'s. */
  repointParent(from: string, to: string): string[] {
    const kittens = this.kittensOf(from);
    for (const k of kittens) this.addParent(to, k);
    this.ctx.storage.sql.exec("DELETE FROM parents WHERE parent = ?", from);
    return kittens;
  }

  async putToken(token: string, row: TokenRow, expires: number): Promise<void> {
    this.ctx.storage.sql.exec("INSERT INTO tokens (token, kitten, kind, expires) VALUES (?, ?, ?, ?)", token, row.kitten, row.kind, expires);
    await this.arm();
  }

  getToken(token: string, now: number): TokenRow | null {
    const r = this.ctx.storage.sql
      .exec<{ kitten: string; kind: string; expires: number }>("SELECT kitten, kind, expires FROM tokens WHERE token = ?", token)
      .toArray()[0];
    return r && r.expires > now ? { kitten: r.kitten, kind: r.kind as TokenKind } : null;
  }

  /** The kitten's link tokens go (all of them, or one kind). */
  async dropTokens(kitten: string, kind?: TokenKind): Promise<void> {
    if (kind) this.ctx.storage.sql.exec("DELETE FROM tokens WHERE kitten = ? AND kind = ?", kitten, kind);
    else this.ctx.storage.sql.exec("DELETE FROM tokens WHERE kitten = ?", kitten);
    await this.arm();
  }

  /** The kitten's phone hash, replaced (null: none). */
  setPhone(kitten: string, hash: string | null): void {
    this.ctx.storage.sql.exec("DELETE FROM phones WHERE kitten = ?", kitten);
    if (hash) this.ctx.storage.sql.exec("INSERT INTO phones (hash, kitten) VALUES (?, ?)", hash, kitten);
  }

  kittensByPhone(hash: string): string[] {
    return this.ctx.storage.sql
      .exec<{ kitten: string }>("SELECT kitten FROM phones WHERE hash = ?", hash)
      .toArray()
      .map((r) => r.kitten);
  }

  setTransaction(kitten: string, tx: string): void {
    this.ctx.storage.sql.exec("DELETE FROM transactions WHERE kitten = ?", kitten);
    this.ctx.storage.sql.exec("INSERT INTO transactions (tx, kitten) VALUES (?, ?) ON CONFLICT (tx) DO UPDATE SET kitten = excluded.kitten", tx, kitten);
  }

  kittenByTransaction(tx: string): string | null {
    return this.ctx.storage.sql.exec<{ kitten: string }>("SELECT kitten FROM transactions WHERE tx = ?", tx).toArray()[0]?.kitten ?? null;
  }

  /** Everything about a kitten goes: its record ended (deleted, expired, turned 13). */
  async forgetKitten(kitten: string): Promise<void> {
    const { sql } = this.ctx.storage;
    for (const table of ["codes", "kids", "parents", "tokens", "phones", "transactions"]) {
      sql.exec(`DELETE FROM ${table} WHERE kitten = ?`, kitten);
    }
    await this.arm();
  }
}
