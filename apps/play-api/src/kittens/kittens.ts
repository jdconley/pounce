import { readNotification } from "../consent/appstore";
import { approvedSet, KID, LINK_CODE, normalizePhone, parentState, textable, VERIFY_CODE, type ConsentRecord, type ParentState } from "../consent/rules";
import { player, type Result } from "../players/accounts";
import { PAIR_ID } from "../players/ids";
import { consentOn } from "../streaks/profile";

import { KITTENS_NAME } from "./kitten-index";

import type { CheckError, CodeError } from "./consents";
import type { Env } from "../env";

/** The route flows of parent consent (consent design §3; plan decisions 1–23). */

const MAX_PAIRS = 64;
const TX_ID = /^[A-Za-z0-9._-]{1,64}$/;

const fail = (status: number, error: string): Result<never> => ({ status, error });
const index = (env: Env) => env.KITTENS.get(env.KITTENS.idFromName(KITTENS_NAME));
export const consents = (env: Env, kitten: string) => env.CONSENTS.get(env.CONSENTS.idFromName(kitten));
const device = (env: Env, id: string) => env.DEVICES.get(env.DEVICES.idFromName(id));

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => typeof v === "object" && v !== null && !Array.isArray(v);
const onlyKeys = (o: Obj, keys: string[]) => Object.keys(o).every((k) => keys.includes(k));

/** The kitten's view of itself (`GET /v1/kittens/me`). */
export type KittenView = { state: "none" | "pending" | "code" | "consented"; linked: boolean; approved: string[] };

/**
 * One kitten on a parent's Kittens panel. People are the kitten's pairs;
 * linked parents are always on. `confirmed`: the confirmation push (the plus,
 * D6) reached the consenting parent.
 */
export type ParentKitten = {
  id: string;
  name: string;
  cat: number;
  state: ParentState;
  confirmed: boolean;
  mode: "parent" | "apple";
  people: { pair: string; name: string; cat: number; approved: boolean; parent: boolean }[];
};

/** The bindings exist (they always do in production; some Miniflare suites leave them out). */
export const kittensBound = (env: Env): boolean => env.CONSENTS !== undefined && env.KITTENS !== undefined;

/** The kitten's pairs: pair id → partner player id. */
async function pairsOf(env: Env, kitten: string): Promise<{ pairId: string; partnerId: string }[]> {
  return (await player(env, kitten).pairList()).map((r) => ({ pairId: r.pairId, partnerId: r.partnerId }));
}

/** Pair ids from the wire → partner player ids, dropping any that aren't the kitten's. */
function partnersFor(pairs: { pairId: string; partnerId: string }[], wire: string[]): string[] {
  const byPair = new Map(pairs.map((p) => [p.pairId, p.partnerId]));
  return wire.flatMap((id) => byPair.get(id) ?? []);
}

function pairList(v: unknown): string[] | null {
  if (!Array.isArray(v) || v.length > MAX_PAIRS || !v.every((p) => typeof p === "string" && PAIR_ID.test(p))) return null;
  return v as string[];
}

/** The request's player is a kitten on a kitten's own device. */
async function isKitten(env: Env, deviceId: string, me: string): Promise<boolean> {
  const [meta, band] = await Promise.all([player(env, me).meta(), device(env, deviceId).ageBand()]);
  return meta?.ageBand === "kitten" && band === "kitten";
}

/** A parent is a signed-in adult, on a device that isn't a kitten's or a teen's (decision 4). */
async function isParent(env: Env, deviceId: string, me: string): Promise<boolean> {
  const [meta, band] = await Promise.all([player(env, me).meta(), device(env, deviceId).ageBand()]);
  return meta !== null && meta.signedIn && meta.ageBand === "adult" && band !== "kitten" && band !== "teen";
}

export async function kittenView(env: Env, kitten: string): Promise<KittenView> {
  const r = await consents(env, kitten).record();
  if (!r) return { state: "none", linked: false, approved: [] };
  const ok = approvedSet(r);
  const pairs = await pairsOf(env, kitten);
  return { state: r.state, linked: true, approved: pairs.filter((p) => ok.has(p.partnerId)).map((p) => p.pairId) };
}

async function parentView(env: Env, r: ConsentRecord): Promise<ParentKitten | null> {
  const meta = await player(env, r.kitten).meta();
  if (!meta) return null;
  const ok = approvedSet(r);
  const people = await Promise.all(
    (await pairsOf(env, r.kitten)).map(async (p) => {
      const m = await player(env, p.partnerId).meta();
      return m ? { pair: p.pairId, name: m.name, cat: m.cat, approved: ok.has(p.partnerId), parent: r.parents.includes(p.partnerId) } : null;
    }),
  );
  return {
    id: r.kid,
    name: meta.name,
    cat: meta.cat,
    state: parentState(r),
    confirmed: r.state === "consented" && r.plusSent,
    mode: r.apple === null ? "parent" : "apple",
    people: people.filter((p) => p !== null),
  };
}

// ---- The kitten's device ----

/** `POST /v1/kittens/me/link-code` (§2 layer 1): six digits for 10 minutes, with the app transaction id if StoreKit has one. */
export async function linkCode(env: Env, deviceId: string, me: string, body: unknown, now: number): Promise<Result<{ code: string; expiresAt: number }>> {
  const b = body ?? {};
  if (!isObj(b) || !onlyKeys(b, ["appTransactionId"])) return fail(400, "bad_request");
  if ("appTransactionId" in b && (typeof b.appTransactionId !== "string" || !TX_ID.test(b.appTransactionId))) return fail(400, "bad_request");
  if (!(await isKitten(env, deviceId, me))) return fail(403, "not_allowed");
  return { ok: await index(env).putCode(me, (b.appTransactionId as string | undefined) ?? null, now) };
}

export async function kittenMe(env: Env, deviceId: string, me: string): Promise<Result<KittenView>> {
  if (!(await isKitten(env, deviceId, me))) return fail(403, "not_allowed");
  return { ok: await kittenView(env, me) };
}

/** `PUT /v1/kittens/me/approved`: Apple's answers mirrored from the kitten's device (decisions 21–23). */
export async function mirrorApple(env: Env, deviceId: string, me: string, body: unknown): Promise<Result<null>> {
  if (!isObj(body) || !onlyKeys(body, ["apple"]) || !("apple" in body)) return fail(400, "bad_request");
  const list = body.apple === null ? null : pairList(body.apple);
  if (body.apple !== null && list === null) return fail(400, "bad_request");
  if (!(await isKitten(env, deviceId, me))) return fail(403, "not_allowed");
  const pairs = await pairsOf(env, me);
  const ok = await consents(env, me).setAppleApprovals(list === null ? null : partnersFor(pairs, list), pairs.map((p) => p.partnerId));
  return ok ? { ok: null } : fail(404, "not_linked");
}

// ---- The parent's device ----

/** `POST /v1/kittens/link` (§2 layer 1). */
export async function linkKitten(env: Env, deviceId: string, parent: string, body: unknown, now: number): Promise<Result<{ kitten: ParentKitten }>> {
  if (!isObj(body) || !onlyKeys(body, ["code"]) || typeof body.code !== "string" || !LINK_CODE.test(body.code)) return fail(400, "bad_request");
  if (!(await isParent(env, deviceId, parent))) return fail(403, "not_allowed");
  const taken = await index(env).takeCode(parent, body.code, now);
  if ("limited" in taken) return fail(429, "rate_limited");
  if ("bad" in taken) return fail(404, "not_found");
  const meta = await player(env, taken.kitten).meta();
  if (!meta || meta.ageBand !== "kitten" || taken.kitten === parent) return fail(404, "not_found");
  const kid = await index(env).kidFor(taken.kitten);
  await index(env).addParent(parent, taken.kitten);
  const r = await consents(env, taken.kitten).link(kid, taken.kitten, parent, taken.tx);
  const view = await parentView(env, r);
  return view ? { ok: { kitten: view } } : fail(404, "not_found");
}

export async function listKittens(env: Env, deviceId: string, parent: string): Promise<Result<{ kittens: ParentKitten[] }>> {
  if (!(await isParent(env, deviceId, parent))) return fail(403, "not_allowed");
  const records = (await Promise.all((await index(env).kittensOf(parent)).map((k) => consents(env, k).record()))) as (ConsentRecord | null)[];
  const views = await Promise.all(records.filter((r) => r !== null && r.parents.includes(parent)).map((r) => parentView(env, r as ConsentRecord)));
  return { ok: { kittens: views.filter((v) => v !== null) } };
}

/** The kitten behind a public id, when this parent is linked to it. */
async function mine(env: Env, deviceId: string, parent: string, kid: string): Promise<ConsentRecord | null> {
  if (!KID.test(kid) || !(await isParent(env, deviceId, parent))) return null;
  const kitten = await index(env).kittenOf(kid);
  const r = kitten ? await consents(env, kitten).record() : null;
  return r && r.parents.includes(parent) ? r : null;
}

/** `PUT /v1/kittens/{k}/approved`: the parent's own toggles (D3). */
export async function setApproved(env: Env, deviceId: string, parent: string, kid: string, body: unknown): Promise<Result<null>> {
  if (!isObj(body) || !onlyKeys(body, ["approved"])) return fail(400, "bad_request");
  const list = pairList(body.approved);
  if (!list) return fail(400, "bad_request");
  const r = await mine(env, deviceId, parent, kid);
  if (!r) return fail(404, "not_found");
  const pairs = await pairsOf(env, r.kitten);
  const out = await consents(env, r.kitten).setParentApprovals(parent, partnersFor(pairs, list), pairs.map((p) => p.partnerId));
  if (out === "apple_managed") return fail(409, "apple_managed");
  return out === "ok" ? { ok: null } : fail(404, "not_found");
}

const CODE_STATUS: Record<CodeError, number> = {
  not_parent: 404,
  consented: 409,
  not_waiting: 409,
  not_configured: 503,
  send_failed: 502,
  rate_limited: 429,
  bad_number: 400,
};

/** `POST /v1/kittens/{k}/consent` (D1, D6): Twilio Verify texts the parent's mobile a code. */
export async function startConsent(env: Env, deviceId: string, parent: string, kid: string, body: unknown, now: number): Promise<Result<{ state: "code" }>> {
  if (!isObj(body) || !onlyKeys(body, ["phone"])) return fail(400, "bad_request");
  const phone = normalizePhone(body.phone);
  if (!phone || !textable(phone)) return fail(400, "bad_request");
  const r = await mine(env, deviceId, parent, kid);
  if (!r) return fail(404, "not_found");
  const out = await consents(env, r.kitten).startCode(parent, phone, now);
  return "ok" in out ? { ok: { state: "code" } } : fail(CODE_STATUS[out.error], out.error);
}

/** `POST /v1/kittens/{k}/consent/resend`: the same number again, 30 s apart at least, within the day's limits. */
export async function resendConsent(env: Env, deviceId: string, parent: string, kid: string, now: number): Promise<Result<{ state: "code" }>> {
  const r = await mine(env, deviceId, parent, kid);
  if (!r) return fail(404, "not_found");
  const out = await consents(env, r.kitten).resendCode(parent, now);
  return "ok" in out ? { ok: { state: "code" } } : fail(CODE_STATUS[out.error], out.error);
}

const CHECK_STATUS: Record<CheckError, number> = {
  not_parent: 404,
  not_waiting: 409,
  not_configured: 503,
  wrong_code: 422,
  expired: 410,
  rate_limited: 429,
  check_failed: 502,
};

/** `POST /v1/kittens/{k}/consent/check`: the six digits from the text. Right is consent (D6). */
export async function checkConsent(env: Env, deviceId: string, parent: string, kid: string, body: unknown, now: number): Promise<Result<{ state: "on" }>> {
  if (!isObj(body) || !onlyKeys(body, ["code"]) || typeof body.code !== "string" || !VERIFY_CODE.test(body.code)) return fail(400, "bad_request");
  const r = await mine(env, deviceId, parent, kid);
  if (!r) return fail(404, "not_found");
  const out = await consents(env, r.kitten).checkCode(parent, body.code, now);
  return "ok" in out ? { ok: { state: "on" } } : fail(CHECK_STATUS[out.error], out.error);
}

export async function revokeConsent(env: Env, deviceId: string, parent: string, kid: string): Promise<Result<null>> {
  const r = await mine(env, deviceId, parent, kid);
  if (!r) return fail(404, "not_found");
  await consents(env, r.kitten).revoke("parent");
  return { ok: null };
}

export async function unlinkKitten(env: Env, deviceId: string, parent: string, kid: string): Promise<Result<null>> {
  const r = await mine(env, deviceId, parent, kid);
  if (!r) return fail(404, "not_found");
  await consents(env, r.kitten).unlinkParent(parent);
  return { ok: null };
}

// ---- Public: the App Store ----

/** `POST /v1/appstore/notifications` (D5): a verified `RESCIND_CONSENT` revokes that app transaction's kitten. */
export async function appStoreNotification(env: Env, body: unknown, roots: readonly string[], now: number): Promise<Response> {
  const read = await readNotification(body, env.SIWA_CLIENT_ID, roots, now);
  if (!read) return new Response(null, { status: 400 });
  if ("rescind" in read) {
    const kitten = await index(env).kittenByTransaction(read.rescind);
    if (kitten) await consents(env, kitten).revoke("rescind");
  }
  return new Response(null, { status: 200 });
}

// ---- Elsewhere ----

// These throw on failure (review I6): the caller's own retry (an account deletion asked again, a
// player's alarm, a sign-in retried) runs them again, so no consent or number is left behind.

/** A kitten's player is deleted, expired or turned 13 (decisions 10, 12): its record goes. */
export async function endKitten(env: Env, kitten: string): Promise<void> {
  if (!kittensBound(env)) return;
  await consents(env, kitten).end();
}

/** A parent's account is deleted (decision 11): unlinked from each kitten. */
export async function parentGone(env: Env, parent: string): Promise<void> {
  if (!kittensBound(env)) return;
  const kittens = await index(env).kittensOf(parent);
  await Promise.all(kittens.map((k) => consents(env, k).unlinkParent(parent)));
}

/**
 * A merge: parent `from` is now `to`, and a kitten that approved `from`
 * (one of `from`'s pair partners) now approves `to` (review M9).
 */
export async function parentMerged(env: Env, from: string, to: string, partners: string[]): Promise<void> {
  if (!kittensBound(env)) return;
  const kittens = await index(env).repointParent(from, to);
  await Promise.all(kittens.map((k) => consents(env, k).repointParent(from, to)));
  await Promise.all(partners.map((k) => consents(env, k).repointPartner(from, to)));
}

/** Any of these players has consent (decision 19). */
export async function anyConsented(env: Env, players: string[]): Promise<boolean> {
  const records = await Promise.all(players.map((p) => consents(env, p).record()));
  return records.some((r) => r?.state === "consented");
}

/** A linked kitten may pounce only approved people (decision 20); an unlinked one as before. */
export async function kittenMayPounce(env: Env, kitten: string, partner: string): Promise<boolean> {
  if (!consentOn(env)) return true;
  const r = await consents(env, kitten).record();
  return r === null || approvedSet(r).has(partner);
}
