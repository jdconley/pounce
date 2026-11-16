import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { BASE, bundle, call, Client, connect, createRoom, eventually, mint, newPerson, profile, settle, worker, type Device, type Person } from "./play-helpers";

import type { ServerMessage } from "../src/protocol";
import type { Miniflare } from "miniflare";

/** Pounce on the TV through the Worker and the room's Durable Object (`TV` on): the screen role, a TV's table, the aim relay. */
let script = "";
const open: Miniflare[] = [];

beforeAll(async () => {
  script = await bundle("../src/index.ts");
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
});

async function start(options: { tv?: boolean; devSpeed?: number; games?: string } = {}): Promise<Miniflare> {
  const mf = await worker(script, { sent: [], tv: options.tv ?? true, ...(options.devSpeed ? { devSpeed: options.devSpeed } : {}), ...(options.games ? { games: options.games } : {}) });
  open.push(mf);
  return mf;
}

/** What an app that can draw Tiles says. */
const TILES = { "x-pounce-games": "tiles" };

const face = (p: Person) => ({ id: p.id, name: p.name, cat: p.cat });

/** The TV makes a table. */
async function tvTable(mf: Miniflare, tv: Device, game = "cat-tower"): Promise<string> {
  const res = await call(mf, tv, "POST", "/v1/rooms", { game, screen: true }, game === "tiles" ? TILES : {});
  expect(res.status).toBe(201);
  return ((await res.json()) as { code: string }).code;
}

/** An upgrade, with whatever query and headers; the response, unaccepted. */
function upgrade(mf: Miniflare, code: string, device: Device, query = "", headers: Record<string, string> = {}) {
  return mf.dispatchFetch(`${BASE}/v1/rooms/${code}/ws${query}`, { headers: { authorization: `Bearer ${device.token}`, upgrade: "websocket", ...headers } });
}

/** A device's socket as a screen. */
async function asScreen(mf: Miniflare, code: string, device: Device, headers: Record<string, string> = {}): Promise<Client> {
  const res = await upgrade(mf, code, device, "?role=screen", headers);
  expect(res.status).toBe(101);
  const ws = res.webSocket as unknown as WebSocket & { accept(): void };
  ws.accept();
  const client = new Client(ws);
  await client.until(() => true);
  return client;
}

async function sit(mf: Miniflare, code: string, device: Device, seat: number, who: Person, headers: Record<string, string> = {}): Promise<Client> {
  const c = await connect(mf, code, device, headers);
  c.send({ t: "claim", seat, person: face(who) });
  await c.until((s) => s.room.seats[seat]?.kind === "human");
  return c;
}

const errors = (c: Client) => c.received.flatMap((m) => (m.t === "error" ? [m.code] : []));
const aims = (c: Client) => c.received.filter((m): m is Extract<ServerMessage, { t: "aim" }> => m.t === "aim");

describe("a TV through the Worker", { timeout: 30_000 }, () => {
  test("a TV makes a table, connects as its screen, and the first phone to sit hosts it", async () => {
    const mf = await start();
    const [tv, a] = [await mint(mf), await mint(mf)];
    const code = await tvTable(mf, tv);
    const screen = await asScreen(mf, code, tv);
    expect(screen.last?.room.youAreHost).toBeFalsy();
    expect(screen.last?.room.screen).toBe(true);

    const phone = await connect(mf, code, a);
    expect(phone.last?.room.screen).toBe(true);
    expect(phone.last?.room.youAreHost).toBeFalsy();
    const alice = newPerson("Alice", 1);
    phone.send({ t: "claim", seat: 0, person: face(alice) });
    await phone.until((s) => s.room.seats[0]?.kind === "human" && s.room.youAreHost);

    screen.send({ t: "claim", seat: 1, person: face(newPerson("Tom", 2)) });
    await screen.find((m) => m.t === "error");
    expect(errors(screen)).toEqual(["not_allowed"]);
  });

  test("a TV table's invite page names nobody until someone sits", async () => {
    const mf = await start();
    const [tv, a] = [await mint(mf), await mint(mf)];
    const code = await tvTable(mf, tv);
    const screen = await asScreen(mf, code, tv);
    const name = screen.last?.room.name as string;
    const page = async () => (await mf.dispatchFetch(`${BASE}/j/${code}`)).text();
    const res = await mf.dispatchFetch(`${BASE}/j/${code}`);
    expect(res.status).toBe(200);
    const before = await res.text();
    // The table is shown (not the hidden fallback), and nobody is named.
    expect(before).toContain(name);
    expect(before).not.toContain("wants to play");
    expect(before).not.toContain("Alice");
    await sit(mf, code, a, 0, newPerson("Alice", 1));
    expect(await page()).toContain("Alice");
  });

  test("a seated phone can't open the same table as a screen", async () => {
    const mf = await start();
    const [tv, a, b] = [await mint(mf), await mint(mf), await mint(mf)];
    const code = await tvTable(mf, tv);
    await sit(mf, code, a, 0, newPerson("Alice", 1));
    const res = await upgrade(mf, code, a, "?role=screen");
    expect(res.status).toBe(409);
    expect(await res.json()).toEqual({ error: "seated" });
    // Someone who only watched can still become the screen.
    expect((await upgrade(mf, code, b, "?role=screen")).status).toBe(101);
  });

  test("a browser screen says role in the query", async () => {
    const mf = await start({ games: "tiles" });
    const [tv, a] = [await mint(mf), await mint(mf)];
    const code = await tvTable(mf, tv, "tiles");
    await sit(mf, code, a, 0, newPerson("Alice", 1), TILES);
    const browser = (device: Device, query: string) =>
      mf.dispatchFetch(`${BASE}/v1/rooms/${code}/ws?${query}`, { headers: { upgrade: "websocket", "sec-websocket-protocol": `pounce, pounce.token.${device.token}` } });
    const listen = async (device: Device, query: string) => {
      const res = await browser(device, query);
      expect(res.status).toBe(101);
      const ws = res.webSocket as unknown as WebSocket & { accept(): void };
      const messages: ServerMessage[] = [];
      const closed = new Promise<number>((resolve) => ws.addEventListener("close", (e) => resolve(e.code)));
      ws.addEventListener("message", (e) => messages.push(JSON.parse(e.data as string) as ServerMessage));
      ws.accept();
      return { messages, closed };
    };
    const screen = await listen(tv, "role=screen&games=tiles");
    const snap = await eventually(() => screen.messages.find((m) => m.t === "snapshot"), (m) => m !== undefined);
    expect(snap?.t === "snapshot" && snap.room.screen).toBe(true);
    // The role is only the query's: a seated phone is refused, readably.
    expect(await (await listen(a, "role=screen&games=tiles")).closed).toBe(4409);
  });

  test("the TV is in nobody's tables list", async () => {
    const mf = await start();
    const [tv, a] = [await mint(mf), await mint(mf)];
    const code = await tvTable(mf, tv);
    await asScreen(mf, code, tv);
    await sit(mf, code, a, 0, newPerson("Alice", 1));
    const list = async (d: Device) => ((await (await call(mf, d, "GET", "/v1/devices/me/tables")).json()) as { tables: { code: string }[] }).tables;
    expect((await eventually(() => list(a), (t) => t.length > 0)).map((t) => t.code)).toEqual([code]);
    await settle();
    expect(await list(tv)).toEqual([]);
  });

  test("the phones see screen go 10 seconds after the TV leaves", { timeout: 25_000 }, async () => {
    const mf = await start();
    const [tv, a] = [await mint(mf), await mint(mf)];
    const code = await tvTable(mf, tv);
    const screen = await asScreen(mf, code, tv);
    const phone = await sit(mf, code, a, 0, newPerson("Alice", 1));
    expect(phone.last?.room.screen).toBe(true);
    screen.ws.close();
    await settle(1500);
    expect(phone.last?.room.screen).toBe(true);
    await phone.until((s) => s.room.screen === undefined, 15_000);
  });

  test("aim reaches the TV and stays out of storage", async () => {
    const mf = await start({ games: "tiles" });
    const [tv, a, b] = [await mint(mf), await mint(mf), await mint(mf)];
    const code = await tvTable(mf, tv, "tiles");
    const screen = await asScreen(mf, code, tv, TILES);
    const pa = await sit(mf, code, a, 0, newPerson("Alice", 1), TILES);
    const pb = await sit(mf, code, b, 1, newPerson("Bob", 2), TILES);
    pa.send({ t: "start" });
    await pa.until((s) => s.room.status === "playing");
    const seat = (pa.last?.room.tiles as { turn: number }).turn;
    const [mover, other] = seat === 0 ? [pa, pb] : [pb, pa];
    mover.send({ t: "aim", seat, aim: { table: [] } });
    const heard = await screen.find<Extract<ServerMessage, { t: "aim" }>>((m) => m.t === "aim");
    expect(heard).toEqual({ t: "aim", seat, aim: { table: [] } });
    await other.find((m) => m.t === "aim");
    expect(aims(mover)).toEqual([]);
    // Nothing is kept: a phone that comes back hears no aim.
    const again = await connect(mf, code, seat === 0 ? b : a, TILES);
    await settle();
    expect(aims(again)).toEqual([]);
  });

  test("play again takes the TV along", async () => {
    const mf = await start();
    const [tv, a, b] = [await mint(mf), await mint(mf), await mint(mf)];
    const [alice, bob] = [newPerson("Alice", 1), newPerson("Bob", 2)];
    const code = await tvTable(mf, tv);
    const screen = await asScreen(mf, code, tv);
    const pa = await sit(mf, code, a, 0, alice);
    const pb = await sit(mf, code, b, 1, bob);
    pa.send({ t: "start" });
    await pa.until((s) => s.room.status === "playing");
    // Bob gives up: the game is over.
    pb.send({ t: "act", seat: 1, action: { type: "forfeit" } });
    await pa.until((s) => s.room.status === "over");
    pa.send({ t: "rematch" });
    const told = await screen.find<Extract<ServerMessage, { t: "rematch" }>>((m) => m.t === "rematch");
    // The TV comes in with no role of its own: the new room already lists it as a screen.
    const next = await connect(mf, told.code, tv);
    expect(next.last?.room.screen).toBe(true);
    expect(next.last?.room.status).toBe("playing");
    next.send({ t: "claim", seat: 0, person: face(newPerson("Tom", 3)) });
    await next.find((m) => m.t === "error");
    expect(errors(next)).toEqual(["not_allowed"]);
    // The one who asked hosts the new table.
    const asker = await connect(mf, told.code, a);
    expect(asker.last?.room.youAreHost).toBe(true);
  });

  test("with TV off, role=screen is refused and screen:true rooms are a bad request", async () => {
    const mf = await start({ tv: false });
    const [tv, a] = [await mint(mf), await mint(mf)];
    expect((await call(mf, tv, "POST", "/v1/rooms", { game: "cat-tower", screen: true })).status).toBe(400);
    const code = ((await (await call(mf, a, "POST", "/v1/rooms", { game: "cat-tower" })).json()) as { code: string }).code;
    expect((await upgrade(mf, code, tv, "?role=screen")).status).toBe(404);
    // A plain socket is as it was.
    expect((await upgrade(mf, code, tv)).status).toBe(101);
  });

  test("a client's own role header is never believed", async () => {
    const mf = await start();
    const [tv, a] = [await mint(mf), await mint(mf)];
    const code = await tvTable(mf, tv);
    const res = await upgrade(mf, code, a, "", { "x-play-role": "screen" });
    expect(res.status).toBe(101);
    const ws = res.webSocket as unknown as WebSocket & { accept(): void };
    ws.accept();
    const c = new Client(ws);
    await c.until(() => true);
    c.send({ t: "claim", seat: 0, person: face(newPerson("Alice", 1)) });
    await c.until((s) => s.room.seats[0]?.kind === "human");
  });

  test("screen: true takes no name", async () => {
    const mf = await start();
    const tv = await mint(mf);
    expect((await call(mf, tv, "POST", "/v1/rooms", { game: "cat-tower", screen: true, name: "Taco Night" })).status).toBe(400);
    expect((await call(mf, tv, "POST", "/v1/rooms", { game: "cat-tower", screen: "yes" })).status).toBe(400);
  });

  test("blocks still hold at a TV table", async () => {
    const mf = await start();
    const [tv, a, b] = [await mint(mf), await mint(mf), await mint(mf)];
    const [alice, bob] = [newPerson("Alice", 1), newPerson("Bob", 2)];
    await profile(mf, a, [alice]);
    await profile(mf, b, [bob]);
    const code = await tvTable(mf, tv);
    await asScreen(mf, code, tv);
    const pa = await sit(mf, code, a, 0, alice);
    const pb = await sit(mf, code, b, 1, bob);
    expect((await call(mf, a, "POST", `/v1/rooms/${code}/blocks?person=${alice.id}`, { person: bob.id })).status).toBe(200);
    pb.send({ t: "leave", seat: 1 });
    await pb.until((s) => s.room.seats[1]?.kind === "open");
    pb.send({ t: "claim", seat: 1, person: face(bob) });
    await pb.find((m) => m.t === "error");
    expect(errors(pb)).toEqual(["blocked"]);
    expect(pa.last?.room.seats[1]?.kind).toBe("open");
  });
});

type Link = { token: string; code: string; url: string; expiresIn: number };
type Heard = { t: "linked"; room: string } | { t: "expired" } | { t: "pong" };

/** The TV asks for a link. */
async function newLink(mf: Miniflare, tv: Device, body: Record<string, unknown> = {}): Promise<Link> {
  const res = await call(mf, tv, "POST", "/v1/screens", body);
  expect(res.status).toBe(201);
  return (await res.json()) as Link;
}

/** A link's waiting socket, as the app opens it (or, with `browser`, as a browser does). */
function waitUpgrade(mf: Miniflare, token: string, device: Device, browser = false) {
  const headers: Record<string, string> = browser
    ? { upgrade: "websocket", "sec-websocket-protocol": `pounce, pounce.token.${device.token}` }
    : { authorization: `Bearer ${device.token}`, upgrade: "websocket" };
  return mf.dispatchFetch(`${BASE}/v1/screens/${token}/ws`, { headers });
}

/** The TV waits on its link: every message it hears, and the close code once it closes. */
async function waitOn(mf: Miniflare, token: string, device: Device, browser = false) {
  const res = await waitUpgrade(mf, token, device, browser);
  expect(res.status).toBe(101);
  const ws = res.webSocket as unknown as WebSocket & { accept(): void };
  const heard: Heard[] = [];
  const closed = new Promise<number>((resolve) => ws.addEventListener("close", (e) => resolve(e.code)));
  ws.addEventListener("message", (e) => heard.push(JSON.parse(e.data as string) as Heard));
  ws.accept();
  return { ws, heard, closed, protocol: res.headers.get("sec-websocket-protocol") };
}

/** A phone links a table to a TV. */
const linkTv = (mf: Miniflare, phone: Device, body: Record<string, unknown>) => call(mf, phone, "POST", "/v1/screens/link", body);

const linkedTo = (heard: Heard[], room: string) => eventually(() => heard.some((m) => m.t === "linked" && m.room === room), (ok) => ok);

/** A phone at its own table, seated. */
async function seated(mf: Miniflare, phone: Device, name = "Alice"): Promise<{ code: string; client: Client }> {
  const code = await createRoom(mf, phone);
  const client = await sit(mf, code, phone, 0, newPerson(name, 1));
  return { code, client };
}

describe("screen links through the Worker", { timeout: 30_000 }, () => {
  test("a phone links its table to a TV by the QR token", async () => {
    const mf = await start();
    const [tv, a] = [await mint(mf), await mint(mf)];
    const link = await newLink(mf, tv);
    expect(link.expiresIn).toBe(600_000);
    expect(link.url).toBe(`${BASE}/tv/${link.token}`);
    expect(link.token).toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect(link.code).toMatch(/^[BCDFGHJKLMNPQRTVWXZ2346789]{6}$/);
    const waiting = await waitOn(mf, link.token, tv);
    // The socket answers pings like a table's, so a link meter works.
    waiting.ws.send(JSON.stringify({ t: "ping" }));
    expect(await linkedTo(waiting.heard, "never")).toBe(false);
    expect(waiting.heard).toContainEqual({ t: "pong" });

    const { code, client: phone } = await seated(mf, a);
    expect(phone.last?.room.screen).toBeUndefined();
    const res = await linkTv(mf, a, { token: link.token, room: code });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ linked: true });
    expect(await linkedTo(waiting.heard, code)).toBe(true);

    // The room already lists the TV: it opens the table as its screen.
    const screen = await asScreen(mf, code, tv);
    expect(screen.last?.room.screen).toBe(true);
    expect(screen.last?.room.youAreHost).toBeFalsy();
    await phone.until((s) => s.room.screen === true);

    // A socket that connects after the link is told at once.
    const late = await waitOn(mf, link.token, tv);
    expect(await linkedTo(late.heard, code)).toBe(true);
  });

  test("and by the backup code, in any case", async () => {
    const mf = await start();
    const [tv, a] = [await mint(mf), await mint(mf)];
    const link = await newLink(mf, tv);
    const waiting = await waitOn(mf, link.token, tv);
    const { code } = await seated(mf, a);
    const res = await linkTv(mf, a, { code: link.code.toLowerCase(), room: code });
    expect(res.status).toBe(200);
    expect(await linkedTo(waiting.heard, code)).toBe(true);
    expect((await connect(mf, code, tv)).last?.room.screen).toBe(true);
  });

  test("a link is spent once used", async () => {
    const mf = await start();
    const [tv, a, b] = [await mint(mf), await mint(mf), await mint(mf)];
    const link = await newLink(mf, tv);
    const { code } = await seated(mf, a);
    expect((await linkTv(mf, a, { token: link.token, room: code })).status).toBe(200);
    const again = await linkTv(mf, a, { token: link.token, room: code });
    expect(again.status).toBe(404);
    expect(await again.json()).toEqual({ error: "not_found" });
    // Nor by its code, nor from another table.
    const other = await seated(mf, b, "Bob");
    expect((await linkTv(mf, b, { code: link.code, room: other.code, move: true })).status).toBe(404);
  });

  test("a link expires after ten minutes and a new one replaces it", { timeout: 30_000 }, async () => {
    const mf = await start({ devSpeed: 100 });
    const [tv, a] = [await mint(mf), await mint(mf)];
    const link = await newLink(mf, tv);
    // The TV renews on the clock it is given.
    expect(link.expiresIn).toBe(6_000);
    const waiting = await waitOn(mf, link.token, tv);
    // Miniflare only delivers a close from alarm() to a hibernatable socket that has sent a frame.
    waiting.ws.send(JSON.stringify({ t: "ping" }));
    const { code } = await seated(mf, a);
    expect(await Promise.race([waiting.closed, settle(12_000).then(() => -1)])).toBe(1000);
    expect(waiting.heard).toContainEqual({ t: "expired" });
    expect((await linkTv(mf, a, { token: link.token, room: code })).status).toBe(404);
    expect((await linkTv(mf, a, { code: link.code, room: code })).status).toBe(404);
    // An expired link can't be waited on either.
    expect((await waitUpgrade(mf, link.token, tv)).status).toBe(404);

    const fresh = await newLink(mf, tv);
    const next = await waitOn(mf, fresh.token, tv);
    expect((await linkTv(mf, a, { code: fresh.code, room: code })).status).toBe(200);
    expect(await linkedTo(next.heard, code)).toBe(true);
  });

  test("two phones racing for one link: one wins", async () => {
    const mf = await start();
    const [tv, a, b] = [await mint(mf), await mint(mf), await mint(mf)];
    const link = await newLink(mf, tv);
    const waiting = await waitOn(mf, link.token, tv);
    const x = await seated(mf, a);
    const y = await seated(mf, b, "Bob");
    const statuses = (await Promise.all([linkTv(mf, a, { token: link.token, room: x.code }), linkTv(mf, b, { token: link.token, room: y.code })])).map((r) => r.status);
    expect([...statuses].sort()).toEqual([200, 404]);
    const winner = statuses[0] === 200 ? x.code : y.code;
    expect(await linkedTo(waiting.heard, winner)).toBe(true);
    await settle();
    expect(waiting.heard.filter((m) => m.t === "linked")).toEqual([{ t: "linked", room: winner }]);
  });

  test("a device makes at most 30 links in ten minutes", { timeout: 60_000 }, async () => {
    const mf = await start();
    const tv = await mint(mf);
    for (let i = 0; i < 30; i++) await newLink(mf, tv);
    const res = await call(mf, tv, "POST", "/v1/screens", {});
    expect(res.status).toBe(429);
    expect(await res.json()).toEqual({ error: "rate_limited" });
    // Another device at the same address still can.
    expect((await call(mf, await mint(mf), "POST", "/v1/screens", {})).status).toBe(201);
  });

  test("only a phone at the table may link it", async () => {
    const mf = await start();
    const [tv, a, watcher] = [await mint(mf), await mint(mf), await mint(mf)];
    const link = await newLink(mf, tv);
    const { code } = await seated(mf, a);
    // Connected, but in no seat.
    await connect(mf, code, watcher);
    const res = await linkTv(mf, watcher, { token: link.token, room: code });
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: "not_seated" });
    // A table that doesn't exist says the same, so the route tells nobody what exists.
    const missing = ["BBBBB", "CCCCC"].find((c) => c !== code) as string;
    const none = await linkTv(mf, a, { token: link.token, room: missing });
    expect(none.status).toBe(403);
    expect(await none.json()).toEqual({ error: "not_seated" });
    // The link is still good for the phone that is seated.
    expect((await linkTv(mf, a, { token: link.token, room: code })).status).toBe(200);
  });

  test("a phone can't make its own table's screen out of a seated device", async () => {
    const mf = await start();
    const a = await mint(mf);
    const { code } = await seated(mf, a);
    // The same device asks for a link (a second browser tab) and links its own table.
    const link = await newLink(mf, a);
    const res = await linkTv(mf, a, { token: link.token, room: code });
    expect(res.status).toBe(409);
    expect(await res.json()).toEqual({ error: "seated" });
  });

  test("wrong codes back off like room codes", { timeout: 60_000 }, async () => {
    const mf = await start();
    const [tv, a, host] = [await mint(mf), await mint(mf), await mint(mf)];
    const link = await newLink(mf, tv);
    const { code } = await seated(mf, a);
    const wrong = ["BBBBBB", "CCCCCC", "DDDDDD", "FFFFFF", "GGGGGG", "HHHHHH", "JJJJJJ"].filter((c) => c !== link.code).slice(0, 6);
    const statuses: number[] = [];
    for (const guess of wrong) statuses.push((await linkTv(mf, a, { code: guess, room: code })).status);
    // Five misses are free, and the sixth starts the lockout, as for room codes.
    expect(statuses).toEqual([404, 404, 404, 404, 404, 404]);
    const locked = await linkTv(mf, a, { code: "KKKKKK", room: code });
    expect(locked.status).toBe(429);
    const body = (await locked.json()) as { error: string; retryAfter: number };
    expect(body.error).toBe("too_many_attempts");
    expect(body.retryAfter).toBeGreaterThan(0);
    expect(locked.headers.get("retry-after")).toBe(String(body.retryAfter));
    // Locked out, the right code looks the same as a wrong one.
    expect((await linkTv(mf, a, { code: link.code, room: code })).status).toBe(429);
    // Joining a table by its code is counted apart.
    const other = await createRoom(mf, host);
    expect((await upgrade(mf, other, a)).status).toBe(101);
  });

  test("moving a TV that shows another table needs move", async () => {
    const mf = await start();
    const [tv, a, b] = [await mint(mf), await mint(mf), await mint(mf)];
    const x = await seated(mf, a);
    const y = await seated(mf, b, "Bob");
    const link = await newLink(mf, tv, { showing: x.code });
    const waiting = await waitOn(mf, link.token, tv);
    // A phone at the table the TV shows: nothing to do.
    expect((await linkTv(mf, a, { token: link.token, room: x.code })).status).toBe(200);
    await settle();
    expect(waiting.heard.filter((m) => m.t === "linked")).toEqual([]);
    const refused = await linkTv(mf, b, { token: link.token, room: y.code });
    expect(refused.status).toBe(409);
    expect(await refused.json()).toEqual({ error: "showing" });
    expect((await linkTv(mf, b, { token: link.token, room: y.code, move: true })).status).toBe(200);
    expect(await linkedTo(waiting.heard, y.code)).toBe(true);
  });

  test("only the TV that made a link may wait on it", async () => {
    const mf = await start();
    const [tv, a] = [await mint(mf), await mint(mf)];
    const link = await newLink(mf, tv);
    const res = await waitUpgrade(mf, link.token, a);
    expect(res.status).toBe(404);
    expect((await waitUpgrade(mf, "A".repeat(22), tv)).status).toBe(404);
    expect((await waitUpgrade(mf, "short", tv)).status).toBe(404);
    // A plain GET is told to upgrade.
    expect((await call(mf, tv, "GET", `/v1/screens/${link.token}/ws`)).status).toBe(426);
    // A browser waits the same way, and is refused readably.
    const browser = await waitOn(mf, link.token, tv, true);
    expect(browser.protocol).toBe("pounce");
    const stranger = await waitUpgrade(mf, link.token, a, true);
    const ws = stranger.webSocket as unknown as WebSocket & { accept(): void };
    const closed = new Promise<number>((resolve) => ws.addEventListener("close", (e) => resolve(e.code)));
    ws.accept();
    expect(await closed).toBe(4404);
    const { code } = await seated(mf, a);
    expect((await linkTv(mf, a, { token: link.token, room: code })).status).toBe(200);
    expect(await linkedTo(browser.heard, code)).toBe(true);
  });

  test("a link asks for a well-formed body", async () => {
    const mf = await start();
    const [tv, a] = [await mint(mf), await mint(mf)];
    expect((await call(mf, tv, "POST", "/v1/screens", { showing: "bcdfg" })).status).toBe(400);
    expect((await call(mf, tv, "POST", "/v1/screens", { other: 1 })).status).toBe(400);
    const link = await newLink(mf, tv);
    const { code } = await seated(mf, a);
    const bad = await linkTv(mf, a, { token: link.token, code: link.code, room: code });
    expect(bad.status).toBe(400);
    expect(await bad.json()).toEqual({ error: "bad_request" });
    expect((await linkTv(mf, a, { room: code })).status).toBe(400);
    expect((await call(mf, a, "POST", "/v1/screens/link")).status).toBe(400);
  });

  test("/tv/<token> sends a phone without the app to the web player", async () => {
    const mf = await start();
    const tv = await mint(mf);
    const link = await newLink(mf, tv);
    const res = await mf.dispatchFetch(link.url, { redirect: "manual" });
    expect(res.status).toBe(302);
    expect(res.headers.get("location")).toBe(`${BASE}/play/tv-link/${link.token}`);
    expect((await mf.dispatchFetch(`${BASE}/tv/not-a-token`, { redirect: "manual" })).status).toBe(404);
  });

  test("with TV off every screens route is a 404", async () => {
    const mf = await start({ tv: false });
    const [tv, a] = [await mint(mf), await mint(mf)];
    expect((await call(mf, tv, "POST", "/v1/screens", {})).status).toBe(404);
    const { code } = await seated(mf, a);
    const token = "A".repeat(22);
    expect((await linkTv(mf, a, { token, room: code })).status).toBe(404);
    expect((await waitUpgrade(mf, token, tv)).status).toBe(404);
    expect((await mf.dispatchFetch(`${BASE}/tv/${token}`, { redirect: "manual" })).status).toBe(404);
  });
});
