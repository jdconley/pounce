import { issueDeviceToken, verifyDeviceToken } from "./auth";
import { appSiteAssociation, ogImage, sharePage } from "./http/links";
import { newRoomCode, ROOM_CODE } from "./room/codes";
import { DEVICE_HEADER } from "./room/game-room";

import type { Env } from "./env";

export { DeviceIndex } from "./room/device-index";
export { GameRoom } from "./room/game-room";

const SHARE_PATH = /^\/j\/([^/]+)$/;
const ROOM_WS = /^\/v1\/rooms\/([^/]+)\/ws$/;
const APNS_TOKEN = /^[0-9a-fA-F]{64,200}$/;
const DEVICE_ID_BYTES = 18; // 24 base64url characters.
const ROOM_CODE_ATTEMPTS = 5;
const MAX_BODY_BYTES = 1024;
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
async function readObject(request: Request): Promise<Record<string, unknown> | null> {
  const text = await request.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) return null;
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
  if (!body || Object.keys(body).length !== 1 || body.game !== "cat-tower") return badRequest();
  for (let i = 0; i < ROOM_CODE_ATTEMPTS; i++) {
    const code = newRoomCode(cryptoRng);
    const result = await env.ROOMS.get(env.ROOMS.idFromName(code)).init(code, deviceId);
    if ("ok" in result) return json(201, { code });
  }
  return json(503, { error: "no_room_code" });
}

function openSocket(request: Request, env: Env, deviceId: string, code: string): Promise<Response> | Response {
  if (!ROOM_CODE.test(code)) return notFound();
  if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
    return json(426, { error: "upgrade_required" });
  }
  // The room trusts this header, so a client-supplied one must never reach it.
  const headers = new Headers(request.headers);
  headers.delete(DEVICE_HEADER);
  headers.set(DEVICE_HEADER, deviceId);
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
  const tables = await env.DEVICES.get(env.DEVICES.idFromName(deviceId)).listTables();
  return json(200, { tables });
}

type Route = (request: Request, env: Env, deviceId: string) => Promise<Response> | Response;

/** The authenticated route for this request, or null for a 404. */
function route(method: string, pathname: string): Route | null {
  if (method === "PUT" && pathname === "/v1/devices/me/push") return setPushToken;
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
      return json(200, { ok: true, service: "play-api", configured: Boolean(env.TOKEN_SECRET) });
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
