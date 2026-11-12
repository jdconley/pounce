import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join as joinPath } from "node:path";

import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { chooseAction } from "../src/bots/house-cat-tiles";
import { slotAt } from "../src/notify/schedule";
import { createRng } from "../src/rules/rng";
import { addDays, dayKey } from "../src/streaks/clock";
import { readSet } from "../src/tiles/sets";

import {
  appleProof,
  BASE,
  bundle,
  call,
  Client,
  connect,
  eventually,
  LA,
  mint,
  newPerson,
  profile,
  settle,
  table,
  takeTurn,
  tokenOf,
  worker,
  type Device,
  type Person,
  type Sent,
  type Snapshot,
} from "./play-helpers";
import { seedOf } from "./seeds";

import type { ServerMessage } from "../src/protocol";
import type { TableEntry } from "../src/room/tables";
import type { TilesView } from "../src/tiles/view";
import type { Miniflare } from "miniflare";

/* The tile game through the real Worker and room sockets, and what an app that can't draw it is kept from. */

/** What an app that can draw the tile game sends with every request. */
const NEW_APP = { "x-pounce-games": "cat-tower,tiles" };
/** An app from before there was a second game sends no such header. */
const OLD_APP = {};
const JD_TOKEN = tokenOf(1);
const MIA_TOKEN = tokenOf(2);
const PAD_TOKEN = tokenOf(3);

let script = "";
let sent: Sent[] = [];
const open: Miniflare[] = [];
const dirs: string[] = [];

beforeAll(async () => {
  script = await bundle("./notify-entry.ts");
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
  sent = [];
});

/**
 * The Worker with the tile game on (`GAMES=tiles`) unless `games` says otherwise, at the dev
 * server's top speed. `persist`: a directory its rooms are kept in, so a second Worker can load them.
 */
async function start(games: string | null = "tiles", persist?: string): Promise<Miniflare> {
  const mf = await worker(script, { sent, devSpeed: 100, ...(games === null ? {} : { games }), ...(persist ? { persist } : {}) });
  open.push(mf);
  return mf;
}

const alertsTo = (token: string, kind?: string) =>
  sent.filter((s) => s.token === token && s.headers["apns-push-type"] === "alert" && (kind === undefined || s.body.kind === kind));

const tilesOf = (c: Client): TilesView => (c.last as Snapshot).room.tiles as TilesView;

async function create(mf: Miniflare, device: Device, game: unknown, headers: Record<string, string>): Promise<Response> {
  return call(mf, device, "POST", "/v1/rooms", { game }, headers);
}

async function tilesRoom(mf: Miniflare, host: Device): Promise<string> {
  const res = await create(mf, host, "tiles", NEW_APP);
  expect(res.status).toBe(201);
  return ((await res.json()) as { code: string }).code;
}

/** The status a socket upgrade gets. */
async function join(mf: Miniflare, code: string, device: Device, headers: Record<string, string>): Promise<number> {
  const res = await mf.dispatchFetch(`${BASE}/v1/rooms/${code}/ws`, {
    headers: { authorization: `Bearer ${device.token}`, upgrade: "websocket", ...headers },
  });
  return res.status;
}

async function tablesOf(mf: Miniflare, device: Device, headers: Record<string, string>): Promise<TableEntry[]> {
  const res = await call(mf, device, "GET", "/v1/devices/me/tables", undefined, headers);
  return ((await res.json()) as { tables: TableEntry[] }).tables;
}

/** A started tile game: seat i is the i-th person on the i-th device, every one a new app. */
async function tilesTable(mf: Miniflare, seats: [Device, Person][], bots = 0): Promise<{ code: string; clients: Client[] }> {
  const code = await tilesRoom(mf, (seats[0] as [Device, Person])[0]);
  const clients: Client[] = [];
  for (const [i, [device, person]] of seats.entries()) {
    const c = await connect(mf, code, device, NEW_APP);
    c.send({ t: "claim", seat: i, person: { id: person.id, name: person.name, cat: person.cat } });
    await c.until((s) => s.room.seats[i]?.kind === "human");
    clients.push(c);
  }
  const host = clients[0] as Client;
  for (let i = 0; i < bots; i++) host.send({ t: "configure", seat: seats.length + i, kind: "bot" });
  if (seats.length + bots < 2) throw new Error("a table needs two seats");
  await host.until((s) => s.room.seats.filter((seat) => seat.kind === "open").length === 0);
  host.send({ t: "start" });
  for (const c of clients) await c.until((s) => s.room.status === "playing" && s.room.tiles !== undefined);
  return { code, clients };
}

/** `seat` draws a piece (a whole turn) once the move is theirs. */
async function draw(clients: Client[], seat: number): Promise<void> {
  const c = clients[seat] as Client;
  await c.until((s) => s.room.tiles?.turn === seat);
  const turns = tilesOf(c).turns;
  c.send({ t: "act", seat, action: { type: "draw" } });
  for (const other of clients) await other.until((s) => (s.room.tiles?.turns ?? 0) > turns);
}

describe("creating a tile game table", { timeout: 30_000 }, () => {
  test("with GAMES off the server refuses it, exactly as it always has, and Cat Tower is untouched", async () => {
    const mf = await start(null);
    const phone = await mint(mf);
    expect((await create(mf, phone, "tiles", NEW_APP)).status).toBe(400);
    expect((await create(mf, phone, "tiles", OLD_APP)).status).toBe(400);
    expect((await create(mf, phone, "cat-tower", OLD_APP)).status).toBe(201);
    const page = await (await mf.dispatchFetch(`${BASE}/j/BCDFG`)).text();
    expect(page).not.toContain("Update Pounce");
  });

  test("with GAMES on: only for an app that says it can draw it", async () => {
    const mf = await start();
    const phone = await mint(mf);
    expect((await create(mf, phone, "tiles", OLD_APP)).status).toBe(400);
    expect((await create(mf, phone, "tiles", { "x-pounce-games": "cat-tower" })).status).toBe(400);
    expect((await create(mf, phone, "chess", NEW_APP)).status).toBe(400);
    expect((await create(mf, phone, "toString", NEW_APP)).status).toBe(400);
    expect((await create(mf, phone, undefined, NEW_APP)).status).toBe(400);
    const made = await create(mf, phone, "tiles", NEW_APP);
    expect(made.status).toBe(201);
    expect(Object.keys((await made.json()) as object)).toEqual(["code"]);
    // An older app still makes Cat Tower tables, and a newer one too.
    expect((await create(mf, phone, "cat-tower", OLD_APP)).status).toBe(201);
    expect((await create(mf, phone, "cat-tower", NEW_APP)).status).toBe(201);
  });

  test("the lobby says its game and seats four", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const code = await tilesRoom(mf, phone);
    const c = await connect(mf, code, phone, NEW_APP);
    const { room } = c.last as Snapshot;
    expect(room).toMatchObject({ code, status: "lobby", game: null, gameId: "tiles" });
    expect("tiles" in room).toBe(false);
    expect(room.seats).toHaveLength(4);
  });

  test("the invite page says what to do when the app can't find a table, for every code alike", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const code = await tilesRoom(mf, phone);
    const real = await (await mf.dispatchFetch(`${BASE}/j/${code}`)).text();
    const none = await (await mf.dispatchFetch(`${BASE}/j/BCDFG`)).text();
    expect(real).toContain("It may be a newer game. Update Pounce, then tap this link again.");
    expect(real.replaceAll(code, "BCDFG")).toBe(none);
  });
});

describe("a whole tile game through the room's sockets", { timeout: 120_000 }, () => {
  test("a person and a House Cat play to the end: every move accepted, nothing hidden shown", async () => {
    const mf = await start();
    const phone = await mint(mf);
    const jd = newPerson("JD", 1);
    const { code, clients } = await tilesTable(mf, [[phone, jd]], 1);
    const me = clients[0] as Client;
    const rng = createRng(seedOf(7));
    let moves = 0;
    let botMoves = 0;

    for (;;) {
      const snap = await me.until((s) => s.room.status === "over" || s.room.tiles?.turn === 0, 20_000);
      const view = snap.room.tiles as TilesView;
      // Every snapshot of this table: its game named, Cat Tower's key empty, one rack (mine), a valid table.
      expect(snap.room).toMatchObject({ game: null, gameId: "tiles" });
      expect(Object.keys(view.racks)).toEqual(["0"]);
      expect(view.rackCounts[0]).toBe(view.racks[0]?.length);
      for (const set of view.table) expect(readSet(set)).not.toBeNull();
      const seen = new Set([...view.table.flat(), ...(view.racks[0] as number[])]);
      expect(seen.size).toBe(view.table.flat().length + (view.racks[0] as number[]).length);
      if (snap.room.status === "over") break;

      // The person plays the way a House Cat would, from what their own phone shows.
      const action = chooseAction(view, 0, rng);
      const id = `move-${(moves += 1)}`;
      me.send({ t: "act", seat: 0, action, id });
      await me.until((s) => s.room.status === "over" || (s.room.link?.acks ?? [id]).includes(id) && (s.room.tiles?.turns ?? 0) > view.turns, 20_000);
      expect(moves).toBeLessThan(400);
    }

    const over = me.last as Snapshot;
    const end = over.room.tiles as TilesView;
    expect(end.status).toBe("gameOver");
    expect(end.winners.length).toBeGreaterThan(0);
    expect(["out", "blocked"]).toContain(end.endReason);
    expect(moves).toBeGreaterThan(3);

    // The server never refused a move, and never spoke of this table in Cat Tower's terms.
    expect(me.received.filter((m) => m.t === "error")).toEqual([]);
    const events = me.received.flatMap((m) => (m.t === "event" ? [m.event] : []));
    expect(events.some((e) => e.kind === "game")).toBe(false);
    const played = events.flatMap((e) => (e.kind === "tiles" ? [e.event] : []));
    for (const e of played) {
      if (e.kind !== "drew") continue;
      if (e.seat === 1) {
        botMoves += 1;
        // The House Cat's draws are as private as anyone's.
        expect("tile" in e).toBe(false);
      } else {
        expect(typeof e.tile).toBe("number");
      }
    }
    expect(played.filter((e) => e.kind === "turn").length).toBeGreaterThan(6);
    expect(played.at(-1)).toMatchObject({ kind: "gameOver", winners: end.winners });
    expect(botMoves + played.filter((e) => e.kind === "played" && e.seat === 1).length).toBeGreaterThan(2);

    // Home's list has the finished table, with its game, for an app that can draw it; and not for one that can't.
    const listed = await eventually(() => tablesOf(mf, phone, NEW_APP), (l) => l.some((t) => t.code === code && t.status === "over"));
    expect(listed.find((t) => t.code === code)).toMatchObject({ game: "tiles", status: "over", yourTurn: false });
    expect((await tablesOf(mf, phone, OLD_APP)).some((t) => t.code === code)).toBe(false);
  });
});

describe("an app that can't draw the tile game", { timeout: 60_000 }, () => {
  /**
   * JD on a new phone. Mia on a new phone and on a tablet still running an older app, both signed
   * in to her account, so they are one player. JD and Mia's phone sit at a tile game table.
   */
  async function family(mf: Miniflare) {
    const jdPhone = await mint(mf);
    const miaPhone = await mint(mf);
    const miaPad = await mint(mf);
    const jd = newPerson("JD", 1);
    const mia = newPerson("Mia", 2);
    const miaOnPad = newPerson("Mia", 2);
    await profile(mf, jdPhone, [jd], { apns: JD_TOKEN });
    await profile(mf, miaPhone, [mia], { apns: MIA_TOKEN });
    await profile(mf, miaPad, [miaOnPad], { apns: PAD_TOKEN });
    const signIn = async (d: Device, p: Person) =>
      call(mf, d, "POST", "/v1/identities/apple", { proof: await appleProof("apple-mia"), person: { id: p.id, key: p.key } });
    expect((await signIn(miaPhone, mia)).status).toBe(200);
    expect((await signIn(miaPad, miaOnPad)).status).toBe(200);
    const t = await tilesTable(mf, [
      [jdPhone, jd],
      [miaPhone, mia],
    ]);
    return { ...t, jdPhone, miaPhone, miaPad, jd, mia, miaOnPad };
  }

  test("can't join one: the table doesn't exist for it, by code or as a member", async () => {
    const mf = await start();
    const { code, jdPhone, miaPad } = await family(mf);
    const stranger = await mint(mf);
    for (const headers of [OLD_APP, { "x-pounce-games": "cat-tower" }, { "x-pounce-games": "chess" }, { "x-pounce-games": "" }]) {
      expect(await join(mf, code, stranger, headers)).toBe(404);
      // Mia's own tablet, and even the host's phone if it ran an older app.
      expect(await join(mf, code, miaPad, headers)).toBe(404);
      expect(await join(mf, code, jdPhone, headers)).toBe(404);
    }
    // The same answer a code that is no table gets.
    expect(await join(mf, "BCDFG", stranger, OLD_APP)).toBe(404);
    // A new app gets in.
    expect(await join(mf, code, stranger, NEW_APP)).toBe(101);
  });

  test("is never shown one in its tables, though its player sits at it", async () => {
    const mf = await start();
    const { code, miaPhone, miaPad } = await family(mf);
    const onPhone = await eventually(() => tablesOf(mf, miaPhone, NEW_APP), (l) => l.some((t) => t.code === code));
    expect(onPhone.find((t) => t.code === code)).toMatchObject({ game: "tiles", status: "playing" });
    // The tablet is the same player, so its list would have the table: it is left out.
    expect(await tablesOf(mf, miaPad, OLD_APP)).toEqual([]);
    expect(await tablesOf(mf, miaPad, { "x-pounce-games": "cat-tower" })).toEqual([]);
    // Asked by the phone again without the header (an older app there), it is left out too.
    expect((await tablesOf(mf, miaPhone, OLD_APP)).some((t) => t.code === code)).toBe(false);
  });

  test("is never pushed toward one: 'your move' goes to the phone that can open it, not the tablet", async () => {
    const mf = await start();
    const { code, clients } = await family(mf);
    const [jdClient, miaClient] = clients as [Client, Client];
    // Mia leaves the table with the move about to come to her.
    if (tilesOf(jdClient).turn === 1) await draw(clients, 1);
    miaClient.away();
    await settle(100);
    sent.length = 0;
    await draw(clients, 0);
    const [push] = await eventually(() => alertsTo(MIA_TOKEN, "your_move"), (l) => l.length === 1);
    expect((push as Sent).body).toMatchObject({ code, kind: "your_move" });
    await settle(400);
    expect(sent.filter((s) => s.token === PAD_TOKEN)).toEqual([]);
    expect(JSON.stringify(sent.filter((s) => s.token !== MIA_TOKEN && s.token !== JD_TOKEN))).not.toContain(code);
  });

  test("is told of no tile game table in its streaks, where the newer phone is", async () => {
    const mf = await start();
    const { code, clients, miaPhone, miaPad, mia, miaOnPad } = await family(mf);
    const first = tilesOf(clients[0] as Client).turn;
    await draw(clients, first);
    await draw(clients, 1 - first);
    await (clients[1] as Client).find((m) => m.t === "streak");
    type Streaks = { pairs: { count: number; myMove: string[]; theirMove: string[] }[] };
    const streaks = async (device: Device, person: Person, headers: Record<string, string>) =>
      (await (await call(mf, device, "GET", `/v1/me/streaks?person=${person.id}`, undefined, headers)).json()) as Streaks;
    const onPhone = await streaks(miaPhone, mia, NEW_APP);
    expect(onPhone.pairs).toHaveLength(1);
    expect([...(onPhone.pairs[0]?.myMove ?? []), ...(onPhone.pairs[0]?.theirMove ?? [])]).toEqual([code]);
    // The same player's tablet: the same streak, with the table it can't open left out.
    const onPad = await streaks(miaPad, miaOnPad, OLD_APP);
    expect(onPad.pairs).toHaveLength(1);
    expect(onPad.pairs[0]).toMatchObject({ count: onPhone.pairs[0]?.count, myMove: [], theirMove: [] });
    expect(JSON.stringify(onPad)).not.toContain(code);
  });

  /** A streak between JD and Mia from a turn each at the tile game, with the move back with whoever moved first. */
  async function streakAtTiles(mf: Miniflare) {
    const f = await family(mf);
    const first = tilesOf(f.clients[0] as Client).turn;
    await draw(f.clients, first);
    await draw(f.clients, 1 - first);
    await (f.clients[1] as Client).find((m) => m.t === "streak");
    // Mia is to move at the tile game: JD plays on if the move is his.
    if (tilesOf(f.clients[0] as Client).turn === 0) await draw(f.clients, 0);
    // The device's people as the server knows them now: Mia's phone and tablet are one player.
    const players = await profile(mf, f.miaPhone, [f.mia]);
    const miaId = players[f.mia.id] as string;
    expect((await profile(mf, f.miaPad, [f.miaOnPad]))[f.miaOnPad.id]).toBe(miaId);
    const tomorrow = slotAt(addDays(dayKey(Date.now(), LA), 1), 19 * 60 + 30, LA);
    const remind = async () => {
      await settle(300);
      sent.length = 0;
      await mf.dispatchFetch(`${BASE}/__test/remind?player=${miaId}&now=${tomorrow}`);
    };
    return { ...f, remind };
  }

  type Alert = { aps: { alert: { title: string; body: string } }; code?: string; kind: string; streak?: { myMove: string[]; theirMove: string[] } };

  test("still gets the streak reminder when the only table to play at is a tile game: with no table to open", async () => {
    const mf = await start();
    const { code, remind } = await streakAtTiles(mf);
    await remind();
    const [onPhone] = await eventually(() => alertsTo(MIA_TOKEN, "reminder"), (l) => l.length === 1);
    const [onPad] = await eventually(() => alertsTo(PAD_TOKEN, "reminder"), (l) => l.length === 1);
    // The phone's opens the tile game's table.
    expect((onPhone as Sent).body).toMatchObject({ kind: "reminder", code });
    // The tablet's is the same reminder for the same streak, pointing nowhere, and never naming the table.
    const pad = (onPad as Sent).body as Alert;
    expect("code" in pad).toBe(false);
    expect(pad.aps.alert.title).toBe(((onPhone as Sent).body as Alert).aps.alert.title);
    expect(pad.streak).toMatchObject({ myMove: [], theirMove: [] });
    expect(JSON.stringify(pad)).not.toContain(code);
    expect(alertsTo(PAD_TOKEN)).toHaveLength(1);
  });

  test("gets it pointing at the Cat Tower table when the pair shares one too", async () => {
    const mf = await start();
    const { code, remind, jdPhone, miaPhone, jd, mia } = await streakAtTiles(mf);
    // The same two at a Cat Tower table, with the move at Mia's seat there as well.
    const tower = await table(mf, [
      [jdPhone, jd],
      [miaPhone, mia],
    ]);
    for (let i = 0; i < 4 && (tower.clients[0] as Client).game().turn !== 1; i++) await takeTurn(tower.clients);
    await eventually(() => tablesOf(mf, miaPhone, NEW_APP), (l) => l.some((t) => t.code === tower.code && t.yourTurn));
    await remind();
    const [onPad] = await eventually(() => alertsTo(PAD_TOKEN, "reminder"), (l) => l.length === 1);
    const [onPhone] = await eventually(() => alertsTo(MIA_TOKEN, "reminder"), (l) => l.length === 1);
    const pad = (onPad as Sent).body as Alert;
    expect(pad.code).toBe(tower.code);
    expect(pad.streak?.myMove).toEqual([tower.code]);
    expect(JSON.stringify(pad)).not.toContain(code);
    // The phone's may point at either: both are tables it can open, and both are in its streak block.
    const phone = (onPhone as Sent).body as Alert;
    expect([code, tower.code]).toContain(phone.code);
    expect([...(phone.streak?.myMove ?? [])].sort()).toEqual([code, tower.code].sort());
  });

  test("still gets everything about a Cat Tower table, with a badge that counts only what it can open", async () => {
    const mf = await start();
    const { code, clients, jdPhone, miaPhone, jd, mia } = await family(mf);
    // The move at the tile game is Mia's, and she is away from it.
    if (tilesOf(clients[0] as Client).turn === 0) await draw(clients, 0);
    (clients[1] as Client).away();
    // The same two at a Cat Tower table: JD plays, so the move comes to Mia there as well.
    const tower = await table(mf, [
      [jdPhone, jd],
      [miaPhone, mia],
    ]);
    for (let i = 0; i < 4 && (tower.clients[0] as Client).game().turn !== 0; i++) await takeTurn(tower.clients);
    (tower.clients[1] as Client).away();
    // The shared helper opened that socket with no header, as an older app would, and the server
    // took it at its word. Mia's phone is a newer app: its next request says so again.
    await tablesOf(mf, miaPhone, NEW_APP);
    await settle(100);
    sent.length = 0;
    await takeTurn(tower.clients);
    const [onPad] = await eventually(() => alertsTo(PAD_TOKEN, "your_move"), (l) => l.length === 1);
    const [onPhone] = await eventually(() => alertsTo(MIA_TOKEN, "your_move"), (l) => l.length === 1);
    expect((onPad as Sent).body).toMatchObject({ code: tower.code, kind: "your_move" });
    // The tablet's badge is the Cat Tower table alone; the phone's counts the tile game too.
    expect(((onPad as Sent).body.aps as { badge: number }).badge).toBe(1);
    expect(((onPhone as Sent).body.aps as { badge: number }).badge).toBe(2);
    // Nothing the tablet was sent names the tile game's table.
    expect(JSON.stringify(sent.filter((s) => s.token === PAD_TOKEN))).not.toContain(code);
  });
});

describe("streaks and play again at a tile game table", { timeout: 60_000 }, () => {
  async function couple(mf: Miniflare) {
    const phone = await mint(mf);
    const tablet = await mint(mf);
    const jd = newPerson("JD", 1);
    const mia = newPerson("Mia", 2);
    await profile(mf, phone, [jd], { apns: JD_TOKEN });
    await profile(mf, tablet, [mia], { apns: MIA_TOKEN });
    const t = await tilesTable(mf, [
      [phone, jd],
      [tablet, mia],
    ]);
    return { ...t, phone, tablet };
  }

  test("a turn each makes a pair and starts a streak, as at any table", async () => {
    const mf = await start();
    const { clients } = await couple(mf);
    const first = tilesOf(clients[0] as Client).turn;
    await draw(clients, first);
    await draw(clients, 1 - first);
    for (const c of clients) {
      const streak = await c.find<Extract<ServerMessage, { t: "streak" }>>((m) => m.t === "streak");
      expect(streak.view).toMatchObject({ count: 1, me: true, them: true });
    }
  });

  test("play again deals the same game, and only an app that can draw it finds the new table", async () => {
    const mf = await start();
    const { code, clients, phone, tablet } = await couple(mf);
    const [a, b] = clients as [Client, Client];
    b.send({ t: "act", seat: 1, action: { type: "forfeit" } });
    await a.until((s) => s.room.status === "over");
    expect((a.last as Snapshot).room.tiles).toMatchObject({ status: "gameOver", winners: [0], endReason: "forfeit" });
    a.send({ t: "rematch" });
    const dealt = await a.find<Extract<ServerMessage, { t: "rematch" }>>((m) => m.t === "rematch");
    expect(dealt.code).not.toBe(code);
    expect(await join(mf, dealt.code, tablet, OLD_APP)).toBe(404);
    const again = await connect(mf, dealt.code, phone, NEW_APP);
    expect((again.last as Snapshot).room).toMatchObject({ status: "playing", game: null, gameId: "tiles" });
    expect(tilesOf(again).rackCounts).toEqual([14, 14]);
    const listed = await eventually(() => tablesOf(mf, tablet, NEW_APP), (l) => l.some((t) => t.code === dealt.code));
    expect(listed.find((t) => t.code === dealt.code)).toMatchObject({ game: "tiles", status: "playing" });
  });

  test("once GAMES is turned off, a tile game table plays to its end but play again deals nothing, and none can be made", async () => {
    const dir = mkdtempSync(joinPath(tmpdir(), "play-api-tiles-"));
    dirs.push(dir);
    const on = await start("tiles", dir);
    const made = await couple(on);
    const { code, phone, tablet } = made;
    await draw(made.clients, tilesOf(made.clients[0] as Client).turn);
    await on.dispose();
    open.splice(open.indexOf(on), 1);

    // The same rooms, under a Worker whose flag lists no game but Cat Tower: production after a kill switch.
    const off = await start(null, dir);
    expect((await create(off, phone, "tiles", NEW_APP)).status).toBe(400);
    // The table that was dealt is still there for the apps that can draw it, and still plays.
    const a = await connect(off, code, phone, NEW_APP);
    const b = await connect(off, code, tablet, NEW_APP);
    expect((a.last as Snapshot).room).toMatchObject({ status: "playing", gameId: "tiles" });
    await draw([a, b], tilesOf(a).turn);
    b.send({ t: "act", seat: 1, action: { type: "forfeit" } });
    await a.until((s) => s.room.status === "over");
    // Play again is refused in so many words, for both, and no table is dealt.
    for (const c of [a, b]) {
      c.send({ t: "rematch" });
      await c.find((m) => m.t === "error" && m.code === "game_off");
    }
    await settle(300);
    expect([...a.received, ...b.received].some((m) => m.t === "rematch")).toBe(false);
    expect((a.last as Snapshot).room.rematch).toBeUndefined();
    // Cat Tower is dealt as ever.
    expect((await create(off, phone, "cat-tower", OLD_APP)).status).toBe(201);
  });

  test("a move the room's parser can't read is a bad message, and Cat Tower's moves are not this game's", async () => {
    const mf = await start();
    const { clients } = await couple(mf);
    const seat = tilesOf(clients[0] as Client).turn;
    const c = clients[seat] as Client;
    for (const action of [{ type: "draw", from: "deck" }, { type: "discard", card: 3 }, { type: "play", table: "all" }]) {
      const before = c.received.length;
      c.send({ t: "act", seat, action });
      await eventually(() => c.received.length, (n) => n > before);
      expect(c.received.at(-1)).toEqual({ t: "error", code: "bad_message" });
    }
    c.send({ t: "act", seat, action: { type: "pass" } });
    await c.find((m) => m.t === "error" && m.code === "pool_not_empty");
  });
});
