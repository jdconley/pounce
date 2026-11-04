import { issueDeviceToken, verifyDeviceToken } from "./auth";
import { devSpeed } from "./env";
import { appSiteAssociation, ogImage, sharePage } from "./http/links";
import {
  deleteMe,
  devicePlayers,
  deviceTables,
  linkIdentity,
  player,
  resolveMe,
  signIn,
  signOut,
  unlinkIdentity,
  uploadProfile,
  type Result,
} from "./players/accounts";
import { PERSON_ID } from "./players/ids";
import { parseProfile, parseStatePatch } from "./players/parse";
import { newRoomCode, ROOM_CODE } from "./room/codes";
import { DEVICE_HEADER, PLAYER_HEADER } from "./room/game-room";
import { parseRoomName } from "./room/names";

import type { Env } from "./env";

export { Identities } from "./players/identities";
export { Player } from "./players/player";
export { DeviceIndex } from "./room/device-index";
export { GameRoom } from "./room/game-room";

const SHARE_PATH = /^\/j\/([^/]+)$/;
const ROOM_WS = /^\/v1\/rooms\/([^/]+)\/ws$/;
const SIGN_IN = /^\/v1\/identities\/([a-z]+)$/;
const MY_IDENTITY = /^\/v1\/me\/identities\/([a-z]+)$/;
const APNS_TOKEN = /^[0-9a-fA-F]{64,200}$/;
const DEVICE_ID_BYTES = 18; // 24 base64url characters.
const ROOM_CODE_ATTEMPTS = 5;
const MAX_BODY_BYTES = 1024;
const MAX_PROFILE_BYTES = 2048;
/** An Apple identity token alone is about 1 KB. */
const MAX_PROOF_BYTES = 4096;
const MAX_STATE_BYTES = 8192;
const MINTS_PER_WINDOW = 10;
const MINT_WINDOW_MS = 60_000;
const MAX_TRACKED_IPS = 10_000;

/** Ruling E: a per-isolate limiter, weak but enough for TestFlight. */
const mints = new Map<string, { count: number; windowStart: number }>();

const cryptoRng = (): number => (crypto.getRandomValues(new Uint32Array(1))[0] as number) / 2 ** 32;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

const noContent = () => new Response(null, { status: 204, headers: { "cache-control": "no-store" } });
const notFound = () => json(404, { error: "not_found" });
const badRequest = () => json(400, { error: "bad_request" });
const unauthorized = () => json(401, { error: "unauthorized" });
const notConfigured = () => json(503, { error: "not_configured" });

function base64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function allowMint(ip: string, now: number): boolean {
  if (mints.size > MAX_TRACKED_IPS) {
    for (const [key, entry] of mints) {
      if (now - entry.windowStart >= MINT_WINDOW_MS) mints.delete(key);
    }
  }
  const entry = mints.get(ip);
  if (!entry || now - entry.windowStart >= MINT_WINDOW_MS) {
    mints.set(ip, { count: 1, windowStart: now });
    return true;
  }
  entry.count += 1;
  return entry.count <= MINTS_PER_WINDOW;
}

/** The parsed JSON object body, or null when it is missing, too big or not an object. */
async function readObject(request: Request, maxBytes = MAX_BODY_BYTES): Promise<Record<string, unknown> | null> {
  const text = await request.text();
  if (new TextEncoder().encode(text).length > maxBytes) return null;
  try {
    const value: unknown = JSON.parse(text);
    return typeof value === "object" && value !== null && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

async function authenticate(request: Request, secret: string): Promise<string | null> {
  const header = request.headers.get("authorization") ?? "";
  if (!header.startsWith("Bearer ")) return null;
  return verifyDeviceToken(secret, header.slice("Bearer ".length).trim());
}

async function mintDevice(request: Request, secret: string): Promise<Response> {
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  if (!allowMint(ip, Date.now())) return json(429, { error: "rate_limited" });
  const deviceId = base64url(crypto.getRandomValues(new Uint8Array(DEVICE_ID_BYTES)));
  return json(200, { deviceId, token: await issueDeviceToken(secret, deviceId) });
}

async function createRoom(request: Request, env: Env, deviceId: string): Promise<Response> {
  const body = await readObject(request);
  if (!body || body.game !== "cat-tower") return badRequest();
  if (Object.keys(body).some((key) => key !== "game" && key !== "name")) return badRequest();
  // Optional: without one the room gets its default name.
  const name = "name" in body ? parseRoomName(body.name) : undefined;
  if (name === null) return badRequest();
  for (let i = 0; i < ROOM_CODE_ATTEMPTS; i++) {
    const code = newRoomCode(cryptoRng);
    const result = await env.ROOMS.get(env.ROOMS.idFromName(code)).init(code, deviceId, name);
    if ("ok" in result) return json(201, { code });
  }
  return json(503, { error: "no_room_code" });
}

async function openSocket(request: Request, env: Env, deviceId: string, code: string): Promise<Response> {
  if (!ROOM_CODE.test(code)) return notFound();
  if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
    return json(426, { error: "upgrade_required" });
  }
  // The room trusts these headers, so client-supplied ones must never reach it.
  const headers = new Headers(request.headers);
  headers.delete(DEVICE_HEADER);
  headers.delete(PLAYER_HEADER);
  headers.set(DEVICE_HEADER, deviceId);
  headers.set(PLAYER_HEADER, JSON.stringify(await devicePlayers(env, deviceId)));
  return env.ROOMS.get(env.ROOMS.idFromName(code)).fetch(new Request(request, { headers }));
}

async function setPushToken(request: Request, env: Env, deviceId: string): Promise<Response> {
  const body = await readObject(request);
  const token = body?.apnsToken;
  if (!body || Object.keys(body).length !== 1 || typeof token !== "string" || !APNS_TOKEN.test(token)) {
    return badRequest();
  }
  await env.DEVICES.get(env.DEVICES.idFromName(deviceId)).setApnsToken(token);
  return noContent();
}

async function listTables(env: Env, deviceId: string): Promise<Response> {
  return json(200, { tables: await deviceTables(env, deviceId) });
}

function respond<T>(result: Result<T>, okStatus = 200): Response {
  if ("ok" in result) return result.ok === null ? noContent() : json(okStatus, result.ok);
  return json(result.status, { error: result.error, ...result.extra });
}

async function putProfile(request: Request, env: Env, deviceId: string): Promise<Response> {
  const profile = parseProfile(await readObject(request, MAX_PROFILE_BYTES));
  if (!profile) return badRequest();
  return json(200, await uploadProfile(env, deviceId, profile, Date.now()));
}

/** The player a `/v1/me` route acts for (`?person=` picks one of the device's people), or a 404. */
async function me(request: Request, env: Env, deviceId: string): Promise<string | Response> {
  const person = new URL(request.url).searchParams.get("person");
  if (person !== null && !PERSON_ID.test(person)) return badRequest();
  return (await resolveMe(env, deviceId, person)) ?? json(404, { error: "no_player" });
}

/** Runs `run` for the request's player. */
function asMe(run: (request: Request, env: Env, deviceId: string, playerId: string) => Promise<Response>): Route {
  return async (request, env, deviceId) => {
    const playerId = await me(request, env, deviceId);
    return typeof playerId === "string" ? run(request, env, deviceId, playerId) : playerId;
  };
}

const getState = asMe(async (_r, env, _d, playerId) => json(200, await player(env, playerId).getState()));

const patchState = asMe(async (request, env, _d, playerId) => {
  const patch = parseStatePatch(await readObject(request, MAX_STATE_BYTES));
  if (!patch) return badRequest();
  await player(env, playerId).patchState(patch, Date.now());
  return noContent();
});

const deleteAccount = asMe(async (_r, env, _d, playerId) => {
  await deleteMe(env, playerId, Date.now(), fetch);
  return noContent();
});

type Route = (request: Request, env: Env, deviceId: string) => Promise<Response> | Response;

/** The authenticated route for this request, or null for a 404. */
function route(method: string, pathname: string): Route | null {
  if (method === "PUT" && pathname === "/v1/devices/me/push") return setPushToken;
  if (method === "PUT" && pathname === "/v1/devices/me/profile") return putProfile;
  if (method === "GET" && pathname === "/v1/me/state") return getState;
  if (method === "PATCH" && pathname === "/v1/me/state") return patchState;
  if (method === "DELETE" && pathname === "/v1/me") return deleteAccount;
  if (method === "POST" && pathname === "/v1/me/signout") {
    return async (_r, env, id) => {
      await signOut(env, id);
      return noContent();
    };
  }
  const signInPath = method === "POST" ? SIGN_IN.exec(pathname) : null;
  if (signInPath) {
    return async (r, env, id) =>
      respond(await signIn(env, id, signInPath[1] as string, await readObject(r, MAX_PROOF_BYTES), Date.now(), fetch));
  }
  const mine = MY_IDENTITY.exec(pathname);
  if (mine && method === "POST") {
    return asMe(async (r, env, _id, playerId) =>
      respond(await linkIdentity(env, playerId, mine[1] as string, await readObject(r, MAX_PROOF_BYTES), Date.now(), fetch)),
    );
  }
  if (mine && method === "DELETE") {
    return asMe(async (_r, env, id, playerId) =>
      respond(await unlinkIdentity(env, id, playerId, mine[1] as string, Date.now(), fetch)),
    );
  }
  if (method === "GET" && pathname === "/v1/devices/me/tables") return (_r, env, id) => listTables(env, id);
  if (method === "POST" && pathname === "/v1/rooms") return createRoom;
  const ws = method === "GET" ? ROOM_WS.exec(pathname) : null;
  if (ws) return (r, env, id) => openSocket(r, env, id, ws[1] as string);
  return null;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const { pathname } = new URL(request.url);
    const { method } = request;
    if (method === "GET" && pathname === "/healthz") {
      const speed = devSpeed(env);
      return json(200, {
        ok: true,
        service: "play-api",
        configured: Boolean(env.TOKEN_SECRET),
        ...(speed === 1 ? {} : { speed }),
      });
    }
    if (method === "GET" && pathname === "/.well-known/apple-app-site-association") {
      return appSiteAssociation();
    }
    if (method === "GET" && pathname === "/og/room.jpg") return ogImage();
    const share = method === "GET" ? SHARE_PATH.exec(pathname) : null;
    if (share) return sharePage(share[1] as string, env.TESTFLIGHT_URL, new URL(request.url).origin);
    const secret = env.TOKEN_SECRET;
    if (method === "POST" && pathname === "/v1/devices") {
      return secret ? mintDevice(request, secret) : notConfigured();
    }
    const handler = route(method, pathname);
    if (!handler) return notFound();
    if (!secret) return notConfigured();
    const deviceId = await authenticate(request, secret);
    if (!deviceId) return unauthorized();
    return handler(request, env, deviceId);
  },
} satisfies ExportedHandler<Env>;
