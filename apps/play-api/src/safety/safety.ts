import { devicePlayers, player, type Result } from "../players/accounts";
import { PLAYER_ID } from "../players/ids";
import { ROOM_CODE } from "../room/codes";

import { DEVICE_JOIN_RULE, ipBucket, IP_JOIN_RULE } from "./backoff";
import { checkName, ownerAsks, parseAfter, parseBlock, parseReport } from "./parse";
import { REPORTS_NAME, type Report } from "./reports";

import type { Env } from "../env";

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
/** Reports one device may file. */
const REPORTS_PER_HOUR = 5;
const REPORTS_PER_DAY = 20;
/** Blocks and unblocks one device may make. */
const BLOCKS_PER_HOUR = 30;
/** Name checks one device may ask for (the app asks as a name is saved). */
const NAME_CHECKS_PER_MINUTE = 30;
/** New devices one address may mint. */
const MINTS_PER_MINUTE = 10;
/** Funnel reports one device may send (the app sends a handful a day). */
const FUNNEL_REPORTS_PER_HOUR = 30;
/** Screen links one device, and one address, may make (a TV renews one every few minutes). */
const SCREEN_LINKS_PER_DEVICE = 30;
const SCREEN_LINKS_PER_IP = 120;
const SCREEN_LINK_WINDOW = 10 * MINUTE;

const fail = (status: number, error: string, extra?: Record<string, unknown>): Result<never> => ({ status, error, ...(extra ? { extra } : {}) });
const limiter = (env: Env, key: string) => env.LIMITS.get(env.LIMITS.idFromName(key));
const reports = (env: Env) => env.REPORTS.get(env.REPORTS.idFromName(REPORTS_NAME));
const room = (env: Env, code: string) => env.ROOMS.get(env.ROOMS.idFromName(code));

type Obj = Record<string, unknown>;

/** Whether one address may mint another device now. */
export function mayMint(env: Env, ip: string, now: number): Promise<boolean> {
  return limiter(env, `mint:${ip}`).take("mint", MINTS_PER_MINUTE, MINUTE, now);
}

/** Whether one device may send another funnel report now. */
export function mayReportFunnel(env: Env, deviceId: string, now: number): Promise<boolean> {
  return limiter(env, `funnel:${deviceId}`).take("funnel", FUNNEL_REPORTS_PER_HOUR, HOUR, now);
}

/** Whether one device, at its address, may make another screen link now. */
export async function mayMakeScreenLink(env: Env, deviceId: string, ip: string, now: number): Promise<boolean> {
  const [byDevice, byIp] = await Promise.all([
    limiter(env, `screen-make:device:${deviceId}`).take("screen-make", SCREEN_LINKS_PER_DEVICE, SCREEN_LINK_WINDOW, now),
    limiter(env, `screen-make:ip:${ip}`).take("screen-make", SCREEN_LINKS_PER_IP, SCREEN_LINK_WINDOW, now),
  ]);
  return byDevice && byIp;
}

/**
 * The guard on joining by code. A device already at the table passes. Anyone else is a guess:
 * a wrong one is counted against the device and its address, and once either has too many
 * (`backoff.ts`) every guess, right or wrong, is refused until its lockout ends, so a locked-out
 * guesser learns nothing. Returns the seconds to wait when refused, else whether the room exists.
 *
 * At a same-room table (Purrtrait) the code alone is not enough: a stranger needs the TV's live
 * near key (`ask.near`), and one without it is a wrong guess too, answered `notNear`, and counted
 * by the table as well once the limits have taken it. A device asking to be a screen
 * (`ask.screen`) needs none; the room says whether it is one. Nor does an app that can't draw the
 * table's game (`ask.games`): the room tells it there is no such table.
 */
export async function guardJoin(
  env: Env,
  code: string,
  deviceId: string,
  ip: string,
  now: number,
  ask: { near?: string | null; screen?: boolean; games?: string[] } = {},
): Promise<{ retryAfter: number } | { exists: boolean; notNear?: true }> {
  const known = await room(env, code).knows(deviceId, ask.near ?? null, ask.screen ?? false, ask.games);
  if (known === "member") return { exists: true };
  const failed = known === "none" || known === "not_near";
  const [byDevice, byIp] = await Promise.all([
    limiter(env, `device:${deviceId}`).guess(failed, DEVICE_JOIN_RULE, now),
    limiter(env, `ip:${ipBucket(ip)}`).guess(failed, IP_JOIN_RULE, now),
  ]);
  const retryAt = Math.max(byDevice.retryAt ?? 0, byIp.retryAt ?? 0);
  if (retryAt > 0) return { retryAfter: Math.max(1, Math.ceil((retryAt - now) / 1000)) };
  // The table counts only a guess the limits took, so a locked-out guesser can't close its typed code.
  if (known === "not_near") await room(env, code).missedNear().catch(() => undefined);
  return known === "not_near" ? { exists: true, notNear: true } : { exists: !failed };
}

/**
 * Whether `near` is a live near key at the table `code` (`/e/<code>?near=`), guarded like the
 * invite page's look: a wrong or stale key is a wrong guess against the address, and an address
 * locked out is told no, right key or wrong. Never throws.
 */
export async function peekNear(env: Env, code: string, near: string, ip: string, now: number): Promise<boolean> {
  try {
    const live = await room(env, code).nearLive(near);
    const { retryAt } = await limiter(env, `ip:${ipBucket(ip)}`).guess(!live, IP_JOIN_RULE, now);
    // As for joining: the table counts a wrong key only when the address wasn't refused.
    if (retryAt === null && !live) await room(env, code).missedNear().catch(() => undefined);
    return retryAt === null && live;
  } catch {
    return false;
  }
}

/**
 * The guard on linking a TV by its backup code: a wrong code is counted against the device and
 * its address under their own keys (joining a table by code is counted apart), with the same
 * backoff. Returns the seconds to wait when locked out, right code or wrong; else null.
 */
export async function guardScreenCode(env: Env, failed: boolean, deviceId: string, ip: string, now: number): Promise<number | null> {
  const [byDevice, byIp] = await Promise.all([
    limiter(env, `screen:device:${deviceId}`).guess(failed, DEVICE_JOIN_RULE, now),
    limiter(env, `screen:ip:${ipBucket(ip)}`).guess(failed, IP_JOIN_RULE, now),
  ]);
  const retryAt = Math.max(byDevice.retryAt ?? 0, byIp.retryAt ?? 0);
  return retryAt > 0 ? Math.max(1, Math.ceil((retryAt - now) / 1000)) : null;
}

/** What an invite page says of a table: its name, its game, and who invited (null: nobody named). */
export type InvitePeek = { table: string | null; game: string; host: { name: string; cat: number } | null };

/**
 * The invite page's look at a table (`/j/<code>`), guarded like joining by code: a code with no
 * table is a wrong guess against the address, and an address locked out learns nothing
 * (`hidden`: the page names nobody and says nothing of whether the table is there). `gone`: no
 * such table, or its game is over. A kitten's table names nobody and keeps its name to itself.
 */
export async function peekInvite(env: Env, code: string, ip: string, now: number): Promise<InvitePeek | "gone" | "hidden"> {
  try {
    const found = await room(env, code).invite();
    const { retryAt } = await limiter(env, `ip:${ipBucket(ip)}`).guess(found === null, IP_JOIN_RULE, now);
    if (retryAt !== null) return "hidden";
    if (!found || found.over) return "gone";
    // A TV's table with nobody seated has no host to ask about: it names nobody.
    const kitten = found.hostDeviceId !== "" && (await env.DEVICES.get(env.DEVICES.idFromName(found.hostDeviceId)).ageBand()) === "kitten";
    return kitten ? { table: null, game: found.game, host: null } : { table: found.table, game: found.game, host: found.host };
  } catch {
    return "hidden";
  }
}

/** `POST /v1/names/check`: whether the server would take this name, so the app can say so as it's typed. */
export async function nameCheck(env: Env, deviceId: string, body: Obj | null, now: number): Promise<Result<{ ok: boolean; reason?: string }>> {
  if (!(await limiter(env, `device:${deviceId}`).take("names", NAME_CHECKS_PER_MINUTE, MINUTE, now))) return fail(429, "rate_limited");
  const kitten = (await env.DEVICES.get(env.DEVICES.idFromName(deviceId)).ageBand()) === "kitten";
  const verdict = checkName(body, kitten);
  return verdict ? { ok: verdict } : fail(400, "bad_request");
}

/**
 * `POST /v1/rooms/{code}/reports`: a device at the table reports someone else there. The server
 * fills in everything but the person and the reason, from the room as it is now.
 */
export async function reportPlayer(env: Env, deviceId: string, code: string, body: Obj | null, now: number): Promise<Result<null>> {
  const parsed = parseReport(body);
  if (!parsed || !ROOM_CODE.test(code)) return fail(400, "bad_request");
  const seat = await room(env, code).seatOf(deviceId, parsed.person);
  if (!seat) return fail(404, "not_found");
  const limit = limiter(env, `device:${deviceId}`);
  if (!(await limit.take("reports", REPORTS_PER_HOUR, HOUR, now)) || !(await limit.take("reports-day", REPORTS_PER_DAY, 24 * HOUR, now))) {
    return fail(429, "rate_limited");
  }
  const report: Omit<Report, "id"> = {
    at: now,
    reason: parsed.reason,
    code,
    table: seat.table,
    name: seat.name,
    person: parsed.person,
    player: seat.playerId,
    device: seat.deviceId,
    byPlayer: seat.byPlayer,
    byDevice: deviceId,
  };
  const id = await reports(env).add(report);
  // No names in the log: it says only that there is something to read.
  console.warn("player_report", id, parsed.reason);
  return { ok: null };
}

/** `POST /v1/rooms/{code}/blocks`: `me` blocks someone at a table this device is at. */
export async function blockPlayer(env: Env, deviceId: string, me: string, code: string, body: Obj | null, now: number): Promise<Result<{ id: string }>> {
  const parsed = parseBlock(body);
  if (!parsed || !ROOM_CODE.test(code)) return fail(400, "bad_request");
  if (!(await limiter(env, `device:${deviceId}`).take("blocks", BLOCKS_PER_HOUR, HOUR, now))) return fail(429, "rate_limited");
  const seat = await room(env, code).seatOf(deviceId, parsed.person);
  if (!seat) return fail(404, "not_found");
  // A seat with no player (an old app) has nothing to block by.
  if (!seat.playerId || Object.values(await devicePlayers(env, deviceId)).includes(seat.playerId)) return fail(409, "no_player");
  const stored = await player(env, me).block({ playerId: seat.playerId, personId: parsed.person, name: seat.name, at: now });
  return stored ? { ok: { id: seat.playerId } } : fail(404, "no_player");
}

/** `GET /v1/me/blocks`: who `me` blocked, newest first. */
export async function listBlocks(env: Env, me: string): Promise<{ blocks: { id: string; person: string; name: string; at: number }[] }> {
  const rows = await player(env, me).blocks();
  return { blocks: rows.map((b) => ({ id: b.playerId, person: b.personId, name: b.name, at: b.at })) };
}

/** `DELETE /v1/me/blocks/{id}`. */
export async function unblockPlayer(env: Env, deviceId: string, me: string, id: string, now: number): Promise<Result<null>> {
  if (!PLAYER_ID.test(id)) return fail(400, "bad_request");
  if (!(await limiter(env, `device:${deviceId}`).take("blocks", BLOCKS_PER_HOUR, HOUR, now))) return fail(429, "rate_limited");
  await player(env, me).unblock(id);
  return { ok: null };
}

/** `GET /v1/admin/reports?after=`: the owner's list, or null (a 404) without the key. */
export async function ownerReports(env: Env, request: Request): Promise<{ reports: Report[] } | null | "bad"> {
  if (!(await ownerAsks(request.headers.get("authorization"), env.REPORTS_KEY))) return null;
  const after = parseAfter(new URL(request.url).searchParams.get("after"));
  if (after === null) return "bad";
  return { reports: await reports(env).list(after) };
}

/** Whether any of `owners` blocked any of `others` (a host and someone joining; a nudge's target and its sender). Never throws: a failed lookup blocks nothing. */
export async function anyBlocked(env: Env, owners: string[], others: string[]): Promise<boolean> {
  if (owners.length === 0 || others.length === 0) return false;
  const found = await Promise.all(owners.map((id) => player(env, id).blocksAny(others).catch(() => false)));
  return found.includes(true);
}
