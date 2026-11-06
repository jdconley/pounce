import { afterEach, beforeAll, describe, expect, test } from "vitest";

import {
  appleProof,
  BASE,
  bundle,
  call,
  connect,
  eventually,
  mint,
  newPerson,
  profile,
  settle,
  table,
  takeTurn,
  tokenOf,
  worker,
  type Client,
  type Device,
  type Person,
  type Sent,
  PLAYER_ID_JSON,
} from "./play-helpers";

import type { PounceRow, PounceView } from "../src/pounce/limits";
import type { ServerMessage } from "../src/protocol";
import type { StreakView } from "../src/streaks/pair-core";
import type { Miniflare } from "miniflare";

const DAY_MS = 24 * 60 * 60 * 1000;
const JD_TOKEN = tokenOf(1);
const MIA_TOKEN = tokenOf(2);
const KIM_TOKEN = tokenOf(5);

let script = "";
let sent: Sent[] = [];
const open: Miniflare[] = [];

beforeAll(async () => {
  script = await bundle("./pounce-entry.ts");
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
  sent = [];
});

async function start(streaks = true): Promise<Miniflare> {
  const mf = await worker(script, { streaks, links: true, sent });
  open.push(mf);
  return mf;
}

const alertsTo = (token: string, kind?: string) =>
  sent.filter((s) => s.token === token && s.headers["apns-push-type"] === "alert" && (kind === undefined || s.body.kind === kind));
type Aps = { alert: { title: string; body: string }; category: string; "thread-id": string; "interruption-level": string };
const aps = (s: Sent) => s.body.aps as Aps;

/** JD and Mia, each with a turn at a shared table: a pair. */
async function pairedUp(mf: Miniflare, miaBand = "adult") {
  const phone = await mint(mf);
  const tablet = await mint(mf);
  const jd = newPerson("JD", 1);
  const mia = newPerson("Mia", 2);
  const ids = {
    ...(await profile(mf, phone, [jd], { apns: JD_TOKEN })),
    ...(await profile(mf, tablet, [mia], { apns: MIA_TOKEN, band: miaBand })),
  };
  const t = await table(mf, [
    [phone, jd],
    [tablet, mia],
  ]);
  await takeTurn(t.clients);
  await takeTurn(t.clients);
  const a = t.clients[0] as Client;
  const streak = await a.find<Extract<ServerMessage, { t: "streak" }>>((m) => m.t === "streak");
  return { phone, tablet, jd, mia, ids, ...t, pairId: streak.pair };
}

const pounce = (mf: Miniflare, d: Device, p: Person, body: unknown) => call(mf, d, "POST", `/v1/pounces?person=${p.id}`, body);
const answer = (mf: Miniflare, d: Device, p: Person, id: string, body: unknown) => call(mf, d, "POST", `/v1/pounces/${id}/answer?person=${p.id}`, body);

async function streakOf(mf: Miniflare, d: Device, p: Person): Promise<StreakView & { pounce: PounceView }> {
  const res = await call(mf, d, "GET", `/v1/me/streaks?person=${p.id}`);
  return ((await res.json()) as { pairs: (StreakView & { pounce: PounceView })[] }).pairs[0] as StreakView & { pounce: PounceView };
}

describe("pounce by push (§12.4)", { timeout: 30_000 }, () => {
  test("reaches the partner as a POUNCE push, shows as sent and waiting, and Play deals a new table for both", async () => {
    const mf = await start();
    const { phone, tablet, jd, mia, pairId, ids } = await pairedUp(mf);
    const res = await pounce(mf, phone, jd, { to: pairId, target: "new" });
    expect(res.status).toBe(201);
    const { id } = (await res.json()) as { id: string };
    expect(id).toMatch(/^pc_/);

    const [push] = (await eventually(() => alertsTo(MIA_TOKEN, "pounce"), (l) => l.length === 1)) as [Sent];
    expect(aps(push)).toMatchObject({
      alert: { title: "Mia", body: "JD wants to play. New game?" },
      category: "POUNCE",
      "thread-id": `pounce:${pairId}`,
    });
    expect(push.body).toMatchObject({ kind: "pounce", from: { name: "JD", cat: 1 }, pounce: { id, target: "new" } });
    expect(push.headers["apns-collapse-id"]).toBe(`pounce:${id}`);
    expect(JSON.stringify(push.body)).not.toMatch(PLAYER_ID_JSON);

    expect((await streakOf(mf, phone, jd)).pounce).toMatchObject({ sent: true, resting: false, waiting: null });
    expect((await streakOf(mf, tablet, mia)).pounce).toMatchObject({ sent: false, waiting: { id, target: "new" } });

    const played = await answer(mf, tablet, mia, id, { answer: "play" });
    expect(played.status).toBe(200);
    const { code } = (await played.json()) as { code: string };
    expect(code).toMatch(/^[A-Z0-9]{5}$/);
    const c = await connect(mf, code, tablet);
    expect(c.last?.room.status).toBe("playing");
    expect(c.last?.room.seats.map((s) => s.person?.id)).toEqual([jd.id, mia.id]);
    expect(c.last?.room.seats.map((s) => s.yours)).toEqual([false, true]);

    const [coming] = (await eventually(() => alertsTo(JD_TOKEN, "pounce_answered"), (l) => l.length === 1)) as [Sent];
    expect(aps(coming)).toMatchObject({ alert: { title: "JD", body: "Mia is coming." }, "interruption-level": "passive" });
    expect(coming.body).toMatchObject({ code, pounce: { id, answer: "play" } });

    // The app retries a background answer: same table, no second push.
    const again = await answer(mf, tablet, mia, id, { answer: "play" });
    expect(await again.json()).toEqual({ code });
    expect(await (await answer(mf, tablet, mia, id, { answer: "no" })).json()).toEqual({ code });
    await settle();
    expect(alertsTo(JD_TOKEN, "pounce_answered")).toHaveLength(1);
    expect((await streakOf(mf, phone, jd)).pounce).toMatchObject({ sent: false, answer: "play", code });
    // Only the person pounced on can answer.
    expect((await answer(mf, phone, jd, id, { answer: "play" })).status).toBe(404);
    expect(ids[jd.id]).toBeDefined();
  });

  test("two answers at once deal one table and tell the sender once; the answerer gets no push for the table they asked for", async () => {
    const mf = await start();
    const { phone, tablet, jd, mia, pairId } = await pairedUp(mf);
    const { id } = (await (await pounce(mf, phone, jd, { to: pairId, target: "new" })).json()) as { id: string };
    const results = await Promise.all([answer(mf, tablet, mia, id, { answer: "play" }), answer(mf, tablet, mia, id, { answer: "play" })]);
    const bodies = (await Promise.all(results.map((r) => r.json()))) as { code?: string }[];
    const codes = new Set(bodies.flatMap((b) => (b.code ? [b.code] : [])));
    expect(codes.size).toBe(1);
    const code = [...codes][0] as string;
    await settle(500);
    expect(alertsTo(JD_TOKEN, "pounce_answered")).toHaveLength(1);
    expect(alertsTo(MIA_TOKEN, "your_move").filter((s) => s.body.code === code)).toEqual([]);
    // A retry once it's dealt gets the table.
    expect(await (await answer(mf, tablet, mia, id, { answer: "play" })).json()).toEqual({ code });
  });

  test("a table target must be one you share; Play opens it", async () => {
    const mf = await start();
    const { phone, tablet, jd, mia, pairId, code } = await pairedUp(mf);
    expect((await pounce(mf, phone, jd, { to: pairId, target: { table: "ZZZZZ" } })).status).toBe(409);
    const res = await pounce(mf, phone, jd, { to: pairId, target: { table: code } });
    expect(res.status).toBe(201);
    const { id } = (await res.json()) as { id: string };
    const [push] = (await eventually(() => alertsTo(MIA_TOKEN, "pounce"), (l) => l.length === 1)) as [Sent];
    expect(push.body).toMatchObject({ code, pounce: { target: { table: code } } });
    expect(aps(push).alert.body).toMatch(/^JD wants to play\. .+\?$/);
    expect(await (await answer(mf, tablet, mia, id, { answer: "play" })).json()).toEqual({ code });
  });

  test("You pick needs a choice; In a bit and Not now tell the sender; Not now rests them an hour", async () => {
    const mf = await start();
    const { phone, tablet, jd, mia, pairId } = await pairedUp(mf);
    const { id } = (await (await pounce(mf, phone, jd, { to: pairId, target: "pick" })).json()) as { id: string };
    expect((await answer(mf, tablet, mia, id, { answer: "play" })).status).toBe(400);
    expect((await answer(mf, tablet, mia, id, { answer: "later" })).status).toBe(200);
    await eventually(() => alertsTo(JD_TOKEN, "pounce_answered"), (l) => l.length === 1);
    expect(aps(alertsTo(JD_TOKEN, "pounce_answered")[0] as Sent).alert.body).toBe("Mia: in a bit.");
    expect((await answer(mf, tablet, mia, id, { answer: "no" })).status).toBe(200);
    await eventually(() => alertsTo(JD_TOKEN, "pounce_answered"), (l) => l.length === 2);
    expect(aps(alertsTo(JD_TOKEN, "pounce_answered")[1] as Sent).alert.body).toBe("Mia: not now.");
    const rested = await pounce(mf, phone, jd, { to: pairId, target: "new" });
    expect(rested.status).toBe(429);
    expect(await rested.json()).toMatchObject({ error: "resting", until: expect.any(Number) });
    expect((await streakOf(mf, phone, jd)).pounce.resting).toBe(true);
  });

  test("3 an hour: the 4th rests", async () => {
    const mf = await start();
    const { phone, jd, pairId } = await pairedUp(mf);
    for (let i = 0; i < 3; i++) expect((await pounce(mf, phone, jd, { to: pairId, target: "pick" })).status).toBe(201);
    expect((await pounce(mf, phone, jd, { to: pairId, target: "pick" })).status).toBe(429);
  });

  test("bad bodies and someone else's pair", async () => {
    const mf = await start();
    const { phone, jd, pairId } = await pairedUp(mf);
    for (const bad of [{}, { to: pairId, target: "soon" }, { to: "pr_AAAAAAAAAAAAAAAAAAAAAA", target: "new", x: 1 }]) {
      expect((await pounce(mf, phone, jd, bad)).status).toBe(400);
    }
    expect((await pounce(mf, phone, jd, { to: "pr_AAAAAAAAAAAAAAAAAAAAAA", target: "new" })).status).toBe(404);
    expect((await answer(mf, phone, jd, "pc_AAAAAAAAAAAAAAAAAAAAAA", { answer: "play" })).status).toBe(404);
    expect((await answer(mf, phone, jd, "nope", { answer: "play" })).status).toBe(404);
  });
});

describe("pounce through Messages (§12.4)", { timeout: 30_000 }, () => {
  test("a link token, a public preview page, single use, and a new table with the person who opened it", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const jd = newPerson("JD", 1);
    await profile(mf, phone, [jd], { apns: JD_TOKEN });
    expect((await pounce(mf, phone, jd, { target: { table: "BCDFG" } })).status).toBe(400);
    const res = await pounce(mf, phone, jd, { target: "new" });
    expect(res.status).toBe(201);
    const { id, link } = (await res.json()) as { id: string; link: string };
    expect(link).toMatch(/^https:\/\/play\.conleychaos\.com\/p\/[A-Za-z0-9_-]{22}$/);
    const token = link.split("/").at(-1) as string;

    const page = await mf.dispatchFetch(`${BASE}/p/${token}`);
    expect(page.status).toBe(200);
    const html = await page.text();
    expect(html).toContain("JD wants to play");
    expect(html).toContain(`${BASE}/og/pounce.jpg`);
    const card = await mf.dispatchFetch(`${BASE}/og/pounce.jpg`);
    expect(card.headers.get("content-type")).toBe("image/jpeg");
    expect((await card.arrayBuffer()).byteLength).toBeGreaterThan(10_000);
    const aasa = (await (await mf.dispatchFetch(`${BASE}/.well-known/apple-app-site-association`)).json()) as {
      applinks: { details: { components: unknown[] }[] };
    };
    expect(aasa.applinks.details[0]?.components).toContainEqual({ "/": "/p/*" });

    const ipad = await mint(mf);
    const kim = newPerson("Kim", 5);
    await profile(mf, ipad, [kim], { apns: KIM_TOKEN });
    const preview = await call(mf, ipad, "GET", `/v1/pounces/links/${token}`);
    expect(await preview.json()).toEqual({ id, from: { name: "JD", cat: 1 }, target: "new" });

    expect((await answer(mf, ipad, kim, id, { answer: "play" })).status).toBe(404);
    const played = await answer(mf, ipad, kim, id, { answer: "play", link: token });
    expect(played.status).toBe(200);
    const { code } = (await played.json()) as { code: string };
    const c = await connect(mf, code, ipad);
    expect(c.last?.room.seats.map((s) => s.person?.id)).toEqual([jd.id, kim.id]);
    await eventually(() => alertsTo(JD_TOKEN, "pounce_answered"), (l) => l.length === 1);
    expect(aps(alertsTo(JD_TOKEN, "pounce_answered")[0] as Sent).alert.body).toBe("Kim is coming.");

    // Single use: gone for everyone else, but the one who answered can retry.
    const other = await mint(mf);
    const sam = newPerson("Sam", 3);
    await profile(mf, other, [sam]);
    expect((await answer(mf, other, sam, id, { answer: "play", link: token })).status).toBe(404);
    expect((await call(mf, other, "GET", `/v1/pounces/links/${token}`)).status).toBe(404);
    expect((await mf.dispatchFetch(`${BASE}/p/${token}`)).status).toBe(404);
    expect(await (await answer(mf, ipad, kim, id, { answer: "play" })).json()).toEqual({ code });
  });

  test("two people opening the same link at once: only one gets it", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const jd = newPerson("JD", 1);
    await profile(mf, phone, [jd], { apns: JD_TOKEN });
    const { id, link } = (await (await pounce(mf, phone, jd, { target: "new" })).json()) as { id: string; link: string };
    const token = link.split("/").at(-1) as string;
    const guests = await Promise.all(
      ["Kim", "Sam"].map(async (name, i) => {
        const d = await mint(mf);
        const p = newPerson(name, 3 + i);
        await profile(mf, d, [p]);
        return [d, p] as const;
      }),
    );
    const results = await Promise.all(guests.map(([d, p]) => answer(mf, d, p, id, { answer: "play", link: token })));
    expect(results.map((r) => r.status).sort()).toEqual([200, 404]);
    await settle(500);
    expect(alertsTo(JD_TOKEN, "pounce_answered")).toHaveLength(1);
  });

  test("links expire after 24 hours and pounces after 7 days", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const jd = newPerson("JD", 1);
    const ids = await profile(mf, phone, [jd]);
    const { id, link } = (await (await pounce(mf, phone, jd, { target: "pick" })).json()) as { id: string; link: string };
    const token = link.split("/").at(-1) as string;
    expect(await (await mf.dispatchFetch(`${BASE}/__test/link?key=${token}&now=${Date.now() + DAY_MS + 1}`)).json()).toBeNull();
    await mf.dispatchFetch(`${BASE}/__test/links-prune?now=${Date.now() + DAY_MS + 1}`);
    expect(await (await mf.dispatchFetch(`${BASE}/__test/link?key=${token}`)).json()).toBeNull();
    expect(await (await mf.dispatchFetch(`${BASE}/__test/link?key=${id}`)).json()).not.toBeNull();
    const rows = () => mf.dispatchFetch(`${BASE}/__test/pounces?player=${ids[jd.id] as string}`).then((r) => r.json() as Promise<PounceRow[]>);
    expect(await rows()).toHaveLength(1);
    await mf.dispatchFetch(`${BASE}/__test/remind?player=${ids[jd.id] as string}&now=${Date.now() + 7 * DAY_MS + 1}`);
    expect(await rows()).toEqual([]);
  });
});

describe("pounces and deletion (§14)", { timeout: 30_000 }, () => {
  const linkOf = async (mf: Miniflare, d: Device, p: Person) => {
    const { id, link } = (await (await pounce(mf, d, p, { target: "new" })).json()) as { id: string; link: string };
    return { id, token: link.split("/").at(-1) as string };
  };
  const indexed = async (mf: Miniflare, key: string) => (await (await mf.dispatchFetch(`${BASE}/__test/link?key=${key}`)).json()) !== null;

  test("deleting an account forgets its links", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const jd = newPerson("JD", 1);
    await profile(mf, phone, [jd]);
    const { id, token } = await linkOf(mf, phone, jd);
    expect(await indexed(mf, token)).toBe(true);
    expect((await call(mf, phone, "DELETE", `/v1/me?person=${jd.id}`)).status).toBe(204);
    expect(await indexed(mf, token)).toBe(false);
    expect(await indexed(mf, id)).toBe(false);
    expect((await mf.dispatchFetch(`${BASE}/p/${token}`)).status).toBe(404);
  });

  test("a guest merged into an account takes no pounces or links along", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const ipad = await mint(mf);
    const jd = newPerson("JD", 1);
    const jdPad = newPerson("JD", 1);
    await profile(mf, phone, [jd]);
    const padIds = await profile(mf, ipad, [jdPad]);
    const { token } = await linkOf(mf, ipad, jdPad);
    const signIn = async (d: Device, p: Person) =>
      call(mf, d, "POST", "/v1/identities/apple", { proof: await appleProof("apple-jd"), person: { id: p.id, key: p.key } });
    expect((await signIn(phone, jd)).status).toBe(200);
    expect(((await (await signIn(ipad, jdPad)).json()) as { outcome: string }).outcome).toBe("merged");
    expect(await indexed(mf, token)).toBe(false);
    const rows = await (await mf.dispatchFetch(`${BASE}/__test/pounces?player=${padIds[jdPad.id] as string}`)).json();
    expect(rows).toEqual([]);
  });
});

describe("pounces and age bands (§14.1)", { timeout: 30_000 }, () => {
  test("a kitten gets no pounce push but sees it waiting; a kitten can pounce in the app but not by link", async () => {
    const mf = await start();
    const { phone, tablet, jd, mia, pairId } = await pairedUp(mf, "kitten");
    const { id } = (await (await pounce(mf, phone, jd, { to: pairId, target: "new" })).json()) as { id: string };
    await settle();
    expect(sent.filter((s) => s.token === MIA_TOKEN)).toEqual([]);
    expect((await streakOf(mf, tablet, mia)).pounce.waiting).toEqual({ id, target: "new" });
    expect((await pounce(mf, tablet, mia, { to: pairId, target: "pick" })).status).toBe(201);
    await eventually(() => alertsTo(JD_TOKEN, "pounce"), (l) => l.length === 1);
    expect((await pounce(mf, tablet, mia, { target: "new" })).status).toBe(403);
  });
});

describe("with STREAKS unset", { timeout: 30_000 }, () => {
  test("pounce routes and pages are 404s and the association lists only /j/*", async () => {
    const mf = await start(false);
    const phone = await mint(mf);
    const jd = newPerson("JD", 1);
    await profile(mf, phone, [jd]);
    expect((await pounce(mf, phone, jd, { target: "new" })).status).toBe(404);
    expect((await mf.dispatchFetch(`${BASE}/p/${"A".repeat(22)}`)).status).toBe(404);
    expect((await mf.dispatchFetch(`${BASE}/og/pounce.jpg`)).status).toBe(404);
    expect((await call(mf, phone, "PUT", "/v1/devices/me/widget-push", { token: tokenOf(9) })).status).toBe(404);
    const aasa = (await (await mf.dispatchFetch(`${BASE}/.well-known/apple-app-site-association`)).json()) as {
      applinks: { details: { components: unknown[] }[] };
    };
    expect(aasa.applinks.details[0]?.components).toEqual([{ "/": "/j/*" }]);
  });
});
