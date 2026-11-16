import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { BASE, bundle, call, Client, connect, eventually, mint, newPerson, profile, settle, worker, type Device, type Person } from "./play-helpers";

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
    await asScreen(mf, code, tv);
    const page = async () => (await mf.dispatchFetch(`${BASE}/j/${code}`)).text();
    const before = await page();
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
    const next = await asScreen(mf, told.code, tv);
    expect(next.last?.room.screen).toBe(true);
    expect(next.last?.room.status).toBe("playing");
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
