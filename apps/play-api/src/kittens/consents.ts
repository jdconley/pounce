import { DurableObject } from "cloudflare:workers";

import { firstText, secondText } from "../consent/pages";
import {
  allows,
  confirm,
  expireText,
  link,
  newRecord,
  nextWake,
  revoke,
  repointParent,
  secondSent,
  setAppleApprovals,
  setParentApprovals,
  text,
  TEXTED_MS,
  unlinkParent,
  type ConsentRecord,
} from "../consent/rules";
import { OPTED_OUT, sendText, twilioConfig } from "../consent/twilio";
import { base64url, sha256Hex } from "../players/ids";

import { KITTENS_NAME } from "./kitten-index";

import type { Env } from "../env";

const TOKEN_BYTES = 16;
const HOUR_MS = 60 * 60_000;
/** A revoke link works while consent lasts; this only bounds the row. */
const REVOKE_MS = 3 * 365 * 24 * HOUR_MS;
/** Text 2 is retried hourly for a day after it was due, then dropped. */
const SECOND_RETRY_MS = HOUR_MS;
const SECOND_GIVE_UP_MS = 24 * HOUR_MS;

export const DEFAULT_ORIGIN = "https://play.conleychaos.com";

export const phoneHash = (e164: string): Promise<string> => sha256Hex(`phone:${e164}`);
const newToken = () => base64url(crypto.getRandomValues(new Uint8Array(TOKEN_BYTES)));
const index = (env: Env) => env.KITTENS.get(env.KITTENS.idFromName(KITTENS_NAME));

export type Why = "parent" | "link" | "stop" | "rescind" | "opted_out";

/**
 * One instance per kitten player (named by the kitten's player id): the
 * consent record (consent design §3), its alarm for the second text and the
 * texted expiry, the texts themselves, and the side effects of revocation:
 * the phone and tokens go from the index, every push token from the kitten's
 * devices.
 */
export class Consents extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => this.schema());
  }

  private schema(): void {
    this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT)");
  }

  private getMeta(k: string): string | null {
    return this.ctx.storage.sql.exec<{ v: string }>("SELECT v FROM meta WHERE k = ?", k).toArray()[0]?.v ?? null;
  }

  private setMeta(k: string, v: string | null): void {
    if (v === null) this.ctx.storage.sql.exec("DELETE FROM meta WHERE k = ?", k);
    else this.ctx.storage.sql.exec("INSERT INTO meta (k, v) VALUES (?, ?) ON CONFLICT (k) DO UPDATE SET v = excluded.v", k, v);
  }

  record(): ConsentRecord | null {
    const v = this.getMeta("rec");
    return v === null ? null : (JSON.parse(v) as ConsentRecord);
  }

  private async save(r: ConsentRecord): Promise<void> {
    this.setMeta("rec", JSON.stringify(r));
    const wake = nextWake(r);
    if (wake === null) await this.ctx.storage.deleteAlarm();
    else await this.ctx.storage.setAlarm(Math.max(wake, Number(this.getMeta("retry_at") ?? 0)));
  }

  /** A parent links (decision 4): the record is made on the first link. */
  async link(kid: string, kitten: string, parent: string, tx: string | null): Promise<ConsentRecord> {
    const existing = this.record();
    const r = existing ? link(existing, parent, tx) : newRecord(kid, kitten, parent, tx);
    await this.save(r);
    if (tx) await index(this.env).setTransaction(kitten, tx);
    return r;
  }

  /** The push gate (decision 16): one read, so revocation applies at once. */
  allows(kind: string, senders: (string | null)[]): boolean {
    return allows(this.record(), kind, senders);
  }

  /**
   * Text 1 (decision 5): the confirm link to `phone`. Without all of
   * Twilio's secrets nothing is sent and nothing changes.
   */
  async startText(parent: string, phone: string, origin: string, now: number): Promise<{ ok: ConsentRecord } | { error: "not_parent" | "consented" | "not_configured" | "send_failed" }> {
    const r = this.record();
    if (!r) return { error: "not_parent" };
    const next = text(r, parent, phone, now);
    if ("error" in next) return next;
    const cfg = twilioConfig(this.env);
    if (!cfg) return { error: "not_configured" };
    const token = newToken();
    const sent = await sendText(cfg, phone, firstText(`${origin}/consent/${token}`), fetch);
    if (!sent.ok) return { error: "send_failed" };
    const ix = index(this.env);
    await ix.dropTokens(r.kitten, "confirm");
    await ix.putToken(token, { kitten: r.kitten, kind: "confirm" }, now + TEXTED_MS);
    await ix.setPhone(r.kitten, await phoneHash(phone));
    this.setMeta("origin", origin);
    await this.save(next.ok);
    return next;
  }

  /** The confirm link's button (decision 6). The zone is the texting parent's, for text 2's hour. */
  async confirm(zone: string | null, now: number): Promise<boolean> {
    const r = this.record();
    const next = r ? confirm(r, now, zone) : null;
    if (!next) return false;
    const ix = index(this.env);
    await ix.dropTokens(next.kitten, "confirm");
    const revokeToken = newToken();
    await ix.putToken(revokeToken, { kitten: next.kitten, kind: "revoke" }, now + REVOKE_MS);
    this.setMeta("revoke_token", revokeToken);
    await this.save(next);
    return true;
  }

  /** Back to pending (decision 9): phone, tokens and the kitten's push tokens go. True if consent (or a text) was live. */
  async revoke(why: Why): Promise<boolean> {
    const r = this.record();
    if (!r || r.state === "pending") return false;
    await this.save(revoke(r));
    await this.forgetContact(r.kitten);
    console.log("consent_revoked", why);
    return true;
  }

  private async forgetContact(kitten: string): Promise<void> {
    this.setMeta("revoke_token", null);
    this.setMeta("retry_at", null);
    const ix = index(this.env);
    await ix.setPhone(kitten, null);
    await ix.dropTokens(kitten);
    await dropKittenTokens(this.env, kitten);
  }

  /** The record ends (decision 10): deleted, expired, or turned 13. */
  async end(): Promise<void> {
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
  async unlinkParent(parent: string): Promise<void> {
    const r = this.record();
    if (!r) return;
    const next = unlinkParent(r, parent);
    await index(this.env).removeParent(parent, r.kitten);
    if (next === null) return this.end();
    await this.save(next);
    if (next.state === "pending" && r.state !== "pending") await this.forgetContact(r.kitten);
  }

  async repointParent(from: string, to: string): Promise<void> {
    const r = this.record();
    if (r) await this.save(repointParent(r, from, to));
  }

  async setParentApprovals(parent: string, approved: string[], partners: string[]): Promise<"ok" | "not_parent" | "apple_managed"> {
    const r = this.record();
    if (!r) return "not_parent";
    const next = setParentApprovals(r, parent, approved, partners);
    if ("error" in next) return next.error;
    await this.save(next);
    return "ok";
  }

  async setAppleApprovals(apple: string[] | null, partners: string[]): Promise<boolean> {
    const r = this.record();
    if (!r) return false;
    await this.save(setAppleApprovals(r, apple, partners));
    return true;
  }

  /** Text 2 and the texted expiry (decisions 7, 8). The alarm runs it; so does a test hook with a chosen time. */
  async tick(now: number): Promise<void> {
    const r = this.record();
    if (!r) return;
    if (r.state === "texted") {
      const next = expireText(r, now);
      if (next !== r) {
        await this.save(next);
        await this.forgetContact(r.kitten);
        return;
      }
      await this.save(r);
      return;
    }
    if (r.state !== "consented" || r.secondSent || (r.secondAt as number) > now) return this.save(r);
    const cfg = twilioConfig(this.env);
    const token = this.getMeta("revoke_token");
    const origin = this.getMeta("origin") ?? DEFAULT_ORIGIN;
    const sent = cfg && token && r.phone ? await sendText(cfg, r.phone, secondText(`${origin}/consent/${token}`), fetch) : null;
    if (sent && !sent.ok && sent.code === OPTED_OUT) {
      await this.revoke("opted_out");
      return;
    }
    if (sent?.ok || now >= (r.secondAt as number) + SECOND_GIVE_UP_MS) {
      this.setMeta("retry_at", null);
      await this.save(secondSent(r));
      return;
    }
    this.setMeta("retry_at", String(now + SECOND_RETRY_MS));
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
