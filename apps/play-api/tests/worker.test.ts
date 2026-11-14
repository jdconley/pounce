import { mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { build } from "esbuild";
import { Miniflare } from "miniflare";
import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { defaultRoomName } from "../src/room/names";
import { card } from "../src/rules/cards";

import type { ServerMessage } from "../src/protocol";
import type { RoomState } from "../src/room/core";
import type { CatTowerState } from "../src/rules/engine";
import type { CatTowerView } from "../src/rules/view";

const SECRET = "s".repeat(64);
/** Idle time after which workerd evicts a Durable Object. */
const HIBERNATE_MS = 11_000;
const BASE = "https://play.conleychaos.com";
const ALICE = { id: "11111111-1111-4111-8111-111111111111", name: "Alice", cat: 1 };
const BOB = { id: "22222222-2222-4222-8222-222222222222", name: "Bob", cat: 2 };

type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;
type Device = { deviceId: string; token: string };
type Table = {
  code: string;
  name?: string;
  status: string;
  yourTurn: boolean;
  updatedAt: number;
  seats?: { kind: string; person?: { id: string; name: string; cat: number }; yours?: true }[];
};
/** A new room's six lobby seats: two open, four closed. */
const LOBBY = [{ kind: "open" }, { kind: "open" }, ...Array.from({ length: 4 }, () => ({ kind: "closed" }))];

let script = "";
const open: Miniflare[] = [];
const dirs: string[] = [];

beforeAll(async () => {
  const built = await build({
    entryPoints: [new URL("../src/index.ts", import.meta.url).pathname],
    bundle: true,
    write: false,
    format: "esm",
    platform: "browser",
    external: ["cloudflare:workers"],
  });
  script = built.outputFiles[0]?.text ?? "";
});

afterEach(async () => {
  await Promise.all(open.splice(0).map((mf) => mf.dispose()));
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

/**
 * A fresh worker, disposed after the test. Concurrent tests pass their own
 * `onTestFinished`, so one test's cleanup cannot dispose another's worker.
 */
function worker(
  options: {
    secret?: string | null;
    testflight?: string;
    persist?: string;
    devSpeed?: string;
    /** The bad connection indicator's server half (`LINK`). */
    link?: boolean;
    onFinished?: (fn: () => Promise<void>) => void;
  } = {},
): Miniflare {
  const secret = options.secret === undefined ? SECRET : options.secret;
  const mf = new Miniflare({
    modules: true,
    script,
    compatibilityDate: "2026-08-01",
    durableObjects: {
      ROOMS: { className: "GameRoom", useSQLite: true },
      DEVICES: { className: "DeviceIndex", useSQLite: true },
      PLAYERS: { className: "Player", useSQLite: true },
      IDENTITIES: { className: "Identities", useSQLite: true },
      LIMITS: { className: "Limiter", useSQLite: true },
      REPORTS: { className: "Reports", useSQLite: true },
    },
    bindings: {
      ...(secret === null ? {} : { TOKEN_SECRET: secret }),
      ...(options.testflight ? { TESTFLIGHT_URL: options.testflight } : {}),
      ...(options.devSpeed ? { DEV_SPEED: options.devSpeed } : {}),
      ...(options.link ? { LINK: "on" } : {}),
    },
    ...(options.persist ? { durableObjectsPersist: options.persist } : {}),
  });
  if (options.onFinished) options.onFinished(() => mf.dispose());
  else open.push(mf);
  return mf;
}

/** node:sqlite, without its one-time ExperimentalWarning on stderr. */
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

/**
 * Rewrites the stored room of a disposed persistent worker. Miniflare keeps one
 * SQLite file per object under "<worker>-<class>".
 */
async function editStoredRoom(dir: string, edit: (state: RoomState) => void): Promise<void> {
  const { DatabaseSync } = await importSqlite();
  const rooms = join(dir, readdirSync(dir).find((d) => d.endsWith("GameRoom")) as string);
  const files = readdirSync(rooms).filter((f) => f.endsWith(".sqlite") && f !== "metadata.sqlite");
  expect(files).toHaveLength(1);
  const db = new DatabaseSync(join(rooms, files[0] as string));
  const row = db.prepare("SELECT json FROM room WHERE id = 1").get() as { json: string };
  const state = JSON.parse(row.json) as RoomState;
  edit(state);
  db.prepare("UPDATE room SET json = ? WHERE id = 1").run(JSON.stringify(state));
  db.close();
}

/** Stops a persistent worker, as a deploy or crash would. */
/**
 * Waits until the room has finished the start and saved it: a new socket is served only after
 * the event before it. Without this a restart can land between the "playing" snapshot reaching
 * the client and the room's write, and the room comes back in the lobby.
 */
async function settled(mf: Miniflare, code: string, device: Device): Promise<void> {
  const probe = await connect(mf, code, device);
  expect((await probe.snapshot()).room.status).toBe("playing");
  probe.ws.close();
}

async function restart(mf: Miniflare): Promise<void> {
  await mf.dispose();
  open.splice(open.indexOf(mf), 1);
}

function tempDir(): string {
  const dir = mkdtempSync(join(tmpdir(), "play-api-"));
  dirs.push(dir);
  return dir;
}

async function mint(mf: Miniflare, ip = "198.51.100.7"): Promise<Device> {
  const res = await mf.dispatchFetch(`${BASE}/v1/devices`, {
    method: "POST",
    headers: { "cf-connecting-ip": ip },
  });
  expect(res.status).toBe(200);
  return (await res.json()) as Device;
}

const auth = (device: Device) => ({ authorization: `Bearer ${device.token}` });

async function createRoom(mf: Miniflare, device: Device, name?: string): Promise<string> {
  const res = await mf.dispatchFetch(`${BASE}/v1/rooms`, {
    method: "POST",
    headers: { ...auth(device), "content-type": "application/json" },
    body: JSON.stringify(name === undefined ? { game: "cat-tower" } : { game: "cat-tower", name }),
  });
  expect(res.status).toBe(201);
  const { code } = (await res.json()) as { code: string };
  return code;
}

async function tables(mf: Miniflare, device: Device): Promise<Table[]> {
  const res = await mf.dispatchFetch(`${BASE}/v1/devices/me/tables`, { headers: auth(device) });
  expect(res.status).toBe(200);
  return ((await res.json()) as { tables: Table[] }).tables;
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

/** A real WebSocket to the room that queues every frame it receives. */
class Client {
  readonly received: ServerMessage[] = [];
  private cursor = 0;
  closed: { code: number } | null = null;
  private waiters: (() => void)[] = [];

  constructor(readonly ws: WebSocket) {
    ws.addEventListener("message", (e) => {
      this.received.push(JSON.parse(e.data as string) as ServerMessage);
      this.wake();
    });
    ws.addEventListener("close", (e) => {
      this.closed = { code: e.code };
      this.wake();
    });
  }

  private wake(): void {
    for (const w of this.waiters.splice(0)) w();
  }

  send(value: unknown): void {
    this.ws.send(typeof value === "string" ? value : JSON.stringify(value));
  }

  /** The next unread message matching `match`; earlier unread ones are skipped. */
  async next<M extends ServerMessage = ServerMessage>(
    match: (m: ServerMessage) => boolean = () => true,
    within = 5000,
  ): Promise<M> {
    const end = Date.now() + within;
    for (;;) {
      while (this.cursor < this.received.length) {
        const m = this.received[this.cursor++] as ServerMessage;
        if (match(m)) return m as M;
      }
      if (Date.now() > end) throw new Error(`timed out; got ${JSON.stringify(this.received)}`);
      await new Promise<void>((resolve) => {
        this.waiters.push(resolve);
        setTimeout(resolve, 100);
      });
    }
  }

  snapshot(): Promise<Snapshot> {
    return this.next<Snapshot>((m) => m.t === "snapshot");
  }

  async waitClosed(): Promise<{ code: number }> {
    const end = Date.now() + 5000;
    while (!this.closed && Date.now() < end) {
      await new Promise<void>((resolve) => {
        this.waiters.push(resolve);
        setTimeout(resolve, 100);
      });
    }
    if (!this.closed) throw new Error("socket did not close");
    return this.closed;
  }
}

async function connect(
  mf: Miniflare,
  code: string,
  device: Device,
  headers: Record<string, string> = {},
): Promise<Client> {
  const res = await mf.dispatchFetch(`${BASE}/v1/rooms/${code}/ws`, {
    headers: { ...auth(device), upgrade: "websocket", ...headers },
  });
  expect(res.status).toBe(101);
  const ws = res.webSocket as unknown as WebSocket & { accept(): void };
  expect(ws).toBeTruthy();
  ws.accept();
  return new Client(ws);
}

/** Two devices in one room, seated at 0 (Alice) and 1 (Bob), game started. */
async function startedGame(mf: Miniflare) {
  const alice = await mint(mf);
  const bob = await mint(mf);
  const code = await createRoom(mf, alice);
  const a = await connect(mf, code, alice);
  const b = await connect(mf, code, bob);
  await a.snapshot();
  await b.snapshot();
  a.send({ t: "claim", seat: 0, person: ALICE });
  await a.snapshot();
  b.send({ t: "claim", seat: 1, person: BOB });
  await b.next((m) => m.t === "snapshot" && m.room.seats[1]?.kind === "human");
  a.send({ t: "start" });
  const sa = await a.next<Snapshot>((m) => m.t === "snapshot" && m.room.status === "playing");
  const sb = await b.next<Snapshot>((m) => m.t === "snapshot" && m.room.status === "playing");
  return { alice, bob, code, a, b, sa, sb };
}

describe("worker", { timeout: 20_000 }, () => {
  test("healthz reports the service and whether TOKEN_SECRET is set", async () => {
    const res = await worker().dispatchFetch(`${BASE}/healthz`);
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(await res.json()).toEqual({ ok: true, service: "play-api", configured: true });

    const bare = await worker({ secret: null }).dispatchFetch(`${BASE}/healthz`);
    expect(await bare.json()).toEqual({ ok: true, service: "play-api", configured: false });

    const fast = await worker({ devSpeed: "10" }).dispatchFetch(`${BASE}/healthz`);
    expect(await fast.json()).toEqual({ ok: true, service: "play-api", configured: true, speed: 10 });
  });

  test("universal links: the association file and the share page need no token", async () => {
    const mf = worker({ secret: null, testflight: "https://testflight.apple.com/join/abc123" });
    const aasa = await mf.dispatchFetch(`${BASE}/.well-known/apple-app-site-association`);
    expect(aasa.status).toBe(200);
    expect(aasa.headers.get("content-type")).toBe("application/json");
    expect(await aasa.json()).toEqual({
      applinks: {
        details: [{ appIDs: ["B222J9J7B8.com.conleychaos.play"], components: [{ "/": "/j/*" }] }],
      },
    });

    const page = await mf.dispatchFetch(`${BASE}/j/BCDFG`);
    expect(page.headers.get("content-type")).toBe("text/html; charset=utf-8");
    const html = await page.text();
    // No such table: the expired page, which needs no token either.
    expect(page.status).toBe(404);
    expect(html).toContain("This invite has expired");
    expect(html).toContain('<a class="go" href="https://testflight.apple.com/join/abc123">Get Pounce</a>');

    for (const path of ["/j/bad!", "/j/BCDFG/extra", "/j/", "/j/%E0%A4%A"]) {
      expect((await mf.dispatchFetch(`${BASE}${path}`)).status, path).toBe(404);
    }
    const post = await mf.dispatchFetch(`${BASE}/j/BCDFG`, { method: "POST" });
    expect(post.status).toBe(404);
  });

  test("the privacy policy is served at /privacy without a token", async () => {
    const mf = worker({ secret: null });
    const res = await mf.dispatchFetch(`${BASE}/privacy`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
    expect(await res.text()).toContain('id="coppa"');
    expect((await mf.dispatchFetch(`${BASE}/privacy`, { method: "POST" })).status).toBe(404);
    expect((await mf.dispatchFetch(`${BASE}/privacy/extra`)).status).toBe(404);
  });

  test("the home and support pages are public and the home page hides the install link until configured", async () => {
    const mf = worker({ secret: null });
    const support = await mf.dispatchFetch(`${BASE}/support`);
    expect(support.status).toBe(200);
    expect(await support.text()).toContain("House Cat");
    const home = await mf.dispatchFetch(`${BASE}/`);
    expect(home.status).toBe(200);
    expect(await home.text()).not.toContain("Get the app");
    expect((await mf.dispatchFetch(`${BASE}/`, { method: "POST" })).status).toBe(404);
    expect((await mf.dispatchFetch(`${BASE}/support/extra`)).status).toBe(404);
  });

  test("the share image is served as a jpeg without a token", async () => {
    const res = await worker({ secret: null }).dispatchFetch(`${BASE}/og/room.jpg`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("image/jpeg");
    const bytes = new Uint8Array(await res.arrayBuffer());
    expect([bytes[0], bytes[1]]).toEqual([0xff, 0xd8]);
  });

  test("device mint returns a verifiable token; rooms require it", async () => {
    const mf = worker();
    const device = await mint(mf);
    expect(device.deviceId).toMatch(/^[A-Za-z0-9_-]{24}$/);
    expect(device.token.startsWith(`v1.${device.deviceId}.`)).toBe(true);

    const none = await mf.dispatchFetch(`${BASE}/v1/rooms`, {
      method: "POST",
      body: JSON.stringify({ game: "cat-tower" }),
    });
    expect(none.status).toBe(401);
    expect(none.headers.get("cache-control")).toBe("no-store");
    expect(await none.json()).toEqual({ error: "unauthorized" });

    const forged = await mf.dispatchFetch(`${BASE}/v1/rooms`, {
      method: "POST",
      headers: { authorization: `Bearer ${device.token}x` },
      body: JSON.stringify({ game: "cat-tower" }),
    });
    expect(forged.status).toBe(401);

    for (const path of ["/v1/devices/me/tables", "/v1/rooms/BCDFG/ws"]) {
      expect((await mf.dispatchFetch(`${BASE}${path}`)).status).toBe(401);
    }
    const push = await mf.dispatchFetch(`${BASE}/v1/devices/me/push`, {
      method: "PUT",
      body: JSON.stringify({ apnsToken: "a".repeat(64) }),
    });
    expect(push.status).toBe(401);

    const code = await createRoom(mf, device);
    expect(code).toMatch(/^[BCDFGHJKLMNPQRTVWXZ2346789]{5}$/);
  });

  test("device mint is limited to 10 per minute per IP", async () => {
    const mf = worker();
    for (let i = 0; i < 10; i++) await mint(mf, "203.0.113.1");
    const limited = await mf.dispatchFetch(`${BASE}/v1/devices`, {
      method: "POST",
      headers: { "cf-connecting-ip": "203.0.113.1" },
    });
    expect(limited.status).toBe(429);
    expect(await limited.json()).toEqual({ error: "rate_limited" });
    // Another address is unaffected.
    await mint(mf, "203.0.113.2");
  });

  test("an unconfigured worker refuses to mint or authenticate", async () => {
    const mf = worker({ secret: null });
    const res = await mf.dispatchFetch(`${BASE}/v1/devices`, { method: "POST" });
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: "not_configured" });
  });

  test("bad requests: room body, code shape, upgrade, push token, unknown routes", async () => {
    const mf = worker();
    const device = await mint(mf);
    const names = ["", "   ", "x".repeat(31), "tab\there", 7, null].map((name) =>
      JSON.stringify({ game: "cat-tower", name }),
    );
    for (const body of ["", "nope", "{}", '{"game":"other"}', '{"game":"cat-tower","x":1}', "[]", ...names]) {
      const res = await mf.dispatchFetch(`${BASE}/v1/rooms`, {
        method: "POST",
        headers: auth(device),
        body,
      });
      expect(res.status, body).toBe(400);
      expect(await res.json()).toEqual({ error: "bad_request" });
    }

    for (const code of ["bcdfg", "BCDF", "BCDFGH", "AEIOU", "BCDF1"]) {
      const res = await mf.dispatchFetch(`${BASE}/v1/rooms/${code}/ws`, {
        headers: { ...auth(device), upgrade: "websocket" },
      });
      expect(res.status, code).toBe(404);
    }
    const plain = await mf.dispatchFetch(`${BASE}/v1/rooms/BCDFG/ws`, { headers: auth(device) });
    expect(plain.status).toBe(426);
    // A well-formed code with no room behind it.
    const missing = await mf.dispatchFetch(`${BASE}/v1/rooms/BCDFG/ws`, {
      headers: { ...auth(device), upgrade: "websocket" },
    });
    expect(missing.status).toBe(404);

    for (const apnsToken of ["a".repeat(63), "a".repeat(201), "g".repeat(64), 7]) {
      const res = await mf.dispatchFetch(`${BASE}/v1/devices/me/push`, {
        method: "PUT",
        headers: auth(device),
        body: JSON.stringify({ apnsToken }),
      });
      expect(res.status).toBe(400);
    }
    const stored = await mf.dispatchFetch(`${BASE}/v1/devices/me/push`, {
      method: "PUT",
      headers: auth(device),
      body: JSON.stringify({ apnsToken: "aB".repeat(32) }),
    });
    expect(stored.status).toBe(204);

    for (const [method, path] of [
      ["POST", "/"],
      ["GET", "/v1/rooms"],
      ["DELETE", "/v1/devices/me/push"],
    ] as const) {
      const res = await mf.dispatchFetch(`${BASE}${path}`, { method, headers: auth(device) });
      expect(res.status, path).toBe(404);
      expect(res.headers.get("cache-control")).toBe("no-store");
      expect(await res.json()).toEqual({ error: "not_found" });
    }
  });

  test("two devices claim, start, draw and discard; each sees only its own hand", async () => {
    const mf = worker();
    const { a, b, sa, sb } = await startedGame(mf);
    const ga = sa.room.game as CatTowerView;
    const gb = sb.room.game as CatTowerView;
    expect(Object.keys(ga.hands)).toEqual(["0"]);
    expect(Object.keys(gb.hands)).toEqual(["1"]);
    expect([sa.protocol, sb.protocol]).toEqual([1, 1]);
    expect(sa.room.seats.map((s) => s.yours)).toEqual([true, false]);
    expect(sb.room.seats.map((s) => s.yours)).toEqual([false, true]);

    const turn = ga.turn;
    const [me, other] = turn === 0 ? [a, b] : [b, a];
    const hand = (turn === 0 ? ga : gb).hands[turn] as number[];

    me.send({ t: "act", seat: turn, action: { type: "draw", from: "deck" } });
    const drewMine = await me.next((m) => m.t === "event" && m.event.kind === "game");
    const drewOther = await other.next((m) => m.t === "event" && m.event.kind === "game");
    const mine = drewMine.t === "event" && drewMine.event.kind === "game" ? drewMine.event.event : null;
    const theirs =
      drewOther.t === "event" && drewOther.event.kind === "game" ? drewOther.event.event : null;
    expect(mine).toMatchObject({ kind: "drew", seat: turn, from: "deck" });
    expect(mine && "card" in mine && typeof mine.card).toBe("number");
    expect(theirs).toEqual({ kind: "drew", seat: turn, from: "deck" });

    const discard = [...hand, (mine as { card: number }).card].find(
      (id) => card(id).kind === "number",
    ) as number;
    me.send({ t: "act", seat: turn, action: { type: "discard", card: discard } });
    for (const client of [me, other]) {
      const e = await client.next(
        (m) => m.t === "event" && m.event.kind === "game" && m.event.event.kind === "discarded",
      );
      expect(e).toMatchObject({ event: { event: { kind: "discarded", seat: turn, card: discard } } });
      await client.next(
        (m) => m.t === "event" && m.event.kind === "game" && m.event.event.kind === "turn",
      );
    }
  });

  test("garbage WebSocket frames get bad_message and the socket stays open", async () => {
    const mf = worker();
    const alice = await mint(mf);
    const code = await createRoom(mf, alice);
    const a = await connect(mf, code, alice);
    await a.snapshot();

    a.send("not json");
    expect(await a.next()).toEqual({ t: "error", code: "bad_message" });
    a.send({ t: "dance" });
    expect(await a.next()).toEqual({ t: "error", code: "bad_message" });
    a.send(JSON.stringify({ t: "start", pad: "x".repeat(9000) }));
    expect(await a.next()).toEqual({ t: "error", code: "bad_message" });
    a.ws.send(new Uint8Array([1, 2, 3]));
    expect(await a.next()).toEqual({ t: "error", code: "bad_message" });
    expect(a.closed).toBeNull();

    a.send({ t: "claim", seat: 0, person: ALICE });
    const snap = await a.snapshot();
    expect(snap.room.seats[0]).toMatchObject({ kind: "human", person: ALICE, yours: true });
  });

  test("a client-supplied x-play-device header is ignored", async () => {
    const mf = worker();
    const alice = await mint(mf);
    const bob = await mint(mf);
    const code = await createRoom(mf, alice);
    const b = await connect(mf, code, bob, { "x-play-device": alice.deviceId });
    const snap = await b.snapshot();
    expect(snap.room.youAreHost).toBe(false);
    b.send({ t: "claim", seat: 1, person: BOB });
    await b.snapshot();
    const a = await connect(mf, code, alice);
    const sa = await a.snapshot();
    expect(sa.room.youAreHost).toBe(true);
    expect(sa.room.seats[1]).toMatchObject({ kind: "human", yours: false });
  });

  test("tables list shows the room for both devices, with whose turn it is", async () => {
    const mf = worker();
    const { alice, bob, code, sa } = await startedGame(mf);
    const turn = (sa.room.game as CatTowerView).turn;
    const ta = await eventually(
      () => tables(mf, alice),
      (t) => t[0]?.status === "playing",
    );
    const tb = await eventually(
      () => tables(mf, bob),
      (t) => t[0]?.status === "playing",
    );
    const name = defaultRoomName(code);
    // Each list carries who sits where, with the list owner's own seat marked.
    const seat = (person: typeof ALICE, yours: boolean) => ({ kind: "human", person, ...(yours ? { yours: true } : {}) });
    expect(ta).toEqual([
      { code, name, status: "playing", yourTurn: turn === 0, updatedAt: expect.any(Number), movedAt: expect.any(Number), seats: [seat(ALICE, true), seat(BOB, false)] },
    ]);
    expect(tb).toEqual([
      { code, name, status: "playing", yourTurn: turn === 1, updatedAt: expect.any(Number), movedAt: expect.any(Number), seats: [seat(ALICE, false), seat(BOB, true)] },
    ]);
  });

  test("a fresh room is listed for its host only", async () => {
    const mf = worker();
    const alice = await mint(mf);
    const bob = await mint(mf);
    const code = await createRoom(mf, alice);
    const ta = await eventually(
      () => tables(mf, alice),
      (t) => t.length > 0,
    );
    expect(ta).toEqual([
      {
        code,
        name: defaultRoomName(code),
        status: "lobby",
        yourTurn: false,
        updatedAt: expect.any(Number),
        seats: LOBBY,
      },
    ]);
    expect(await tables(mf, bob)).toEqual([]);
  });

  test("a table named at creation keeps its name; a rename reaches every socket and the tables list", async () => {
    const mf = worker();
    const alice = await mint(mf);
    const bob = await mint(mf);
    const code = await createRoom(mf, alice, "  Taco   Night ");
    const a = await connect(mf, code, alice);
    const b = await connect(mf, code, bob);
    expect((await a.snapshot()).room.name).toBe("Taco Night");
    expect((await b.snapshot()).room.name).toBe("Taco Night");
    expect(
      await eventually(
        () => tables(mf, alice),
        (t) => t.length > 0,
      ),
    ).toEqual([
      {
        code,
        name: "Taco Night",
        status: "lobby",
        yourTurn: false,
        updatedAt: expect.any(Number),
        seats: LOBBY,
      },
    ]);

    // Bob holds no seat and isn't the host: refused.
    b.send({ t: "rename", name: "Bob's Table" });
    expect(await b.next((m) => m.t === "error")).toEqual({ t: "error", code: "not_seated" });

    b.send({ t: "claim", seat: 1, person: BOB });
    await b.next((m) => m.t === "snapshot" && m.room.seats[1]?.kind === "human");
    b.send({ t: "rename", name: "Bob's Table" });
    expect((await a.next<Snapshot>((m) => m.t === "snapshot" && m.room.name !== "Taco Night")).room.name).toBe(
      "Bob's Table",
    );
    expect((await b.next<Snapshot>((m) => m.t === "snapshot" && m.room.name !== "Taco Night")).room.name).toBe(
      "Bob's Table",
    );
    const listed = await eventually(
      () => tables(mf, bob),
      (t) => t[0]?.name === "Bob's Table",
    );
    expect(listed[0]?.name).toBe("Bob's Table");
    expect(listed[0]?.seats?.[1]).toEqual({ kind: "human", person: BOB, yours: true });
    expect((await tables(mf, alice))[0]?.name).toBe("Bob's Table");
    // Bob's seat is on the host's list too, as someone else's.
    expect((await tables(mf, alice))[0]?.seats?.[1]).toEqual({ kind: "human", person: BOB });
    // A seat's new name reaches the lists as well.
    b.send({ t: "renameSeat", seat: 1, name: "Robert" });
    const renamed = await eventually(
      () => tables(mf, alice),
      (t) => t[0]?.seats?.[1]?.person?.name === "Robert",
    );
    expect(renamed[0]?.seats?.[1]).toEqual({ kind: "human", person: { ...BOB, name: "Robert" } });

    // A name that isn't one never reaches the room.
    a.send({ t: "rename", name: "line\nbreak" });
    expect(await a.next((m) => m.t === "error")).toEqual({ t: "error", code: "bad_message" });
  });

  test("a room saved before tables had names loads with its default name", async () => {
    const dir = tempDir();
    const mf1 = worker({ persist: dir });
    const alice = await mint(mf1);
    const code = await createRoom(mf1, alice, "Taco Night");
    await (await connect(mf1, code, alice)).snapshot();
    await restart(mf1);
    await editStoredRoom(dir, (state) => {
      delete (state as Partial<RoomState>).name;
    });

    const mf2 = worker({ persist: dir });
    const after = await (await connect(mf2, code, alice)).snapshot();
    expect(after.room.name).toBe(defaultRoomName(code));
  });

  test("a device that leaves its seat drops the room from its tables", async () => {
    const mf = worker();
    const alice = await mint(mf);
    const bob = await mint(mf);
    const code = await createRoom(mf, alice);
    const b = await connect(mf, code, bob);
    await b.snapshot();
    b.send({ t: "claim", seat: 1, person: BOB });
    await b.snapshot();
    await eventually(
      () => tables(mf, bob),
      (t) => t.length === 1,
    );
    b.send({ t: "leave", seat: 1 });
    await b.snapshot();
    expect(
      await eventually(
        () => tables(mf, bob),
        (t) => t.length === 0,
      ),
    ).toEqual([]);
  });

  test("closing one of two sockets keeps the device awake", async () => {
    const mf = worker();
    const alice = await mint(mf);
    const bob = await mint(mf);
    const code = await createRoom(mf, alice);
    const a1 = await connect(mf, code, alice);
    await a1.snapshot();
    a1.send({ t: "claim", seat: 0, person: ALICE });
    await a1.snapshot();
    const a2 = await connect(mf, code, alice);
    await a2.snapshot();
    const b = await connect(mf, code, bob);
    await b.snapshot();

    a1.ws.close(1000);
    await new Promise((resolve) => setTimeout(resolve, 300));
    const b2 = await connect(mf, code, bob);
    expect((await b2.snapshot()).room.seats[0]?.presence).toBe("awake");

    a2.ws.close(1000);
    const away = await b.next((m) => m.t === "event" && m.event.kind === "presence");
    expect(away).toMatchObject({ event: { kind: "presence", seat: 0, presence: "away" } });
  });

  // workerd evicts an idle Durable Object after about 10 s and keeps its
  // hibernatable sockets open, so the next frame lands on a fresh instance with
  // nothing in memory. A restart cannot show this: every path after a restart
  // starts with a connect.
  test.concurrent("a device that leaves after hibernation still drops the room from its tables", async ({ onTestFinished }) => {
    const mf = worker({ onFinished: onTestFinished });
    const alice = await mint(mf);
    const bob = await mint(mf);
    const code = await createRoom(mf, alice);
    const b = await connect(mf, code, bob);
    await b.snapshot();
    b.send({ t: "claim", seat: 1, person: BOB });
    await b.snapshot();
    await eventually(
      () => tables(mf, bob),
      (t) => t.length === 1,
    );

    await new Promise((resolve) => setTimeout(resolve, HIBERNATE_MS));
    b.send({ t: "leave", seat: 1 });
    await b.snapshot();
    expect(
      await eventually(
        () => tables(mf, bob),
        (t) => t.length === 0,
      ),
    ).toEqual([]);
    expect(await tables(mf, alice)).toEqual([
      {
        code,
        name: defaultRoomName(code),
        status: "lobby",
        yourTurn: false,
        updatedAt: expect.any(Number),
        seats: LOBBY,
      },
    ]);
  });

  test.concurrent("after hibernation, a presence-only change leaves the tables untouched", async ({ onTestFinished }) => {
    const mf = worker({ onFinished: onTestFinished });
    const alice = await mint(mf);
    const bob = await mint(mf);
    const code = await createRoom(mf, alice);
    const a = await connect(mf, code, alice);
    await a.snapshot();
    const b = await connect(mf, code, bob);
    await b.snapshot();
    b.send({ t: "claim", seat: 1, person: BOB });
    await b.snapshot();
    const before = {
      alice: await eventually(
        () => tables(mf, alice),
        (t) => t.length === 1,
      ),
      bob: await eventually(
        () => tables(mf, bob),
        (t) => t.length === 1,
      ),
    };

    await new Promise((resolve) => setTimeout(resolve, HIBERNATE_MS));
    b.send({ t: "presence", state: "background" });
    await a.next((m) => m.t === "event" && m.event.kind === "presence" && m.event.presence === "away");
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect({ alice: await tables(mf, alice), bob: await tables(mf, bob) }).toEqual(before);
  });

  test("after a restart, a presence-only change leaves the tables untouched", async () => {
    const dir = tempDir();
    const mf1 = worker({ persist: dir });
    const alice = await mint(mf1);
    const bob = await mint(mf1);
    const code = await createRoom(mf1, alice);
    const b1 = await connect(mf1, code, bob);
    await b1.snapshot();
    b1.send({ t: "claim", seat: 1, person: BOB });
    await b1.snapshot();
    const before = {
      alice: await eventually(
        () => tables(mf1, alice),
        (t) => t.length === 1,
      ),
      bob: await eventually(
        () => tables(mf1, bob),
        (t) => t.length === 1,
      ),
    };
    await restart(mf1);

    const mf2 = worker({ persist: dir });
    const a = await connect(mf2, code, alice);
    await a.snapshot();
    // Bob's device reconnecting is a presence event for his seat.
    const b2 = await connect(mf2, code, bob);
    await b2.snapshot();
    b2.send({ t: "presence", state: "background" });
    await a.next((m) => m.t === "event" && m.event.kind === "presence" && m.event.presence === "away");
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect({ alice: await tables(mf2, alice), bob: await tables(mf2, bob) }).toEqual(before);
  });

  test("room survives a restart: state reloads from storage", async () => {
    const dir = tempDir();
    const mf1 = worker({ persist: dir });
    const { alice, code, a, sa } = await startedGame(mf1);
    const turn = (sa.room.game as CatTowerView).turn;
    if (turn === 0) {
      a.send({ t: "act", seat: 0, action: { type: "draw", from: "deck" } });
      await a.next((m) => m.t === "event" && m.event.kind === "game");
    }
    const before = await (await connect(mf1, code, alice)).snapshot();
    await restart(mf1);

    const mf2 = worker({ persist: dir });
    const after = await (await connect(mf2, code, alice)).snapshot();
    // The game is untouched. Only presence moved on: Bob's socket died in the
    // restart, and each presence change took a seq.
    const awayBob = structuredClone(before.room);
    (awayBob.seats[1] as { presence: string }).presence = "away";
    // The wait to retire a stalled seat counts down between the two snapshots.
    delete awayBob.retire;
    delete after.room.retire;
    expect(after.room).toEqual(awayBob);
    expect(after.seq).toBeGreaterThan(before.seq);
    expect(after.room.status).toBe("playing");
  });

  test("a new round sends both sockets a snapshot with their own new hand", async () => {
    const dir = tempDir();
    const mf1 = worker({ persist: dir });
    const { alice, bob, code, sa, sb } = await startedGame(mf1);
    const dealt = {
      a: (sa.room.game as CatTowerView).hands[0] as number[],
      b: (sb.room.game as CatTowerView).hands[1] as number[],
    };
    await settled(mf1, code, alice);
    await restart(mf1);

    // Seat 0 is to draw from a deck that cannot be refilled: drawing ends the round.
    await editStoredRoom(dir, (state) => {
      const game = state.gameState as CatTowerState;
      game.deck = [];
      game.discard = [game.discard.at(-1) as number];
      game.turn = 0;
      game.step = "draw";
    });

    const mf2 = worker({ persist: dir });
    const a = await connect(mf2, code, alice);
    await a.snapshot();
    const b = await connect(mf2, code, bob);
    await b.snapshot();
    a.send({ t: "act", seat: 0, action: { type: "draw", from: "deck" } });
    for (const client of [a, b]) {
      await client.next((m) => m.t === "event" && m.event.kind === "game" && m.event.event.kind === "roundOver");
    }
    b.send({ t: "act", seat: 1, action: { type: "nextRound" } });

    const round2 = (m: ServerMessage) => m.t === "snapshot" && (m.room.game as CatTowerView).round === 2;
    const na = (await a.next<Snapshot>(round2)).room.game as CatTowerView;
    const nb = (await b.next<Snapshot>(round2)).room.game as CatTowerView;
    expect(Object.keys(na.hands)).toEqual(["0"]);
    expect(Object.keys(nb.hands)).toEqual(["1"]);
    expect(na.hands[0]).toHaveLength(10);
    expect(nb.hands[1]).toHaveLength(10);
    expect(na.hands[0]).not.toEqual(dealt.a);
    expect(nb.hands[1]).not.toEqual(dealt.b);
    expect(na.laid).toEqual([null, null]);
    expect(na.deckCount).toBe(nb.deckCount);
    expect(na.deckCount).toBe(108 - 20 - 1);
  });

  test("after a restart, a device whose socket died shows as away", async () => {
    const dir = tempDir();
    const mf1 = worker({ persist: dir });
    const { alice, code, sa } = await startedGame(mf1);
    expect(sa.room.seats.map((s) => s.presence)).toEqual(["awake", "awake"]);
    await settled(mf1, code, alice);
    await restart(mf1);

    // Bob's socket died with the old instance; only Alice comes back.
    const mf2 = worker({ persist: dir });
    const a = await connect(mf2, code, alice);
    expect((await a.snapshot()).room.seats.map((s) => s.presence)).toEqual(["awake", "away"]);
    // And the correction was saved: a second connect sees the same.
    const a2 = await connect(mf2, code, alice);
    expect((await a2.snapshot()).room.seats.map((s) => s.presence)).toEqual(["awake", "away"]);
  });

  test("an expired room closes every socket, forgets its tables and deletes itself", async () => {
    const dir = tempDir();
    const mf1 = worker({ persist: dir });
    const alice = await mint(mf1);
    const bob = await mint(mf1);
    const code = await createRoom(mf1, alice);
    await eventually(
      () => tables(mf1, alice),
      (t) => t.length === 1,
    );
    await restart(mf1);

    // Bring the stored room's cleanup time to two seconds from now. The
    // alarm is re-armed from the stored timers on the next call into the room.
    await editStoredRoom(dir, (state) => {
      state.timers.cleanupAt = Date.now() + 2000;
      // A game closes 30 days after its last move, whatever the stored timer says.
      state.lastActivity = Date.now() + 2000 - 30 * 24 * 60 * 60_000;
    });

    const mf2 = worker({ persist: dir });
    const clients = [await connect(mf2, code, alice), await connect(mf2, code, bob)];
    for (const client of clients) {
      await client.snapshot();
      // Miniflare only delivers a server-initiated close from alarm() to a
      // hibernatable socket that has sent at least one frame (see report).
      client.send({ t: "presence", state: "active" });
    }
    for (const client of clients) {
      expect(await client.next((m) => m.t === "error")).toEqual({ t: "error", code: "room_closed" });
      expect((await client.waitClosed()).code).toBe(1000);
    }
    expect(
      await eventually(
        () => tables(mf2, alice),
        (t) => t.length === 0,
      ),
    ).toEqual([]);
    const gone = await mf2.dispatchFetch(`${BASE}/v1/rooms/${code}/ws`, {
      headers: { ...auth(alice), upgrade: "websocket" },
    });
    expect(gone.status).toBe(404);

    // Deleted from storage too, not just forgotten in memory.
    await restart(mf2);
    const mf3 = worker({ persist: dir });
    const stillGone = await mf3.dispatchFetch(`${BASE}/v1/rooms/${code}/ws`, {
      headers: { ...auth(alice), upgrade: "websocket" },
    });
    expect(stillGone.status).toBe(404);
  });

  describe("bad connections (LINK)", () => {
    test("the room answers pings itself and snapshots say so", async () => {
      const mf = worker({ link: true });
      const { a, sa } = await startedGame(mf);
      expect(sa.room.link).toEqual({ ping: 3000, acks: [] });
      a.send({ t: "ping" });
      expect(await a.next((m) => m.t === "pong")).toEqual({ t: "pong" });
      // Off, no `link` in snapshots (and a ping still gets its pong, from the room itself).
      const off = await startedGame(worker());
      expect(off.sa.room.link).toBeUndefined();
      off.a.send({ t: "ping" });
      expect(await off.a.next((m) => m.t === "pong")).toEqual({ t: "pong" });
    });

    test("a socket that drops shows the seat as lost to the others; a close it asked for does not", async () => {
      const mf = worker({ link: true });
      const { bob, code, a, b } = await startedGame(mf);
      b.ws.close(4000, "network gone");
      expect(await a.next((m) => m.t === "link")).toEqual({ t: "link", seats: [null, "lost"] });
      const again = await connect(mf, code, bob);
      expect((await again.snapshot()).room.seats[1]?.link).toBeUndefined();
      expect(await a.next((m) => m.t === "link")).toEqual({ t: "link", seats: [null, null] });
      again.ws.close(1000);
      const away = await a.next((m) => m.t === "event" && m.event.kind === "presence");
      expect(away).toMatchObject({ event: { kind: "presence", seat: 1, presence: "away" } });
      expect(a.received.filter((m) => m.t === "link")).toHaveLength(2);
    });

    test("a move sent twice with one id is applied once", async () => {
      const mf = worker({ link: true });
      const { a, b, sb } = await startedGame(mf);
      const turn = (sb.room.game as CatTowerView).turn;
      const mover = turn === 0 ? a : b;
      const move = { t: "act", seat: turn, action: { type: "draw", from: "deck" }, id: "move-1" };
      mover.send(move);
      const applied = await mover.next<Snapshot>((m) => m.t === "snapshot" && m.room.link?.acks.includes("move-1") === true);
      const deck = (applied.room.game as CatTowerView).deckCount;
      mover.send(move);
      const answer = await mover.next();
      expect(answer.t).toBe("snapshot");
      expect(((answer as Snapshot).room.game as CatTowerView).deckCount).toBe(deck);
    });

    test.concurrent("a phone that goes silent turns weak for the others", async ({ onTestFinished }) => {
      const mf = worker({ link: true, onFinished: onTestFinished });
      const { a } = await startedGame(mf);
      // Alice keeps pinging; Bob's phone says nothing at all.
      const beat = setInterval(() => a.send({ t: "ping" }), 1000);
      onTestFinished(() => clearInterval(beat));
      const weak = await a.next((m) => m.t === "link", 12_000);
      expect(weak).toEqual({ t: "link", seats: [null, "weak"] });
    }, 20_000);
  });
});
