import { Response as MiniflareResponse, type Request as MiniflareRequest } from "miniflare";
import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { BASE, bundle, call, connect, eventually, mint, newPerson, profile, settle, tokenOf, worker, type Client, type Device, type Person, type Sent, type Snapshot } from "./play-helpers";

import type { TilesView } from "../src/tiles/view";
import type { Miniflare } from "miniflare";

/*
 * App updates (docs/superpowers/specs/2026-11-12-app-updates-design.md), against the real Worker.
 *
 * Version 1.0 of the app is in App Review against production and can't be changed. It sends no
 * `X-Pounce-App`. The first suite holds the line that matters most: whatever the update settings
 * say, short of the owner retiring 1.0 on purpose, a request without that header is answered
 * exactly as it was before any of this existed.
 */

const V10 = {};
const V11 = { "x-pounce-app": "platform=ios; version=1.1; build=57; protocol=1" };
const V12 = { "x-pounce-app": "platform=ios; version=1.2; build=80; protocol=1" };
const TILES = { "x-pounce-games": "cat-tower,tiles" };
const V12_TILES = { ...V12, ...TILES };
const STORE = "https://apps.apple.com/app/id6829560061";
const BETA = "https://testflight.apple.com/join/abc";
const JD_TOKEN = tokenOf(1);
const MIA_TOKEN = tokenOf(2);

let script = "";
let sent: Sent[] = [];
const open: Miniflare[] = [];

beforeAll(async () => {
  script = await bundle("./games-entry.ts");
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispatchFetch(`${BASE}/__test/device-calls`).then(() => mf.dispose())));
  sent = [];
});

type Options = Parameters<typeof worker>[1];

async function start(options: Partial<Options> = {}): Promise<Miniflare> {
  const mf = await worker(script, { sent, devSpeed: 100, games: "tiles", ...options });
  open.push(mf);
  return mf;
}

/**
 * A fake Apple lookup that says `version` is live (null: the app isn't listed), and counts what it
 * was asked. `hangMs`: how long it sits on each request before answering.
 */
function apple(version: string | null, hangMs = 0) {
  const asked: { url: string; headers: Record<string, string> }[] = [];
  const lookup = async (request: MiniflareRequest) => {
    asked.push({ url: request.url, headers: Object.fromEntries(request.headers) });
    if (hangMs > 0) await new Promise((resolve) => setTimeout(resolve, hangMs));
    const body = version === null ? { resultCount: 0, results: [] } : { resultCount: 1, results: [{ trackId: 6829560061, version }] };
    return new MiniflareResponse(JSON.stringify(body), { headers: { "content-type": "text/javascript; charset=utf-8" } });
  };
  return { asked, lookup };
}

/**
 * A server on which Apple has said `version` is live, and the Worker has heard it. Nothing waits
 * on Apple, so the first ask only starts the lookup: this asks until the answer is known.
 */
async function startWith(version: string, options: Partial<Options> = {}): Promise<Miniflare> {
  const mf = await start({ lookup: apple(version).lookup, ...options });
  await eventually(async () => (JSON.parse((await ask(mf, "GET", "/v1/app", {})).body) as { latest?: string; minimum?: string }), (b) => b.latest !== undefined || b.minimum !== undefined);
  return mf;
}

type Answer = { status: number; body: string; headers: Record<string, string> };

/** One request, and everything about its answer an app could tell apart. */
async function ask(mf: Miniflare, method: string, path: string, headers: Record<string, string>, body?: unknown): Promise<Answer> {
  const res = await mf.dispatchFetch(`${BASE}${path}`, {
    method,
    headers: { ...(body === undefined ? {} : { "content-type": "application/json" }), ...headers },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  if (res.status === 101) (res.webSocket as unknown as { accept(): void; close(): void }).accept();
  return { status: res.status, body: res.status === 101 ? "" : await res.text(), headers: Object.fromEntries(res.headers) };
}

const as = (device: Device, more: Record<string, string> = {}) => ({ authorization: `Bearer ${device.token}`, ...more });
const socket = (device: Device, more: Record<string, string> = {}) => as(device, { upgrade: "websocket", ...more });

const alertsTo = (token: string, kind?: string) =>
  sent.filter((s) => s.token === token && s.headers["apns-push-type"] === "alert" && (kind === undefined || s.body.kind === kind));

async function deviceCalls(mf: Miniflare): Promise<{ method: string; args: unknown[] }[]> {
  return (await (await mf.dispatchFetch(`${BASE}/__test/device-calls`)).json()) as { method: string; args: unknown[] }[];
}

/** JD and Mia, each on a phone that can draw the tile game, at a started tile game table JD hosts. */
async function tilesTable(mf: Miniflare, app: Record<string, string> = TILES) {
  const jdPhone = await mint(mf);
  const miaPhone = await mint(mf);
  const jd = newPerson("JD", 1);
  const mia = newPerson("Mia", 2);
  const jdPlayers = await profile(mf, jdPhone, [jd], { apns: JD_TOKEN });
  const miaPlayers = await profile(mf, miaPhone, [mia], { apns: MIA_TOKEN });
  const code = ((await (await call(mf, jdPhone, "POST", "/v1/rooms", { game: "tiles" }, app)).json()) as { code: string }).code;
  const clients: Client[] = [];
  for (const [i, [device, person]] of ([[jdPhone, jd], [miaPhone, mia]] as [Device, Person][]).entries()) {
    const c = await connect(mf, code, device, app);
    c.send({ t: "claim", seat: i, person: { id: person.id, name: person.name, cat: person.cat } });
    await c.until((s) => s.room.seats[i]?.kind === "human");
    clients.push(c);
  }
  const host = clients[0] as Client;
  for (const seat of [2, 3]) host.send({ t: "configure", seat, kind: "closed" });
  host.send({ t: "start" });
  for (const c of clients) await c.until((s) => s.room.tiles !== undefined);
  return { code, clients, jdPhone, miaPhone, jd, mia, jdPlayer: jdPlayers[jd.id] as string, miaPlayer: miaPlayers[mia.id] as string };
}

/** A tile game table in its lobby, hosted by JD, who has taken seat 0. */
async function tilesLobby(mf: Miniflare) {
  const jdPhone = await mint(mf);
  const jd = newPerson("JD", 1);
  await profile(mf, jdPhone, [jd], { apns: JD_TOKEN });
  const code = ((await (await call(mf, jdPhone, "POST", "/v1/rooms", { game: "tiles" }, TILES)).json()) as { code: string }).code;
  const host = await connect(mf, code, jdPhone, TILES);
  host.send({ t: "claim", seat: 0, person: { id: jd.id, name: jd.name, cat: jd.cat } });
  await host.until((s) => s.room.seats[0]?.kind === "human");
  return { code, host, jdPhone, jd, name: (host.last as Snapshot).room.name };
}

const tilesOf = (c: Client): TilesView => (c.last as Snapshot).room.tiles as TilesView;

async function draw(clients: Client[], seat: number): Promise<void> {
  const c = clients[seat] as Client;
  await c.until((s) => s.room.tiles?.turn === seat);
  const turns = tilesOf(c).turns;
  c.send({ t: "act", seat, action: { type: "draw" } });
  for (const other of clients) await other.until((s) => (s.room.tiles?.turns ?? 0) > turns);
}

describe("version 1.0 sends no X-Pounce-App, and is answered exactly as before", { timeout: 60_000 }, () => {
  /** A script of requests 1.0 makes, run against a server; the answers, with what differs run to run taken out. */
  async function tour(mf: Miniflare): Promise<Answer[]> {
    const phone = await mint(mf);
    const answers: Answer[] = [];
    const add = async (method: string, path: string, headers: Record<string, string>, body?: unknown) => {
      const a = await ask(mf, method, path, headers, body);
      answers.push(a);
      return a;
    };
    await add("POST", "/v1/devices", { "cf-connecting-ip": "203.0.113.9" });
    await add("GET", "/v1/devices/me/tables", as(phone));
    await add("GET", "/v1/devices/me/tables", {});
    await add("GET", "/v1/me/streaks", as(phone));
    await add("GET", "/v1/me/state", as(phone));
    await add("PUT", "/v1/devices/me/push", as(phone), { apnsToken: MIA_TOKEN });
    await add("POST", "/v1/rooms", as(phone), { game: "tiles" });
    await add("POST", "/v1/rooms", as(phone), { game: "chess" });
    const made = await add("POST", "/v1/rooms", as(phone), { game: "cat-tower" });
    const code = (JSON.parse(made.body) as { code: string }).code;
    await add("GET", `/v1/rooms/${code}/ws`, as(phone));
    await add("GET", `/v1/rooms/${code}/ws`, socket(phone));
    await add("GET", "/v1/rooms/ZZZZZ/ws", socket(phone));
    await add("GET", "/v1/nothing", as(phone));
    const { code: tiles } = await tilesLobby(mf);
    await add("GET", `/v1/rooms/${tiles}/ws`, socket(phone));
    await add("GET", `/j/${tiles}`, {});
    await add("GET", "/healthz", {});
    const scrub = (text: string) => text.replaceAll(code, "CODE1").replaceAll(tiles, "CODE2").replace(/"(deviceId|token)":"[^"]+"/g, '"$1":"…"');
    return answers.map((a) => ({ status: a.status, body: scrub(a.body), headers: Object.fromEntries(Object.entries(a.headers).filter(([k]) => k !== "date" && k !== "sec-websocket-accept")) }));
  }

  test("every answer is the same with every update setting on as with none of them", async () => {
    const before = await tour(await start());
    // Apple says a far newer version is live, and the Worker knows it.
    const after = await tour(await startWith("9.9", { appMinimum: "", appLatest: "9.9" }));
    // A minimum of 1.0 retires nothing: 1.0 is at it.
    const pinned = await tour(await start({ appLatest: "9.9", appMinimum: "1.0" }));
    expect(after).toEqual(before);
    expect(pinned).toEqual(before);
    // And they are the answers this suite thinks they are: the tour did reach every route.
    expect(before.map((a) => a.status)).toEqual([200, 200, 401, 404, 404, 204, 400, 400, 201, 426, 101, 404, 404, 404, 200, 200]);
  });

  test("its tables list is {tables} and nothing else, even with a table it is being left out of", async () => {
    const mf = await startWith("1.2");
    const { code, miaPhone } = await tilesTable(mf);
    await eventually(async () => JSON.parse((await ask(mf, "GET", "/v1/devices/me/tables", as(miaPhone, TILES))).body) as { tables: { code: string }[] }, (b) => b.tables.some((t) => t.code === code));
    const old = await ask(mf, "GET", "/v1/devices/me/tables", as(miaPhone, V10));
    expect(old.status).toBe(200);
    expect(old.body).toBe('{"tables":[]}');
    expect(old.headers["x-pounce-update"]).toBeUndefined();
  });

  test("a table of a game it can't draw is still a bare 404: no body, no new header", async () => {
    const mf = await startWith("1.2");
    const { code } = await tilesLobby(mf);
    const phone = await mint(mf);
    const answer = await ask(mf, "GET", `/v1/rooms/${code}/ws`, socket(phone, V10));
    expect(answer.status).toBe(404);
    expect(answer.body).toBe("");
    expect(Object.keys(answer.headers).filter((k) => k.startsWith("x-pounce"))).toEqual([]);
  });

  test("the Worker makes the same calls to its device's index, with the same arguments", async () => {
    const mf = await startWith("1.2");
    const phone = await mint(mf);
    const code = ((await (await call(mf, phone, "POST", "/v1/rooms", { game: "cat-tower" })).json()) as { code: string }).code;
    await deviceCalls(mf);
    await ask(mf, "GET", "/v1/devices/me/tables", as(phone, V10));
    expect(await deviceCalls(mf)).toEqual([{ method: "players", args: [[]] }, { method: "listTables", args: [] }]);
    await ask(mf, "GET", `/v1/rooms/${code}/ws`, socket(phone, V10));
    expect(await deviceCalls(mf)).toEqual([{ method: "players", args: [[]] }]);
    // An app that says what it is rides on those same calls: one more argument, no more calls.
    await ask(mf, "GET", "/v1/devices/me/tables", as(phone, V11));
    expect(await deviceCalls(mf)).toEqual([{ method: "players", args: [[], "1.1"] }, { method: "listTables", args: [] }]);
    await ask(mf, "GET", `/v1/rooms/${code}/ws`, socket(phone, V11));
    expect(await deviceCalls(mf)).toEqual([{ method: "players", args: [[], "1.1"] }]);
  });

  test("a header nobody can read is no header", async () => {
    const mf = await startWith("1.2");
    const { code } = await tilesLobby(mf);
    const phone = await mint(mf);
    for (const header of ["", "ios", "version=soon", "platform=ios"]) {
      const answer = await ask(mf, "GET", `/v1/rooms/${code}/ws`, { ...socket(phone), "x-pounce-app": header });
      // The bare 404 version 1.0 gets, not the 426 for an app that said what it is.
      expect([answer.status, answer.body]).toEqual([404, ""]);
      expect((await ask(mf, "GET", "/v1/devices/me/tables", { ...as(phone), "x-pounce-app": header })).body).toBe('{"tables":[]}');
    }
  });
});

describe("GET /v1/app says what is current", { timeout: 30_000 }, () => {
  const status = async (mf: Miniflare, headers: Record<string, string> = {}) => {
    const answer = await ask(mf, "GET", "/v1/app", headers);
    expect(answer.status).toBe(200);
    expect(answer.headers["cache-control"]).toBe("no-store");
    return JSON.parse(answer.body) as Record<string, string>;
  };

  test("before the app is on the store: no latest, no minimum, no store link", async () => {
    const { asked, lookup } = apple(null);
    const mf = await start({ lookup, appMinimum: "1.1", appStoreUrl: "" });
    expect(await status(mf)).toEqual({ testflightUrl: BETA });
    await eventually(() => asked, (a) => a.length === 1);
    for (let i = 0; i < 5; i++) expect(await status(mf)).toEqual({ testflightUrl: BETA });
    expect(asked).toHaveLength(1);
  });

  test("when Apple can't be asked: the same nothing", async () => {
    const mf = await start({ appMinimum: "1.1" });
    expect(await status(mf)).toEqual({ testflightUrl: BETA });
  });

  test("once it is: the version Apple says is live, asked once for many requests and with nothing of the asker's", async () => {
    const { asked, lookup } = apple("1.1");
    const mf = await start({ lookup });
    const phone = await mint(mf);
    const who = { ...as(phone, V11), "cf-connecting-ip": "203.0.113.7", cookie: "a=b" };
    await eventually(() => status(mf, who), (b) => b.latest === "1.1");
    for (let i = 0; i < 5; i++) expect(await status(mf, who)).toEqual({ latest: "1.1", storeUrl: STORE, testflightUrl: BETA });
    expect(asked).toHaveLength(1);
    expect(asked[0]?.url).toBe("https://itunes.apple.com/lookup?id=6829560061");
    const said = JSON.stringify(asked[0]?.headers).toLowerCase();
    for (const secret of ["authorization", "bearer", phone.deviceId.toLowerCase(), "x-pounce", "203.0.113.7", "cookie"]) expect(said).not.toContain(secret);
  });

  test("it never waits on Apple: with Apple hanging, a cold server answers at once with what it knows, which is nothing", async () => {
    const { asked, lookup } = apple("1.1", 2500);
    const mf = await start({ lookup, appMinimum: "1.1" });
    const started = Date.now();
    expect(await status(mf)).toEqual({ testflightUrl: BETA });
    expect(Date.now() - started).toBeLessThan(1000);
    // The lookup it started is for whoever asks next.
    await eventually(() => status(mf), (b) => b.latest === "1.1");
    expect(asked).toHaveLength(1);
  });

  test("thirty at once, cold, make one lookup; and so does anyone, credential or not, whatever they claim to be", async () => {
    const { asked, lookup } = apple("1.2", 300);
    const mf = await start({ lookup, appMinimum: "1.2" });
    await Promise.all(Array.from({ length: 30 }, () => status(mf)));
    // No credential, on routes of every kind, claiming a protocol the server never spoke.
    const liar = { "x-pounce-app": "platform=ios; version=0.1; build=1; protocol=0" };
    await Promise.all([
      ...Array.from({ length: 10 }, () => ask(mf, "GET", "/v1/devices/me/tables", liar)),
      ...Array.from({ length: 10 }, () => ask(mf, "POST", "/v1/devices", { ...liar, "cf-connecting-ip": "203.0.113.50" })),
      ...Array.from({ length: 10 }, () => ask(mf, "GET", "/v1/rooms/ZZZZZ/ws", { ...liar, upgrade: "websocket" })),
      ...Array.from({ length: 10 }, () => ask(mf, "GET", "/v1/me/state", {})),
    ]);
    await eventually(() => status(mf), (b) => b.latest === "1.2");
    await Promise.all(Array.from({ length: 30 }, () => status(mf)));
    expect(asked).toHaveLength(1);
  });

  test("APP_LATEST changes what apps are told is newest, and never makes a minimum bite", async () => {
    const mf = await startWith("1.1", { appLatest: "1.3", appMinimum: "1.2" });
    // Apple says 1.1 is live: the minimum of 1.2 can't be met, whatever the override announces.
    expect(await status(mf)).toEqual({ latest: "1.3", storeUrl: STORE, testflightUrl: BETA });
  });

  test("a minimum the store can't meet yet is not said", async () => {
    const mf = await startWith("1.1", { appMinimum: "1.2" });
    expect(await status(mf)).toEqual({ latest: "1.1", storeUrl: STORE, testflightUrl: BETA });
  });

  test("needs no credential, and answers an app that is too old for everything else", async () => {
    const mf = await startWith("1.2", { appMinimum: "1.2" });
    expect(await status(mf, V11)).toMatchObject({ latest: "1.2", minimum: "1.2" });
  });
});

describe("an app that is too old (APP_MINIMUM)", { timeout: 60_000 }, () => {
  const REQUIRED = { error: "update_required", minimum: "1.2", storeUrl: STORE, testflightUrl: BETA };

  test("one that said what it is gets 426 update_required on every API call and socket upgrade", async () => {
    const mf = await startWith("1.2", { appMinimum: "1.2" });
    const phone = await mint(mf);
    const code = ((await (await call(mf, phone, "POST", "/v1/rooms", { game: "cat-tower" })).json()) as { code: string }).code;
    const calls: [string, string, Record<string, string>, unknown?][] = [
      ["POST", "/v1/devices", V11],
      ["GET", "/v1/devices/me/tables", as(phone, V11)],
      ["GET", "/v1/me/streaks", as(phone, V11)],
      ["POST", "/v1/rooms", as(phone, V11), { game: "cat-tower" }],
      ["GET", `/v1/rooms/${code}/ws`, socket(phone, V11)],
      // Whoever it is: the answer doesn't wait on the credential.
      ["GET", "/v1/devices/me/tables", V11],
    ];
    for (const [method, path, headers, body] of calls) {
      const answer = await ask(mf, method, path, headers, body);
      expect(answer.status, `${method} ${path}`).toBe(426);
      expect(JSON.parse(answer.body)).toEqual(REQUIRED);
      expect(answer.headers["x-pounce-update"]).toBe("required");
    }
    // A route that doesn't exist is still a 404, and the public pages are untouched.
    expect((await ask(mf, "GET", "/v1/nothing", as(phone, V11))).status).toBe(404);
    expect((await ask(mf, "GET", `/j/${code}`, V11)).status).toBe(200);
    expect((await ask(mf, "GET", "/healthz", V11)).status).toBe(200);
  });

  test("one at the minimum, or above it, is served", async () => {
    const mf = await startWith("1.3", { appMinimum: "1.2" });
    const phone = await mint(mf);
    for (const app of [V12, { "x-pounce-app": "platform=ios; version=1.2.0; build=1; protocol=1" }, { "x-pounce-app": "platform=ios; version=1.10; build=1; protocol=1" }]) {
      expect((await ask(mf, "GET", "/v1/devices/me/tables", as(phone, app))).status).toBe(200);
    }
  });

  test("nobody is turned away for a version the App Store doesn't have yet", async () => {
    const servers = [
      // Apple says 1.1 is the newest.
      () => startWith("1.1", { appMinimum: "1.2" }),
      // Nobody knows what Apple has.
      () => start({ appMinimum: "1.2" }),
      // APP_LATEST announces 1.2, but that is the server's word, not Apple's: it locks nobody out.
      () => start({ appLatest: "1.2", appMinimum: "1.2" }),
      () => startWith("1.1", { appLatest: "1.2", appMinimum: "1.2" }),
    ];
    for (const make of servers) {
      const mf = await make();
      const phone = await mint(mf);
      const code = ((await (await call(mf, phone, "POST", "/v1/rooms", { game: "cat-tower" })).json()) as { code: string }).code;
      expect((await ask(mf, "GET", "/v1/devices/me/tables", as(phone, V11))).status).toBe(200);
      expect((await ask(mf, "GET", `/v1/rooms/${code}/ws`, socket(phone, V11))).status).toBe(101);
      expect((await ask(mf, "GET", `/v1/rooms/${code}/ws`, socket(phone, V10))).status).toBe(101);
    }
  });

  test("APP_MINIMUM_FORCE is the one way to enforce a minimum without Apple's word", async () => {
    const mf = await start({ appMinimum: "1.2", appMinimumForce: "on" });
    const phone = await mint(mf);
    const answer = await ask(mf, "GET", "/v1/devices/me/tables", as(phone, V11));
    expect(answer.status).toBe(426);
    expect(JSON.parse(answer.body)).toEqual({ error: "update_required", minimum: "1.2", storeUrl: STORE, testflightUrl: BETA });
    expect((await ask(mf, "GET", "/v1/devices/me/tables", as(phone, V12))).status).toBe(200);
  });

  test("with a minimum set and Apple hanging, no request waits: it is served as if there were none", async () => {
    const { asked, lookup } = apple("1.2", 2500);
    const mf = await start({ lookup, appMinimum: "1.2" });
    const phone = await mint(mf);
    const code = ((await (await call(mf, phone, "POST", "/v1/rooms", { game: "cat-tower" })).json()) as { code: string }).code;
    const requests: [string, string, Record<string, string>][] = [
      ["GET", "/v1/devices/me/tables", as(phone, V10)],
      ["GET", "/v1/devices/me/tables", as(phone, V11)],
      ["GET", "/v1/me/state", as(phone, V10)],
      ["GET", `/v1/rooms/${code}/ws`, socket(phone, V10)],
      ["GET", `/v1/rooms/${code}/ws`, socket(phone, V11)],
    ];
    for (const [method, path, headers] of requests) {
      const started = Date.now();
      const answer = await ask(mf, method, path, headers);
      expect(Date.now() - started, `${method} ${path}`).toBeLessThan(1000);
      expect(answer.status, `${method} ${path}`).not.toBe(426);
    }
    // One lookup went out behind them; once it lands, the minimum is enforced.
    await eventually(() => ask(mf, "GET", "/v1/devices/me/tables", as(phone, V11)), (a) => a.status === 426);
    expect(asked).toHaveLength(1);
  });

  test("an app that is too old can still delete its account and sign out, and nothing else", async () => {
    const mf = await startWith("1.2", { appMinimum: "1.2" });
    const phone = await mint(mf);
    const mia = newPerson("Mia", 2);
    // (Set up as a current app would have, before the minimum caught up with this one.)
    await call(mf, phone, "PUT", "/v1/devices/me/profile", { timeZone: "America/Los_Angeles", ageBand: "adult", people: [mia] }, V12);
    const refused: [string, string, unknown?][] = [
      ["GET", "/v1/me/state"],
      ["PATCH", "/v1/me/state", {}],
      ["GET", "/v1/me/streaks"],
      ["GET", "/v1/me/blocks"],
      ["POST", "/v1/me/identities/apple", {}],
      ["DELETE", "/v1/me/identities/apple"],
      ["POST", "/v1/identities/apple", {}],
      ["PUT", "/v1/devices/me/profile", {}],
      ["PUT", "/v1/devices/me/push", {}],
      ["GET", "/v1/devices/me/tables"],
      ["POST", "/v1/rooms", { game: "cat-tower" }],
      ["POST", "/v1/names/check", {}],
      ["POST", "/v1/devices"],
      // The exempt paths, by any other method.
      ["GET", "/v1/me"],
      ["POST", "/v1/me"],
      ["DELETE", "/v1/me/signout"],
      ["DELETE", "/v1/me/state"],
    ];
    for (const [method, path, body] of refused) {
      const answer = await ask(mf, method, `${path}?person=${mia.id}`, as(phone, V11), body);
      // 426 for a route there is; 404 for one there isn't. Never an answer from the route itself.
      expect([426, 404], `${method} ${path}`).toContain(answer.status);
      if (answer.status === 404) expect(answer.body).toBe('{"error":"not_found"}');
    }
    expect((await ask(mf, "GET", "/v1/me/state", as(phone, V11))).status).toBe(426);
    // Signing out and deleting the account go through to the routes themselves.
    const out = await ask(mf, "POST", "/v1/me/signout", as(phone, V11));
    expect([out.status, out.headers["x-pounce-update"]]).toEqual([204, undefined]);
    const gone = await ask(mf, "DELETE", `/v1/me?person=${mia.id}`, as(phone, V11));
    expect([gone.status, gone.headers["x-pounce-update"]]).toEqual([204, undefined]);
    // The player really is gone: a current app asking for it finds none.
    expect((await ask(mf, "GET", `/v1/me/state?person=${mia.id}`, as(phone, V12))).status).toBe(404);
    // And they still need a credential like anything else.
    expect((await ask(mf, "DELETE", "/v1/me", V11)).status).toBe(401);
    expect((await ask(mf, "POST", "/v1/me/signout", V11)).status).toBe(401);
  });

  test("version 1.0, once the minimum is above it: its API calls are answered as ever, and a table tells it to update", async () => {
    const mf = await startWith("1.1", { appMinimum: "1.1" });
    const phone = await mint(mf);
    expect((await ask(mf, "GET", "/v1/devices/me/tables", as(phone, V10))).body).toBe('{"tables":[]}');
    const made = await ask(mf, "POST", "/v1/rooms", as(phone, V10), { game: "cat-tower" });
    expect(made.status).toBe(201);
    const code = (JSON.parse(made.body) as { code: string }).code;
    // The socket opens, says one thing 1.0 answers with its own "Update the app to play" card, and closes.
    for (const table of [code, "ZZZZZ"]) {
      const res = await mf.dispatchFetch(`${BASE}/v1/rooms/${table}/ws`, { headers: socket(phone, V10) });
      expect(res.status).toBe(101);
      const ws = res.webSocket as unknown as WebSocket & { accept(): void };
      const frames: string[] = [];
      const closed = new Promise<number>((resolve) => ws.addEventListener("close", (e) => resolve(e.code)));
      ws.addEventListener("message", (e) => frames.push(e.data as string));
      ws.accept();
      expect(await closed).toBe(1000);
      expect(frames).toEqual(['{"t":"snapshot","protocol":0}']);
    }
    // Without a credential it is still nobody.
    expect((await ask(mf, "GET", `/v1/rooms/${code}/ws`, { upgrade: "websocket" })).status).toBe(401);
    // And asking for the socket without upgrading is the 426 it always was, which is not this one.
    const plain = await ask(mf, "GET", `/v1/rooms/${code}/ws`, as(phone, V10));
    expect([plain.status, plain.body, plain.headers["x-pounce-update"]]).toEqual([426, '{"error":"upgrade_required"}', undefined]);
  });
});

describe("a table whose game the app can't draw", { timeout: 60_000 }, () => {
  test("an app that said what it is is told which game, in the body and in headers", async () => {
    const mf = await start();
    const { code } = await tilesLobby(mf);
    const phone = await mint(mf);
    const answer = await ask(mf, "GET", `/v1/rooms/${code}/ws`, socket(phone, V11));
    expect(answer.status).toBe(426);
    expect(JSON.parse(answer.body)).toEqual({ error: "game_unsupported", game: "tiles", title: "Tuna Tiles" });
    expect(answer.headers).toMatchObject({ "x-pounce-update": "game", "x-pounce-game": "tiles", "x-pounce-game-title": "Tuna%20Tiles" });
    // The same app, once it can draw the game, sits down; and a table that isn't there is still not there.
    expect((await ask(mf, "GET", `/v1/rooms/${code}/ws`, socket(phone, V12_TILES))).status).toBe(101);
    expect((await ask(mf, "GET", "/v1/rooms/ZZZZZ/ws", socket(phone, V11))).status).toBe(404);
  });

  test("its tables list shows the table locked, beside the tables it can open, and never among them", async () => {
    const mf = await start();
    const { code, miaPhone, clients } = await tilesTable(mf);
    type Body = { tables: { code: string }[]; locked?: Record<string, unknown>[] };
    const list = async (headers: Record<string, string>) => JSON.parse((await ask(mf, "GET", "/v1/devices/me/tables", as(miaPhone, headers))).body) as Body;
    await eventually(() => list(V12_TILES), (b) => b.tables.some((t) => t.code === code));
    const behind = await list(V11);
    expect(behind.tables).toEqual([]);
    expect(behind.locked).toHaveLength(1);
    expect(behind.locked?.[0]).toMatchObject({ code, game: "tiles", title: "Tuna Tiles", name: (clients[0]?.last as Snapshot).room.name });
    expect(Object.keys(behind.locked?.[0] ?? {}).sort()).toEqual(["code", "game", "name", "seats", "title", "updatedAt"]);
    // An app that can draw it has nothing locked, and no such key.
    const current = await list(V12_TILES);
    expect(current.tables.map((t) => t.code)).toEqual([code]);
    expect("locked" in current).toBe(false);
  });
});

describe("the update push, for a device whose app can't draw the table", { timeout: 90_000 }, () => {
  /** Mia on a phone with version 1.0: a profile, a push token, and no headers at all. */
  async function oldPhone(mf: Miniflare, options: { band?: string } = {}) {
    const phone = await mint(mf);
    const mia = newPerson("Mia", 2);
    const players = await profile(mf, phone, [mia], { apns: MIA_TOKEN, ...options });
    return { phone, mia, player: players[mia.id] as string };
  }

  test("version 1.0 opening a tile game table is told there is none, and pushed who asked and what to do", async () => {
    const mf = await startWith("1.2");
    const { code, name } = await tilesLobby(mf);
    const { phone } = await oldPhone(mf);
    expect((await ask(mf, "GET", `/v1/rooms/${code}/ws`, socket(phone, V10))).status).toBe(404);
    const [push] = await eventually(() => alertsTo(MIA_TOKEN), (l) => l.length === 1);
    // Quiet in the recipient's quiet hours (22:00 to 08:00 unless they chose others), like any push that isn't a reminder.
    const level = ((push as Sent).body.aps as Record<string, unknown>)["interruption-level"];
    expect(["active", "passive"]).toContain(level);
    expect((push as Sent).body).toEqual({
      aps: {
        alert: { title: name, body: "JD wants to play Tuna Tiles. Update Pounce to join." },
        ...(level === "active" ? { sound: "default" } : {}),
        "thread-id": `update:${code}`,
        category: "STATUS",
        "interruption-level": level,
        "relevance-score": 0.9,
      },
      kind: "update",
      from: { name: "JD", cat: 1 },
      update: { code, game: "tiles" },
    });
    expect((push as Sent).headers["apns-collapse-id"]).toBe(`update:${code}`);
    // Once per table: trying again, and again, sends nothing more.
    for (let i = 0; i < 3; i++) await ask(mf, "GET", `/v1/rooms/${code}/ws`, socket(phone, V10));
    await settle(400);
    expect(alertsTo(MIA_TOKEN)).toHaveLength(1);
  });

  test("another table within 20 minutes sends nothing more", async () => {
    const mf = await startWith("1.2");
    const first = await tilesLobby(mf);
    const second = await tilesLobby(mf);
    const { phone } = await oldPhone(mf);
    await ask(mf, "GET", `/v1/rooms/${first.code}/ws`, socket(phone, V10));
    await eventually(() => alertsTo(MIA_TOKEN), (l) => l.length === 1);
    await ask(mf, "GET", `/v1/rooms/${second.code}/ws`, socket(phone, V10));
    await settle(400);
    expect(alertsTo(MIA_TOKEN)).toHaveLength(1);
  });

  test.each([
    ["the App Store has nothing newer than 1.0", () => startWith("1.0"), {}],
    ["nobody knows what the App Store has", () => start(), {}],
    ["only APP_LATEST says there is something newer, not Apple", () => start({ appLatest: "1.2" }), {}],
    ["the device is a kitten's", () => startWith("1.2"), { band: "kitten" }],
  ])("nothing is pushed when %s", async (_, server, device) => {
    const mf = await server();
    const { code } = await tilesLobby(mf);
    const { phone } = await oldPhone(mf, device);
    expect((await ask(mf, "GET", `/v1/rooms/${code}/ws`, socket(phone, V10))).status).toBe(404);
    await settle(500);
    expect(alertsTo(MIA_TOKEN)).toEqual([]);
  });

  test("nothing is pushed between people who blocked each other", async () => {
    const mf = await startWith("1.2");
    const table = await tilesTable(mf);
    const { phone, mia } = await oldPhone(mf);
    // Mia, at a Cat Tower table with JD, blocks him there.
    const tower = ((await (await call(mf, phone, "POST", "/v1/rooms", { game: "cat-tower" })).json()) as { code: string }).code;
    const hers = await connect(mf, tower, phone);
    hers.send({ t: "claim", seat: 0, person: { id: mia.id, name: mia.name, cat: mia.cat } });
    const his = await connect(mf, tower, table.jdPhone, TILES);
    his.send({ t: "claim", seat: 1, person: { id: table.jd.id, name: table.jd.name, cat: table.jd.cat } });
    await hers.until((s) => s.room.seats[1]?.kind === "human");
    expect((await call(mf, phone, "POST", `/v1/rooms/${tower}/blocks?person=${mia.id}`, { person: table.jd.id })).status).toBeLessThan(300);
    sent.length = 0;
    expect((await ask(mf, "GET", `/v1/rooms/${table.code}/ws`, socket(phone, V10))).status).toBe(404);
    await settle(500);
    expect(alertsTo(MIA_TOKEN, "update")).toEqual([]);
  });

  test("an app that said what it is gets its answer in the app, not a push", async () => {
    const mf = await startWith("1.2");
    const { code } = await tilesLobby(mf);
    const { phone } = await oldPhone(mf);
    expect((await ask(mf, "GET", `/v1/rooms/${code}/ws`, socket(phone, V11))).status).toBe(426);
    await settle(500);
    expect(alertsTo(MIA_TOKEN)).toEqual([]);
  });

  test("a move at a tile game table reaches a seat's older device as the update push, once, in place of 'your move'", async () => {
    const mf = await startWith("1.2");
    const { code, clients, miaPhone } = await tilesTable(mf);
    if (tilesOf(clients[0] as Client).turn === 1) await draw(clients, 1);
    (clients[1] as Client).away();
    await settle(100);
    // An older build is back on Mia's phone: it fetches its tables with no header at all.
    expect((await ask(mf, "GET", "/v1/devices/me/tables", as(miaPhone, V10))).body).toBe('{"tables":[]}');
    sent.length = 0;
    await draw(clients, 0);
    const [push] = await eventually(() => alertsTo(MIA_TOKEN), (l) => l.length === 1);
    expect((push as Sent).body).toMatchObject({ kind: "update", from: { name: "JD", cat: 1 }, update: { code, game: "tiles" } });
    expect(((push as Sent).body.aps as { alert: { title: string; body: string } }).alert).toEqual({ title: "Mia", body: "JD wants to play Tuna Tiles. Update Pounce to join." });
    expect("code" in (push as Sent).body).toBe(false);
    // The next moves say nothing more.
    await draw(clients, 1);
    await draw(clients, 0);
    await settle(500);
    expect(alertsTo(MIA_TOKEN)).toHaveLength(1);
  });

  test("nor to a device whose app is already the newest there is", async () => {
    const mf = await startWith("1.1");
    const { clients, miaPhone } = await tilesTable(mf);
    if (tilesOf(clients[0] as Client).turn === 1) await draw(clients, 1);
    (clients[1] as Client).away();
    await settle(100);
    // Version 1.1, which can't draw the tile game, and nothing newer on the store.
    await ask(mf, "GET", "/v1/devices/me/tables", as(miaPhone, V11));
    sent.length = 0;
    await draw(clients, 0);
    await settle(500);
    expect(alertsTo(MIA_TOKEN)).toEqual([]);
  });

  test("a held push never waits on Apple: with Apple hanging, the move and the table go on at once", async () => {
    const { asked, lookup } = apple("1.2", 2500);
    const mf = await start({ lookup });
    const { clients, miaPhone } = await tilesTable(mf);
    if (tilesOf(clients[0] as Client).turn === 1) await draw(clients, 1);
    (clients[1] as Client).away();
    await settle(100);
    await ask(mf, "GET", "/v1/devices/me/tables", as(miaPhone, V10));
    const started = Date.now();
    // JD moves (its push to Mia's older phone is held), Mia answers, JD moves again.
    await draw(clients, 0);
    await draw(clients, 1);
    await draw(clients, 0);
    expect(Date.now() - started).toBeLessThan(1500);
    // Apple was asked once, behind all of it; nothing was known yet, so nothing was said.
    await eventually(() => asked, (a) => a.length === 1);
    expect(alertsTo(MIA_TOKEN, "update")).toEqual([]);
  });
});
