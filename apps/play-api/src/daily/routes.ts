import { player, resolveMe } from "../players/accounts";
import { PERSON_ID, sha256Hex } from "../players/ids";
import { BOARD_HASH_HEADER, BOARD_ROLE_HEADER } from "../players/player";
import { LINK_TOKEN } from "../screens/screens";
import { addDays, daysBetween } from "../streaks/clock";

import { dailyModule } from "./games";
import { runId } from "./seed";

import type { DailyGameId } from "./module";
import type { Answer, StartView } from "./run-core";
import type { Env } from "../env";

/** Hands work to the request's `waitUntil`, as `src/index.ts` does. */
export type Later = (work: Promise<unknown>) => void;

/** An authenticated route, the same shape as `src/index.ts`'s. */
export type Route = (request: Request, env: Env, deviceId: string, later: Later) => Promise<Response> | Response;

/** A batch of 100 moves fits; anything bigger is refused unread. */
const MAX_BODY_BYTES = 8192;
const HOUR_MS = 3_600_000;
/** Run starts per device per hour (spec §3, "Limits"). */
const STARTS_PER_HOUR = 30;
/** Calls on one run per second: moves, hints, giving up (spec §3, "Limits"). */
const RUN_CALLS_PER_SECOND = 20;

const START = /^\/v1\/daily\/([a-z-]{1,20})\/start$/;
const RUN = /^\/v1\/daily\/runs\/([A-Za-z0-9_-]{43})\/(moves|hint|giveup|tv)$/;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
}

const noContent = () => new Response(null, { status: 204, headers: { "cache-control": "no-store" } });
const notFound = () => json(404, { error: "not_found" });
const badRequest = () => json(400, { error: "bad_request" });

/** The parsed JSON object body, or null when it is missing, too big or not an object. */
async function readObject(request: Request): Promise<Record<string, unknown> | null> {
  const text = await request.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) return null;
  try {
    const value: unknown = JSON.parse(text);
    return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

const limiter = (env: Env, key: string) => env.LIMITS.get(env.LIMITS.idFromName(key));
const runs = (env: Env, id: string) => env.DAILY_RUNS.get(env.DAILY_RUNS.idFromName(id));

/**
 * The player `?person=` names on this device, or the device's account without one. A person the
 * device doesn't speak for is a 403; no person and no account, a 404.
 */
export async function who(request: Request, env: Env, deviceId: string): Promise<string | Response> {
  const person = new URL(request.url).searchParams.get("person");
  if (person !== null && !PERSON_ID.test(person)) return badRequest();
  const id = await resolveMe(env, deviceId, person);
  if (id) return id;
  return person === null ? json(404, { error: "no_player" }) : json(403, { error: "not_allowed" });
}

/**
 * `POST /v1/daily/{game}/start` for `playerId` at `now`: the run for the player's day, made on
 * the first start. Exported so the tests can start at a made-up time.
 */
export async function startRun(env: Env, deviceId: string, playerId: string, game: string, now: number, rules?: string): Promise<Response> {
  const module = dailyModule(game, env);
  const secret = env.TOKEN_SECRET;
  if (!module || !secret) return notFound();
  if (!(await limiter(env, `daily-start:${deviceId}`).take("daily-start", STARTS_PER_HOUR, HOUR_MS, now))) {
    return json(429, { error: "rate_limited" });
  }
  const me = player(env, playerId);
  const day = await me.dailyDay(now);
  if (!day) return json(404, { error: "no_player" });
  // The run already started for this game and date, which after an account merge may be one the
  // guest started: one run per person, game and date, never a second.
  const id = (await me.dailyRunFor(day.day, module.id)) ?? (await runId(secret, playerId, module.id, day.day));
  const view = (await runs(env, id).start({ id, playerId, game: module.id as DailyGameId, date: day.day, zone: day.zone, now, ...(rules ? { rules } : {}) })) as StartView;
  const noted = await me.noteRun(view.date, view.game, view.run, view.startedAt);
  if (noted === null) return json(404, { error: "no_player" });
  // A merge noted another run meanwhile: that one is this player's.
  if (noted !== view.run) return json(200, await runs(env, noted).start({ id: noted, playerId, game: module.id as DailyGameId, date: day.day, zone: day.zone, now, ...(rules ? { rules } : {}) }));
  return json(200, view);
}

const RULES = /^[a-z]{1,20}$/;

/**
 * The rules a start asks for: `{ "rules": "lives" }`, or nothing. No body, or one that isn't
 * that (an old app sends none), starts on the game's first rules; the start isn't refused for it.
 */
async function rulesAsked(request: Request): Promise<string | undefined> {
  const text = await request.text().catch(() => "");
  if (text.trim() === "" || text.length > 200) return undefined;
  try {
    const rules = (JSON.parse(text) as { rules?: unknown } | null)?.rules;
    return typeof rules === "string" && RULES.test(rules) ? rules : undefined;
  } catch {
    return undefined;
  }
}

/**
 * A client's active time (`activeMs`, spec §3 "The clock"), when it sent a sane one: a whole
 * number of milliseconds, 0 or more. Anything else is as if it sent none.
 */
function activeOf(body: unknown): number | undefined {
  const v = (body as { activeMs?: unknown } | null)?.activeMs;
  return typeof v === "number" && Number.isSafeInteger(v) && v >= 0 ? v : undefined;
}

/** `{ from, moves, activeMs? }`: anything else in the body (a result, a score) is never read. */
function parseBatch(body: Record<string, unknown> | null): { from: number; moves: unknown[]; activeMs?: number } | null {
  if (!body || !Number.isInteger(body.from) || (body.from as number) < 0 || !("moves" in body)) return null;
  const activeMs = activeOf(body);
  return { from: body.from as number, moves: body.moves as unknown[], ...(activeMs === undefined ? {} : { activeMs }) };
}

async function onRun(request: Request, env: Env, deviceId: string, run: string, action: string): Promise<Response> {
  const playerId = await who(request, env, deviceId);
  if (typeof playerId !== "string") return playerId;
  const stub = runs(env, run);
  const now = Date.now();
  if (action === "tv") {
    const body = await readObject(request);
    if (!body || typeof body.on !== "boolean") return badRequest();
    return (await stub.setTv(playerId, body.on)) ? noContent() : notFound();
  }
  const batch = action === "moves" ? parseBatch(await readObject(request)) : null;
  if (action === "moves" && !batch) return badRequest();
  if (!(await limiter(env, `daily-moves:${run}`).take("daily-moves", RUN_CALLS_PER_SECOND, 1000, now))) {
    return json(429, { error: "rate_limited" });
  }
  let answer: Answer | null;
  if (batch) answer = await stub.moves(playerId, batch.from, batch.moves, now, batch.activeMs);
  else if (action === "hint") {
    // `{ "hints": <used so far>, "activeMs"? }` makes a resent hint safe; an empty body is a new hint, as before.
    const text = await request.text();
    let seen: number | undefined;
    let activeMs: number | undefined;
    if (text.trim() !== "") {
      let body: unknown;
      try {
        body = JSON.parse(text);
      } catch {
        return badRequest();
      }
      const hints = (body as { hints?: unknown } | null)?.hints;
      if (typeof body !== "object" || body === null || !Number.isInteger(hints) || (hints as number) < 0) return badRequest();
      seen = hints as number;
      activeMs = activeOf(body);
    }
    answer = await stub.hint(playerId, now, seen, activeMs);
  } else {
    // `{ "activeMs" }`, or no body (before active time): never refused for its body.
    const text = await request.text().catch(() => "");
    let activeMs: number | undefined;
    try {
      activeMs = text.trim() === "" || text.length > 200 ? undefined : activeOf(JSON.parse(text));
    } catch {
      activeMs = undefined;
    }
    answer = await stub.giveUp(playerId, now, activeMs);
  }
  // Someone else's run, or none, says the same: ids reveal nothing.
  return answer ? json(200, answer) : notFound();
}

const DATE = /^\d{4}-\d{2}-\d{2}$/;
/** How far back a board may be read: results are kept 120 days (spec §6). */
const BOARD_DAYS = 120;

/**
 * `GET /v1/daily/board?person=&date=`: the player's board for `date`, by default their own day;
 * only today or the past 120 days.
 */
async function getBoard(request: Request, env: Env, deviceId: string): Promise<Response> {
  const playerId = await who(request, env, deviceId);
  if (typeof playerId !== "string") return playerId;
  const now = Date.now();
  const day = await player(env, playerId).dailyDay(now);
  if (!day) return json(404, { error: "no_player" });
  const asked = new URL(request.url).searchParams.get("date");
  if (asked !== null) {
    const valid = DATE.test(asked) && !Number.isNaN(Date.parse(`${asked}T00:00:00Z`)) && addDays(asked, 0) === asked;
    if (!valid || asked > day.day || daysBetween(asked, day.day) > BOARD_DAYS) return badRequest();
  }
  return json(200, await player(env, playerId).board(asked ?? day.day, now));
}

/** `GET /v1/daily/stats?person=`: the player's stats for each listed game. */
async function getStats(request: Request, env: Env, deviceId: string): Promise<Response> {
  const playerId = await who(request, env, deviceId);
  if (typeof playerId !== "string") return playerId;
  const day = await player(env, playerId).dailyDay(Date.now());
  if (!day) return json(404, { error: "no_player" });
  return json(200, { games: await player(env, playerId).dailyStats(day.day) });
}

/**
 * `GET /v1/daily/board/ws`: a board socket, handed to the board's player. A phone names its person
 * (`?person=`); a TV gives its board token (`?board=`), good only from the TV it was given to.
 */
async function boardSocket(request: Request, env: Env, deviceId: string): Promise<Response> {
  if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") return json(426, { error: "upgrade_required" });
  const board = new URL(request.url).searchParams.get("board");
  const headers = new Headers({ upgrade: "websocket" });
  let playerId: string;
  if (board !== null) {
    if (!LINK_TOKEN.test(board)) return notFound();
    const hash = await sha256Hex(board);
    const found = await env.BOARD_TOKENS.get(env.BOARD_TOKENS.idFromName(hash)).resolve(deviceId, Date.now());
    if (found === null) return notFound();
    playerId = found;
    headers.set(BOARD_ROLE_HEADER, "tv");
    headers.set(BOARD_HASH_HEADER, hash);
  } else {
    const found = await who(request, env, deviceId);
    if (typeof found !== "string") return found;
    playerId = found;
    headers.set(BOARD_ROLE_HEADER, "phone");
  }
  // A fresh request: nothing the client sent but the upgrade reaches the player.
  return env.PLAYERS.get(env.PLAYERS.idFromName(playerId)).fetch(new Request("https://player/board", { headers }));
}

/** `DELETE /v1/daily/board/tv?person=`: every TV showing the person's board forgets it. */
async function unlinkBoards(request: Request, env: Env, deviceId: string): Promise<Response> {
  const playerId = await who(request, env, deviceId);
  if (typeof playerId !== "string") return playerId;
  await player(env, playerId).revokeBoards();
  return noContent();
}

/** The Daily Dish's authenticated route for this request, or null (a 404). Only while `DAILY` is on. */
export function dailyRoute(method: string, pathname: string): Route | null {
  if (method === "GET" && pathname === "/v1/daily/board/ws") return boardSocket;
  if (method === "DELETE" && pathname === "/v1/daily/board/tv") return unlinkBoards;
  if (method === "GET" && pathname === "/v1/daily/board") return getBoard;
  if (method === "GET" && pathname === "/v1/daily/stats") return getStats;
  const start = method === "POST" ? START.exec(pathname) : null;
  if (start) {
    return async (request, env, deviceId) => {
      const playerId = await who(request, env, deviceId);
      return typeof playerId === "string" ? startRun(env, deviceId, playerId, start[1] as string, Date.now(), await rulesAsked(request)) : playerId;
    };
  }
  const run = RUN.exec(pathname);
  if (run && method === (run[2] === "tv" ? "PUT" : "POST")) {
    return (request, env, deviceId) => onRun(request, env, deviceId, run[1] as string, run[2] as string);
  }
  return null;
}
