import { storeLatest } from "./app/live";
import { appStatus, refusalFor, RETIRED_SNAPSHOT, UPDATE_HEADER, UPDATE_REQUIRED, type UpdateRequired } from "./app/status";
import { APP_HEADER, parseApp } from "./app/version";
import { issueDeviceToken, verifyDeviceToken } from "./auth";
import { APPLE_ROOTS } from "./consent/appstore";
import { noticePage } from "./consent/pages";
import { devSpeed } from "./env";
import { DEFAULT_GAME, GAMES_HEADER, gamesListed, gamesOn, gameTitle, isGameId, type GameId } from "./games";
import { appSiteAssociation, ogImage, pouncePage, sharePage } from "./http/links";
import { mediaFile } from "./http/media";
import { privacyPage } from "./http/privacy";
import { getRedirect, homePage, llmsTxt, robotsTxt, sitemapXml, supportPage } from "./http/site";
import {
  anyConsented,
  appStoreNotification,
  checkConsent,
  kittenMe,
  linkCode,
  linkKitten,
  listKittens,
  mirrorApple,
  resendConsent,
  revokeConsent,
  setApproved,
  startConsent,
  unlinkKitten,
} from "./kittens/kittens";
import { parseLiveTokens } from "./live/live";
import { nameAllowed } from "./names/filter";
import {
  deleteMe,
  devicePlayers,
  deviceTableLists,
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
import { answerPounce, createPounce, linkPounce } from "./pounce/pounces";
import { MIN_PROTOCOL } from "./protocol";
import { newRoomCode, ROOM_CODE } from "./room/codes";
import { DEVICE_HEADER, PLAYER_HEADER } from "./room/game-room";
import { parseRoomName } from "./room/names";
import { lockedFor, withoutUndrawable } from "./room/tables";
import { blockPlayer, guardJoin, listBlocks, mayMint, nameCheck, ownerReports, reportPlayer, unblockPlayer } from "./safety/safety";
import { creatorLook, isMine, leavePair, myLeft, myOwn, myStreaks, myTrophies, PAIR_ID, pairStub, rejoinPair, syncPairPeople } from "./streaks/pairs";
import { consentOn, liveOn, notifyOn, streaksOn, trophyOn } from "./streaks/profile";

import type { Env } from "./env";

export { Consents } from "./kittens/consents";
export { KittenIndex } from "./kittens/kitten-index";
export { Links } from "./links/links";
export { Identities } from "./players/identities";
export { Player } from "./players/player";
export { DeviceIndex } from "./room/device-index";
export { GameRoom } from "./room/game-room";
export { Limiter } from "./safety/limiter";
export { Reports } from "./safety/reports";
export { Pair } from "./streaks/pair";

const SHARE_PATH = /^\/j\/([^/]+)$/;
const POUNCE_PAGE = /^\/p\/([^/]+)$/;
const POUNCE_ANSWER = /^\/v1\/pounces\/([^/]+)\/answer$/;
const POUNCE_LINK = /^\/v1\/pounces\/links\/([^/]+)$/;
const ROOM_WS = /^\/v1\/rooms\/([^/]+)\/ws$/;
/** `/v1/rooms/{code}/reports` or `/blocks`: report or block someone at that table. */
const ROOM_SAFETY = /^\/v1\/rooms\/([^/]+)\/(reports|blocks)$/;
const MY_BLOCK = /^\/v1\/me\/blocks\/([^/]+)$/;
const SIGN_IN = /^\/v1\/identities\/([a-z]+)$/;
const MY_IDENTITY = /^\/v1\/me\/identities\/([a-z]+)$/;
/** `/v1/pairs/{pair}`, `/pause`, `/pin` or `/gifts/{id}/open` (§13.4). */
/** `DELETE /v1/me/left/{pair}`: undo leaving a streak (§14's ghosted cat). */
/** `/v1/kittens/{k}`, `/approved`, `/consent`, `/consent/check` or `/consent/resend` (parent consent, plan decision 1). */
const KITTEN_PATH = /^\/v1\/kittens\/(k_[A-Za-z0-9_-]{22})(?:\/(approved|consent|consent\/check|consent\/resend))?$/;
/** An App Store notification is a few KB of JWS. */
const MAX_NOTIFICATION_BYTES = 32_768;
const LEFT_PATH = /^\/v1\/me\/left\/([^/]+)$/;
const PAIR_PATH = /^\/v1\/pairs\/([^/]+)(?:\/(pause|pin)|\/gifts\/(g[0-9]{1,9})\/open)?$/;
const MAX_PAUSE_DAYS = 14;
const APNS_TOKEN = /^[0-9a-fA-F]{64,200}$/;
const DEVICE_ID_BYTES = 18; // 24 base64url characters.
const ROOM_CODE_ATTEMPTS = 5;
const MAX_BODY_BYTES = 1024;
const MAX_PROFILE_BYTES = 2048;
/** An Apple identity token alone is about 1 KB. */
const MAX_PROOF_BYTES = 4096;
const MAX_STATE_BYTES = 8192;

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
/** Where the landing page, `/get` and the invite pages send people without the app. */
const install = (env: Env) => ({ appStoreUrl: env.APP_STORE_URL, testflightUrl: env.TESTFLIGHT_URL });

function base64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
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

const clientIp = (request: Request) => request.headers.get("cf-connecting-ip") ?? "unknown";

async function mintDevice(request: Request, env: Env, secret: string): Promise<Response> {
  // Counted in a Durable Object, so the limit holds across isolates.
  if (!(await mayMint(env, clientIp(request), Date.now()))) return json(429, { error: "rate_limited" });
  const deviceId = base64url(crypto.getRandomValues(new Uint8Array(DEVICE_ID_BYTES)));
  return json(200, { deviceId, token: await issueDeviceToken(secret, deviceId) });
}

/** The games this request's app can draw (`X-Pounce-Games`): always Cat Tower, plus what it lists. */
const appGames = (request: Request): GameId[] => gamesListed(request.headers.get(GAMES_HEADER));

/**
 * The same, less Cat Tower: what the device's index is told when the app opens a socket or
 * fetches its tables (`DeviceIndex.players`). It rides on the call those requests always made,
 * so no request waits on, or fails by, a call of its own. Empty for an app that sent no header,
 * which is then what the device is known by.
 */
const declared = (request: Request): GameId[] => appGames(request).filter((id) => id !== DEFAULT_GAME);

/**
 * The version in this request's `X-Pounce-App`, for the device's index to remember alongside its
 * games. Undefined for an app that sent none (version 1.0), which changes nothing about the call.
 */
const appVersion = (request: Request): string | undefined => parseApp(request.headers.get(APP_HEADER))?.version;

/** `GET /v1/app`: the version live on the App Store, the oldest one still supported, and where to update. Public. */
async function getApp(env: Env): Promise<Response> {
  return json(200, appStatus(env, await storeLatest(env).catch(() => null)));
}

/** 426 for an app that said what it is and is too old (design §4.3). The header is for a refused socket upgrade, whose body the app can't read. */
function updateRequired(refusal: UpdateRequired): Response {
  const response = json(426, refusal);
  response.headers.set(UPDATE_HEADER, UPDATE_REQUIRED);
  return response;
}

/**
 * Version 1.0, once it is no longer supported, opening a table: the socket opens, says one thing
 * and closes. The one thing is a snapshot of a protocol 1.0 doesn't speak, which it answers with
 * its own "Update the app to play" card. Any other answer here it shows as a lost connection.
 */
function retiredSocket(): Response {
  const pair = new WebSocketPair();
  const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
  server.accept();
  server.send(RETIRED_SNAPSHOT);
  server.close(1000, "update required");
  return new Response(null, { status: 101, webSocket: client });
}

async function createRoom(request: Request, env: Env, deviceId: string): Promise<Response> {
  const body = await readObject(request);
  // Only a game the `GAMES` flag has turned on, and only for an app that can draw it.
  if (!body || !isGameId(body.game) || !gamesOn(env).includes(body.game)) return badRequest();
  const game = body.game;
  if (!appGames(request).includes(game)) return badRequest();
  if (Object.keys(body).some((key) => key !== "game" && key !== "name")) return badRequest();
  // Optional: without one the room gets its default name.
  const name = "name" in body ? parseRoomName(body.name) : undefined;
  if (name === null) return badRequest();
  if (name !== undefined) {
    if (!nameAllowed(name)) return json(400, { error: "bad_name" });
    // A kitten's device types no names (spec §14.1): its tables keep the server's.
    if ((await env.DEVICES.get(env.DEVICES.idFromName(deviceId)).ageBand()) === "kitten") return json(403, { error: "not_allowed" });
  }
  let look;
  if (streaksOn(env)) {
    const { people, account } = await env.DEVICES.get(env.DEVICES.idFromName(deviceId)).players();
    look = (await creatorLook(env, people, account)) ?? undefined;
  }
  for (let i = 0; i < ROOM_CODE_ATTEMPTS; i++) {
    const code = newRoomCode(cryptoRng);
    const result = await env.ROOMS.get(env.ROOMS.idFromName(code)).init(code, deviceId, name, look, game);
    if ("ok" in result) return json(201, { code });
    if ("off" in result) return badRequest();
  }
  return json(503, { error: "no_room_code" });
}

async function openSocket(request: Request, env: Env, deviceId: string, code: string): Promise<Response> {
  if (!ROOM_CODE.test(code)) return notFound();
  if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
    return json(426, { error: "upgrade_required" });
  }
  // Joining by code (`guardJoin`): wrong guesses are counted, and too many lock the guesser out.
  const guard = await guardJoin(env, code, deviceId, clientIp(request), Date.now());
  if ("retryAfter" in guard) {
    const response = json(429, { error: "too_many_attempts", retryAfter: guard.retryAfter });
    response.headers.set("retry-after", String(guard.retryAfter));
    return response;
  }
  if (!guard.exists) return notFound();
  // The room trusts these headers, so client-supplied ones must never reach it.
  const headers = new Headers(request.headers);
  headers.delete(DEVICE_HEADER);
  headers.delete(PLAYER_HEADER);
  headers.set(DEVICE_HEADER, deviceId);
  // The same call tells the device's index what this app can draw, before the room can push to it.
  headers.set(PLAYER_HEADER, JSON.stringify(await devicePlayers(env, deviceId, declared(request), appVersion(request))));
  return env.ROOMS.get(env.ROOMS.idFromName(code)).fetch(new Request(request, { headers }));
}

async function setPushToken(request: Request, env: Env, deviceId: string): Promise<Response> {
  const body = await readObject(request);
  const token = body?.apnsToken;
  if (!body || Object.keys(body).length !== 1 || typeof token !== "string" || !APNS_TOKEN.test(token)) {
    return badRequest();
  }
  const index = env.DEVICES.get(env.DEVICES.idFromName(deviceId));
  // A kitten's device holds a token only with a parent's consent (plan decision 19).
  if (consentOn(env) && (await index.ageBand()) === "kitten") {
    const { people } = await index.players();
    if (!(await anyConsented(env, Object.values(people)))) return json(403, { error: "not_allowed" });
  }
  await index.setApnsToken(token);
  return noContent();
}

/** The device's tables, less any table of a game the asking app can't draw. */
async function listTables(request: Request, env: Env, deviceId: string): Promise<Response> {
  const app = appVersion(request);
  const { tables, all } = await deviceTableLists(env, deviceId, declared(request), app);
  // An app that said what it is also hears of the tables it was left out of, as `locked`: there
  // to say "update to join", never to open. An app that didn't gets the body it always got.
  const locked = app === undefined ? [] : lockedFor(all, declared(request), gameTitle);
  return json(200, locked.length > 0 ? { tables, locked } : { tables });
}

function respond<T>(result: Result<T>, okStatus = 200): Response {
  if ("ok" in result) return result.ok === null ? noContent() : json(okStatus, result.ok);
  return json(result.status, { error: result.error, ...result.extra });
}

async function putProfile(request: Request, env: Env, deviceId: string): Promise<Response> {
  const profile = parseProfile(await readObject(request, MAX_PROFILE_BYTES));
  if (!profile) return badRequest();
  // A name the filter refuses never reaches a player, a table or a push.
  if (!profile.people.every((p) => nameAllowed(p.name))) return json(400, { error: "bad_name" });
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
  // Quiet hours set when the evening cutoff falls (§6.1).
  if (streaksOn(env)) await syncPairPeople(env, playerId, Date.now()).catch(() => undefined);
  return noContent();
});

const deleteAccount = asMe(async (_r, env, _d, playerId) => {
  await deleteMe(env, playerId, Date.now(), fetch);
  return noContent();
});

type Route = (request: Request, env: Env, deviceId: string) => Promise<Response> | Response;

const getStreaks = asMe(async (request, env, _d, me) => {
  const now = Date.now();
  const [all, left] = await Promise.all([myStreaks(env, me, now), myLeft(env, me)]);
  // While another game is on: a streak names its tables by code, and an app is told only of the
  // ones it can draw. Off, nothing is looked up and the answer is what it always was.
  const other = gamesOn(env).length > 1;
  const [tables, games] = other ? [await player(env, me).listTables(), appGames(request)] : [[], []];
  const pairs = all.map((view) => withoutUndrawable(view, tables, games));
  // Your own streak, for Home's strip (trophy room design §1): only with TROPHY on.
  const own = trophyOn(env) ? await myOwn(env, me, now, pairs) : null;
  return json(200, own ? { own, pairs, left } : { pairs, left });
});

const getTrophies = asMe(async (_r, env, _d, me) => {
  const found = await myTrophies(env, me, Date.now());
  // A player that isn't there now (merging, being deleted) is no_player, never "no trophy room".
  return found ? json(200, found) : json(404, { error: "no_player" });
});

type PairHandler = (request: Request, env: Env, me: string, pairId: string) => Promise<Response>;

async function putPause(request: Request, env: Env, me: string, pairId: string): Promise<Response> {
  const body = await readObject(request);
  const days = body?.days;
  if (!body || Object.keys(body).length !== 1 || typeof days !== "number" || !Number.isInteger(days)) return badRequest();
  if (days < 1 || days > MAX_PAUSE_DAYS) return badRequest();
  return (await pairStub(env, pairId).pause(me, days, Date.now())) ? noContent() : badRequest();
}

/** The handler for one `/v1/pairs/...` method and path, or null for a 404. */
function pairHandler(method: string, action: string | undefined, gift: string | undefined): PairHandler | null {
  if (gift !== undefined) {
    return method === "POST"
      ? async (_r, env, me, pairId) => ((await pairStub(env, pairId).openGift(me, gift)) ? noContent() : notFound())
      : null;
  }
  if (action === "pause" && method === "PUT") return putPause;
  if (action === "pause" && method === "DELETE") {
    return async (_r, env, me, pairId) => {
      await pairStub(env, pairId).unpause(me, Date.now());
      return noContent();
    };
  }
  if (action === "pin" && method === "PUT") {
    return async (_r, env, me, pairId) => ((await player(env, me).pin(pairId)) ? noContent() : notFound());
  }
  if (action === undefined && method === "DELETE") {
    return async (_r, env, me, pairId) => ((await leavePair(env, me, pairId, Date.now())) ? noContent() : notFound());
  }
  return null;
}

/** The widget extension's WidgetKit push token (§11.2). */
async function setWidgetToken(request: Request, env: Env, deviceId: string): Promise<Response> {
  const body = await readObject(request);
  const token = body?.token;
  if (!body || Object.keys(body).length !== 1 || typeof token !== "string" || !APNS_TOKEN.test(token)) return badRequest();
  await env.DEVICES.get(env.DEVICES.idFromName(deviceId)).setWidgetToken(token);
  return noContent();
}

/** The live table's push-to-start and activity tokens (§11.3, §13.4). */
async function setLiveTokens(request: Request, env: Env, deviceId: string): Promise<Response> {
  const tokens = parseLiveTokens(await readObject(request), ROOM_CODE);
  if (!tokens) return badRequest();
  await env.DEVICES.get(env.DEVICES.idFromName(deviceId)).setLiveTokens(tokens);
  return noContent();
}

const personParam = (request: Request) => new URL(request.url).searchParams.get("person");

const postPounce = asMe(async (request, env, deviceId, me) =>
  respond(
    await createPounce(env, deviceId, me, personParam(request), await readObject(request), Date.now(), new URL(request.url).origin),
    201,
  ),
);

/** Pounce routes (§13.4), only while `STREAKS` is on. */
function pounceRoute(method: string, pathname: string): Route | null {
  if (method === "POST" && pathname === "/v1/pounces") return postPounce;
  const answer = method === "POST" ? POUNCE_ANSWER.exec(pathname) : null;
  if (answer) {
    return asMe(async (request, env, deviceId, me) =>
      respond(await answerPounce(env, deviceId, me, personParam(request), answer[1] as string, await readObject(request), Date.now())),
    );
  }
  const link = method === "GET" ? POUNCE_LINK.exec(pathname) : null;
  if (link) {
    return async (request, env, deviceId) => {
      // Who's asking, when this device has a player: a link someone answered "Not now" to stays theirs.
      const viewer = await me(request, env, deviceId);
      const found = await linkPounce(env, link[1] as string, Date.now(), typeof viewer === "string" ? viewer : null);
      return found ? json(200, found) : notFound();
    };
  }
  return null;
}

/** Streak routes (§13.4), only while `STREAKS` is on. */
function streakRoute(method: string, pathname: string, notify: boolean, live: boolean, trophy: boolean): Route | null {
  if (method === "GET" && pathname === "/v1/me/streaks") return getStreaks;
  if (trophy && method === "GET" && pathname === "/v1/me/trophies") return getTrophies;
  if (live && method === "PUT" && pathname === "/v1/devices/me/live-activity") return setLiveTokens;
  if (notify) {
    if (method === "PUT" && pathname === "/v1/devices/me/widget-push") return setWidgetToken;
    const pounce = pounceRoute(method, pathname);
    if (pounce) return pounce;
  }
  const left = method === "DELETE" ? LEFT_PATH.exec(pathname) : null;
  if (left) {
    const pairId = left[1] as string;
    return asMe(async (_r, env, _d, me) =>
      PAIR_ID.test(pairId) && (await rejoinPair(env, me, pairId, Date.now())) ? noContent() : notFound(),
    );
  }
  const path = PAIR_PATH.exec(pathname);
  if (!path) return null;
  const [, pairId, action, gift] = path as unknown as [string, string, string | undefined, string | undefined];
  const handler = pairHandler(method, action, gift);
  if (!handler) return null;
  return asMe(async (request, env, _d, me) => {
    // Someone else's pair is a 404, like one that doesn't exist.
    if (!PAIR_ID.test(pairId) || !(await isMine(env, me, pairId))) return notFound();
    return handler(request, env, me, pairId);
  });
}

/** Parent consent routes (consent design §3), only while `CONSENT` is on. */
function kittenRoute(method: string, pathname: string): Route | null {
  if (method === "POST" && pathname === "/v1/kittens/me/link-code") {
    return asMe(async (r, env, d, me) => respond(await linkCode(env, d, me, await readObject(r), Date.now()), 201));
  }
  if (method === "GET" && pathname === "/v1/kittens/me") return asMe(async (_r, env, d, me) => respond(await kittenMe(env, d, me)));
  if (method === "PUT" && pathname === "/v1/kittens/me/approved") {
    return asMe(async (r, env, d, me) => respond(await mirrorApple(env, d, me, await readObject(r, MAX_STATE_BYTES))));
  }
  if (method === "POST" && pathname === "/v1/kittens/link") {
    return asMe(async (r, env, d, me) => respond(await linkKitten(env, d, me, await readObject(r), Date.now()), 201));
  }
  if (method === "GET" && pathname === "/v1/kittens") return asMe(async (_r, env, d, me) => respond(await listKittens(env, d, me)));
  const k = KITTEN_PATH.exec(pathname);
  if (!k) return null;
  const [, kid, action] = k as unknown as [string, string, string | undefined];
  if (action === "approved" && method === "PUT") {
    return asMe(async (r, env, d, me) => respond(await setApproved(env, d, me, kid, await readObject(r, MAX_STATE_BYTES))));
  }
  if (action === "consent" && method === "POST") {
    return asMe(async (r, env, d, me) => respond(await startConsent(env, d, me, kid, await readObject(r), Date.now()), 202));
  }
  if (action === "consent/resend" && method === "POST") return asMe(async (_r, env, d, me) => respond(await resendConsent(env, d, me, kid, Date.now()), 202));
  if (action === "consent/check" && method === "POST") {
    return asMe(async (r, env, d, me) => respond(await checkConsent(env, d, me, kid, await readObject(r), Date.now())));
  }
  if (action === "consent" && method === "DELETE") return asMe(async (_r, env, d, me) => respond(await revokeConsent(env, d, me, kid)));
  if (action === undefined && method === "DELETE") return asMe(async (_r, env, d, me) => respond(await unlinkKitten(env, d, me, kid)));
  return null;
}

/** Parent consent's public routes: the notice and App Store notifications. */
async function publicConsent(request: Request, env: Env, method: string, pathname: string): Promise<Response | null> {
  if (method === "GET" && pathname === "/privacy/kitten-notice") return noticePage();
  if (method === "POST" && pathname === "/v1/appstore/notifications") {
    return appStoreNotification(env, await readObject(request, MAX_NOTIFICATION_BYTES), APPLE_ROOTS, Date.now());
  }
  return null;
}

/** Name checks, reports and blocks (App Store guideline 1.2). */
function safetyRoute(method: string, pathname: string): Route | null {
  if (method === "POST" && pathname === "/v1/names/check") {
    return async (r, env, id) => respond(await nameCheck(env, id, await readObject(r), Date.now()));
  }
  if (method === "GET" && pathname === "/v1/me/blocks") return asMe(async (_r, env, _d, me) => json(200, await listBlocks(env, me)));
  const mine = method === "DELETE" ? MY_BLOCK.exec(pathname) : null;
  if (mine) return asMe(async (_r, env, id, me) => respond(await unblockPlayer(env, id, me, mine[1] as string, Date.now())));
  const at = method === "POST" ? ROOM_SAFETY.exec(pathname) : null;
  if (!at) return null;
  const code = at[1] as string;
  if (at[2] === "reports") return async (r, env, id) => respond(await reportPlayer(env, id, code, await readObject(r), Date.now()));
  return asMe(async (r, env, id, me) => respond(await blockPlayer(env, id, me, code, await readObject(r), Date.now())));
}

/** The authenticated route for this request, or null for a 404. */
function route(
  method: string,
  pathname: string,
  streaks: boolean,
  notify: boolean,
  live: boolean,
  consent: boolean,
  trophy: boolean,
): Route | null {
  if (consent) {
    const kitten = kittenRoute(method, pathname);
    if (kitten) return kitten;
  }
  if (streaks) {
    const streak = streakRoute(method, pathname, notify, live, trophy);
    if (streak) return streak;
  }
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
    return asMe(async (r, env, id, playerId) =>
      respond(await linkIdentity(env, id, playerId, mine[1] as string, await readObject(r, MAX_PROOF_BYTES), Date.now(), fetch)),
    );
  }
  if (mine && method === "DELETE") {
    return asMe(async (_r, env, id, playerId) =>
      respond(await unlinkIdentity(env, id, playerId, mine[1] as string, Date.now(), fetch)),
    );
  }
  if (method === "GET" && pathname === "/v1/devices/me/tables") return listTables;
  const safety = safetyRoute(method, pathname);
  if (safety) return safety;
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
    const streaks = streaksOn(env);
    const notify = notifyOn(env);
    if (method === "GET" && pathname === "/.well-known/apple-app-site-association") {
      return appSiteAssociation(notify);
    }
    if (method === "GET" && pathname === "/og/room.jpg") return ogImage();
    if (method === "GET" && pathname === "/privacy") return privacyPage(consentOn(env));
    if (method === "GET" && pathname === "/support") return supportPage();
    if (method === "GET") {
      const origin = () => new URL(request.url).origin;
      if (pathname === "/") return homePage(install(env), origin(), consentOn(env));
      if (pathname === "/get") return getRedirect(install(env), origin());
      if (pathname === "/robots.txt") return robotsTxt(origin());
      if (pathname === "/sitemap.xml") return sitemapXml(origin());
      if (pathname === "/llms.txt") return llmsTxt(origin(), consentOn(env));
      if (pathname.startsWith("/media/")) return (await mediaFile(request, env.ASSETS)) ?? notFound();
    }
    const share = method === "GET" ? SHARE_PATH.exec(pathname) : null;
    if (share) return sharePage(share[1] as string, install(env), new URL(request.url).origin, gamesOn(env).length > 1);
    if (notify && method === "GET") {
      // The pounce card reuses the room card until the bell art lands (§9.6).
      if (pathname === "/og/pounce.jpg") return ogImage();
      const p = POUNCE_PAGE.exec(pathname);
      if (p) {
        const token = p[1] as string;
        const found = await linkPounce(env, token, Date.now()).catch(() => null);
        return pouncePage(found?.from ?? null, token, install(env), new URL(request.url).origin);
      }
    }
    const consent = consentOn(env);
    if (consent) {
      const answered = await publicConsent(request, env, method, pathname);
      if (answered) return answered;
    }
    if (method === "GET" && pathname === "/v1/admin/reports") {
      // The owner's list of player reports; without `REPORTS_KEY` (or the right one) there is no such page.
      const found = await ownerReports(env, request);
      return found === null ? notFound() : found === "bad" ? badRequest() : json(200, found);
    }
    if (method === "GET" && pathname === "/v1/app") return getApp(env);
    const secret = env.TOKEN_SECRET;
    const mints = method === "POST" && pathname === "/v1/devices";
    const handler = mints ? null : route(method, pathname, streaks, notify, liveOn(env), consent, trophyOn(env));
    if (!mints && !handler) return notFound();
    // Too old to be served (`APP_MINIMUM`, or a protocol the server dropped)? Nobody is while
    // there is no minimum, and then this asks nothing and costs nothing.
    const app = parseApp(request.headers.get(APP_HEADER));
    const refusal = await refusalFor(app, env, MIN_PROTOCOL, () => storeLatest(env).catch(() => null));
    // An app that said what it is gets a plain answer on every route.
    if (refusal && app) return updateRequired(refusal);
    if (mints) return secret ? mintDevice(request, env, secret) : notConfigured();
    if (!secret) return notConfigured();
    const deviceId = await authenticate(request, secret);
    if (!deviceId) return unauthorized();
    // Version 1.0 says nothing of itself, and reads no answer but a table's: its HTTP calls are
    // answered as ever, and a table it opens tells it to update (design §6).
    if (refusal && ROOM_WS.test(pathname) && request.headers.get("upgrade")?.toLowerCase() === "websocket") return retiredSocket();
    return (handler as Route)(request, env, deviceId);
  },
} satisfies ExportedHandler<Env>;
