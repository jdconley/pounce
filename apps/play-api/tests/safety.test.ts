import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { NUDGE_AFTER_MS } from "../src/room/core";

import { BASE, bundle, call, connect, createRoom, eventually, mint, newPerson, profile, settle, table, takeTurn, tokenOf, worker, type Client, type Device, type Person, type Sent } from "./play-helpers";

import type { ServerMessage } from "../src/protocol";
import type { Report } from "../src/safety/reports";
import type { Miniflare } from "miniflare";

const JD_TOKEN = tokenOf(1);
const MIA_TOKEN = tokenOf(2);
const SPEED = 100;
const KEY = "owner-key-for-tests";

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

async function start(options: { key?: boolean } = {}): Promise<Miniflare> {
  const mf = await worker(script, { links: true, sent, nudge: true, devSpeed: SPEED, ...(options.key === false ? {} : { reportsKey: KEY }) });
  open.push(mf);
  return mf;
}

const face = (p: Person) => ({ id: p.id, name: p.name, cat: p.cat });
const errors = (c: Client) => c.received.flatMap((m) => (m.t === "error" ? [m.code] : []));
const alertsTo = (token: string, kind?: string) =>
  sent.filter((s) => s.token === token && s.headers["apns-push-type"] === "alert" && (kind === undefined || s.body.kind === kind));

function open_(mf: Miniflare, code: string, device: Device, ip = "198.51.100.7"): Promise<Response> {
  return mf.dispatchFetch(`${BASE}/v1/rooms/${code}/ws`, {
    headers: { authorization: `Bearer ${device.token}`, upgrade: "websocket", "cf-connecting-ip": ip },
  }) as unknown as Promise<Response>;
}

async function ownerList(mf: Miniflare, key: string | null, after?: number): Promise<Response> {
  return mf.dispatchFetch(`${BASE}/v1/admin/reports${after === undefined ? "" : `?after=${String(after)}`}`, {
    headers: key === null ? {} : { authorization: `Bearer ${key}` },
  }) as unknown as Promise<Response>;
}

/** JD (phone, host) and Mia (tablet) at a started table. */
async function twoAtTable(mf: Miniflare) {
  const phone = await mint(mf);
  const tablet = await mint(mf);
  const jd = newPerson("JD", 1);
  const mia = newPerson("Mia", 2);
  const ids = { ...(await profile(mf, phone, [jd], { apns: JD_TOKEN })), ...(await profile(mf, tablet, [mia], { apns: MIA_TOKEN })) };
  const t = await table(mf, [
    [phone, jd],
    [tablet, mia],
  ]);
  return { phone, tablet, jd, mia, ids, ...t };
}

describe("the name filter", { timeout: 30_000 }, () => {
  test("a refused name never becomes a table, a profile or a seat, and each says bad_name", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const made = await call(mf, phone, "POST", "/v1/rooms", { game: "cat-tower", name: "The Sh1t Show" });
    expect(made.status).toBe(400);
    expect(await made.json()).toEqual({ error: "bad_name" });
    expect((await call(mf, phone, "POST", "/v1/rooms", { game: "cat-tower", name: "Taco Night" })).status).toBe(201);

    const rude = newPerson("f u c k", 1);
    const up = await call(mf, phone, "PUT", "/v1/devices/me/profile", { timeZone: "America/Los_Angeles", ageBand: "adult", people: [rude] });
    expect(up.status).toBe(400);
    expect(await up.json()).toEqual({ error: "bad_name" });

    const code = await createRoom(mf, phone);
    const c = await connect(mf, code, phone);
    c.send({ t: "claim", seat: 0, person: face(rude) });
    await c.find((m) => m.t === "error");
    expect(errors(c)).toEqual(["bad_name"]);
    c.send({ t: "claim", seat: 0, person: { ...face(rude), name: "Cassandra" } });
    await c.until((s) => s.room.seats[0]?.person?.name === "Cassandra");
    c.send({ t: "rename", name: "a$$ hat club" });
    c.send({ t: "renameSeat", seat: 0, name: "B1tch" });
    await eventually(() => errors(c), (l) => l.length === 3);
    expect(errors(c)).toEqual(["bad_name", "bad_name", "bad_name"]);
    expect(c.last?.room.seats[0]?.person?.name).toBe("Cassandra");
  });

  test("the app can ask before it saves: POST /v1/names/check", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const check = async (d: Device, body: unknown) => {
      const res = await call(mf, d, "POST", "/v1/names/check", body);
      return [res.status, await res.json()];
    };
    expect(await check(phone, { kind: "person", name: "Mia" })).toEqual([200, { ok: true }]);
    expect(await check(phone, { kind: "table", name: "cunts" })).toEqual([200, { ok: false, reason: "bad_name" }]);
    expect((await check(phone, { kind: "chair", name: "Mia" }))[0]).toBe(400);

    const kid = await mint(mf);
    await profile(mf, kid, [newPerson("Mochi", 3)], { band: "kitten" });
    expect(await check(kid, { kind: "person", name: "Mia" })).toEqual([200, { ok: false, reason: "not_allowed" }]);
    expect(await check(kid, { kind: "person", name: "Pickle" })).toEqual([200, { ok: true }]);
  });
});

describe("a kitten's device (§14.1), enforced by the server", { timeout: 30_000 }, () => {
  test("no typed names: not the table's, not a seat's", async () => {
    const mf = await start();
    const kid = await mint(mf);
    const mochi = newPerson("Mochi", 3);
    await profile(mf, kid, [mochi], { band: "kitten" });
    const named = await call(mf, kid, "POST", "/v1/rooms", { game: "cat-tower", name: "My Table" });
    expect(named.status).toBe(403);
    expect(await named.json()).toEqual({ error: "not_allowed" });

    const code = await createRoom(mf, kid);
    const c = await connect(mf, code, kid);
    const name = c.last?.room.name;
    c.send({ t: "claim", seat: 0, person: { ...face(mochi), name: "Zoe" } });
    await c.find((m) => m.t === "error");
    expect(errors(c)).toEqual(["bad_name"]);
    c.send({ t: "claim", seat: 0, person: face(mochi) });
    await c.until((s) => s.room.seats[0]?.person?.name === "Mochi");
    c.send({ t: "rename", name: "My Table" });
    c.send({ t: "renameSeat", seat: 0, name: "Zoe" });
    await eventually(() => errors(c), (l) => l.length === 3);
    expect(errors(c)).toEqual(["bad_name", "not_allowed", "bad_name"]);
    // Another roll of the dice is fine.
    c.send({ t: "renameSeat", seat: 0, name: "Pickle" });
    await c.until((s) => s.room.seats[0]?.person?.name === "Pickle");
    expect(c.last?.room.name).toBe(name);
  });
});

describe("reports", { timeout: 30_000 }, () => {
  test("a player at the table reports another; the owner reads it with the key", async () => {
    const mf = await start();
    const { phone, tablet, jd, mia, ids, code, name } = await twoAtTable(mf);
    const before = Date.now();
    expect((await call(mf, phone, "POST", `/v1/rooms/${code}/reports`, { person: mia.id, reason: "name" })).status).toBe(204);
    // Again changes nothing; another reason is another report.
    expect((await call(mf, phone, "POST", `/v1/rooms/${code}/reports`, { person: mia.id, reason: "name" })).status).toBe(204);
    expect((await call(mf, tablet, "POST", `/v1/rooms/${code}/reports`, { person: jd.id.toUpperCase(), reason: "bothering" })).status).toBe(204);

    const res = await ownerList(mf, KEY);
    expect(res.status).toBe(200);
    const { reports } = (await res.json()) as { reports: Report[] };
    expect(reports).toHaveLength(2);
    expect(reports[0]).toMatchObject({
      id: 1,
      reason: "name",
      code,
      table: name,
      name: "Mia",
      person: mia.id,
      player: ids[mia.id],
      device: tablet.deviceId,
      byPlayer: ids[jd.id],
      byDevice: phone.deviceId,
    });
    expect(reports[0]?.at).toBeGreaterThanOrEqual(before);
    expect(reports[1]).toMatchObject({ reason: "bothering", name: "JD", byDevice: tablet.deviceId });
    const later = (await (await ownerList(mf, KEY, 1)).json()) as { reports: Report[] };
    expect(later.reports.map((r) => r.id)).toEqual([reports[1]?.id]);
    expect((await ownerList(mf, KEY, -1)).status).toBe(400);
  });

  test("only from the table, only someone else, only a listed reason, and only so many", async () => {
    const mf = await start();
    const { phone, jd, mia, code } = await twoAtTable(mf);
    const stranger = await mint(mf);
    expect((await call(mf, stranger, "POST", `/v1/rooms/${code}/reports`, { person: mia.id, reason: "name" })).status).toBe(404);
    expect((await call(mf, phone, "POST", `/v1/rooms/${code}/reports`, { person: jd.id, reason: "name" })).status).toBe(404);
    expect((await call(mf, phone, "POST", `/v1/rooms/${code}/reports`, { person: crypto.randomUUID(), reason: "name" })).status).toBe(404);
    expect((await call(mf, phone, "POST", "/v1/rooms/BBBBB/reports", { person: mia.id, reason: "name" })).status).toBe(404);
    expect((await call(mf, phone, "POST", `/v1/rooms/${code}/reports`, { person: mia.id, reason: "she is mean" })).status).toBe(400);
    expect((await call(mf, phone, "POST", `/v1/rooms/${code}/reports`, { person: mia.id, reason: "name", text: "hi" })).status).toBe(400);
    const statuses: number[] = [];
    for (let i = 0; i < 6; i++) {
      statuses.push((await call(mf, phone, "POST", `/v1/rooms/${code}/reports`, { person: mia.id, reason: i % 2 ? "other" : "bothering" })).status);
    }
    expect(statuses).toEqual([204, 204, 204, 204, 204, 429]);
  });

  test("without the key, or with a wrong one, there is no such page", async () => {
    const mf = await start();
    expect((await ownerList(mf, null)).status).toBe(404);
    expect((await ownerList(mf, "nope")).status).toBe(404);
    const device = await mint(mf);
    expect((await ownerList(mf, device.token)).status).toBe(404);
    const unset = await start({ key: false });
    expect((await ownerList(unset, KEY)).status).toBe(404);
    expect((await ownerList(unset, "")).status).toBe(404);
  });
});

describe("blocks", { timeout: 60_000 }, () => {
  const block = (mf: Miniflare, d: Device, me: Person, code: string, who: Person) =>
    call(mf, d, "POST", `/v1/rooms/${code}/blocks?person=${me.id}`, { person: who.id });
  const blocks = async (mf: Miniflare, d: Device, me: Person) =>
    ((await (await call(mf, d, "GET", `/v1/me/blocks?person=${me.id}`)).json()) as { blocks: { id: string; person: string; name: string }[] }).blocks;

  test("block and unblock: listed by person, and a blocked player can't sit at a table you host", async () => {
    const mf = await start();
    const { phone, tablet, jd, mia, ids, code } = await twoAtTable(mf);
    expect((await block(mf, phone, jd, code, jd)).status).toBe(404);
    const res = await block(mf, phone, jd, code, mia);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ id: ids[mia.id] });
    expect(await blocks(mf, phone, jd)).toMatchObject([{ id: ids[mia.id], person: mia.id, name: "Mia" }]);
    expect(await blocks(mf, tablet, mia)).toEqual([]);

    // JD's next table: Mia gets in the door but not into a seat. A third person does.
    const next = await createRoom(mf, phone);
    const host = await connect(mf, next, phone);
    host.send({ t: "claim", seat: 0, person: face(jd) });
    await host.until((s) => s.room.seats[0]?.kind === "human");
    const guest = await connect(mf, next, tablet);
    guest.send({ t: "claim", seat: 1, person: face(mia) });
    await guest.find((m) => m.t === "error");
    expect(errors(guest)).toEqual(["blocked"]);
    expect(host.last?.room.seats[1]?.kind).toBe("open");

    // A table Mia hosts is hers: JD may still join it.
    const hers = await createRoom(mf, tablet);
    const there = await connect(mf, hers, phone);
    there.send({ t: "claim", seat: 0, person: face(jd) });
    await there.until((s) => s.room.seats[0]?.kind === "human");

    expect((await call(mf, phone, "DELETE", `/v1/me/blocks/${ids[mia.id] as string}?person=${jd.id}`)).status).toBe(204);
    expect(await blocks(mf, phone, jd)).toEqual([]);
    guest.send({ t: "claim", seat: 1, person: face(mia) });
    await guest.until((s) => s.room.seats[1]?.kind === "human");
  });

  test("a blocked player's pounce is dropped: sent as far as they can tell, never delivered", async () => {
    const mf = await start();
    const { phone, tablet, jd, mia, code, clients } = await twoAtTable(mf);
    await takeTurn(clients);
    await takeTurn(clients);
    const a = clients[0] as Client;
    const streak = await a.find<Extract<ServerMessage, { t: "streak" }>>((m) => m.t === "streak");
    expect((await block(mf, tablet, mia, code, jd)).status).toBe(200);
    sent.length = 0;
    const res = await call(mf, phone, "POST", `/v1/pounces?person=${jd.id}`, { to: streak.pair, target: "new" });
    expect(res.status).toBe(201);
    await settle(400);
    expect(alertsTo(MIA_TOKEN, "pounce")).toEqual([]);
    const mine = (await (await call(mf, tablet, "GET", `/v1/me/streaks?person=${mia.id}`)).json()) as { pairs: { pounce: { waiting: unknown } }[] };
    expect(mine.pairs[0]?.pounce.waiting).toBeNull();
  });

  test("a blocked player's nudge is dropped: no in-app nudge, no push", async () => {
    const mf = await start();
    const { phone, tablet, jd, mia, code, clients } = await twoAtTable(mf);
    const turn = (clients[0] as Client).game().turn;
    const [target, sender] = turn === 0 ? [clients[0] as Client, clients[1] as Client] : [clients[1] as Client, clients[0] as Client];
    // Whoever holds the move blocks the other.
    const [blocker, blockerPerson, other] = turn === 0 ? [phone, jd, mia] : [tablet, mia, jd];
    expect((await block(mf, blocker, blockerPerson, code, other)).status).toBe(200);
    target.away();
    await settle(NUDGE_AFTER_MS / SPEED + 150);
    sent.length = 0;
    sender.send({ t: "nudge", seat: turn });
    await sender.find((m) => m.t === "nudgeSent");
    await settle(400);
    expect(target.received.some((m) => m.t === "nudged")).toBe(false);
    expect(sent.filter((s) => s.body.kind === "nudge")).toEqual([]);
  });
});

describe("joining by code", { timeout: 60_000 }, () => {
  test("wrong codes are counted per device: five free, then a lockout that doubles, for right codes too", async () => {
    const mf = await start();
    const host = await mint(mf);
    const real = await createRoom(mf, host);
    const guesser = await mint(mf);
    const own = await createRoom(mf, guesser);
    const wrong = ["BBBBB", "CCCCC", "DDDDD", "FFFFF", "GGGGG", "HHHHH"].filter((c) => c !== real && c !== own);
    const statuses: number[] = [];
    for (const code of wrong) statuses.push((await open_(mf, code, guesser)).status);
    expect(statuses).toEqual([404, 404, 404, 404, 404, 404]);

    // The sixth miss locked the device out: a wrong code and a right one look the same.
    const locked = await open_(mf, "JJJJJ", guesser);
    expect(locked.status).toBe(429);
    const body = (await locked.json()) as { error: string; retryAfter: number };
    expect(body.error).toBe("too_many_attempts");
    expect(body.retryAfter).toBeGreaterThan(0);
    expect(body.retryAfter).toBeLessThanOrEqual(30);
    expect(locked.headers.get("retry-after")).toBe(String(body.retryAfter));
    expect((await open_(mf, real, guesser)).status).toBe(429);

    // Tables the device is already at still open, and nobody else is locked out.
    const mine = await open_(mf, own, guesser);
    expect(mine.status).toBe(101);
    (mine.webSocket as unknown as WebSocket & { accept(): void }).accept();
    const friend = await mint(mf);
    const joined = await open_(mf, real, friend, "198.51.100.8");
    expect(joined.status).toBe(101);
    (joined.webSocket as unknown as WebSocket & { accept(): void }).accept();
  });

  test("wrong codes are counted per address too, across devices", async () => {
    const mf = await start();
    const ip = "203.0.113.50";
    const codes = "BCDFGHJKLMNPQRTVWXZ2".split("").map((ch) => ch.repeat(5));
    // Twenty free misses for an address, four from each of five devices (under each device's own five).
    const devices = await Promise.all(Array.from({ length: 6 }, () => mint(mf)));
    const statuses: number[] = [];
    for (const [i, code] of codes.entries()) statuses.push((await open_(mf, code, devices[Math.floor(i / 4)] as Device, ip)).status);
    expect(new Set(statuses)).toEqual(new Set([404]));
    expect((await open_(mf, "33333", devices[5] as Device, ip)).status).toBe(404);
    // The twenty-first miss locked the address: a fresh device there is refused, one elsewhere is not.
    const fresh = await mint(mf);
    expect((await open_(mf, "44444", fresh, ip)).status).toBe(429);
    expect((await open_(mf, "44444", fresh, "203.0.113.51")).status).toBe(404);
  });

  test("minting devices is limited per address, in storage that outlives an isolate", async () => {
    const mf = await start();
    const statuses: number[] = [];
    for (let i = 0; i < 11; i++) {
      const res = await mf.dispatchFetch(`${BASE}/v1/devices`, { method: "POST", headers: { "cf-connecting-ip": "203.0.113.99" } });
      statuses.push(res.status);
    }
    expect(statuses).toEqual([...Array.from({ length: 10 }, () => 200), 429]);
  });
});

describe("the invite page's look at a table (/j/<code>)", { timeout: 60_000 }, () => {
  const page = (mf: Miniflare, code: string, ip = "198.51.100.20") =>
    mf.dispatchFetch(`${BASE}/j/${code}`, { headers: { "cf-connecting-ip": ip } }) as unknown as Promise<Response>;

  /** A lobby with `person` in the host's seat. */
  async function lobby(mf: Miniflare, device: Device, person: Person): Promise<{ code: string; name: string }> {
    const code = await createRoom(mf, device);
    const c = await connect(mf, code, device);
    c.send({ t: "claim", seat: 0, person: face(person) });
    const s = await c.until((m) => m.room.seats[0]?.person?.name === person.name);
    c.ws.close();
    return { code, name: s.room.name as string };
  }

  test("names who saved the seat, the game and the table", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const jd = newPerson("JD", 1);
    await profile(mf, phone, [jd]);
    const { code, name } = await lobby(mf, phone, jd);
    const res = await page(mf, code);
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("no-store");
    const html = await res.text();
    expect(html).toContain("<h1>JD saved you a seat</h1>");
    expect(html).toContain('<p class="game cat-tower">Cat Tower</p>');
    expect(html).toContain(`<p class="table">${name}</p>`);
    expect(html).toContain(`<meta property="og:title" content="JD saved you a seat">`);
    expect(html).toContain(`<strong>${code}</strong>`);
  });

  test("a code with no table is the expired page, and counts as a wrong guess", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const jd = newPerson("JD", 1);
    await profile(mf, phone, [jd]);
    const { code } = await lobby(mf, phone, jd);
    const ip = "198.51.100.21";
    const unknown = await page(mf, "BCDFG", ip);
    expect(unknown.status).toBe(404);
    expect(await unknown.text()).toContain("This invite has expired");
    // 20 wrong guesses an hour are free; the next locks the address out.
    for (let i = 0; i < 20; i++) await (await page(mf, "BCDFG", ip)).arrayBuffer();
    // Locked out: every code, real or not, gets the same page, naming nobody.
    const real = await (await page(mf, code, ip)).text();
    const none = await page(mf, "BCDFH", ip);
    expect(none.status).toBe(200);
    expect(real).toContain("<h1>Come play Pounce</h1>");
    expect(real).not.toContain("JD saved");
    expect(real).not.toContain('class="game');
    expect(real.replaceAll(code, "BCDFH")).toBe(await none.text());
    // Another address still sees the table.
    expect(await (await page(mf, code, "198.51.100.22")).text()).toContain("JD saved you a seat");
  });

  test("a real table is never a wrong guess", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const jd = newPerson("JD", 1);
    await profile(mf, phone, [jd]);
    const { code } = await lobby(mf, phone, jd);
    for (let i = 0; i < 25; i++) await (await page(mf, code, "198.51.100.23")).arrayBuffer();
    expect(await (await page(mf, code, "198.51.100.23")).text()).toContain("JD saved you a seat");
  });

  test("a kitten's table names nobody and keeps its name", async () => {
    const mf = await start();
    const kid = await mint(mf);
    const mochi = newPerson("Mochi", 3);
    await profile(mf, kid, [mochi], { band: "kitten" });
    const { code, name } = await lobby(mf, kid, mochi);
    const html = await (await page(mf, code)).text();
    expect(html).toContain("<h1>Come play Pounce</h1>");
    expect(html).toContain('<p class="game cat-tower">Cat Tower</p>');
    expect(html).not.toContain("Mochi");
    expect(html).not.toContain(name);
  });
});
