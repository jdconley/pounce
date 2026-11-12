import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { BASE, bundle, call, connect, eventually, mint, newPerson, profile, settle, tokenOf, worker, type Client, type Device, type Person, type Sent, type Snapshot } from "./play-helpers";

import type { TableEntry } from "../src/room/tables";
import type { TilesView } from "../src/tiles/view";
import type { Miniflare } from "miniflare";

/*
 * What a device's app says it can draw (`X-Pounce-Games`), how the server hears it, and what
 * that costs. The Worker's own calls to a device's index are counted by `games-entry.ts`.
 */

const NEW_APP = { "x-pounce-games": "cat-tower,tiles" };
const OLD_APP = {};
const JD_TOKEN = tokenOf(1);
const MIA_TOKEN = tokenOf(2);

let script = "";
let sent: Sent[] = [];
const open: Miniflare[] = [];

beforeAll(async () => {
  script = await bundle("./games-entry.ts");
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
  sent = [];
});

async function start(): Promise<Miniflare> {
  const mf = await worker(script, { sent, devSpeed: 100, games: "tiles" });
  open.push(mf);
  return mf;
}

type Call = { method: string; args: unknown[] };

/** The Worker's calls to device indexes since the last look, and a clean slate. */
async function deviceCalls(mf: Miniflare): Promise<Call[]> {
  return (await (await mf.dispatchFetch(`${BASE}/__test/device-calls`)).json()) as Call[];
}

const alertsTo = (token: string, kind?: string) =>
  sent.filter((s) => s.token === token && s.headers["apns-push-type"] === "alert" && (kind === undefined || s.body.kind === kind));

async function tablesOf(mf: Miniflare, device: Device, headers: Record<string, string>): Promise<TableEntry[]> {
  const res = await call(mf, device, "GET", "/v1/devices/me/tables", undefined, headers);
  expect(res.status).toBe(200);
  return ((await res.json()) as { tables: TableEntry[] }).tables;
}

async function upgrade(mf: Miniflare, code: string, device: Device, headers: Record<string, string>): Promise<number> {
  const res = await mf.dispatchFetch(`${BASE}/v1/rooms/${code}/ws`, { headers: { authorization: `Bearer ${device.token}`, upgrade: "websocket", ...headers } });
  if (res.status === 101) (res.webSocket as unknown as { accept(): void; close(): void }).accept();
  return res.status;
}

/** JD and Mia, each on a newer phone, at a started tile game table. */
async function tilesTable(mf: Miniflare) {
  const jdPhone = await mint(mf);
  const miaPhone = await mint(mf);
  const jd = newPerson("JD", 1);
  const mia = newPerson("Mia", 2);
  await profile(mf, jdPhone, [jd], { apns: JD_TOKEN });
  await profile(mf, miaPhone, [mia], { apns: MIA_TOKEN });
  const code = ((await (await call(mf, jdPhone, "POST", "/v1/rooms", { game: "tiles" }, NEW_APP)).json()) as { code: string }).code;
  const clients: Client[] = [];
  for (const [i, [device, person]] of ([[jdPhone, jd], [miaPhone, mia]] as [Device, Person][]).entries()) {
    const c = await connect(mf, code, device, NEW_APP);
    c.send({ t: "claim", seat: i, person: { id: person.id, name: person.name, cat: person.cat } });
    await c.until((s) => s.room.seats[i]?.kind === "human");
    clients.push(c);
  }
  const host = clients[0] as Client;
  for (const seat of [2, 3]) host.send({ t: "configure", seat, kind: "closed" });
  host.send({ t: "start" });
  for (const c of clients) await c.until((s) => s.room.tiles !== undefined);
  return { code, clients, jdPhone, miaPhone };
}

const tilesOf = (c: Client): TilesView => (c.last as Snapshot).room.tiles as TilesView;

/** `seat` draws once the move is theirs: a whole turn. */
async function draw(clients: Client[], seat: number): Promise<void> {
  const c = clients[seat] as Client;
  await c.until((s) => s.room.tiles?.turn === seat);
  const turns = tilesOf(c).turns;
  c.send({ t: "act", seat, action: { type: "draw" } });
  for (const other of clients) await other.until((s) => (s.room.tiles?.turns ?? 0) > turns);
}

describe("hearing what an app can draw costs no call of its own", { timeout: 30_000 }, () => {
  test("the tables fetch makes the same two calls with the header as without, and says what it heard in the first", async () => {
    const mf = await start();
    const phone = await mint(mf);
    await deviceCalls(mf);
    await tablesOf(mf, phone, OLD_APP);
    const without = await deviceCalls(mf);
    await tablesOf(mf, phone, NEW_APP);
    const withHeader = await deviceCalls(mf);
    expect(without.map((c) => c.method)).toEqual(["players", "listTables"]);
    expect(withHeader.map((c) => c.method)).toEqual(["players", "listTables"]);
    // What the app listed rides on the call that was always made: nothing for an app that sent no header.
    expect(without[0]?.args).toEqual([[]]);
    expect(withHeader[0]?.args).toEqual([["tiles"]]);
  });

  test("opening a socket makes the same one call with the header as without", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const code = ((await (await call(mf, phone, "POST", "/v1/rooms", { game: "cat-tower" })).json()) as { code: string }).code;
    await deviceCalls(mf);
    expect(await upgrade(mf, code, phone, OLD_APP)).toBe(101);
    const without = await deviceCalls(mf);
    expect(await upgrade(mf, code, phone, NEW_APP)).toBe(101);
    const withHeader = await deviceCalls(mf);
    expect(without).toEqual([{ method: "players", args: [[]] }]);
    expect(withHeader).toEqual([{ method: "players", args: [["tiles"]] }]);
  });

  test("creating a table asks the device's index nothing about games, whichever the game", async () => {
    const mf = await start();
    const phone = await mint(mf);
    await deviceCalls(mf);
    expect((await call(mf, phone, "POST", "/v1/rooms", { game: "tiles" }, NEW_APP)).status).toBe(201);
    const tiles = await deviceCalls(mf);
    expect((await call(mf, phone, "POST", "/v1/rooms", { game: "cat-tower" }, OLD_APP)).status).toBe(201);
    const tower = await deviceCalls(mf);
    // Both make only the call a new table always made (its creator's last look).
    expect(tiles.map((c) => c.method)).toEqual(tower.map((c) => c.method));
    expect(tiles.every((c) => c.args.length === 0)).toBe(true);
    // And a refusal asks nothing at all.
    expect((await call(mf, phone, "POST", "/v1/rooms", { game: "tiles" }, OLD_APP)).status).toBe(400);
    expect(await deviceCalls(mf)).toEqual([]);
  });

  test("the answer follows the request's own header, whatever the device said before", async () => {
    const mf = await start();
    const { code, miaPhone } = await tilesTable(mf);
    await eventually(() => tablesOf(mf, miaPhone, NEW_APP), (l) => l.some((t) => t.code === code));
    // The same device, asked without the header and then with it again: each answer is by that request alone.
    expect((await tablesOf(mf, miaPhone, OLD_APP)).some((t) => t.code === code)).toBe(false);
    expect((await tablesOf(mf, miaPhone, NEW_APP)).some((t) => t.code === code)).toBe(true);
    expect((await tablesOf(mf, miaPhone, { "x-pounce-games": "chess" })).some((t) => t.code === code)).toBe(false);
  });
});

describe("a device that stops sending the header", { timeout: 60_000 }, () => {
  /** JD draws while Mia is away, so the move (and its push) comes to her. */
  async function moveToMia(mf: Miniflare) {
    const t = await tilesTable(mf);
    if (tilesOf(t.clients[0] as Client).turn === 1) await draw(t.clients, 1);
    (t.clients[1] as Client).away();
    await settle(100);
    return t;
  }

  test("is pushed its tile game table's moves while it sends it", async () => {
    const mf = await start();
    const { code, clients } = await moveToMia(mf);
    await draw(clients, 0);
    const [push] = await eventually(() => alertsTo(MIA_TOKEN, "your_move"), (l) => l.length === 1);
    expect((push as Sent).body).toMatchObject({ code, kind: "your_move" });
  });

  test("is no longer pushed them once it fetches its tables without it: an older build is back on the device", async () => {
    const mf = await start();
    const { code, clients, miaPhone } = await moveToMia(mf);
    expect(await tablesOf(mf, miaPhone, OLD_APP)).toEqual([]);
    sent.length = 0;
    await draw(clients, 0);
    await settle(500);
    expect(alertsTo(MIA_TOKEN)).toEqual([]);
    expect(JSON.stringify(sent)).not.toContain(code);
  });

  test("nor once it opens a socket without it, to any table", async () => {
    const mf = await start();
    const { clients, jdPhone, miaPhone } = await moveToMia(mf);
    const tower = ((await (await call(mf, jdPhone, "POST", "/v1/rooms", { game: "cat-tower" })).json()) as { code: string }).code;
    expect(await upgrade(mf, tower, miaPhone, OLD_APP)).toBe(101);
    sent.length = 0;
    await draw(clients, 0);
    await settle(500);
    expect(alertsTo(MIA_TOKEN)).toEqual([]);
  });

  test("and is pushed them again as soon as it sends the header again", async () => {
    const mf = await start();
    const { code, clients, miaPhone } = await moveToMia(mf);
    await tablesOf(mf, miaPhone, OLD_APP);
    await tablesOf(mf, miaPhone, NEW_APP);
    sent.length = 0;
    await draw(clients, 0);
    const [push] = await eventually(() => alertsTo(MIA_TOKEN, "your_move"), (l) => l.length === 1);
    expect((push as Sent).body).toMatchObject({ code });
  });

  test("a request that says nothing about the app (its push token, its profile) changes nothing", async () => {
    const mf = await start();
    const { code, clients, miaPhone } = await moveToMia(mf);
    expect((await call(mf, miaPhone, "PUT", "/v1/devices/me/push", { apnsToken: MIA_TOKEN })).status).toBe(204);
    sent.length = 0;
    await draw(clients, 0);
    const [push] = await eventually(() => alertsTo(MIA_TOKEN, "your_move"), (l) => l.length === 1);
    expect((push as Sent).body).toMatchObject({ code });
  });
});
