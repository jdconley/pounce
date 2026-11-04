import { mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { build } from "esbuild";
import { Miniflare, Response as MiniflareResponse, type Request as MiniflareRequest } from "miniflare";
import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { base64url, sha256Hex } from "../src/players/ids";
import { card } from "../src/rules/cards";

import type { ServerMessage } from "../src/protocol";
import type { RoomState } from "../src/room/core";
import type { CatTowerView } from "../src/rules/view";
import type { PairState, StreakView } from "../src/streaks/pair-core";

const SECRET = "s".repeat(64);
const BASE = "https://play.conleychaos.com";
const CLIENT_ID = "com.conleychaos.play";
const DAY_MS = 24 * 60 * 60 * 1000;
const encoder = new TextEncoder();

type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;
type StreakMessage = Extract<ServerMessage, { t: "streak" }>;
type Device = { deviceId: string; token: string };
type Person = { id: string; name: string; cat: number; key: string };
type Listed = StreakView & { pinned: boolean };

let script = "";
let rsa: CryptoKeyPair;
let jwk: JsonWebKey;
const open: Miniflare[] = [];
const dirs: string[] = [];

beforeAll(async () => {
  const built = await build({
    entryPoints: [new URL("./streaks-entry.ts", import.meta.url).pathname],
    bundle: true,
    write: false,
    format: "esm",
    platform: "browser",
    external: ["cloudflare:workers"],
  });
  script = built.outputFiles[0]?.text ?? "";
  rsa = (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  jwk = { ...(await crypto.subtle.exportKey("jwk", rsa.publicKey)), kid: "TEST1", use: "sig", alg: "RS256" } as JsonWebKey;
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

function worker(options: { streaks?: boolean; persist?: string } = {}): Miniflare {
  const mf = new Miniflare({
    modules: true,
    script,
    compatibilityDate: "2026-08-01",
    durableObjects: {
      ROOMS: { className: "GameRoom", useSQLite: true },
      DEVICES: { className: "DeviceIndex", useSQLite: true },
      PLAYERS: { className: "Player", useSQLite: true },
      IDENTITIES: { className: "Identities", useSQLite: true },
      PAIRS: { className: "Pair", useSQLite: true },
    },
    bindings: {
      TOKEN_SECRET: SECRET,
      SIWA_CLIENT_ID: CLIENT_ID,
      APNS_TEAM_ID: "B222J9J7B8",
      APNS_TOPIC: CLIENT_ID,
      APNS_HOST: "api.push.apple.com",
      ...(options.streaks === false ? {} : { STREAKS: "on" }),
    },
    ...(options.persist ? { durableObjectsPersist: options.persist } : {}),
    // Stands in for Apple's public keys, which need no secret.
    outboundService: async (request: MiniflareRequest) =>
      request.url === "https://appleid.apple.com/auth/keys"
        ? new MiniflareResponse(JSON.stringify({ keys: [jwk] }), { headers: { "content-type": "application/json" } })
        : new MiniflareResponse(null, { status: 599 }),
  });
  open.push(mf);
  return mf;
}

let nonceCount = 0;

async function appleProof(sub: string): Promise<{ identityToken: string; nonce: string }> {
  const nonce = `nonce-${(nonceCount += 1)}-${Math.random()}`;
  const now = Math.floor(Date.now() / 1000);
  const json = (v: unknown) => base64url(encoder.encode(JSON.stringify(v)));
  const input = `${json({ alg: "RS256", kid: "TEST1" })}.${json({
    iss: "https://appleid.apple.com",
    aud: CLIENT_ID,
    exp: now + 600,
    iat: now,
    sub,
    nonce: await sha256Hex(nonce),
  })}`;
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", rsa.privateKey, encoder.encode(input));
  return { identityToken: `${input}.${base64url(new Uint8Array(sig))}`, nonce };
}

const newPerson = (name: string, cat: number): Person => ({
  id: crypto.randomUUID(),
  name,
  cat,
  key: base64url(crypto.getRandomValues(new Uint8Array(32))),
});

async function mint(mf: Miniflare): Promise<Device> {
  const res = await mf.dispatchFetch(`${BASE}/v1/devices`, { method: "POST", headers: { "cf-connecting-ip": crypto.randomUUID() } });
  return (await res.json()) as Device;
}

function call(mf: Miniflare, device: Device, method: string, path: string, body?: unknown): Promise<Response> {
  return mf.dispatchFetch(`${BASE}${path}`, {
    method,
    headers: { authorization: `Bearer ${device.token}`, "content-type": "application/json" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }) as unknown as Promise<Response>;
}

async function profile(mf: Miniflare, device: Device, people: Person[]): Promise<Record<string, string>> {
  const res = await call(mf, device, "PUT", "/v1/devices/me/profile", { timeZone: "America/Los_Angeles", ageBand: "adult", people });
  expect(res.status).toBe(200);
  return ((await res.json()) as { players: Record<string, string> }).players;
}

async function streaks(mf: Miniflare, device: Device, person: Person): Promise<Listed[]> {
  const res = await call(mf, device, "GET", `/v1/me/streaks?person=${person.id}`);
  expect(res.status).toBe(200);
  return ((await res.json()) as { pairs: Listed[] }).pairs;
}

async function eventually<T>(read: () => Promise<T>, ok: (value: T) => boolean): Promise<T> {
  const end = Date.now() + 5000;
  let value = await read();
  while (!ok(value) && Date.now() < end) {
    await new Promise((resolve) => setTimeout(resolve, 50));
    value = await read();
  }
  return value;
}

/** A socket that keeps every frame and its latest snapshot. */
class Client {
  readonly received: ServerMessage[] = [];
  last: Snapshot | null = null;

  constructor(readonly ws: WebSocket) {
    ws.addEventListener("message", (e) => {
      const m = JSON.parse(e.data as string) as ServerMessage;
      this.received.push(m);
      if (m.t === "snapshot") this.last = m;
    });
  }

  send(value: unknown): void {
    this.ws.send(JSON.stringify(value));
  }

  /** The first frame so far, or to come, that matches. */
  async find<M extends ServerMessage>(match: (m: ServerMessage) => boolean): Promise<M> {
    const end = Date.now() + 5000;
    for (;;) {
      const found = this.received.find(match);
      if (found) return found as M;
      if (Date.now() > end) throw new Error(`timed out; got ${JSON.stringify(this.received.map((m) => m.t))}`);
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }

  async until(ok: (s: Snapshot) => boolean): Promise<Snapshot> {
    const end = Date.now() + 5000;
    while (!(this.last && ok(this.last))) {
      if (Date.now() > end) throw new Error("snapshot never matched");
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    return this.last;
  }

  game(): CatTowerView {
    return (this.last as Snapshot).room.game as CatTowerView;
  }
}

async function connect(mf: Miniflare, code: string, device: Device): Promise<Client> {
  const res = await mf.dispatchFetch(`${BASE}/v1/rooms/${code}/ws`, {
    headers: { authorization: `Bearer ${device.token}`, upgrade: "websocket" },
  });
  expect(res.status).toBe(101);
  const ws = res.webSocket as unknown as WebSocket & { accept(): void };
  ws.accept();
  const client = new Client(ws);
  await client.until(() => true);
  return client;
}

async function createRoom(mf: Miniflare, device: Device): Promise<string> {
  const res = await call(mf, device, "POST", "/v1/rooms", { game: "cat-tower" });
  return ((await res.json()) as { code: string }).code;
}

/** A started game: seat 0 is `p0` on `d0`, seat 1 is `p1` on `d1`. Returns the clients by seat. */
async function table(mf: Miniflare, seats: [Device, Person][]): Promise<{ code: string; clients: Client[] }> {
  const code = await createRoom(mf, (seats[0] as [Device, Person])[0]);
  const clients: Client[] = [];
  for (const [i, [device, person]] of seats.entries()) {
    const c = await connect(mf, code, device);
    c.send({ t: "claim", seat: i, person: { id: person.id, name: person.name, cat: person.cat } });
    await c.until((s) => s.room.seats[i]?.kind === "human");
    clients.push(c);
  }
  (clients[0] as Client).send({ t: "start" });
  for (const c of clients) await c.until((s) => s.room.status === "playing");
  return { code, clients };
}

/** Whoever's turn it is draws from the deck and discards a number card. */
async function takeTurn(clients: Client[]): Promise<void> {
  const seat = (clients[0] as Client).game().turn;
  const c = clients[seat] as Client;
  await c.until((s) => s.room.game?.turn === seat);
  c.send({ t: "act", seat, action: { type: "draw", from: "deck" } });
  const drawn = await c.until((s) => s.room.game?.step === "play");
  const hand = (drawn.room.game as CatTowerView).hands[seat] as number[];
  const pick = hand.find((id) => card(id).kind === "number") as number;
  c.send({ t: "act", seat, action: { type: "discard", card: pick } });
  for (const other of clients) await other.until((s) => s.room.game?.turn !== seat || s.room.status !== "playing");
}

const isStreak = (m: ServerMessage): m is StreakMessage => m.t === "streak";

/** JD on a phone and Mia on a tablet, each taken one turn at a shared table. */
async function pairedUp(mf: Miniflare) {
  const phone = await mint(mf);
  const tablet = await mint(mf);
  const jd = newPerson("JD", 1);
  const mia = newPerson("Mia", 2);
  const ids = { ...(await profile(mf, phone, [jd])), ...(await profile(mf, tablet, [mia])) };
  const { code, clients } = await table(mf, [
    [phone, jd],
    [tablet, mia],
  ]);
  await takeTurn(clients);
  await takeTurn(clients);
  const [a, b] = clients as [Client, Client];
  const mine = await a.find<StreakMessage>(isStreak);
  return { phone, tablet, jd, mia, ids, code, a, b, clients, pairId: mine.pair };
}

describe("streaks", { timeout: 30_000 }, () => {
  test("two people who each take a turn form a pair, and both sockets hear the kept day", async () => {
    const mf = worker();
    const { jd, mia, a, b, pairId, phone, tablet } = await pairedUp(mf);
    const forJd = await a.find<StreakMessage>((m) => isStreak(m) && m.view.count === 1);
    expect(forJd).toMatchObject({ pair: pairId, person: jd.id, view: { me: true, them: true, partner: { name: "Mia", cat: 2 } } });
    const forMia = await b.find<StreakMessage>((m) => isStreak(m) && m.view.count === 1);
    expect(forMia).toMatchObject({ pair: pairId, person: mia.id, view: { partner: { name: "JD", cat: 1 } } });
    expect(JSON.stringify(forJd)).not.toContain("p_");

    const [listed] = await streaks(mf, phone, jd);
    expect(listed).toMatchObject({ pair: pairId, count: 1, pinned: false, partner: { name: "Mia", cat: 2 } });
    expect(await streaks(mf, tablet, mia)).toHaveLength(1);
  });

  test("pause, pin and gifts act on your own pairs only", async () => {
    const mf = worker();
    const { jd, phone, pairId } = await pairedUp(mf);
    const at = (path: string) => `/v1/pairs/${pairId}${path}?person=${jd.id}`;
    expect((await call(mf, phone, "PUT", at("/pause"), { days: 3 })).status).toBe(204);
    expect((await streaks(mf, phone, jd))[0]?.pausedUntil).not.toBeNull();
    for (const bad of [{ days: 15 }, { days: 0 }, { days: "3" }, { days: 3, extra: 1 }]) {
      expect((await call(mf, phone, "PUT", at("/pause"), bad)).status).toBe(400);
    }
    expect((await call(mf, phone, "DELETE", at("/pause"))).status).toBe(204);
    expect((await call(mf, phone, "PUT", at("/pin"))).status).toBe(204);
    expect((await streaks(mf, phone, jd))[0]?.pinned).toBe(true);
    expect((await call(mf, phone, "POST", at("/gifts/g99/open"))).status).toBe(404);
    expect((await call(mf, phone, "GET", at("/pin"))).status).toBe(404);

    const stranger = await mint(mf);
    const kim = newPerson("Kim", 4);
    await profile(mf, stranger, [kim]);
    expect((await call(mf, stranger, "PUT", `/v1/pairs/${pairId}/pin?person=${kim.id}`)).status).toBe(404);
    expect((await call(mf, stranger, "DELETE", `/v1/pairs/${pairId}?person=${kim.id}`)).status).toBe(404);
    expect((await call(mf, phone, "PUT", `/v1/pairs/nope/pin?person=${jd.id}`)).status).toBe(404);
  });

  test("leaving a streak removes it for both, and it doesn't re-form", async () => {
    const mf = worker();
    const { jd, mia, phone, tablet, pairId, clients } = await pairedUp(mf);
    expect((await call(mf, phone, "DELETE", `/v1/pairs/${pairId}?person=${jd.id}`)).status).toBe(204);
    expect(await streaks(mf, phone, jd)).toEqual([]);
    expect(await streaks(mf, tablet, mia)).toEqual([]);
    const pair = await mf.dispatchFetch(`${BASE}/__test/pair?pair=${pairId}`);
    expect(await pair.json()).toBeNull();
    await takeTurn(clients);
    await takeTurn(clients);
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(await streaks(mf, phone, jd)).toEqual([]);
    expect(await streaks(mf, tablet, mia)).toEqual([]);
  });

  test("table looks come from the setter's unlocks and follow them to a new table", async () => {
    const mf = worker();
    const { a, b, phone, pairId } = await pairedUp(mf);
    a.send({ t: "setLook", rug: "rug-night-sky" });
    await a.find((m) => m.t === "error" && m.code === "not_unlocked");
    await mf.dispatchFetch(`${BASE}/__test/grant?pair=${pairId}&item=rug-night-sky`);
    a.send({ t: "setLook", rug: "rug-night-sky" });
    const look = { kind: "look", seat: 0, rug: "rug-night-sky", back: "back-violet-paw" };
    for (const c of [a, b]) await c.find((m) => m.t === "event" && m.event.kind === "look");
    expect(b.received.find((m) => m.t === "event" && m.event.kind === "look")).toMatchObject({ event: look });
    await eventually(
      async () => (await connect(mf, await createRoom(mf, phone), phone)).last?.room.look?.rug,
      (rug) => rug === "rug-night-sky",
    );
    const fresh = await connect(mf, await createRoom(mf, phone), phone);
    expect(fresh.last?.room.look).toEqual({ rug: "rug-night-sky", back: "back-violet-paw" });
  });

  test("a missed day after a kept one settles into win-back", async () => {
    const mf = worker();
    const { pairId } = await pairedUp(mf);
    await mf.dispatchFetch(`${BASE}/__test/settle?pair=${pairId}&now=${Date.now() + 2 * DAY_MS}`);
    const state = (await (await mf.dispatchFetch(`${BASE}/__test/pair?pair=${pairId}`)).json()) as PairState;
    expect(state.streak.count).toBe(1);
    expect(state.streak.winback).not.toBeNull();
    expect(Object.values(state.days).map((d) => d.state)).toContain("kept");
  });

  test("a pair whose object lost its state forms again at the next turns", async () => {
    const mf = worker();
    const { jd, phone, pairId, a, clients } = await pairedUp(mf);
    await mf.dispatchFetch(`${BASE}/__test/break?pair=${pairId}`);
    await takeTurn(clients);
    const healed = await a.find<StreakMessage>((m) => isStreak(m) && m.pair !== pairId);
    expect(healed.view.count).toBe(1);
    const listed = await streaks(mf, phone, jd);
    expect(listed.map((p) => p.pair)).toEqual([healed.pair]);
  });

  test("a player on the way out (deleted or merged away) forms no new pair", async () => {
    const mf = worker();
    const phone = await mint(mf);
    const tablet = await mint(mf);
    const jd = newPerson("JD", 1);
    const mia = newPerson("Mia", 2);
    const ids = { ...(await profile(mf, phone, [jd])), ...(await profile(mf, tablet, [mia])) };
    await mf.dispatchFetch(`${BASE}/__test/retire?player=${ids[mia.id]}`);
    const { clients } = await table(mf, [
      [phone, jd],
      [tablet, mia],
    ]);
    await takeTurn(clients);
    await takeTurn(clients);
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(await streaks(mf, phone, jd)).toEqual([]);
  });

  test("streak views never say when anyone last played", async () => {
    const mf = worker();
    const { jd, phone, a } = await pairedUp(mf);
    expect((await a.find<StreakMessage>(isStreak)).view).not.toHaveProperty("lastTurnAt");
    expect((await streaks(mf, phone, jd))[0]).not.toHaveProperty("lastTurnAt");
  });

  test("deleting an account leaves every pair", async () => {
    const mf = worker();
    const { jd, mia, phone, tablet } = await pairedUp(mf);
    expect((await call(mf, phone, "DELETE", `/v1/me?person=${jd.id}`)).status).toBe(204);
    expect(await streaks(mf, tablet, mia)).toEqual([]);
  });

  test("a merge re-points pairs, merges two with the same partner, and never pairs a player with themself", async () => {
    const mf = worker();
    const { jd, mia, phone, tablet } = await pairedUp(mf);
    const ipad = await mint(mf);
    const jdPad = newPerson("JD", 1);
    await profile(mf, ipad, [jdPad]);
    // The iPad's guest plays with Mia, and with JD on the phone.
    const withMia = await table(mf, [
      [ipad, jdPad],
      [tablet, mia],
    ]);
    await takeTurn(withMia.clients);
    await takeTurn(withMia.clients);
    const withSelf = await table(mf, [
      [ipad, jdPad],
      [phone, jd],
    ]);
    await takeTurn(withSelf.clients);
    await takeTurn(withSelf.clients);
    await eventually(() => streaks(mf, tablet, mia), (p) => p.length === 2);
    await eventually(() => streaks(mf, phone, jd), (p) => p.length === 2);

    const signIn = (device: Device, person: Person) =>
      appleProof("apple-jd").then((proof) =>
        call(mf, device, "POST", "/v1/identities/apple", { proof, person: { id: person.id, key: person.key } }),
      );
    expect((await signIn(phone, jd)).status).toBe(200);
    const merged = await signIn(ipad, jdPad);
    expect(((await merged.json()) as { outcome: string }).outcome).toBe("merged");

    const miaPairs = await streaks(mf, tablet, mia);
    expect(miaPairs).toHaveLength(1);
    expect(miaPairs[0]?.partner).toEqual({ name: "JD", cat: 1 });
    expect(await streaks(mf, phone, jd)).toHaveLength(1);

    // JD now sits in both seats at the iPad table: turns there make no pair.
    await takeTurn(withSelf.clients);
    await takeTurn(withSelf.clients);
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(await streaks(mf, phone, jd)).toHaveLength(1);
  });
});

describe("play again", { timeout: 30_000 }, () => {
  async function importSqlite(): Promise<typeof import("node:sqlite")> {
    const emit = process.emitWarning;
    process.emitWarning = ((warning: string | Error, ...rest: unknown[]) => {
      if (String(warning).includes("SQLite")) return;
      (emit as (...args: unknown[]) => void).call(process, warning, ...rest);
    }) as typeof process.emitWarning;
    try {
      return await import("node:sqlite");
    } finally {
      process.emitWarning = emit;
    }
  }

  /** Ends the one stored room of a disposed persistent worker. */
  async function endStoredRoom(dir: string): Promise<void> {
    const { DatabaseSync } = await importSqlite();
    const rooms = join(dir, readdirSync(dir).find((d) => d.endsWith("GameRoom")) as string);
    const files = readdirSync(rooms).filter((f) => f.endsWith(".sqlite") && f !== "metadata.sqlite");
    expect(files).toHaveLength(1);
    const db = new DatabaseSync(join(rooms, files[0] as string));
    const row = db.prepare("SELECT json FROM room WHERE id = 1").get() as { json: string };
    const state = JSON.parse(row.json) as RoomState;
    state.status = "over";
    db.prepare("UPDATE room SET json = ? WHERE id = 1").run(JSON.stringify(state));
    db.close();
  }

  test("deals a new table at once with the same people, and everyone at the old one hears where", async () => {
    const dir = mkdtempSync(join(tmpdir(), "play-api-streaks-"));
    dirs.push(dir);
    const first = worker({ persist: dir });
    const phone = await mint(first);
    const tablet = await mint(first);
    const jd = newPerson("JD", 1);
    const mia = newPerson("Mia", 2);
    const ids = { ...(await profile(first, phone, [jd])), ...(await profile(first, tablet, [mia])) };
    const { code } = await table(first, [
      [phone, jd],
      [tablet, mia],
    ]);
    await first.dispose();
    open.splice(open.indexOf(first), 1);
    await endStoredRoom(dir);

    const mf = worker({ persist: dir });
    const a = await connect(mf, code, phone);
    const b = await connect(mf, code, tablet);
    a.send({ t: "rematch" });
    a.send({ t: "rematch" });
    const told = await b.find<Extract<ServerMessage, { t: "rematch" }>>((m) => m.t === "rematch");
    await a.find((m) => m.t === "rematch");
    expect(told.code).not.toBe(code);

    const next = await connect(mf, told.code, tablet);
    expect(next.last?.room.status).toBe("playing");
    expect(next.last?.room.seats.map((s) => s.person?.id)).toEqual([mia.id, jd.id]);
    expect(next.last?.room.seats.map((s) => s.yours)).toEqual([true, false]);
    expect(ids[mia.id]).toBeDefined();

    const listed = await eventually(
      async () => ((await (await call(mf, tablet, "GET", "/v1/devices/me/tables")).json()) as { tables: { code: string; next?: string }[] }).tables,
      (t) => t.some((e) => e.code === code && e.next === told.code) && t.some((e) => e.code === told.code),
    );
    expect(listed.find((e) => e.code === code)?.next).toBe(told.code);
  });
});

describe("with STREAKS unset", { timeout: 30_000 }, () => {
  test("the streak routes are 404s and looks are bad messages", async () => {
    const mf = worker({ streaks: false });
    const phone = await mint(mf);
    const jd = newPerson("JD", 1);
    await profile(mf, phone, [jd]);
    expect((await call(mf, phone, "GET", `/v1/me/streaks?person=${jd.id}`)).status).toBe(404);
    expect((await call(mf, phone, "PUT", `/v1/pairs/pr_AAAAAAAAAAAAAAAAAAAAAA/pin?person=${jd.id}`)).status).toBe(404);
    const c = await connect(mf, await createRoom(mf, phone), phone);
    expect(c.last?.room).not.toHaveProperty("look");
    c.send({ t: "setLook", rug: "rug-classic" });
    await c.find((m) => m.t === "error" && m.code === "bad_message");
  });
});
