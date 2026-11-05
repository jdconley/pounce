import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { twilioSignature } from "../src/consent/twilio";

import { rescindBody, TEST_ROOTS } from "./appstore-fixtures";
import {
  appleProof,
  BASE,
  bundle,
  call,
  eventually,
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
  type Text,
} from "./play-helpers";

import type { ConsentRecord } from "../src/consent/rules";
import type { KittenView, ParentKitten } from "../src/kittens/kittens";
import type { ServerMessage } from "../src/protocol";
import type { Miniflare } from "miniflare";

const KID_TOKEN = tokenOf(7);
const MIA_TOKEN = tokenOf(2);
const MOM_TOKEN = tokenOf(3);
const PHONE = "+15551234567";

let script = "";
let sent: Sent[] = [];
let texts: Text[] = [];
const optedOut = new Set<string>();
const open: Miniflare[] = [];

beforeAll(async () => {
  script = await bundle("./consent-entry.ts");
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
  sent = [];
  texts = [];
  optedOut.clear();
});

async function start(options: { twilio?: boolean; consentFlag?: boolean } = {}): Promise<Miniflare> {
  const mf = await worker(script, { links: true, sent, consent: true, texts, optedOut, ...options });
  open.push(mf);
  return mf;
}

const alertsTo = (token: string, kind?: string) =>
  sent.filter((s) => s.token === token && s.headers["apns-push-type"] === "alert" && (kind === undefined || s.body.kind === kind));
const json = async <T>(res: Response | Promise<Response>): Promise<T> => (await (await res).json()) as T;
const hook = (mf: Miniflare, path: string, init?: RequestInit) => mf.dispatchFetch(`${BASE}${path}`, init as never) as unknown as Promise<Response>;
const record = (mf: Miniflare, kitten: string) => json<ConsentRecord | null>(hook(mf, `/__test/consent?player=${kitten}`));
const tokens = (mf: Miniflare, d: Device) => json<{ apns: boolean; widget: boolean; live: boolean }>(hook(mf, `/__test/tokens?device=${d.deviceId}`));

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

const linkFrom = (t: Text) => /https:\/\/play\.conleychaos\.com\/consent\/([A-Za-z0-9_-]{22})/.exec(t.body)?.[1] as string;

/** Linked, texted, confirmed, and the kitten's token uploaded. */
async function consented(mf: Miniflare, f: Family, body: unknown = {}): Promise<ParentKitten> {
  const k = await linked(mf, f, body);
  expect((await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: "(555) 123-4567" })).status).toBe(202);
  const token = linkFrom(texts.at(-1) as Text);
  expect((await hook(mf, `/consent/${token}`, { method: "POST" })).status).toBe(200);
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

async function stop(mf: Miniflare, from: string, body: string, signed = true): Promise<Response> {
  const params: [string, string][] = [
    ["From", from],
    ["To", "+18005550100"],
    ["Body", body],
    ["MessageSid", "SMtest"],
  ];
  const url = `${BASE}/v1/twilio/inbound`;
  const headers: Record<string, string> = { "content-type": "application/x-www-form-urlencoded" };
  if (signed) headers["x-twilio-signature"] = await twilioSignature(TWILIO.TWILIO_AUTH_TOKEN, url, params);
  return hook(mf, "/v1/twilio/inbound", { method: "POST", headers, body: new URLSearchParams(params).toString() });
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
    expect(JSON.stringify(kitten)).not.toContain("p_");
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

describe("consent by text plus (D1)", { timeout: 30_000 }, () => {
  test("text 1, a GET that changes nothing, a POST that confirms, then text 2 from the alarm", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await linked(mf, f);
    const kitten = f.ids[f.kid.id] as string;
    expect((await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: "nope" })).status).toBe(400);
    expect((await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: "(555) 123-4567" })).status).toBe(202);
    expect(texts).toHaveLength(1);
    const one = texts[0] as Text;
    expect(one.to).toBe(PHONE);
    expect(one.service).toBe(TWILIO.TWILIO_MESSAGING_SERVICE_SID);
    expect(one.auth).toBe(`Basic ${btoa(`${TWILIO.TWILIO_API_KEY_SID}:${TWILIO.TWILIO_API_KEY_SECRET}`)}`);
    expect(one.body).not.toContain("Mochi");
    expect(await json<{ kittens: ParentKitten[] }>(call(mf, f.momPhone, "GET", "/v1/kittens"))).toMatchObject({ kittens: [{ state: "texted" }] });
    // Before consent the kitten's device can't hold a token.
    expect((await call(mf, f.kidPad, "PUT", "/v1/devices/me/push", { apnsToken: KID_TOKEN })).status).toBe(403);

    const token = linkFrom(one);
    const page = await hook(mf, `/consent/${token}`);
    expect(page.status).toBe(200);
    const html = await page.text();
    expect(html).toContain("Allow notifications for Mochi?");
    expect(html).toContain(`action="/consent/${token}"`);
    expect((await record(mf, kitten))?.state).toBe("texted");

    expect(await (await hook(mf, `/consent/${token}`, { method: "POST" })).text()).toContain("Notifications are on");
    const r = (await record(mf, kitten)) as ConsentRecord;
    expect(r).toMatchObject({ state: "consented", phone: PHONE, secondSent: false });
    // Single use.
    expect((await hook(mf, `/consent/${token}`, { method: "POST" })).status).toBe(404);
    expect((await hook(mf, `/consent/${token}`)).status).toBe(404);
    expect(await json(kidCall(mf, f, "GET", "/v1/kittens/me"))).toMatchObject({ state: "consented" });
    expect((await call(mf, f.kidPad, "PUT", "/v1/devices/me/push", { apnsToken: KID_TOKEN })).status).toBe(204);
    // While consented, no new text.
    expect((await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: PHONE })).status).toBe(409);

    // Text 2, 24–48 h later, by the alarm.
    const due = r.secondAt as number;
    expect(due - (r.consentedAt as number)).toBeGreaterThanOrEqual(24 * 3_600_000);
    expect(due - (r.consentedAt as number)).toBeLessThanOrEqual(48 * 3_600_000);
    expect(await json(hook(mf, `/__test/consent-alarm?player=${kitten}`))).toBe(due);
    await hook(mf, `/__test/consent-tick?player=${kitten}&now=${due - 1}`);
    expect(texts).toHaveLength(1);
    await hook(mf, `/__test/consent-tick?player=${kitten}&now=${due}`);
    expect(texts).toHaveLength(2);
    const two = texts[1] as Text;
    expect(two.body).toContain("you allowed notifications");
    expect(two.body).not.toContain("Mochi");
    expect((await record(mf, kitten))?.secondSent).toBe(true);
    await hook(mf, `/__test/consent-tick?player=${kitten}&now=${due + 1}`);
    expect(texts).toHaveLength(2);

    // The revoke link: GET shows, POST revokes.
    const revoke = linkFrom(two);
    expect(await (await hook(mf, `/consent/${revoke}`)).text()).toContain("Turn off notifications for Mochi?");
    expect((await record(mf, kitten))?.state).toBe("consented");
    expect(await (await hook(mf, `/consent/${revoke}`, { method: "POST" })).text()).toContain("deleted your number");
    expect(await record(mf, kitten)).toMatchObject({ state: "pending", phone: null });
    expect(await tokens(mf, f.kidPad)).toEqual({ apns: false, widget: false, live: false });
  });

  test("without Twilio's secrets nothing is sent and the kitten stays pending", async () => {
    const mf = await start({ twilio: false });
    const f = await family(mf);
    const k = await linked(mf, f);
    const res = await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: PHONE });
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: "not_configured" });
    expect(texts).toHaveLength(0);
    expect((await record(mf, f.ids[f.kid.id] as string))?.state).toBe("pending");
    // And STOP can't be checked.
    expect((await stop(mf, PHONE, "STOP")).status).toBe(503);
  });

  test("a number nobody confirms is deleted after 7 days; text 2 to an opted-out number revokes", async () => {
    const mf = await start();
    const f = await family(mf);
    const k = await linked(mf, f);
    const kitten = f.ids[f.kid.id] as string;
    await call(mf, f.momPhone, "POST", `/v1/kittens/${k.id}/consent`, { phone: PHONE });
    const texted = (await record(mf, kitten)) as ConsentRecord;
    await hook(mf, `/__test/consent-tick?player=${kitten}&now=${(texted.textedAt as number) + 7 * 86_400_000}`);
    expect(await record(mf, kitten)).toMatchObject({ state: "pending", phone: null });
    expect((await hook(mf, `/consent/${linkFrom(texts[0] as Text)}`, { method: "POST" })).status).toBe(404);

    await consented(mf, f);
    optedOut.add(PHONE);
    const r = (await record(mf, kitten)) as ConsentRecord;
    await hook(mf, `/__test/consent-tick?player=${kitten}&now=${r.secondAt as number}`);
    expect(await record(mf, kitten)).toMatchObject({ state: "pending", phone: null });
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

  test("a signed STOP revokes; an unsigned one changes nothing", async () => {
    const mf = await start();
    const f = await family(mf);
    await consented(mf, f);
    const kitten = f.ids[f.kid.id] as string;
    expect((await stop(mf, PHONE, "STOP", false)).status).toBe(403);
    expect((await record(mf, kitten))?.state).toBe("consented");
    const hello = await stop(mf, PHONE, "hello");
    expect(hello.status).toBe(200);
    expect((await record(mf, kitten))?.state).toBe("consented");
    const res = await stop(mf, "+1 (555) 123-4567", " Stop ");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("text/xml");
    expect(await record(mf, kitten)).toMatchObject({ state: "pending", phone: null });
    expect(await tokens(mf, f.kidPad)).toMatchObject({ apns: false });
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
    expect((await hook(mf, "/consent/not-a-token")).status).toBe(404);
  });
});
