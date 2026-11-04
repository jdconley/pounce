import { build } from "esbuild";
import { Miniflare, Response as MiniflareResponse, type Request as MiniflareRequest } from "miniflare";
import { afterEach, beforeAll, describe, expect, test } from "vitest";

import { base64url, sha256Hex } from "../src/players/ids";

import type { ServerMessage } from "../src/protocol";

const SECRET = "s".repeat(64);
const BASE = "https://play.conleychaos.com";
const CLIENT_ID = "com.conleychaos.play";
const encoder = new TextEncoder();

type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;
type Device = { deviceId: string; token: string };
type Person = { id: string; name: string; cat: number; key: string; ageBand?: string; at?: number };

let script = "";
let rsa: CryptoKeyPair;
let jwk: JsonWebKey;
const open: Miniflare[] = [];

beforeAll(async () => {
  const built = await build({
    entryPoints: [new URL("./accounts-entry.ts", import.meta.url).pathname],
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
});

/** Device tokens APNs was asked to deliver to, with the push type. */
let apnsSent: { token: string; type: string | null }[] = [];

async function p8(): Promise<string> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign"])) as CryptoKeyPair;
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  return `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----\n`;
}

/** Calls to Apple's token and revoke endpoints. Each authorization code works once, as at Apple. */
let appleCalls: { path: string; form: URLSearchParams }[] = [];

function worker(push?: { p8: string }, siwa?: { p8: string }): Miniflare {
  apnsSent = [];
  appleCalls = [];
  const usedCodes = new Set<string>();
  const mf = new Miniflare({
    modules: true,
    script,
    compatibilityDate: "2026-08-01",
    durableObjects: {
      ROOMS: { className: "GameRoom", useSQLite: true },
      DEVICES: { className: "DeviceIndex", useSQLite: true },
      PLAYERS: { className: "Player", useSQLite: true },
      IDENTITIES: { className: "Identities", useSQLite: true },
    },
    bindings: {
      TOKEN_SECRET: SECRET,
      SIWA_CLIENT_ID: CLIENT_ID,
      APNS_TEAM_ID: "B222J9J7B8",
      APNS_TOPIC: CLIENT_ID,
      APNS_HOST: "api.push.apple.com",
      ...(push ? { APNS_KEY_P8: push.p8, APNS_KEY_ID: "KID-ACCOUNTS", DEV_SPEED: "100" } : {}),
      ...(siwa ? { SIWA_KEY_P8: siwa.p8, SIWA_KEY_ID: "KID-SIWA" } : {}),
    },
    // Stands in for Apple: the public keys, which need no secret, and APNs.
    outboundService: async (request: MiniflareRequest) => {
      if (request.url === "https://appleid.apple.com/auth/keys") {
        return new MiniflareResponse(JSON.stringify({ keys: [jwk] }), { headers: { "content-type": "application/json" } });
      }
      const { pathname } = new URL(request.url);
      if (request.url.startsWith("https://appleid.apple.com/auth/")) {
        const form = new URLSearchParams(await request.text());
        appleCalls.push({ path: pathname, form });
        const code = form.get("code");
        if (pathname === "/auth/token") {
          if (!code || usedCodes.has(code)) return new MiniflareResponse(JSON.stringify({ error: "invalid_grant" }), { status: 400 });
          usedCodes.add(code);
          return new MiniflareResponse(JSON.stringify({ refresh_token: `r-${code}` }), { headers: { "content-type": "application/json" } });
        }
        return new MiniflareResponse(null, { status: 200 });
      }
      if (new URL(request.url).host === "api.push.apple.com") {
        apnsSent.push({ token: new URL(request.url).pathname.split("/").at(-1) as string, type: request.headers.get("apns-push-type") });
        return new MiniflareResponse(null, { status: 200 });
      }
      return new MiniflareResponse(null, { status: 599 });
    },
  });
  open.push(mf);
  return mf;
}

let nonceCount = 0;

/** A Sign in with Apple proof for `sub`, signed with the test's key. */
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

const newPerson = (name: string, extra: Partial<Person> = {}): Person => ({
  id: crypto.randomUUID(),
  name,
  cat: 3,
  key: base64url(crypto.getRandomValues(new Uint8Array(32))),
  ...extra,
});

async function mint(mf: Miniflare): Promise<Device> {
  const res = await mf.dispatchFetch(`${BASE}/v1/devices`, { method: "POST", headers: { "cf-connecting-ip": crypto.randomUUID() } });
  return (await res.json()) as Device;
}

function call(
  mf: Miniflare,
  device: Device,
  method: string,
  path: string,
  body?: unknown,
  headers: Record<string, string> = {},
): Promise<Response> {
  return mf.dispatchFetch(`${BASE}${path}`, {
    method,
    headers: { authorization: `Bearer ${device.token}`, "content-type": "application/json", ...headers },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }) as unknown as Promise<Response>;
}

async function profile(mf: Miniflare, device: Device, people: Person[], ageBand = "adult") {
  const res = await call(mf, device, "PUT", "/v1/devices/me/profile", { timeZone: "America/Los_Angeles", ageBand, people });
  expect(res.status).toBe(200);
  return (await res.json()) as { players: Record<string, string>; rejected: string[] };
}

async function signIn(mf: Miniflare, device: Device, person: Person, proof: unknown, headers: Record<string, string> = {}) {
  return call(mf, device, "POST", "/v1/identities/apple", { proof, person: { id: person.id, key: person.key } }, headers);
}

/** `device` creates a room and takes seat 0 as `person`. */
async function seatedRoom(mf: Miniflare, device: Device, person: Person): Promise<string> {
  const code = await createRoom(mf, device);
  const socket = await connect(mf, code, device);
  await socket.snapshot();
  socket.send({ t: "claim", seat: 0, person: { id: person.id, name: person.name, cat: person.cat } });
  await socket.next((m) => m.t === "snapshot" && m.room.seats[0]?.kind === "human");
  socket.close();
  return code;
}

async function createRoom(mf: Miniflare, device: Device): Promise<string> {
  const res = await call(mf, device, "POST", "/v1/rooms", { game: "cat-tower" });
  return ((await res.json()) as { code: string }).code;
}

async function tables(mf: Miniflare, device: Device): Promise<string[]> {
  const res = await call(mf, device, "GET", "/v1/devices/me/tables");
  return ((await res.json()) as { tables: { code: string }[] }).tables.map((t) => t.code);
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

/** A socket that keeps every frame; `next` waits for the first unread match. */
class Client {
  private readonly received: ServerMessage[] = [];
  private cursor = 0;

  constructor(readonly ws: WebSocket) {
    ws.addEventListener("message", (e) => this.received.push(JSON.parse(e.data as string) as ServerMessage));
  }

  send(value: unknown): void {
    this.ws.send(JSON.stringify(value));
  }

  async next<M extends ServerMessage>(match: (m: ServerMessage) => boolean): Promise<M> {
    const end = Date.now() + 5000;
    for (;;) {
      while (this.cursor < this.received.length) {
        const m = this.received[this.cursor++] as ServerMessage;
        if (match(m)) return m as M;
      }
      if (Date.now() > end) throw new Error(`timed out; got ${JSON.stringify(this.received)}`);
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }

  snapshot(): Promise<Snapshot> {
    return this.next<Snapshot>((m) => m.t === "snapshot");
  }

  close(): void {
    this.ws.close(1000);
  }
}

async function connect(mf: Miniflare, code: string, device: Device, headers: Record<string, string> = {}): Promise<Client> {
  const res = await mf.dispatchFetch(`${BASE}/v1/rooms/${code}/ws`, {
    headers: { authorization: `Bearer ${device.token}`, upgrade: "websocket", ...headers },
  });
  expect(res.status).toBe(101);
  const ws = res.webSocket as unknown as WebSocket & { accept(): void };
  ws.accept();
  return new Client(ws);
}

/** Whether a fresh socket from `device` sees seat 0 as its own. */
async function ownsSeat0(mf: Miniflare, code: string, device: Device): Promise<boolean> {
  const client = await connect(mf, code, device);
  const yours = (await client.snapshot()).room.seats[0]?.yours ?? false;
  client.close();
  return yours;
}

/**
 * JD's phone: a room where JD took seat 0 before uploading a profile (as
 * today's app does), then the profile and a Sign in with Apple.
 */
async function signedInPhone(mf: Miniflare) {
  const phone = await mint(mf);
  const jd = newPerson("JD");
  const code = await createRoom(mf, phone);
  const socket = await connect(mf, code, phone);
  await socket.snapshot();
  socket.send({ t: "claim", seat: 0, person: { id: jd.id, name: jd.name, cat: jd.cat } });
  await socket.next((m) => m.t === "snapshot" && m.room.seats[0]?.kind === "human");
  socket.close();
  const { players } = await profile(mf, phone, [jd]);
  const res = await signIn(mf, phone, jd, await appleProof("apple-jd"));
  expect(res.status).toBe(200);
  const body = (await res.json()) as { playerId: string; outcome: string; account: boolean };
  return { phone, jd, code, playerId: players[jd.id] as string, signIn: body };
}

/** JD's iPad joins as a guest and signs in with the same Apple account. */
async function mergedIpad(mf: Miniflare) {
  const ipad = await mint(mf);
  const jdIpad = newPerson("JD on iPad");
  await profile(mf, ipad, [jdIpad]);
  const res = await signIn(mf, ipad, jdIpad, await appleProof("apple-jd"));
  expect(res.status).toBe(200);
  return { ipad, jdIpad, signIn: (await res.json()) as { playerId: string; outcome: string; account: boolean } };
}

describe("profiles make guest players", () => {
  test("each person gets a player, and the same one on every upload", async () => {
    const mf = worker();
    const phone = await mint(mf);
    const people = [newPerson("JD"), newPerson("Mia")];
    const first = await profile(mf, phone, people);
    expect(first.rejected).toEqual([]);
    const ids = people.map((p) => first.players[p.id]);
    for (const id of ids) expect(id).toMatch(/^p_[A-Za-z0-9_-]{22}$/);
    expect(new Set(ids).size).toBe(2);
    expect((await profile(mf, phone, people)).players).toEqual(first.players);
  });

  test("a person id without its key is rejected", async () => {
    const mf = worker();
    const jd = newPerson("JD");
    await profile(mf, await mint(mf), [jd]);
    const thief = await mint(mf);
    const result = await profile(mf, thief, [{ ...jd, key: newPerson("x").key }]);
    expect(result).toEqual({ players: {}, rejected: [jd.id] });
  });

  test("a bad profile is a 400", async () => {
    const mf = worker();
    const res = await call(mf, await mint(mf), "PUT", "/v1/devices/me/profile", { timeZone: "UTC", people: [] });
    expect(res.status).toBe(400);
  });
});

describe("Sign in with Apple", () => {
  test("a guest's first sign-in upgrades them in place and signs the device in", async () => {
    const mf = worker();
    const { playerId, signIn: body } = await signedInPhone(mf);
    expect(body).toMatchObject({ playerId, outcome: "upgraded", account: true });
  });

  test("the same token can't be used twice", async () => {
    const mf = worker();
    const phone = await mint(mf);
    const jd = newPerson("JD");
    await profile(mf, phone, [jd]);
    const proof = await appleProof("apple-jd");
    expect((await signIn(mf, phone, jd, proof)).status).toBe(200);
    expect((await signIn(mf, phone, jd, proof)).status).toBe(401);
  });

  test("a forged token, an unknown person, a wrong key and an unknown provider are refused", async () => {
    const mf = worker();
    const phone = await mint(mf);
    const jd = newPerson("JD");
    await profile(mf, phone, [jd]);
    const proof = await appleProof("apple-jd");
    const forged = { ...proof, identityToken: `${proof.identityToken.slice(0, -4)}AAAA` };
    expect((await signIn(mf, phone, jd, forged)).status).toBe(401);
    expect((await signIn(mf, phone, newPerson("ghost"), await appleProof("apple-jd"))).status).toBe(404);
    expect((await signIn(mf, phone, { ...jd, key: newPerson("x").key }, await appleProof("apple-jd"))).status).toBe(404);
    const google = await call(mf, phone, "POST", "/v1/identities/google", { proof: {}, person: { id: jd.id, key: jd.key } });
    expect(google.status).toBe(404);
  });

  test("a person under 13 can't sign in", async () => {
    const mf = worker();
    const phone = await mint(mf);
    const kid = newPerson("Mochi", { ageBand: "kitten" });
    await profile(mf, phone, [kid]);
    const res = await signIn(mf, phone, kid, await appleProof("apple-kid"));
    expect(res.status).toBe(403);
  });

  test("a signed-in person signing in with another Apple account is a conflict", async () => {
    const mf = worker();
    const { phone, jd } = await signedInPhone(mf);
    expect((await signIn(mf, phone, jd, await appleProof("apple-someone-else"))).status).toBe(409);
    const again = await signIn(mf, phone, jd, await appleProof("apple-jd"));
    expect(((await again.json()) as { outcome: string }).outcome).toBe("same");
  });

  test("a second device merges into the player and takes over its seats and tables", async () => {
    const mf = worker();
    const { code, playerId } = await signedInPhone(mf);
    const { ipad, signIn: body } = await mergedIpad(mf);
    expect(body).toMatchObject({ playerId, outcome: "merged", account: true });
    expect(await ownsSeat0(mf, code, ipad)).toBe(true);
    expect(await eventually(() => tables(mf, ipad), (codes) => codes.includes(code))).toContain(code);

    const client = await connect(mf, code, ipad);
    await client.snapshot();
    client.send({ t: "renameSeat", seat: 0, name: "Big JD" });
    const renamed = await client.next<Snapshot>((m) => m.t === "snapshot" && m.room.seats[0]?.person?.name === "Big JD");
    expect(renamed.room.seats[0]?.person?.name).toBe("Big JD");
    client.close();
  });

  test("a client can't claim players with its own x-play-player header", async () => {
    const mf = worker();
    const { code, jd, playerId } = await signedInPhone(mf);
    const stranger = await mint(mf);
    const client = await connect(mf, code, stranger, { "x-play-player": JSON.stringify({ [jd.id]: playerId }) });
    expect((await client.snapshot()).room.seats[0]?.yours).toBe(false);
    client.close();
  });
});

describe("synced state", () => {
  test("settings written on the iPad are read on the phone", async () => {
    const mf = worker();
    const { phone } = await signedInPhone(mf);
    const { ipad } = await mergedIpad(mf);
    const patch = await call(mf, ipad, "PATCH", "/v1/me/state", { settings: { sound: { v: false, at: Date.now() } } });
    expect(patch.status).toBe(204);
    const state = (await (await call(mf, phone, "GET", "/v1/me/state")).json()) as { settings: Record<string, { v: unknown }> };
    expect(state.settings.sound?.v).toBe(false);
  });

  test("a guest names the person; a device with no player gets 404", async () => {
    const mf = worker();
    const phone = await mint(mf);
    const mia = newPerson("Mia");
    await profile(mf, phone, [mia]);
    expect((await call(mf, phone, "GET", "/v1/me/state")).status).toBe(404);
    const patch = await call(mf, phone, "PATCH", `/v1/me/state?person=${mia.id}`, { tutorial: { done: { v: true, at: 1 } } });
    expect(patch.status).toBe(204);
    const state = (await (await call(mf, phone, "GET", `/v1/me/state?person=${mia.id}`)).json()) as {
      tutorial: Record<string, { v: unknown }>;
    };
    expect(state.tutorial.done?.v).toBe(true);
    expect((await call(mf, await mint(mf), "GET", `/v1/me/state?person=${mia.id}`)).status).toBe(404);
    expect((await call(mf, phone, "PATCH", `/v1/me/state?person=${mia.id}`, { nope: {} })).status).toBe(400);
  });

  test("the state carries the player's name and cat, and when they last changed", async () => {
    const mf = worker();
    const phone = await mint(mf);
    const mia = { ...newPerson("Mia"), at: 1234 };
    await profile(mf, phone, [mia]);
    const state = (await (await call(mf, phone, "GET", `/v1/me/state?person=${mia.id}`)).json()) as { profile: unknown };
    expect(state.profile).toEqual({ name: "Mia", cat: 3, at: 1234 });
    await profile(mf, phone, [{ ...mia, name: "Mochi", cat: 5, at: 1000 }]);
    const older = (await (await call(mf, phone, "GET", `/v1/me/state?person=${mia.id}`)).json()) as { profile: unknown };
    expect(older.profile).toEqual({ name: "Mia", cat: 3, at: 1234 });
  });

  test("household people on a signed-in phone follow the account to the iPad", async () => {
    const mf = worker();
    const { phone, jd } = await signedInPhone(mf);
    const mia = newPerson("Mia");
    const { players } = await profile(mf, phone, [jd, mia]);
    const { ipad } = await mergedIpad(mf);
    const ipadState = (await (await call(mf, ipad, "GET", "/v1/me/state")).json()) as { people: { personId: string; playerId: string }[] };
    expect(ipadState.people).toEqual([expect.objectContaining({ personId: mia.id, playerId: players[mia.id], name: "Mia" })]);
  });
});

describe("signing out, unlinking and deleting", () => {
  test("a device that signs out stops controlling the player's seats and starts over as a guest", async () => {
    const mf = worker();
    const { code, playerId } = await signedInPhone(mf);
    const { ipad, jdIpad } = await mergedIpad(mf);
    expect((await call(mf, ipad, "POST", "/v1/me/signout")).status).toBe(204);
    expect(await ownsSeat0(mf, code, ipad)).toBe(false);
    const { players } = await profile(mf, ipad, [jdIpad]);
    expect(players[jdIpad.id]).not.toBe(playerId);
  });

  test("linking a provider the player already has is a conflict", async () => {
    const mf = worker();
    const { phone } = await signedInPhone(mf);
    const res = await call(mf, phone, "POST", "/v1/me/identities/apple", { proof: await appleProof("apple-jd") });
    expect(res.status).toBe(409);
  });

  test("unlinking the last sign-in leaves a guest on this device and detaches the others", async () => {
    const mf = worker();
    const { phone, code } = await signedInPhone(mf);
    const { ipad } = await mergedIpad(mf);
    expect((await call(mf, phone, "DELETE", "/v1/me/identities/apple")).status).toBe(204);
    expect(await ownsSeat0(mf, code, ipad)).toBe(false);
    expect(await ownsSeat0(mf, code, phone)).toBe(true);
    expect((await call(mf, phone, "DELETE", "/v1/me/identities/apple")).status).toBe(404);
  });

  test("deleting the account keeps the game going on the phone and forgets the player everywhere", async () => {
    const mf = worker();
    const { phone, jd, code, playerId } = await signedInPhone(mf);
    const { ipad } = await mergedIpad(mf);
    await eventually(() => tables(mf, ipad), (codes) => codes.includes(code));

    expect((await call(mf, phone, "DELETE", "/v1/me")).status).toBe(204);
    expect(await ownsSeat0(mf, code, phone)).toBe(true);
    expect(await ownsSeat0(mf, code, ipad)).toBe(false);
    expect(await tables(mf, ipad)).toEqual([]);

    // Coming back makes a brand-new player.
    const { players } = await profile(mf, phone, [jd]);
    expect(players[jd.id]).not.toBe(playerId);
    const again = (await (await signIn(mf, phone, jd, await appleProof("apple-jd"))).json()) as { playerId: string; outcome: string };
    expect(again).toMatchObject({ playerId: players[jd.id], outcome: "upgraded" });
  });
});

describe("pushes reach every device of a player", () => {
  test("your turn goes to the phone and the iPad", async () => {
    const mf = worker({ p8: await p8() });
    const { phone, code } = await signedInPhone(mf);
    const { ipad } = await mergedIpad(mf);
    const PHONE = "aa".repeat(32);
    const IPAD = "bb".repeat(32);
    expect((await call(mf, phone, "PUT", "/v1/devices/me/push", { apnsToken: PHONE })).status).toBe(204);
    expect((await call(mf, ipad, "PUT", "/v1/devices/me/push", { apnsToken: IPAD })).status).toBe(204);

    const client = await connect(mf, code, phone);
    await client.snapshot();
    client.send({ t: "configure", seat: 1, kind: "bot" });
    await client.next((m) => m.t === "snapshot" && m.room.seats[1]?.kind === "bot");
    client.send({ t: "start" });
    await client.next((m) => m.t === "snapshot" && m.room.status === "playing");
    // Away on every device, so the House Cat's move hands JD a pushed turn.
    client.send({ t: "presence", state: "background" });

    const sent = await eventually(
      async () => apnsSent,
      (list) => list.length >= 2,
    );
    expect(sent.map((s) => s.token).sort()).toEqual([PHONE, IPAD]);
    expect(sent.every((s) => s.type === "alert")).toBe(true);
    client.close();
  });
});

describe("review fixes", () => {
  test("a table-mate who uploads someone else's person id first doesn't get their seat", async () => {
    const mf = worker();
    const victim = await mint(mf);
    const jd = newPerson("JD");
    const code = await seatedRoom(mf, victim, jd);
    // The attacker sits at the same table, so its profile upload reaches this room.
    const attacker = await mint(mf);
    const own = newPerson("Mallory");
    const seat = await connect(mf, code, attacker);
    await seat.snapshot();
    seat.send({ t: "claim", seat: 1, person: { id: own.id, name: own.name, cat: own.cat } });
    await seat.next((m) => m.t === "snapshot" && m.room.seats[1]?.kind === "human");
    seat.close();
    await eventually(() => tables(mf, attacker), (codes) => codes.includes(code));
    await profile(mf, attacker, [own, { ...jd, key: newPerson("x").key }]);
    expect(await ownsSeat0(mf, code, attacker)).toBe(false);
    expect(await ownsSeat0(mf, code, victim)).toBe(true);
  });

  test("the phone that claimed a seat stops controlling it once it signs out", async () => {
    const mf = worker();
    const { phone, code } = await signedInPhone(mf);
    expect(await ownsSeat0(mf, code, phone)).toBe(true);
    expect((await call(mf, phone, "POST", "/v1/me/signout")).status).toBe(204);
    expect(await ownsSeat0(mf, code, phone)).toBe(false);
  });

  test("a seat moved to another device by move code goes with the device, not the player", async () => {
    const mf = worker();
    const { phone, code } = await signedInPhone(mf);
    const wife = await mint(mf);
    const a = await connect(mf, code, phone);
    await a.snapshot();
    a.send({ t: "moveSeat", seat: 0 });
    const { code: move } = await a.next<Extract<ServerMessage, { t: "moveCode" }>>((m) => m.t === "moveCode");
    const b = await connect(mf, code, wife);
    await b.snapshot();
    b.send({ t: "claimMove", code: move });
    await b.next((m) => m.t === "snapshot" && m.room.seats[0]?.yours === true);
    a.close();
    b.close();
    expect(await ownsSeat0(mf, code, phone)).toBe(false);
    expect(await ownsSeat0(mf, code, wife)).toBe(true);
  });

  test("a household person unlinking doesn't sign the phone out of the owner's account", async () => {
    const mf = worker();
    const { phone, jd } = await signedInPhone(mf);
    const kid = newPerson("Twin", { ageBand: "teen" });
    await profile(mf, phone, [jd, kid]);
    const kidIn = (await (await signIn(mf, phone, kid, await appleProof("apple-kid"))).json()) as { account: boolean };
    expect(kidIn.account).toBe(false);
    expect((await call(mf, phone, "DELETE", `/v1/me/identities/apple?person=${kid.id}`)).status).toBe(204);
    expect((await call(mf, phone, "GET", "/v1/me/state")).status).toBe(200);
  });

  test("a merge cut short by a failing room finishes on the next sign-in", async () => {
    const mf = worker();
    const { phone } = await signedInPhone(mf);
    const ipad = await mint(mf);
    const jdIpad = newPerson("JD on iPad");
    await profile(mf, ipad, [jdIpad]);
    const code = await seatedRoom(mf, ipad, jdIpad);
    await eventually(
      () => call(mf, ipad, "GET", "/v1/devices/me/tables").then((r) => r.json() as Promise<{ tables: unknown[] }>),
      (t) => t.tables.length > 0,
    );
    const cut = await signIn(mf, ipad, jdIpad, await appleProof("apple-jd"), { "x-test-fail-adopt": "1" });
    expect(cut.status).toBe(500);
    const retry = (await (await signIn(mf, ipad, jdIpad, await appleProof("apple-jd"))).json()) as { outcome: string };
    expect(retry.outcome).toBe("merged");
    expect(await ownsSeat0(mf, code, phone)).toBe(true);
  });

  test("a guest that expires hands its seats back to its device and is forgotten there", async () => {
    const mf = worker();
    const phone = await mint(mf);
    const mia = newPerson("Mia");
    const { players } = await profile(mf, phone, [mia]);
    const code = await seatedRoom(mf, phone, mia);
    expect((await mf.dispatchFetch(`${BASE}/__test/expire?player=${players[mia.id]}`)).status).toBe(204);
    expect(await ownsSeat0(mf, code, phone)).toBe(true);
    expect((await call(mf, phone, "GET", `/v1/me/state?person=${mia.id}`)).status).toBe(404);
  });

  test("confirming a merge keeps the Apple token, so deleting the account revokes it", async () => {
    const mf = worker(undefined, { p8: await p8() });
    await signedInPhone(mf);
    const ipad = await mint(mf);
    const jdIpad = newPerson("JD on iPad");
    await profile(mf, ipad, [jdIpad]);
    const proof = { ...(await appleProof("apple-jd")), authorizationCode: "code-ipad" };
    const path = `/v1/me/identities/apple?person=${jdIpad.id}`;
    expect((await call(mf, ipad, "POST", path, { proof })).status).toBe(409);
    const confirmed = await call(mf, ipad, "POST", path, { proof, confirmMerge: true });
    expect(await confirmed.json()).toEqual({ linked: true, merged: true });
    expect((await call(mf, ipad, "DELETE", `/v1/me?person=${jdIpad.id}`)).status).toBe(204);
    const revoked = appleCalls.filter((c) => c.path === "/auth/revoke").map((c) => c.form.get("token"));
    expect(revoked).toContain("r-code-ipad");
  });

  test("a phone whose owner is under 13 can't sign in, even if the person carries no band", async () => {
    const mf = worker();
    const phone = await mint(mf);
    const kid = newPerson("Mochi");
    await profile(mf, phone, [kid], "kitten");
    expect((await signIn(mf, phone, kid, await appleProof("apple-kid"))).status).toBe(403);
  });
});
