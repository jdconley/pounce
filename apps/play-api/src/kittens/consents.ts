import { DurableObject } from "cloudflare:workers";

import { plusPush } from "../consent/pages";
import {
  allows,
  attemptAllowed,
  confirm,
  expireCode,
  FAIL_WINDOW_MS,
  link,
  newRecord,
  nextWake,
  plusDone,
  PLUS_GIVE_UP_MS,
  plusRetryAt,
  repointParent,
  repointPartner,
  resend,
  revoke,
  setAppleApprovals,
  setParentApprovals,
  startCode,
  textAllowed,
  TEXTS_PER_KITTEN,
  TEXT_WINDOW_MS,
  unlinkParent,
  upgrade,
  type ConsentRecord,
} from "../consent/rules";
import { checkVerification, startVerification, twilioConfig, type TwilioConfig } from "../consent/twilio";
import { deliverToPlayer } from "../notify/deliver";

import { KITTENS_NAME } from "./kitten-index";

import type { Env } from "../env";

const encoder = new TextEncoder();

/** A phone's index key: HMAC-SHA-256 under the token secret, so the index alone can't be brute-forced back to numbers. */
export async function phoneHash(env: Pick<Env, "TOKEN_SECRET">, e164: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(`phone:${env.TOKEN_SECRET ?? ""}`), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(e164)));
  return [...mac].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const index = (env: Env) => env.KITTENS.get(env.KITTENS.idFromName(KITTENS_NAME));
const playerRpc = (env: Env, id: string) => env.PLAYERS.get(env.PLAYERS.idFromName(id));

export type Why = "parent" | "rescind" | "no_plus";
export type CodeError = "not_parent" | "consented" | "not_waiting" | "not_configured" | "send_failed" | "rate_limited" | "bad_number";
export type CheckError = "not_parent" | "not_waiting" | "not_configured" | "wrong_code" | "expired" | "rate_limited" | "check_failed";

/**
 * One instance per kitten player (named by the kitten's player id): the
 * consent record (consent design §3), its alarm for the confirmation push and
 * the code's expiry, the Twilio Verify calls, and the side effects of
 * revocation: the number goes, and every push token from the kitten's devices.
 *
 * Every change runs one at a time (`serial`): a change awaits outside calls
 * (Verify, APNs, the index, the kitten's devices), during which a Durable
 * Object takes other requests, so a revoke arriving while a code check is out
 * would otherwise be overwritten by the older record (review I1).
 */
export class Consents extends DurableObject<Env> {
  private queue: Promise<unknown> = Promise.resolve();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => this.schema());
  }

  private schema(): void {
    this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT)");
    // The text plus build's leftovers: Twilio message SIDs and the texted pages' revoke token.
    this.ctx.storage.sql.exec("DELETE FROM meta WHERE k IN ('sids', 'revoke_token', 'origin')");
  }

  /** Runs `fn` after every change before it has finished, failed or not. */
  private serial<T>(fn: () => Promise<T>): Promise<T> {
    const run = this.queue.then(fn, fn);
    this.queue = run.catch(() => undefined);
    return run;
  }

  private getMeta(k: string): string | null {
    return this.ctx.storage.sql.exec<{ v: string }>("SELECT v FROM meta WHERE k = ?", k).toArray()[0]?.v ?? null;
  }

  private setMeta(k: string, v: string | null): void {
    if (v === null) this.ctx.storage.sql.exec("DELETE FROM meta WHERE k = ?", k);
    else this.ctx.storage.sql.exec("INSERT INTO meta (k, v) VALUES (?, ?) ON CONFLICT (k) DO UPDATE SET v = excluded.v", k, v);
  }

  private times(k: string, now: number, window: number): number[] {
    const v = this.getMeta(k);
    return v === null ? [] : (JSON.parse(v) as number[]).filter((t) => t > now - window);
  }

  record(): ConsentRecord | null {
    const v = this.getMeta("rec");
    return v === null ? null : upgrade(JSON.parse(v) as ConsentRecord);
  }

  private async save(r: ConsentRecord): Promise<void> {
    this.setMeta("rec", JSON.stringify(r));
    const wake = nextWake(r);
    if (wake === null) await this.ctx.storage.deleteAlarm();
    else await this.ctx.storage.setAlarm(Math.max(wake, Number(this.getMeta("retry_at") ?? 0)));
  }

  /** A parent links (decision 4): the record is made on the first link. */
  link(kid: string, kitten: string, parent: string, tx: string | null): Promise<ConsentRecord> {
    return this.serial(async () => {
      const existing = this.record();
      const r = existing ? link(existing, parent, tx) : newRecord(kid, kitten, parent, tx);
      await this.save(r);
      if (tx) await index(this.env).setTransaction(kitten, tx);
      return r;
    });
  }

  /** The push gate (decision 16): one read, so revocation applies at once. */
  allows(kind: string, senders: (string | null)[]): boolean {
    return allows(this.record(), kind, senders);
  }

  /**
   * Counts a code against the day's limits (3 for a kitten, 5 from a parent,
   * 3 to one number; review I2), then asks Verify to text it. Without all of
   * Twilio's secrets nothing is sent and nothing changes.
   */
  private async send(parent: string, phone: string, now: number): Promise<{ cfg: TwilioConfig } | { error: CodeError }> {
    const cfg = twilioConfig(this.env);
    if (!cfg) return { error: "not_configured" };
    const times = this.times("text_times", now, TEXT_WINDOW_MS);
    if (!textAllowed(times, now, TEXTS_PER_KITTEN) || !(await index(this.env).noteText(parent, await phoneHash(this.env, phone), now))) {
      return { error: "rate_limited" };
    }
    this.setMeta("text_times", JSON.stringify([...times, now]));
    const sent = await startVerification(cfg, phone, fetch);
    if (sent === "sent") return { cfg };
    return { error: sent === "limited" ? "rate_limited" : sent === "bad_number" ? "bad_number" : "send_failed" };
  }

  /** A code to the parent's number (decision 5; D6). A new number replaces the old one. */
  startCode(parent: string, phone: string, now: number): Promise<{ ok: ConsentRecord } | { error: CodeError }> {
    return this.serial(async () => {
      const r = this.record();
      if (!r) return { error: "not_parent" as const };
      const next = startCode(r, parent, phone, now);
      if ("error" in next) return next;
      const sent = await this.send(parent, phone, now);
      if ("error" in sent) return sent;
      this.setMeta("check_fails", null);
      await this.save(next.ok);
      return next;
    });
  }

  /** Another code to the same number: Verify repeats the live one, or makes a fresh one once it expired. */
  resendCode(parent: string, now: number): Promise<{ ok: ConsentRecord } | { error: CodeError }> {
    return this.serial(async () => {
      const r = this.record();
      if (!r) return { error: "not_parent" as const };
      const next = resend(r, parent, now);
      if ("error" in next) return { error: next.error === "too_soon" ? ("rate_limited" as const) : next.error };
      const sent = await this.send(parent, r.phone as string, now);
      if ("error" in sent) return sent;
      await this.save(next.ok);
      return next;
    });
  }

  /**
   * The parent types the code (decision 6; D6). Verify's `approved` is
   * consent. A wrong code counts against 5 in 10 minutes, like link codes.
   * The zone is the number owner's, for the confirmation push's hour.
   */
  checkCode(parent: string, code: string, now: number): Promise<{ ok: ConsentRecord } | { error: CheckError }> {
    return this.serial(async () => {
      const r = this.record();
      if (!r || !r.parents.includes(parent)) return { error: "not_parent" as const };
      if (r.state !== "code") return { error: "not_waiting" as const };
      const cfg = twilioConfig(this.env);
      if (!cfg) return { error: "not_configured" as const };
      const fails = this.times("check_fails", now, FAIL_WINDOW_MS);
      if (!attemptAllowed(fails, now)) return { error: "rate_limited" as const };
      const result = await checkVerification(cfg, r.phone as string, code, fetch);
      if (result === "wrong") {
        this.setMeta("check_fails", JSON.stringify([...fails, now]));
        return { error: "wrong_code" as const };
      }
      if (result !== "approved") {
        return { error: result === "expired" ? ("expired" as const) : result === "limited" ? ("rate_limited" as const) : ("check_failed" as const) };
      }
      const zone = (await playerRpc(this.env, r.codeBy as string).pushProfile())?.zone ?? null;
      const next = confirm(r, now, zone) as ConsentRecord;
      this.setMeta("check_fails", null);
      await this.save(next);
      return { ok: next };
    });
  }

  /** Back to pending (decision 9): the number and the kitten's push tokens go. True if consent (or a code) was live. */
  revoke(why: Why): Promise<boolean> {
    return this.serial(() => this.revokeNow(why));
  }

  private async revokeNow(why: Why): Promise<boolean> {
    const r = this.record();
    if (!r || r.state === "pending") return false;
    await this.save(revoke(r));
    await this.forgetContact(r.kitten);
    console.log("consent_revoked", why);
    return true;
  }

  /** The number is already gone from the record; the retry state and the kitten's push tokens go too. */
  private async forgetContact(kitten: string): Promise<void> {
    this.setMeta("retry_at", null);
    this.setMeta("check_fails", null);
    await dropKittenTokens(this.env, kitten);
  }

  /** The record ends (decision 10): deleted, expired, or turned 13. */
  end(): Promise<void> {
    return this.serial(() => this.endNow());
  }

  private async endNow(): Promise<void> {
    const r = this.record();
    if (r) {
      await index(this.env).forgetKitten(r.kitten);
      await dropKittenTokens(this.env, r.kitten);
    }
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
    this.schema();
  }

  /** A parent leaves (decision 11). The last one leaving ends the record. */
  unlinkParent(parent: string): Promise<void> {
    return this.serial(async () => {
      const r = this.record();
      if (!r) return;
      const next = unlinkParent(r, parent);
      if (next === null) return this.endNow();
      await this.save(next);
      await index(this.env).removeParent(parent, r.kitten);
      if (next.state === "pending" && r.state !== "pending") await this.forgetContact(r.kitten);
    });
  }

  repointParent(from: string, to: string): Promise<void> {
    return this.serial(async () => {
      const r = this.record();
      if (r) await this.save(repointParent(r, from, to));
    });
  }

  /** An approved partner merged into another player (review M9). */
  repointPartner(from: string, to: string): Promise<void> {
    return this.serial(async () => {
      const r = this.record();
      if (r) await this.save(repointPartner(r, from, to));
    });
  }

  setParentApprovals(parent: string, approved: string[], partners: string[]): Promise<"ok" | "not_parent" | "apple_managed"> {
    return this.serial(async () => {
      const r = this.record();
      if (!r) return "not_parent" as const;
      const next = setParentApprovals(r, parent, approved, partners);
      if ("error" in next) return next.error;
      await this.save(next);
      return "ok" as const;
    });
  }

  setAppleApprovals(apple: string[] | null, partners: string[]): Promise<boolean> {
    return this.serial(async () => {
      const r = this.record();
      if (!r) return false;
      await this.save(setAppleApprovals(r, apple, partners));
      return true;
    });
  }

  /** The confirmation push and the code's expiry (decisions 7, 8; D6). The alarm runs it; so does a test hook with a chosen time. */
  tick(now: number): Promise<void> {
    return this.serial(() => this.tickNow(now));
  }

  private async tickNow(now: number): Promise<void> {
    const r = this.record();
    if (!r) return;
    if (r.state === "code") {
      const next = expireCode(r, now);
      await this.save(next);
      if (next !== r) await this.forgetContact(r.kitten);
      return;
    }
    if (r.state !== "consented" || r.plusSent || (r.plusAt as number) > now) return this.save(r);
    // No device of the consenting parent's accepted it for a day: no plus, no consent (review I4).
    const giveUp = (r.plusAt as number) + PLUS_GIVE_UP_MS;
    if (now >= giveUp) {
      await this.revokeNow("no_plus");
      return;
    }
    const parent = await playerRpc(this.env, r.consentedBy as string).pushProfile();
    const kitten = await playerRpc(this.env, r.kitten).meta();
    const delivered = parent !== null && kitten !== null && (await deliverToPlayer(this.env, parent, plusPush(r.kid, kitten.name), "active"));
    if (delivered) {
      this.setMeta("retry_at", null);
      await this.save(plusDone(r));
      return;
    }
    // Hourly inside 10:00–20:00, and once more exactly when the day is up, which revokes.
    this.setMeta("retry_at", String(Math.min(plusRetryAt(now, parent?.zone ?? null), giveUp)));
    await this.save(r);
  }

  async alarm(): Promise<void> {
    await this.tick(Date.now());
  }

  /** When the alarm is set, for tests. */
  async alarmAt(): Promise<number | null> {
    return this.ctx.storage.getAlarm();
  }
}

/** Every push token on the kitten's devices goes (decision 9): APNs, widget and live table. */
export async function dropKittenTokens(env: Env, kitten: string): Promise<void> {
  try {
    const devices = await env.PLAYERS.get(env.PLAYERS.idFromName(kitten)).deviceIds();
    await Promise.all(devices.map((d) => env.DEVICES.get(env.DEVICES.idFromName(d)).dropPushTokens()));
  } catch {
    console.error("kitten_tokens_drop_failed");
  }
}
