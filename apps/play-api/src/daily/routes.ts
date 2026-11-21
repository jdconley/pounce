import { player, resolveMe } from "../players/accounts";
import { PERSON_ID } from "../players/ids";

import { dailyModule } from "./games";
import { runId } from "./seed";

import type { DailyGameId } from "./module";
import type { Answer } from "./run-core";
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
async function who(request: Request, env: Env, deviceId: string): Promise<string | Response> {
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
export async function startRun(env: Env, deviceId: string, playerId: string, game: string, now: number): Promise<Response> {
  const module = dailyModule(game, env);
  const secret = env.TOKEN_SECRET;
  if (!module || !secret) return notFound();
  if (!(await limiter(env, `daily-start:${deviceId}`).take("daily-start", STARTS_PER_HOUR, HOUR_MS, now))) {
    return json(429, { error: "rate_limited" });
  }
  const day = await player(env, playerId).dailyDay(now);
  if (!day) return json(404, { error: "no_player" });
  const id = await runId(secret, playerId, module.id, day.day);
  return json(200, await runs(env, id).start({ id, playerId, game: module.id as DailyGameId, date: day.day, zone: day.zone, now }));
}

/** `{ from, moves }`: anything else in the body (a result, a time) is never read. */
function parseBatch(body: Record<string, unknown> | null): { from: number; moves: unknown[] } | null {
  if (!body || !Number.isInteger(body.from) || (body.from as number) < 0 || !("moves" in body)) return null;
  return { from: body.from as number, moves: body.moves as unknown[] };
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
  if (batch) answer = await stub.moves(playerId, batch.from, batch.moves, now);
  else if (action === "hint") answer = await stub.hint(playerId, now);
  else answer = await stub.giveUp(playerId, now);
  // Someone else's run, or none, says the same: ids reveal nothing.
  return answer ? json(200, answer) : notFound();
}

/** The Daily Dish's authenticated route for this request, or null (a 404). Only while `DAILY` is on. */
export function dailyRoute(method: string, pathname: string): Route | null {
  const start = method === "POST" ? START.exec(pathname) : null;
  if (start) {
    return async (request, env, deviceId) => {
      const playerId = await who(request, env, deviceId);
      return typeof playerId === "string" ? startRun(env, deviceId, playerId, start[1] as string, Date.now()) : playerId;
    };
  }
  const run = RUN.exec(pathname);
  if (run && method === (run[2] === "tv" ? "PUT" : "POST")) {
    return (request, env, deviceId) => onRun(request, env, deviceId, run[1] as string, run[2] as string);
  }
  return null;
}
