import { build } from "esbuild";
import { Miniflare, Response as MiniflareResponse, type Request as MiniflareRequest } from "miniflare";
import { expect } from "vitest";

import { base64url } from "../src/players/ids";
import { card } from "../src/rules/cards";

import type { ServerMessage } from "../src/protocol";
import type { CatTowerView } from "../src/rules/view";

/** Shared Miniflare plumbing for the notification and pounce suites. */

export const SECRET = "s".repeat(64);
export const BASE = "https://play.conleychaos.com";
export const CLIENT_ID = "com.conleychaos.play";
export const LA = "America/Los_Angeles";

export type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;
export type Device = { deviceId: string; token: string };
export type Person = { id: string; name: string; cat: number; key: string };
/** One request APNs was asked to deliver. */
export type Sent = { token: string; headers: Record<string, string>; body: Record<string, unknown> };
/** Fixture Twilio secrets: never real ones. */
export const TWILIO = {
  TWILIO_ACCOUNT_SID: "ACtest0000000000000000000000000000",
  TWILIO_API_KEY_SID: "SKtest0000000000000000000000000000",
  TWILIO_API_KEY_SECRET: "fixture-api-key-secret",
  TWILIO_VERIFY_SERVICE_SID: "VAtest0000000000000000000000000000",
};

/** One code the fake Verify was asked to send. */
export type VerifySend = { to: string; channel: string | null; auth: string | null; service: string };

/**
 * A fake Twilio Verify, as its docs describe it: a verification per number
 * with one six-digit code that a resend within its life repeats, 5 sends,
 * 5 wrong checks before it's deleted (then 404, as for an expired or approved
 * one), 404 once approved. `expire` stands in for its 10 minutes passing.
 */
export class FakeVerify {
  sends: VerifySend[] = [];
  checks: { to: string; code: string }[] = [];
  live = new Map<string, { code: string; sends: number; wrong: number }>();
  /** Numbers whose sends fail with a 500. */
  failing = new Set<string>();
  /** A delay before a check answers, changeable mid-test. */
  delay = { ms: 0 };

  code(to: string): string {
    return this.live.get(to)?.code as string;
  }

  expire(to: string): void {
    this.live.delete(to);
  }

  reset(): void {
    this.sends = [];
    this.checks = [];
    this.live.clear();
    this.failing.clear();
    this.delay.ms = 0;
  }

  async answer(request: MiniflareRequest): Promise<MiniflareResponse> {
    const url = new URL(request.url);
    const [, , , service, action] = url.pathname.split("/");
    const form = new URLSearchParams(await request.text());
    const to = form.get("To") ?? "";
    const json = (status: number, body: unknown) => new MiniflareResponse(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
    if (request.method !== "POST" || !service) return json(404, { code: 20404 });
    if (action === "Verifications") {
      if (this.failing.has(to)) return json(500, { code: 20500 });
      const v = this.live.get(to) ?? { code: String(Math.floor(Math.random() * 1e6)).padStart(6, "0"), sends: 0, wrong: 0 };
      if (v.sends >= 5) return json(429, { code: 60203 });
      v.sends += 1;
      this.live.set(to, v);
      this.sends.push({ to, channel: form.get("Channel"), auth: request.headers.get("authorization"), service });
      return json(201, { sid: `VE${"0".repeat(32)}`, status: "pending", to });
    }
    if (action === "VerificationCheck") {
      if (this.delay.ms) await new Promise((resolve) => setTimeout(resolve, this.delay.ms));
      const code = form.get("Code") ?? "";
      this.checks.push({ to, code });
      const v = this.live.get(to);
      if (!v) return json(404, { code: 20404 });
      if (v.code === code) {
        this.live.delete(to);
        return json(200, { status: "approved", to });
      }
      v.wrong += 1;
      if (v.wrong >= 5) this.live.delete(to);
      return json(200, { status: "pending", to });
    }
    return json(404, { code: 20404 });
  }
}

export async function bundle(entry: string): Promise<string> {
  const built = await build({
    entryPoints: [new URL(entry, import.meta.url).pathname],
    bundle: true,
    write: false,
    format: "esm",
    platform: "browser",
    external: ["cloudflare:workers"],
  });
  return built.outputFiles[0]?.text ?? "";
}

/** A PKCS#8 PEM for a fresh P-256 key, like the .p8 Apple issues. */
export async function p8(): Promise<string> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  return `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----\n`;
}

/** A worker whose APNs is a recorder: every push lands in `sent`. */
export async function worker(
  script: string,
  options: {
    streaks?: boolean;
    notify?: boolean;
    live?: boolean;
    /** `TROPHY` (your own streak, the trophy room, connections on accept). */
    trophy?: boolean;
    persist?: string;
    links?: boolean;
    sent: Sent[];
    /** Parent consent's DOs, with `CONSENT` on unless `consentFlag` is false. */
    consent?: boolean;
    consentFlag?: boolean;
    /** The fake Twilio Verify; the secrets are set unless `twilio` is false. */
    verify?: FakeVerify;
    twilio?: boolean;
    /** Device tokens the fake APNs fails with a 500 (no device accepted the push). */
    apnsDown?: Set<string>;
    /** `NUDGE` (a player asks the one with the move to take it). */
    nudge?: boolean;
    /** `DEV_SPEED`: divides the bots' think time, the next round's gap and a nudge's waits. */
    devSpeed?: number;
  },
): Promise<Miniflare> {
  return new Miniflare({
    modules: true,
    script,
    compatibilityDate: "2026-08-01",
    durableObjects: {
      ROOMS: { className: "GameRoom", useSQLite: true },
      DEVICES: { className: "DeviceIndex", useSQLite: true },
      PLAYERS: { className: "Player", useSQLite: true },
      IDENTITIES: { className: "Identities", useSQLite: true },
      PAIRS: { className: "Pair", useSQLite: true },
      ...(options.links ? { LINKS: { className: "Links", useSQLite: true } } : {}),
      ...(options.consent
        ? { CONSENTS: { className: "Consents", useSQLite: true }, KITTENS: { className: "KittenIndex", useSQLite: true } }
        : {}),
    },
    bindings: {
      TOKEN_SECRET: SECRET,
      SIWA_CLIENT_ID: CLIENT_ID,
      APNS_TEAM_ID: "B222J9J7B8",
      APNS_TOPIC: CLIENT_ID,
      APNS_HOST: "api.push.apple.com",
      APNS_KEY_P8: await p8(),
      APNS_KEY_ID: `KID-${crypto.randomUUID()}`,
      TESTFLIGHT_URL: "https://testflight.apple.com/join/abc",
      ...(options.streaks === false ? {} : { STREAKS: "on" }),
      ...(options.notify === false ? {} : { NOTIFY: "on" }),
      ...(options.live ? { LIVE: "on" } : {}),
      ...(options.trophy ? { TROPHY: "on" } : {}),
      ...(options.nudge ? { NUDGE: "on" } : {}),
      ...(options.devSpeed ? { DEV_SPEED: String(options.devSpeed) } : {}),
      ...(options.consent && options.consentFlag !== false ? { CONSENT: "on" } : {}),
      ...(options.consent && options.twilio !== false ? TWILIO : {}),
    },
    ...(options.persist ? { durableObjectsPersist: options.persist } : {}),
    outboundService: async (request: MiniflareRequest) => {
      if (request.url === "https://appleid.apple.com/auth/keys") {
        return new MiniflareResponse(JSON.stringify({ keys: [(await appleKeys()).jwk] }), { headers: { "content-type": "application/json" } });
      }
      if (new URL(request.url).host === "api.push.apple.com") {
        if (options.apnsDown?.has(new URL(request.url).pathname.split("/").at(-1) as string)) return new MiniflareResponse(null, { status: 500 });
        options.sent.push({
          token: new URL(request.url).pathname.split("/").at(-1) as string,
          headers: Object.fromEntries(request.headers),
          body: (await request.json()) as Record<string, unknown>,
        });
        return new MiniflareResponse(null, { status: 200 });
      }
      if (new URL(request.url).host === "verify.twilio.com" && options.verify) return options.verify.answer(request);
      return new MiniflareResponse(null, { status: 599 });
    },
  });
}

let apple: Promise<{ rsa: CryptoKeyPair; jwk: JsonWebKey }> | null = null;
const encoder = new TextEncoder();

/** A fixture Sign in with Apple key pair; the fake Apple serves its public half. */
function appleKeys(): Promise<{ rsa: CryptoKeyPair; jwk: JsonWebKey }> {
  apple ??= (async () => {
    const rsa = (await crypto.subtle.generateKey(
      { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
      true,
      ["sign", "verify"],
    )) as CryptoKeyPair;
    const jwk = { ...(await crypto.subtle.exportKey("jwk", rsa.publicKey)), kid: "TEST1", use: "sig", alg: "RS256" } as JsonWebKey;
    return { rsa, jwk };
  })();
  return apple;
}

let nonces = 0;

/** A Sign in with Apple proof for `sub`, signed with the fixture key (never a real one). */
export async function appleProof(sub: string): Promise<{ identityToken: string; nonce: string }> {
  const { rsa } = await appleKeys();
  const nonce = `nonce-${(nonces += 1)}-${Math.random()}`;
  const now = Math.floor(Date.now() / 1000);
  const json = (v: unknown) => base64url(encoder.encode(JSON.stringify(v)));
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(nonce)));
  const hashed = [...digest].map((b) => b.toString(16).padStart(2, "0")).join("");
  const input = `${json({ alg: "RS256", kid: "TEST1" })}.${json({ iss: "https://appleid.apple.com", aud: CLIENT_ID, exp: now + 600, iat: now, sub, nonce: hashed })}`;
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", rsa.privateKey, encoder.encode(input));
  return { identityToken: `${input}.${base64url(new Uint8Array(sig))}`, nonce };
}

export const newPerson = (name: string, cat: number): Person => ({
  id: crypto.randomUUID(),
  name,
  cat,
  key: base64url(crypto.getRandomValues(new Uint8Array(32))),
});

export async function mint(mf: Miniflare): Promise<Device> {
  const res = await mf.dispatchFetch(`${BASE}/v1/devices`, { method: "POST", headers: { "cf-connecting-ip": crypto.randomUUID() } });
  return (await res.json()) as Device;
}

export function call(mf: Miniflare, device: Device, method: string, path: string, body?: unknown): Promise<Response> {
  return mf.dispatchFetch(`${BASE}${path}`, {
    method,
    headers: { authorization: `Bearer ${device.token}`, "content-type": "application/json" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }) as unknown as Promise<Response>;
}

/** Uploads the device's profile and its APNs token; returns personId → playerId. */
export async function profile(
  mf: Miniflare,
  device: Device,
  people: Person[],
  options: { band?: string; zone?: string; apns?: string } = {},
): Promise<Record<string, string>> {
  const res = await call(mf, device, "PUT", "/v1/devices/me/profile", { timeZone: options.zone ?? LA, ageBand: options.band ?? "adult", people });
  expect(res.status).toBe(200);
  if (options.apns) expect((await call(mf, device, "PUT", "/v1/devices/me/push", { apnsToken: options.apns })).status).toBe(204);
  return ((await res.json()) as { players: Record<string, string> }).players;
}

export async function eventually<T>(read: () => Promise<T> | T, ok: (value: T) => boolean): Promise<T> {
  const end = Date.now() + 5000;
  let value = await read();
  while (!ok(value) && Date.now() < end) {
    await new Promise((resolve) => setTimeout(resolve, 50));
    value = await read();
  }
  return value;
}

/**
 * A whole player id in JSON: `"p_"` plus 22 base64url characters. Checking for the bare text `p_` flakes, because other
 * random ids are base64url too and contain `p_` about once in a few hundred (`k_…zp_8…`).
 */
export const PLAYER_ID_JSON = /"p_[A-Za-z0-9_-]{22}"/;

export const settle = (ms = 300) => new Promise((resolve) => setTimeout(resolve, ms));

/** A socket that keeps every frame and its latest snapshot. */
export class Client {
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

  async find<M extends ServerMessage>(match: (m: ServerMessage) => boolean): Promise<M> {
    const end = Date.now() + 5000;
    for (;;) {
      const found = this.received.find(match);
      if (found) return found as M;
      if (Date.now() > end) throw new Error(`timed out; got ${JSON.stringify(this.received.map((m) => m.t))}`);
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }

  async until(ok: (s: Snapshot) => boolean, ms = 5000): Promise<Snapshot> {
    const end = Date.now() + ms;
    while (!(this.last && ok(this.last))) {
      if (Date.now() > end) throw new Error("snapshot never matched");
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    return this.last;
  }

  game(): CatTowerView {
    return (this.last as Snapshot).room.game as CatTowerView;
  }

  /** The app went to the background: the room pushes this seat's turns. */
  away(): void {
    this.send({ t: "presence", state: "background" });
  }
}

export async function connect(mf: Miniflare, code: string, device: Device): Promise<Client> {
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

export async function createRoom(mf: Miniflare, device: Device): Promise<string> {
  const res = await call(mf, device, "POST", "/v1/rooms", { game: "cat-tower" });
  return ((await res.json()) as { code: string }).code;
}

/** A started game: seat i is the i-th person on the i-th device. Returns the clients by seat. */
export async function table(mf: Miniflare, seats: [Device, Person][]): Promise<{ code: string; clients: Client[]; name: string }> {
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
  return { code, clients, name: (clients[0] as Client).last?.room.name as string };
}

/** Whoever's turn it is draws from the deck and discards a number card. */
export async function takeTurn(clients: Client[]): Promise<number> {
  const seat = (clients[0] as Client).game().turn;
  const c = clients[seat] as Client;
  await c.until((s) => s.room.game?.turn === seat);
  c.send({ t: "act", seat, action: { type: "draw", from: "deck" } });
  const drawn = await c.until((s) => s.room.game?.step === "play");
  const hand = (drawn.room.game as CatTowerView).hands[seat] as number[];
  const pick = hand.find((id) => card(id).kind === "number") as number;
  c.send({ t: "act", seat, action: { type: "discard", card: pick } });
  for (const other of clients) await other.until((s) => s.room.game?.turn !== seat || s.room.status !== "playing");
  return seat;
}

export const tokenOf = (n: number) => n.toString(16).padStart(2, "0").repeat(32);

/**
 * At a two-seat table, whoever's turn it is plays while the other is away,
 * so the move reaches them as a push. The first move is usually seat 1, but
 * a flipped Cucumber skips it, so callers must not assume which.
 */
export async function playWhileAway(clients: Client[]): Promise<{ mover: number; next: number }> {
  const mover = (clients[0] as Client).game().turn;
  const next = 1 - mover;
  (clients[next] as Client).away();
  await takeTurn(clients);
  return { mover, next };
}
