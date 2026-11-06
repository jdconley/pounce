import { DurableObject } from "cloudflare:workers";

import { attemptAllowed, LINK_CODE_MS, newKid, newLinkCode, textAllowed, TEXTS_PER_PARENT, TEXTS_PER_PHONE, TEXT_WINDOW_MS } from "../consent/rules";

import type { Env } from "../env";

/** The single instance's name. */
export const KITTENS_NAME = "kittens";

const cryptoRng = (): number => (crypto.getRandomValues(new Uint32Array(1))[0] as number) / 2 ** 32;
const CODE_ATTEMPTS = 8;
/** Failed link tries from everyone in 10 minutes before every try waits (review M12). */
const GLOBAL_FAILS = 200;

/**
 * One instance (plan decisions 1, 13–15, 41): six-digit link codes and each
 * parent's failed tries; the public `k_` id of each kitten; which parents
 * link which kittens; app transaction ids (for `RESCIND_CONSENT`); and the
 * day's Verify codes per parent and per number. No phone number is kept here,
 * only its HMAC, and that only for a day.
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
      sql.exec("CREATE TABLE IF NOT EXISTS transactions (tx TEXT PRIMARY KEY, kitten TEXT)");
      sql.exec("CREATE TABLE IF NOT EXISTS texts (parent TEXT, at INTEGER)");
      sql.exec("CREATE TABLE IF NOT EXISTS phone_texts (hash TEXT, at INTEGER)");
      // The text plus build's texted-link tokens and STOP lookup: Verify needs neither.
      sql.exec("DROP TABLE IF EXISTS tokens");
      sql.exec("DROP TABLE IF EXISTS phones");
    });
  }

  private async arm(): Promise<void> {
    const t = this.ctx.storage.sql
      .exec<{ t: number | null }>(
        "SELECT MIN(t) AS t FROM (SELECT MIN(expires) AS t FROM codes UNION ALL SELECT MIN(at) + 600000 FROM fails UNION ALL SELECT MIN(at) + 86400000 FROM texts UNION ALL SELECT MIN(at) + 86400000 FROM phone_texts)",
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
    sql.exec("DELETE FROM fails WHERE at <= ?", now - LINK_CODE_MS);
    sql.exec("DELETE FROM texts WHERE at <= ?", now - TEXT_WINDOW_MS);
    sql.exec("DELETE FROM phone_texts WHERE at <= ?", now - TEXT_WINDOW_MS);
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
    const everyone = sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM fails WHERE at > ?", now - LINK_CODE_MS).toArray()[0]?.n ?? 0;
    if (!attemptAllowed(fails, now) || everyone >= GLOBAL_FAILS) return { limited: true };
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
    this.ctx.storage.sql.exec("UPDATE texts SET parent = ? WHERE parent = ?", to, from);
    return kittens;
  }

  /** A kitten's app transaction id. One already held by another kitten keeps its owner (review M8). */
  setTransaction(kitten: string, tx: string): void {
    const owner = this.kittenByTransaction(tx);
    if (owner !== null && owner !== kitten) return;
    this.ctx.storage.sql.exec("DELETE FROM transactions WHERE kitten = ?", kitten);
    this.ctx.storage.sql.exec("INSERT OR IGNORE INTO transactions (tx, kitten) VALUES (?, ?)", tx, kitten);
  }

  /**
   * A parent asks for a code to a number (by its HMAC): allowed, and counted,
   * unless they asked 5 times in the last day, or anyone asked 3 times for
   * that number (review I2).
   */
  async noteText(parent: string, hash: string, now: number): Promise<boolean> {
    const { sql } = this.ctx.storage;
    const times = sql.exec<{ at: number }>("SELECT at FROM texts WHERE parent = ?", parent).toArray().map((r) => r.at);
    const phone = sql.exec<{ at: number }>("SELECT at FROM phone_texts WHERE hash = ?", hash).toArray().map((r) => r.at);
    if (!textAllowed(times, now, TEXTS_PER_PARENT) || !textAllowed(phone, now, TEXTS_PER_PHONE)) return false;
    sql.exec("INSERT INTO texts (parent, at) VALUES (?, ?)", parent, now);
    sql.exec("INSERT INTO phone_texts (hash, at) VALUES (?, ?)", hash, now);
    await this.arm();
    return true;
  }

  kittenByTransaction(tx: string): string | null {
    return this.ctx.storage.sql.exec<{ kitten: string }>("SELECT kitten FROM transactions WHERE tx = ?", tx).toArray()[0]?.kitten ?? null;
  }

  /** Everything about a kitten goes: its record ended (deleted, expired, turned 13). */
  async forgetKitten(kitten: string): Promise<void> {
    const { sql } = this.ctx.storage;
    for (const table of ["codes", "kids", "parents", "transactions"]) {
      sql.exec(`DELETE FROM ${table} WHERE kitten = ?`, kitten);
    }
    await this.arm();
  }
}
