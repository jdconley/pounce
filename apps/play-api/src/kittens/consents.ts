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
  repointPartner,
  secondSent,
  setAppleApprovals,
  setParentApprovals,
  text,
  textAllowed,
  TEXTED_MS,
  TEXTS_PER_KITTEN,
  TEXT_WINDOW_MS,
  unlinkParent,
  type ConsentRecord,
} from "../consent/rules";
import { deleteText, OPTED_OUT, sendText, twilioConfig } from "../consent/twilio";
import { base64url } from "../players/ids";

import { KITTENS_NAME } from "./kitten-index";

import type { Env } from "../env";

const TOKEN_BYTES = 16;
const HOUR_MS = 60 * 60_000;
/** A revoke link works while consent lasts; this only bounds the row. */
const REVOKE_MS = 3 * 365 * 24 * HOUR_MS;
/** Text 2 is retried hourly; a day of failures revokes, since text plus needs it (review I4). */
const SECOND_RETRY_MS = HOUR_MS;
const SECOND_GIVE_UP_MS = 24 * HOUR_MS;

export const DEFAULT_ORIGIN = "https://play.conleychaos.com";

const encoder = new TextEncoder();

/** A phone's index key: HMAC-SHA-256 under the token secret, so the index alone can't be brute-forced back to numbers. */
export async function phoneHash(env: Pick<Env, "TOKEN_SECRET">, e164: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(`phone:${env.TOKEN_SECRET ?? ""}`), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(e164)));
  return [...mac].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const newToken = () => base64url(crypto.getRandomValues(new Uint8Array(TOKEN_BYTES)));
const index = (env: Env) => env.KITTENS.get(env.KITTENS.idFromName(KITTENS_NAME));

export type Why = "parent" | "link" | "stop" | "rescind" | "opted_out" | "no_plus";
export type TextError = "not_parent" | "consented" | "not_configured" | "send_failed" | "rate_limited";

/**
 * One instance per kitten player (named by the kitten's player id): the
 * consent record (consent design §3), its alarm for the second text and the
 * texted expiry, the texts themselves, and the side effects of revocation:
 * the phone and tokens go from the index, our texts from Twilio's logs, and
 * every push token from the kitten's devices.
 *
 * Every change runs one at a time (`serial`): a change awaits outside calls
 * (Twilio, the index, the kitten's devices), during which a Durable Object
 * takes other requests, so a revoke arriving while text 2 is out would
 * otherwise be overwritten by the older record (review I1).
 */
export class Consents extends DurableObject<Env> {
  private queue: Promise<unknown> = Promise.resolve();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => this.schema());
  }

  private schema(): void {
    this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT)");
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

  private list(k: string): string[] {
    const v = this.getMeta(k);
    return v === null ? [] : (JSON.parse(v) as string[]);
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
   * Text 1 (decision 5): the confirm link to `phone`. Without all of
   * Twilio's secrets nothing is sent and nothing changes. At most 3 a day for
   * a kitten, and 5 a day from a parent (review I2).
   */
  startText(parent: string, phone: string, origin: string, now: number): Promise<{ ok: ConsentRecord } | { error: TextError }> {
    return this.serial(async () => {
      const r = this.record();
      if (!r) return { error: "not_parent" as const };
      const next = text(r, parent, phone, now);
      if ("error" in next) return next;
      const cfg = twilioConfig(this.env);
      if (!cfg) return { error: "not_configured" as const };
      const times = this.list("text_times").map(Number).filter((t) => t > now - TEXT_WINDOW_MS);
      if (!textAllowed(times, now, TEXTS_PER_KITTEN) || !(await index(this.env).noteText(parent, now))) {
        return { error: "rate_limited" as const };
      }
      this.setMeta("text_times", JSON.stringify([...times, now].map(String)));
      // The token exists before the text can be opened (review M13).
      const ix = index(this.env);
      const token = newToken();
      await ix.dropTokens(r.kitten, "confirm");
      await ix.putToken(token, { kitten: r.kitten, kind: "confirm" }, now + TEXTED_MS);
      const sent = await sendText(cfg, phone, firstText(`${origin}/consent/${token}`), fetch);
      if (!sent.ok) {
        await ix.dropTokens(r.kitten, "confirm");
        return { error: "send_failed" as const };
      }
      this.noteSid(sent.sid);
      await ix.setPhone(r.kitten, await phoneHash(this.env, phone));
      this.setMeta("origin", origin);
      await this.save(next.ok);
      return next;
    });
  }

  private noteSid(sid: string | null): void {
    if (sid) this.setMeta("sids", JSON.stringify([...this.list("sids"), sid]));
  }

  /** The confirm link's button (decision 6). The zone is the texting parent's, for text 2's hour. */
  confirm(zone: string | null, now: number): Promise<boolean> {
    return this.serial(async () => {
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
    });
  }

  /** Back to pending (decision 9): phone, tokens and the kitten's push tokens go. True if consent (or a text) was live. */
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

  /** The number goes everywhere it was: our index, the link tokens, Twilio's logs; and the kitten's push tokens. */
  private async forgetContact(kitten: string): Promise<void> {
    this.setMeta("revoke_token", null);
    this.setMeta("retry_at", null);
    const ix = index(this.env);
    await ix.setPhone(kitten, null);
    await ix.dropTokens(kitten);
    await this.deleteTexts();
    await dropKittenTokens(this.env, kitten);
  }

  /** Our texts leave Twilio's logs (review I5). A SID Twilio can't delete yet stays for the next try. */
  private async deleteTexts(): Promise<void> {
    const cfg = twilioConfig(this.env);
    const sids = this.list("sids");
    if (!cfg || sids.length === 0) return;
    const kept: string[] = [];
    for (const sid of sids) if (!(await deleteText(cfg, sid, fetch))) kept.push(sid);
    this.setMeta("sids", kept.length === 0 ? null : JSON.stringify(kept));
  }

  /** The record ends (decision 10): deleted, expired, or turned 13. */
  end(): Promise<void> {
    return this.serial(() => this.endNow());
  }

  private async endNow(): Promise<void> {
    const r = this.record();
    if (r) {
      await this.deleteTexts();
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

  /** Text 2 and the texted expiry (decisions 7, 8). The alarm runs it; so does a test hook with a chosen time. */
  tick(now: number): Promise<void> {
    return this.serial(() => this.tickNow(now));
  }

  private async tickNow(now: number): Promise<void> {
    const r = this.record();
    if (!r) return;
    if (r.state === "texted") {
      const next = expireText(r, now);
      await this.save(next);
      if (next !== r) await this.forgetContact(r.kitten);
      return;
    }
    if (r.state !== "consented" || r.secondSent || (r.secondAt as number) > now) return this.save(r);
    const cfg = twilioConfig(this.env);
    const token = this.getMeta("revoke_token");
    const origin = this.getMeta("origin") ?? DEFAULT_ORIGIN;
    const sent = cfg && token && r.phone ? await sendText(cfg, r.phone, secondText(`${origin}/consent/${token}`), fetch) : null;
    if (sent?.ok) {
      this.noteSid(sent.sid);
      this.setMeta("retry_at", null);
      await this.save(secondSent(r));
      return;
    }
    // A number that replied STOP, or a day without delivering the "plus": consent ends (review I4).
    const optedOut = sent !== null && !sent.ok && sent.code === OPTED_OUT;
    if (optedOut || now >= (r.secondAt as number) + SECOND_GIVE_UP_MS) {
      await this.revokeNow(optedOut ? "opted_out" : "no_plus");
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
