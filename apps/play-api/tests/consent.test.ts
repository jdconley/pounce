import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { rescindBody, TEST_ROOTS } from "./appstore-fixtures";
import {
  appleProof,
  BASE,
  bundle,
  call,
  eventually,
  FakeVerify,
  LA,
  mint,
  newPerson,
  profile,
  settle,
  table,
  takeTurn,
  tokenOf,
  TWILIO,
  worker,
  type Client,
  type Device,
  type Person,
  type Sent,
  PLAYER_ID_JSON,
} from "./play-helpers";

import type { ConsentRecord } from "../src/consent/rules";
import type { KittenView, ParentKitten } from "../src/kittens/kittens";
import type { ServerMessage } from "../src/protocol";
import type { Miniflare } from "miniflare";

const KID_TOKEN = tokenOf(7);
const MIA_TOKEN = tokenOf(2);
const MOM_TOKEN = tokenOf(3);
const DAD_TOKEN = tokenOf(4);
const PHONE = "+14155550123";
const H = 3_600_000;

let script = "";
let sent: Sent[] = [];
const verify = new FakeVerify();
const apnsDown = new Set<string>();
const open: Miniflare[] = [];

beforeAll(async () => {
  script = await bundle("./consent-entry.ts");
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
  sent = [];
  verify.reset();
  apnsDown.clear();
});

async function start(options: { twilio?: boolean; consentFlag?: boolean; nudge?: boolean } = {}): Promise<Miniflare> {
  // With nudges, at the dev server's top speed: a nudge's 2-minute wait is 1.2 s, its 10-minute cooldown 6 s.
  const fast = options.nudge ? { devSpeed: 100 } : {};
  const mf = await worker(script, { links: true, sent, consent: true, verify, apnsDown, ...fast, ...options });
  open.push(mf);
  return mf;
}

const alertsTo = (token: string, kind?: string) =>
  sent.filter((s) => s.token === token && s.headers["apns-push-type"] === "alert" && (kind === undefined || s.body.kind === kind));
const json = async <T>(res: Response | Promise<Response>): Promise<T> => (await (await res).json()) as T;
const hook = (mf: Miniflare, path: string, init?: RequestInit) => mf.dispatchFetch(`${BASE}${path}`, init as never) as unknown as Promise<Response>;
const record = (mf: Miniflare, kitten: string) => json<ConsentRecord | null>(hook(mf, `/__test/consent?player=${kitten}`));
const tokens = (mf: Miniflare, d: Device) => json<{ apns: boolean; widget: boolean; live: boolean }>(hook(mf, `/__test/tokens?device=${d.deviceId}`));
const tick = (mf: Miniflare, kitten: string, now: number) => hook(mf, `/__test/consent-tick?player=${kitten}&now=${now}`);
const alarm = (mf: Miniflare, kitten: string) => json<number | null>(hook(mf, `/__test/consent-alarm?player=${kitten}`));
const localTime = (t: number, zone: string) =>
  new Intl.DateTimeFormat("en-US", { timeZone: zone, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(t));
const hourIn = (t: number, zone: string) =>
  Number(new Intl.DateTimeFormat("en-US", { timeZone: zone, hour: "numeric", hourCycle: "h23" }).format(new Date(t)));

type Family = {
  momPhone: Device;
  kidPad: Device;
  miaPhone: Device;
  mom: Person;
  kid: Person;
  mia: Person;
  ids: Record<string, string>;
};

/** Mom (a signed-in adult), her kitten on its own iPad, and Mia (an adult the kitten plays with). */
async function family(mf: Miniflare): Promise<Family> {
  const momPhone = await mint(mf);
  const kidPad = await mint(mf);
  const miaPhone = await mint(mf);
  const mom = newPerson("Mom", 3);
  const kid = newPerson("Mochi", 4);
  const mia = newPerson("Mia", 2);
  const ids = {
    ...(await profile(mf, momPhone, [mom], { apns: MOM_TOKEN })),
    ...(await profile(mf, kidPad, [kid], { band: "kitten" })),
    ...(await profile(mf, miaPhone, [mia], { apns: MIA_TOKEN })),
  };
  const signed = await call(mf, momPhone, "POST", "/v1/identities/apple", {
    proof: await appleProof(`apple-mom-${crypto.randomUUID()}`),
    person: { id: mom.id, key: mom.key },
  });
  expect(signed.status).toBe(200);
  return { momPhone, kidPad, miaPhone, mom, kid, mia, ids };
}

const kidCall = (mf: Miniflare, f: Family, method: string, path: string, body?: unknown) =>
  call(mf, f.kidPad, method, `${path}?person=${f.kid.id}`, body);

async function linked(mf: Miniflare, f: Family, body: unknown = {}): Promise<ParentKitten> {
  const res = await kidCall(mf, f, "POST", "/v1/kittens/me/link-code", body);
  expect(res.status).toBe(201);
  const { code } = (await res.json()) as { code: string };
  const link = await call(mf, f.momPhone, "POST", "/v1/kittens/link", { code });
  expect(link.status).toBe(201);
  return ((await link.json()) as { kitten: ParentKitten }).kitten;
}

const check = (mf: Miniflare, f: Family, k: ParentKitten, code: string) => call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent/check`, { code });
const wrongCode = (right: string) => (right === "000000" ? "000001" : "000000");

/** Linked, the code sent and entered, and the kitten's token uploaded. */
async function consented(mf: Miniflare, f: Family, body: unknown = {}): Promise<ParentKitten> {
  const k = await linked(mf, f, body);
  expect((await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: "(415) 555-0123" })).status).toBe(202);
  expect((await check(mf, f, k, verify.code(PHONE))).status).toBe(200);
  expect((await call(mf, f.kidPad, "PUT", "/v1/devices/me/push", { apnsToken: KID_TOKEN })).status).toBe(204);
  return k;
}

/** The kitten and Mia at one table, both having taken a turn: a pair. The kitten's pair id. */
async function sharedTable(mf: Miniflare, f: Family): Promise<{ clients: Client[]; pair: string }> {
  const t = await table(mf, [
    [f.miaPhone, f.mia],
    [f.kidPad, f.kid],
  ]);
  await takeTurn(t.clients);
  await takeTurn(t.clients);
  const streak = await (t.clients[1] as Client).find<Extract<ServerMessage, { t: "streak" }>>((m) => m.t === "streak");
  return { clients: t.clients, pair: streak.pair };
}

/** Mia moves while the kitten is away, so the move reaches the kitten as a push. */
async function miaMovesToKid(clients: Client[]): Promise<void> {
  const [miaC, kidC] = clients as [Client, Client];
  if (miaC.game().turn === 1) {
    kidC.send({ t: "presence", state: "active" });
    await takeTurn(clients);
  }
  kidC.away();
  await settle(100);
  await takeTurn(clients);
}

describe("link (consent design §2 layer 1)", { timeout: 30_000 }, () => {
  test("the kitten's code links a signed-in adult, once; the kitten sees pending", async () => {
    const mf = await start();
    const f = await family(mf);
    expect(await json(kidCall(mf, f, "GET", "/v1/kittens/me"))).toEqual({ state: "none", linked: false, approved: [] });
    const res = await kidCall(mf, f, "POST", "/v1/kittens/me/link-code", {});
    const { code, expiresAt } = (await res.json()) as { code: string; expiresAt: number };
    expect(code).toMatch(/^[0-9]{6}$/);
    expect(expiresAt).toBeGreaterThan(Date.now() + 9 * 60_000);
    // A new code replaces the old one.
    const second = (await json<{ code: string }>(kidCall(mf, f, "POST", "/v1/kittens/me/link-code"))).code;
    if (second !== code) expect((await call(mf, f.momPhone, "POST", "/v1/kittens/link", { code })).status).toBe(404);
    const link = await call(mf, f.momPhone, "POST", "/v1/kittens/link", { code: second });
    expect(link.status).toBe(201);
    const { kitten } = (await link.json()) as { kitten: ParentKitten };
    expect(kitten).toMatchObject({ name: "Mochi", cat: 4, state: "pending", mode: "parent", people: [] });
    expect(kitten.id).toMatch(/^k_[A-Za-z0-9_-]{22}$/);
    expect(JSON.stringify(kitten)).not.toMatch(PLAYER_ID_JSON);
    // Used once.
    expect((await call(mf, f.momPhone, "POST", "/v1/kittens/link", { code: second })).status).toBe(404);
    expect(await json(kidCall(mf, f, "GET", "/v1/kittens/me"))).toEqual({ state: "pending", linked: true, approved: [] });
    expect(await json(call(mf, f.momPhone, "GET", "/v1/kittens"))).toEqual({ kittens: [kitten] });
  });

  test("only a kitten on its own device gets a code; only a signed-in adult links", async () => {
    const mf = await start();
    const f = await family(mf);
    expect((await call(mf, f.miaPhone, "POST", `/v1/kittens/me/link-code?person=${f.mia.id}`, {})).status).toBe(403);
    expect((await kidCall(mf, f, "POST", "/v1/kittens/me/link-code", { appTransactionId: "no spaces" })).status).toBe(400);
    expect((await kidCall(mf, f, "POST", "/v1/kittens/me/link-code", { other: 1 })).status).toBe(400);
    const { code } = await json<{ code: string }>(kidCall(mf, f, "POST", "/v1/kittens/me/link-code", {}));
    // Mia is an adult but not signed in.
    expect((await call(mf, f.miaPhone, "POST", `/v1/kittens/link?person=${f.mia.id}`, { code })).status).toBe(403);
    expect((await call(mf, f.miaPhone, "GET", `/v1/kittens?person=${f.mia.id}`)).status).toBe(403);
    expect((await call(mf, f.momPhone, "POST", "/v1/kittens/link", { code: "12345" })).status).toBe(400);
  });

  test("five wrong codes in 10 minutes and even the right one is refused", async () => {
    const mf = await start();
    const f = await family(mf);
    const { code } = await json<{ code: string }>(kidCall(mf, f, "POST", "/v1/kittens/me/link-code", {}));
    const wrong = code === "000000" ? "000001" : "000000";
    for (let i = 0; i < 5; i++) expect((await call(mf, f.momPhone, "POST", "/v1/kittens/link", { code: wrong })).status).toBe(404);
    expect((await call(mf, f.momPhone, "POST", "/v1/kittens/link", { code })).status).toBe(429);
  });

  test("a second parent links too; unlinking the last one ends the record", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await linked(mf, f);
    const dadPhone = await mint(mf);
    const dad = newPerson("Dad", 5);
    await profile(mf, dadPhone, [dad]);
    await call(mf, dadPhone, "POST", "/v1/identities/apple", { proof: await appleProof(`apple-dad-${crypto.randomUUID()}`), person: { id: dad.id, key: dad.key } });
    const { code } = await json<{ code: string }>(kidCall(mf, f, "POST", "/v1/kittens/me/link-code", {}));
    const dadView = await json<{ kitten: ParentKitten }>(call(mf, dadPhone, "POST", "/v1/kittens/link", { code }));
    expect(dadView.kitten.id).toBe(k.id);
    expect((await record(mf, f.ids[f.kid.id] as string))?.parents).toHaveLength(2);
    expect((await call(mf, f.momPhone, "DELETE", `/v1/kittens/${k.id}`)).status).toBe(204);
    expect(await json(call(mf, f.momPhone, "GET", "/v1/kittens"))).toEqual({ kittens: [] });
    expect((await call(mf, f.momPhone, "DELETE", `/v1/kittens/${k.id}`)).status).toBe(404);
    expect((await call(mf, dadPhone, "DELETE", `/v1/kittens/${k.id}`)).status).toBe(204);
    expect(await record(mf, f.ids[f.kid.id] as string)).toBeNull();
  });
});

describe("consent by Twilio Verify (D1, D6)", { timeout: 30_000 }, () => {
  test("a code to the parent's number; a wrong code changes nothing; the right one consents", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await linked(mf, f);
    const kitten = f.ids[f.kid.id] as string;
    expect((await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: "nope" })).status).toBe(400);
    const res = await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: "(415) 555-0123" });
    expect(res.status).toBe(202);
    expect(await res.json()).toEqual({ state: "code" });
    expect(verify.sends).toEqual([
      { to: PHONE, channel: "sms", auth: `Basic ${btoa(`${TWILIO.TWILIO_API_KEY_SID}:${TWILIO.TWILIO_API_KEY_SECRET}`)}`, service: TWILIO.TWILIO_VERIFY_SERVICE_SID },
    ]);
    expect(await json<{ kittens: ParentKitten[] }>(call(mf, f.momPhone, "GET", "/v1/kittens"))).toMatchObject({ kittens: [{ state: "code", confirmed: false }] });
    expect(await json(kidCall(mf, f, "GET", "/v1/kittens/me"))).toMatchObject({ state: "code" });
    // Before consent the kitten's device can't hold a token.
    expect((await call(mf, f.kidPad, "PUT", "/v1/devices/me/push", { apnsToken: KID_TOKEN })).status).toBe(403);

    for (const bad of [{ code: "12" }, { code: "abcdef" }, {}, { code: "123456", x: 1 }]) {
      expect((await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent/check`, bad)).status).toBe(400);
    }
    const wrong = await check(mf, f, k, wrongCode(verify.code(PHONE)));
    expect(wrong.status).toBe(422);
    expect(await wrong.json()).toEqual({ error: "wrong_code" });
    expect((await record(mf, kitten))?.state).toBe("code");

    const right = await check(mf, f, k, verify.code(PHONE));
    expect(right.status).toBe(200);
    expect(await right.json()).toEqual({ state: "on" });
    expect(verify.checks.at(-1)?.to).toBe(PHONE);
    expect(await record(mf, kitten)).toMatchObject({ state: "consented", phone: PHONE, plusSent: false });
    expect(await json<{ kittens: ParentKitten[] }>(call(mf, f.momPhone, "GET", "/v1/kittens"))).toMatchObject({ kittens: [{ state: "on", confirmed: false }] });
    expect(await json(kidCall(mf, f, "GET", "/v1/kittens/me"))).toMatchObject({ state: "consented" });
    expect((await call(mf, f.kidPad, "PUT", "/v1/devices/me/push", { apnsToken: KID_TOKEN })).status).toBe(204);
    // While consented, no new code, and nothing left to check.
    expect((await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: PHONE })).status).toBe(409);
    expect((await check(mf, f, k, "123456")).status).toBe(409);
    // Only Verify's own code message was ever texted.
    expect(verify.sends).toHaveLength(1);
  });

  test("without Twilio's secrets nothing is sent and the kitten stays pending", async () => {
    const mf = await start({ twilio: false });
    const f = await family(mf);
    const k = await linked(mf, f);
    const res = await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: PHONE });
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: "not_configured" });
    expect(verify.sends).toHaveLength(0);
    expect((await record(mf, f.ids[f.kid.id] as string))?.state).toBe("pending");
    const checked = await check(mf, f, k, "123456");
    expect(checked.status).toBe(409);
    expect(await checked.json()).toEqual({ error: "not_waiting" });
  });

  test("five wrong codes in 10 minutes, and even the right one is refused", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await linked(mf, f);
    await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: PHONE });
    const code = verify.code(PHONE);
    for (let i = 0; i < 5; i++) expect((await check(mf, f, k, wrongCode(code))).status).toBe(422);
    const limited = await check(mf, f, k, code);
    expect(limited.status).toBe(429);
    expect(verify.checks).toHaveLength(5);
    expect((await record(mf, f.ids[f.kid.id] as string))?.state).toBe("code");
  });

  test("an expired code needs a fresh one; a resend within its life repeats it, and waits 30 s", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await linked(mf, f);
    const kitten = f.ids[f.kid.id] as string;
    const mom = f.ids[f.mom.id] as string;
    await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: PHONE });
    const first = verify.code(PHONE);
    // At once: too soon.
    const soon = await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent/resend`);
    expect(soon.status).toBe(429);
    expect(verify.sends).toHaveLength(1);
    const codeAt = ((await record(mf, kitten)) as ConsentRecord).codeAt as number;
    const resend = (now: number) => json<unknown>(hook(mf, `/__test/consent-resend?player=${kitten}&parent=${mom}&now=${now}`));
    expect(await resend(codeAt + 30_000)).toEqual({ state: "code" });
    expect(verify.sends).toHaveLength(2);
    expect(verify.code(PHONE)).toBe(first);
    // Verify's 10 minutes pass: the old code is expired, and the kitten still waits for one.
    verify.expire(PHONE);
    const expired = await check(mf, f, k, first);
    expect(expired.status).toBe(410);
    expect(await expired.json()).toEqual({ error: "expired" });
    expect((await record(mf, kitten))?.state).toBe("code");
    expect(await resend(codeAt + 11 * 60_000)).toEqual({ state: "code" });
    expect(verify.sends).toHaveLength(3);
    expect((await check(mf, f, k, verify.code(PHONE))).status).toBe(200);
    // Nothing to resend once consented.
    expect((await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent/resend`)).status).toBe(409);
  });

  test("a number whose code nobody enters is deleted after 30 minutes", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await linked(mf, f);
    const kitten = f.ids[f.kid.id] as string;
    await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: PHONE });
    const r = (await record(mf, kitten)) as ConsentRecord;
    expect(await alarm(mf, kitten)).toBe((r.codeAt as number) + 30 * 60_000);
    await tick(mf, kitten, (r.codeAt as number) + 30 * 60_000);
    expect(await record(mf, kitten)).toMatchObject({ state: "pending", phone: null });
    expect((await check(mf, f, k, verify.code(PHONE))).status).toBe(409);
  });
});

describe("the plus: a push to the parent's own devices (D6)", { timeout: 30_000 }, () => {
  test("24–48 h later, inside 10:00–20:00, an alert with the Revoke category; the panel shows it confirmed", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await consented(mf, f);
    const kitten = f.ids[f.kid.id] as string;
    const r = (await record(mf, kitten)) as ConsentRecord;
    const due = r.plusAt as number;
    expect(due - (r.consentedAt as number)).toBeGreaterThanOrEqual(24 * H);
    expect(due - (r.consentedAt as number)).toBeLessThanOrEqual(48 * H);
    expect(hourIn(due, LA)).toBeGreaterThanOrEqual(10);
    expect(hourIn(due, LA)).toBeLessThan(20);
    expect(await alarm(mf, kitten)).toBe(due);
    await tick(mf, kitten, due - 1);
    expect(alertsTo(MOM_TOKEN, "consent")).toEqual([]);
    await tick(mf, kitten, due);
    const [push, ...more] = alertsTo(MOM_TOKEN, "consent");
    expect(more).toEqual([]);
    expect(push?.body).toMatchObject({ kind: "consent", kitten: k.id, aps: { category: "CONSENT", alert: { title: "Mochi" } } });
    expect(JSON.stringify(push?.body)).not.toMatch(PLAYER_ID_JSON);
    // Never to the kitten or anyone else.
    expect(sent.filter((s) => s.body.kind === "consent" && s.token !== MOM_TOKEN)).toEqual([]);
    expect((await record(mf, kitten))?.plusSent).toBe(true);
    expect(await json<{ kittens: ParentKitten[] }>(call(mf, f.momPhone, "GET", "/v1/kittens"))).toMatchObject({ kittens: [{ state: "on", confirmed: true }] });
    expect(await alarm(mf, kitten)).toBeNull();
    await tick(mf, kitten, due + H);
    expect(alertsTo(MOM_TOKEN, "consent")).toHaveLength(1);
  });

  test("the push's Revoke action (the parent's own revoke) ends consent at once", async () => {
    const mf = await start();
    const f = await family(mf);
    await consented(mf, f);
    const kitten = f.ids[f.kid.id] as string;
    await tick(mf, kitten, ((await record(mf, kitten)) as ConsentRecord).plusAt as number);
    const kid = alertsTo(MOM_TOKEN, "consent")[0]?.body.kitten as string;
    expect((await call(mf, f.momPhone, "DELETE", `/v1/kittens/${kid}/consent`)).status).toBe(204);
    expect(await record(mf, kitten)).toMatchObject({ state: "pending", phone: null });
    expect(await tokens(mf, f.kidPad)).toEqual({ apns: false, widget: false, live: false });
  });

  test("no device of the parent's accepted it: retried hourly inside the window, and a day of that revokes", async () => {
    const mf = await start();
    const f = await family(mf);
    await consented(mf, f);
    const kitten = f.ids[f.kid.id] as string;
    const due = ((await record(mf, kitten)) as ConsentRecord).plusAt as number;
    apnsDown.add(MOM_TOKEN);
    await tick(mf, kitten, due);
    expect((await record(mf, kitten))?.state).toBe("consented");
    const retry = (await alarm(mf, kitten)) as number;
    expect(retry).toBeGreaterThan(due);
    expect(hourIn(retry, LA)).toBeGreaterThanOrEqual(10);
    expect(hourIn(retry, LA)).toBeLessThan(20);
    // A late-evening miss waits for the morning.
    let evening = due;
    while (localTime(evening, LA) !== "19:30") evening += 60_000;
    expect(evening).toBeLessThan(due + 24 * H);
    await tick(mf, kitten, evening);
    const next = (await alarm(mf, kitten)) as number;
    // The plus is due at the time of day the test's consent was given (inside the window), so
    // when that is after 19:30 the day is up before the morning: the last try is exactly then.
    if (localTime(due, LA) > "19:30") expect(next).toBe(due + 24 * H);
    else expect(hourIn(next, LA)).toBe(10);
    await tick(mf, kitten, due + 24 * H);
    expect(await record(mf, kitten)).toMatchObject({ state: "pending", phone: null });
    expect(await tokens(mf, f.kidPad)).toMatchObject({ apns: false });
  });

  test("goes to the consenting parent only, not a second linked parent", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await consented(mf, f);
    const dadPhone = await mint(mf);
    const dad = newPerson("Dad", 5);
    await profile(mf, dadPhone, [dad], { apns: DAD_TOKEN });
    await call(mf, dadPhone, "POST", "/v1/identities/apple", { proof: await appleProof(`apple-dad-${crypto.randomUUID()}`), person: { id: dad.id, key: dad.key } });
    const { code } = await json<{ code: string }>(kidCall(mf, f, "POST", "/v1/kittens/me/link-code", {}));
    expect((await json<{ kitten: ParentKitten }>(call(mf, dadPhone, "POST", "/v1/kittens/link", { code }))).kitten.id).toBe(k.id);
    const kitten = f.ids[f.kid.id] as string;
    await tick(mf, kitten, ((await record(mf, kitten)) as ConsentRecord).plusAt as number);
    expect(alertsTo(MOM_TOKEN, "consent")).toHaveLength(1);
    expect(alertsTo(DAD_TOKEN, "consent")).toEqual([]);
  });
});

describe("revoke (consent design §2 Revocation)", { timeout: 30_000 }, () => {
  test("a parent's revoke drops the kitten's tokens and stops pushes at once", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await consented(mf, f);
    expect(await tokens(mf, f.kidPad)).toMatchObject({ apns: true });
    expect((await call(mf, f.momPhone, "DELETE", `/v1/kittens/${k.id}/consent`)).status).toBe(204);
    expect(await tokens(mf, f.kidPad)).toEqual({ apns: false, widget: false, live: false });
    expect(await json(kidCall(mf, f, "GET", "/v1/kittens/me"))).toMatchObject({ state: "pending", linked: true });
    expect((await call(mf, f.kidPad, "PUT", "/v1/devices/me/push", { apnsToken: KID_TOKEN })).status).toBe(403);
    // Someone else's kitten id is a 404.
    expect((await call(mf, f.miaPhone, "DELETE", `/v1/kittens/${k.id}/consent?person=${f.mia.id}`)).status).toBe(404);
  });

  test("RESCIND_CONSENT for the kitten's app transaction revokes; Apple's pin refuses the fixture chain", async () => {
    const mf = await start();
    const f = await family(mf);
    await consented(mf, f, { appTransactionId: "704289231001" });
    const kitten = f.ids[f.kid.id] as string;
    const body = await rescindBody("704289231001");
    const real = await hook(mf, "/v1/appstore/notifications", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
    expect(real.status).toBe(400);
    expect((await record(mf, kitten))?.state).toBe("consented");
    const other = await hook(mf, "/__test/appstore", { method: "POST", body: JSON.stringify({ roots: TEST_ROOTS, body: await rescindBody("999") }) });
    expect(other.status).toBe(200);
    expect((await record(mf, kitten))?.state).toBe("consented");
    const res = await hook(mf, "/__test/appstore", { method: "POST", body: JSON.stringify({ roots: TEST_ROOTS, body }) });
    expect(res.status).toBe(200);
    expect(await record(mf, kitten)).toMatchObject({ state: "pending", phone: null });
  });

  test("turning 13 ends the record", async () => {
    const mf = await start();
    const f = await family(mf);
    await consented(mf, f);
    const kitten = f.ids[f.kid.id] as string;
    await profile(mf, f.kidPad, [f.kid], { band: "teen" });
    expect(await record(mf, kitten)).toBeNull();
    expect(await tokens(mf, f.kidPad)).toMatchObject({ apns: false });
    expect(await json(call(mf, f.momPhone, "GET", "/v1/kittens"))).toEqual({ kittens: [] });
  });

  test("the kitten's 90-day expiry ends the record; the parent's deletion unlinks them", async () => {
    const mf = await start();
    const f = await family(mf);
    await consented(mf, f);
    const kitten = f.ids[f.kid.id] as string;
    await hook(mf, `/__test/expire?player=${kitten}`);
    expect(await record(mf, kitten)).toBeNull();
    expect(await tokens(mf, f.kidPad)).toMatchObject({ apns: false });

    const g = await family(mf);
    await consented(mf, g);
    const kitten2 = g.ids[g.kid.id] as string;
    expect((await call(mf, g.momPhone, "DELETE", "/v1/me")).status).toBe(204);
    expect(await record(mf, kitten2)).toBeNull();
    expect(await tokens(mf, g.kidPad)).toMatchObject({ apns: false });
  });
});

describe("push gating (decision 16)", { timeout: 30_000 }, () => {
  test("your move reaches a consented kitten only when everyone else at the table is approved", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await consented(mf, f);
    const { clients, pair } = await sharedTable(mf, f);
    const view = await json<{ kittens: ParentKitten[] }>(call(mf, f.momPhone, "GET", "/v1/kittens"));
    expect(view.kittens[0]?.people).toEqual([{ pair, name: "Mia", cat: 2, approved: false, parent: false }]);

    await miaMovesToKid(clients);
    await settle(400);
    expect(alertsTo(KID_TOKEN)).toEqual([]);

    expect((await call(mf, f.momPhone, "PUT", `/v1/kittens/${k.id}/approved`, { approved: [pair] })).status).toBe(204);
    expect(await json<KittenView>(kidCall(mf, f, "GET", "/v1/kittens/me"))).toMatchObject({ approved: [pair] });
    await miaMovesToKid(clients);
    const [push] = (await eventually(() => alertsTo(KID_TOKEN, "your_move"), (l) => l.length === 1)) as [Sent];
    expect(push.body).toMatchObject({ kind: "your_move", from: { name: "Mia" } });

    // Revoked: refused at once, and the token is gone.
    await call(mf, f.momPhone, "DELETE", `/v1/kittens/${k.id}/consent`);
    await miaMovesToKid(clients);
    await settle(400);
    expect(alertsTo(KID_TOKEN, "your_move")).toHaveLength(1);
  });

  test("pounces from approved people only; a linked kitten can't pounce someone unapproved", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await consented(mf, f);
    const { pair } = await sharedTable(mf, f);
    const miaPair = (await json<{ pairs: { pair: string }[] }>(call(mf, f.miaPhone, "GET", `/v1/me/streaks?person=${f.mia.id}`))).pairs[0]?.pair as string;
    expect(miaPair).toBe(pair);

    expect((await call(mf, f.miaPhone, "POST", `/v1/pounces?person=${f.mia.id}`, { to: pair, target: "new" })).status).toBe(201);
    await settle(400);
    expect(alertsTo(KID_TOKEN, "pounce")).toEqual([]);
    expect((await kidCall(mf, f, "POST", "/v1/pounces", { to: pair, target: "new" })).status).toBe(403);

    await call(mf, f.momPhone, "PUT", `/v1/kittens/${k.id}/approved`, { approved: [pair] });
    expect((await kidCall(mf, f, "POST", "/v1/pounces", { to: pair, target: "pick" })).status).toBe(201);
    // Mia rests after one unanswered pounce? No: 3 an hour.
    expect((await call(mf, f.miaPhone, "POST", `/v1/pounces?person=${f.mia.id}`, { to: pair, target: "pick" })).status).toBe(201);
    const [push] = (await eventually(() => alertsTo(KID_TOKEN, "pounce"), (l) => l.length === 1)) as [Sent];
    expect(push.body).toMatchObject({ kind: "pounce", from: { name: "Mia" } });
    // Status pushes (an answer) never reach the kitten's device.
    await settle(200);
    expect(alertsTo(KID_TOKEN).every((s) => s.body.kind === "pounce")).toBe(true);
  });

  test("nudges from approved people only; otherwise the kitten sees them in the app alone", async () => {
    const mf = await start({ nudge: true });
    const f = await family(mf);
    const k = await consented(mf, f);
    const { clients, pair } = await sharedTable(mf, f);
    const [miaC, kidC] = clients as [Client, Client];
    const nudge = async () => {
      // Past the 2-minute wait and the 10-minute cooldown, both at speed.
      await settle(6200);
      miaC.received.length = 0;
      miaC.send({ t: "nudge", seat: 1 });
      await miaC.find((m) => m.t === "nudgeSent");
    };

    await miaMovesToKid(clients);
    await nudge();
    await settle(400);
    expect(alertsTo(KID_TOKEN, "nudge")).toEqual([]);

    await call(mf, f.momPhone, "PUT", `/v1/kittens/${k.id}/approved`, { approved: [pair] });
    await miaMovesToKid(clients);
    kidC.received.length = 0;
    await nudge();
    const [push] = (await eventually(() => alertsTo(KID_TOKEN, "nudge"), (l) => l.length === 1)) as [Sent];
    expect(push.body).toMatchObject({ kind: "nudge", from: { name: "Mia" } });
  }, 60_000);

  test("CONSENT off is today exactly: no kitten routes, and a kitten's device gets nothing", async () => {
    const mf = await start({ consentFlag: false });
    const f = await family(mf);
    expect((await kidCall(mf, f, "POST", "/v1/kittens/me/link-code", {})).status).toBe(404);
    expect((await call(mf, f.momPhone, "GET", "/v1/kittens")).status).toBe(404);
    expect((await hook(mf, "/privacy/kitten-notice")).status).toBe(404);
    expect((await hook(mf, "/v1/twilio/inbound", { method: "POST" })).status).toBe(404);
    expect((await hook(mf, "/v1/appstore/notifications", { method: "POST" })).status).toBe(404);
    // Today a kitten's token is stored if sent, and never used.
    expect((await call(mf, f.kidPad, "PUT", "/v1/devices/me/push", { apnsToken: KID_TOKEN })).status).toBe(204);
    const { clients, pair } = await sharedTable(mf, f);
    await miaMovesToKid(clients);
    await call(mf, f.miaPhone, "POST", `/v1/pounces?person=${f.mia.id}`, { to: pair, target: "new" });
    await settle(500);
    expect(alertsTo(KID_TOKEN)).toEqual([]);
    // And the kitten pounces as before.
    expect((await kidCall(mf, f, "POST", "/v1/pounces", { to: pair, target: "new" })).status).toBe(201);
  });
});

describe("approvals (D3)", { timeout: 30_000 }, () => {
  test("Apple's answers from the kitten's device rule; the parent's toggles are refused; strangers are cut", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await consented(mf, f);
    const { pair } = await sharedTable(mf, f);
    const stranger = "pr_AAAAAAAAAAAAAAAAAAAAAA";
    expect((await kidCall(mf, f, "PUT", "/v1/kittens/me/approved", { apple: [stranger] })).status).toBe(204);
    let view = (await json<{ kittens: ParentKitten[] }>(call(mf, f.momPhone, "GET", "/v1/kittens"))).kittens[0] as ParentKitten;
    expect(view.mode).toBe("apple");
    expect(view.people[0]?.approved).toBe(false);
    expect((await kidCall(mf, f, "PUT", "/v1/kittens/me/approved", { apple: [pair] })).status).toBe(204);
    view = (await json<{ kittens: ParentKitten[] }>(call(mf, f.momPhone, "GET", "/v1/kittens"))).kittens[0] as ParentKitten;
    expect(view.people[0]?.approved).toBe(true);
    const refused = await call(mf, f.momPhone, "PUT", `/v1/kittens/${k.id}/approved`, { approved: [] });
    expect(refused.status).toBe(409);
    expect(await refused.json()).toEqual({ error: "apple_managed" });
    expect((await kidCall(mf, f, "PUT", "/v1/kittens/me/approved", { apple: null })).status).toBe(204);
    view = (await json<{ kittens: ParentKitten[] }>(call(mf, f.momPhone, "GET", "/v1/kittens"))).kittens[0] as ParentKitten;
    expect(view).toMatchObject({ mode: "parent", people: [{ approved: false }] });
    for (const bad of [{}, { apple: "x" }, { apple: ["nope"] }, { apple: [], x: 1 }]) {
      expect((await kidCall(mf, f, "PUT", "/v1/kittens/me/approved", bad)).status).toBe(400);
    }
    expect((await call(mf, f.momPhone, "PUT", `/v1/kittens/${k.id}/approved`, { approved: [stranger] })).status).toBe(204);
    expect(await json<KittenView>(kidCall(mf, f, "GET", "/v1/kittens/me"))).toMatchObject({ approved: [] });
  });
});

describe("the notice page", { timeout: 30_000 }, () => {
  test("is public and static", async () => {
    const mf = await start();
    const res = await hook(mf, "/privacy/kitten-notice");
    expect(res.status).toBe(200);
    expect(await res.text()).toContain("Notice to parents");
  });
});

describe("what Verify made unnecessary is gone", { timeout: 30_000 }, () => {
  test("the texted confirm and revoke pages and the STOP webhook answer 404", async () => {
    const mf = await start();
    const f = await family(mf);
    await consented(mf, f);
    const token = "AAAAAAAAAAAAAAAAAAAAAA";
    expect((await hook(mf, `/consent/${token}`)).status).toBe(404);
    expect((await hook(mf, `/consent/${token}`, { method: "POST" })).status).toBe(404);
    const form = new URLSearchParams({ From: PHONE, Body: "STOP" }).toString();
    const stop = await hook(mf, "/v1/twilio/inbound", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: form });
    expect(stop.status).toBe(404);
    expect((await record(mf, f.ids[f.kid.id] as string))?.state).toBe("consented");
  });
});

describe("review fixes", { timeout: 30_000 }, () => {
  test("a revoke while a code check is out is applied after it (I1)", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await linked(mf, f);
    const kitten = f.ids[f.kid.id] as string;
    await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: PHONE });
    verify.delay.ms = 600;
    const checking = check(mf, f, k, verify.code(PHONE));
    await settle(150);
    expect((await call(mf, f.momPhone, "DELETE", `/v1/kittens/${k.id}/consent`)).status).toBe(204);
    expect((await checking).status).toBe(200);
    expect(await record(mf, kitten)).toMatchObject({ state: "pending", phone: null });
    expect((await call(mf, f.kidPad, "PUT", "/v1/devices/me/push", { apnsToken: KID_TOKEN })).status).toBe(403);
  });

  test("codes are limited per kitten and per number, and only North American numbers get one (I2)", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await linked(mf, f);
    expect((await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: "+44 20 7946 0958" })).status).toBe(400);
    for (let i = 0; i < 3; i++) expect((await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: PHONE })).status).toBe(202);
    const fourth = await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: PHONE });
    expect(fourth.status).toBe(429);
    expect(verify.sends).toHaveLength(3);
    // Another family can't send that number a fourth code today either; another number is fine.
    const g = await family(mf);
    const gk = await linked(mf, g);
    expect((await call(mf, g.momPhone, "POST", `/v1/kittens/${gk.id}/consent`, { phone: PHONE })).status).toBe(429);
    expect((await call(mf, g.momPhone, "POST", `/v1/kittens/${gk.id}/consent`, { phone: "+14155550199" })).status).toBe(202);
    expect(verify.sends).toHaveLength(4);
  });

  test("Verify's own send limit is a 429, and a failed send changes nothing", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await linked(mf, f);
    verify.failing.add(PHONE);
    expect((await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: PHONE })).status).toBe(502);
    expect((await record(mf, f.ids[f.kid.id] as string))?.state).toBe("pending");
    verify.failing.clear();
    verify.live.set(PHONE, { code: "123456", sends: 5, wrong: 0 });
    expect((await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: PHONE })).status).toBe(429);
    expect((await record(mf, f.ids[f.kid.id] as string))?.state).toBe("pending");
  });

  test("an approved partner who merges into their account stays approved (M9)", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await consented(mf, f);
    const { pair } = await sharedTable(mf, f);
    await call(mf, f.momPhone, "PUT", `/v1/kittens/${k.id}/approved`, { approved: [pair] });
    // Mia already has an account on her iPad; her phone's guest signs in to it and merges.
    const miaPad = await mint(mf);
    const miaToo = newPerson("Mia", 2);
    await profile(mf, miaPad, [miaToo]);
    const sub = `apple-mia-${crypto.randomUUID()}`;
    expect((await call(mf, miaPad, "POST", "/v1/identities/apple", { proof: await appleProof(sub), person: { id: miaToo.id, key: miaToo.key } })).status).toBe(200);
    const merged = await call(mf, f.miaPhone, "POST", "/v1/identities/apple", { proof: await appleProof(sub), person: { id: f.mia.id, key: f.mia.key } });
    expect(((await merged.json()) as { outcome: string }).outcome).toBe("merged");
    const view = (await json<{ kittens: ParentKitten[] }>(call(mf, f.momPhone, "GET", "/v1/kittens"))).kittens[0] as ParentKitten;
    expect(view.people).toMatchObject([{ approved: true }]);
  });
});
