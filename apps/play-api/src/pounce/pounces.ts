import { LINKS_NAME } from "../links/links";
import { deliverToPlayer } from "../notify/deliver";
import { gate } from "../notify/policy";
import { answeredPush, pouncePush, streakBlock } from "../notify/pushes";
import { devicePlayers, player, type Result } from "../players/accounts";
import { base64url } from "../players/ids";
import { newRoomCode } from "../room/codes";
import { defaultRoomName } from "../room/names";
import { DEFAULT_BACK, DEFAULT_RUG } from "../streaks/catalog";
import { FALLBACK_ZONE } from "../streaks/clock";

import { ANSWER_MS, answerable, KEEP_MS, nextAnswer, type Target } from "./limits";
import { LINK_TOKEN, parseAnswer, parsePounce, POUNCE_ID } from "./parse";

import type { Env } from "../env";
import type { Face } from "../notify/pushes";
import type { StoredPounce } from "../players/player";
import type { SeatInfo } from "../room/core";

const ID_BYTES = 16;
const ROOM_CODE_ATTEMPTS = 5;
const LINK_MS = ANSWER_MS;

const fail = (status: number, error: string, extra?: Record<string, unknown>): Result<never> => ({ status, error, ...(extra ? { extra } : {}) });
const links = (env: Env) => env.LINKS.get(env.LINKS.idFromName(LINKS_NAME));
const pairStub = (env: Env, id: string) => env.PAIRS.get(env.PAIRS.idFromName(id));
const randomId = () => base64url(crypto.getRandomValues(new Uint8Array(ID_BYTES)));
const cryptoRng = (): number => (crypto.getRandomValues(new Uint32Array(1))[0] as number) / 2 ** 32;

/** The person on `deviceId` who is `playerId`: their seat at a new table carries this id. */
async function personOn(env: Env, deviceId: string, playerId: string, named: string | null): Promise<string | null> {
  const map = await devicePlayers(env, deviceId);
  if (named !== null) return map[named] === playerId ? named : null;
  return Object.entries(map).find(([, p]) => p === playerId)?.[0] ?? null;
}

/**
 * `POST /v1/pounces` (§12.4, §13.3 flow 4): with `to` (a pair), a push to the
 * partner; without, a Messages link. Limits are checked as the pounce is
 * stored. A kitten may pounce in the app only (§14.1).
 */
export async function createPounce(
  env: Env,
  deviceId: string,
  me: string,
  named: string | null,
  body: unknown,
  now: number,
  origin: string,
): Promise<Result<{ id: string; link?: string }>> {
  const parsed = parsePounce(body);
  if (!parsed) return fail(400, "bad_request");
  const self = player(env, me);
  const profile = await self.pushProfile();
  const fromPerson = await personOn(env, deviceId, me, named);
  if (!profile || !fromPerson) return fail(404, "no_player");
  const id = `pc_${randomId()}`;
  const base = { id, target: parsed.target, at: now, answer: null, answeredAt: null, code: null, fromPerson, fromDevice: deviceId };

  if (parsed.to === null) {
    if (profile.band === "kitten" || (await env.DEVICES.get(env.DEVICES.idFromName(deviceId)).ageBand()) === "kitten") {
      return fail(403, "not_allowed");
    }
    if (typeof parsed.target === "object") return fail(400, "bad_request");
    const token = randomId();
    const stored = await self.tryPounce({ ...base, to: null, quiet: false, link: token }, now);
    if ("until" in stored) return fail(429, "resting", { until: stored.until });
    if ("gone" in stored) return fail(404, "no_player");
    await links(env).put(id, { kind: "pounce", playerId: me, pounceId: id, expires: now + KEEP_MS });
    await links(env).put(token, { kind: "link", playerId: me, pounceId: id, expires: now + LINK_MS });
    return { ok: { id, link: `${origin}/p/${token}` } };
  }

  const pairId = parsed.to;
  const row = (await self.pairList()).find((r) => r.pairId === pairId);
  if (!row) return fail(404, "not_found");
  const facts = await pairStub(env, pairId).facts(row.partnerId, now);
  if (!facts) return fail(404, "not_found");
  if (typeof parsed.target === "object" && !facts.tables.includes(parsed.target.table)) return fail(409, "not_shared");
  const them = await player(env, row.partnerId).pushProfile();
  if (!them) return fail(404, "not_found");
  const g = gate({ kind: "pounce", band: them.band, zone: them.zone ?? FALLBACK_ZONE, settings: them.settings, now, spacedAt: null, remindersToday: 0 });
  const quiet = !g.send || g.level === "passive";
  const stored = await self.tryPounce({ ...base, to: row.partnerId, quiet, link: null }, now);
  if ("until" in stored) return fail(429, "resting", { until: stored.until });
  if ("gone" in stored) return fail(404, "no_player");
  await links(env).put(id, { kind: "pounce", playerId: me, pounceId: id, expires: now + KEEP_MS });
  if (g.send) {
    const names = new Map((await player(env, row.partnerId).listTables()).map((t) => [t.code, t.name]));
    const target =
      typeof parsed.target === "object"
        ? { table: parsed.target.table, name: names.get(parsed.target.table) ?? defaultRoomName(parsed.target.table) }
        : parsed.target;
    const push = pouncePush({
      id,
      pair: pairId,
      to: them.name,
      from: { name: profile.name, cat: (await self.meta())?.cat ?? 0 },
      target,
      streak: streakBlock(facts.view),
    });
    await deliverToPlayer(env, them, push, g.level);
  }
  return { ok: { id } };
}

/** The pounce behind an id, with its sender; null when it's unknown, expired or someone else's. */
async function findPounce(env: Env, id: string, now: number): Promise<{ sender: string; row: StoredPounce } | null> {
  if (!POUNCE_ID.test(id)) return null;
  const index = await links(env).get(id, now);
  if (!index || index.kind !== "pounce") return null;
  const row = await player(env, index.playerId).pounce(id);
  return row ? { sender: index.playerId, row } : null;
}

/** Whether both players hold a seat at a table still in play. */
async function shared(env: Env, a: string, b: string, code: string): Promise<boolean> {
  const [x, y] = await Promise.all([player(env, a).listTables(), player(env, b).listTables()]);
  const live = (list: typeof x) => list.some((t) => t.code === code && t.status !== "over");
  return live(x) && live(y);
}

/** Deals a new Cat Tower table seating exactly these two (§12.4), with the sender's last-used look. */
async function dealFor(env: Env, seats: SeatInfo[], sender: string, hostDeviceId: string): Promise<string | null> {
  const look = (await player(env, sender).lastLook()) ?? { rug: DEFAULT_RUG, back: DEFAULT_BACK };
  for (let i = 0; i < ROOM_CODE_ATTEMPTS; i++) {
    const code = newRoomCode(cryptoRng);
    const made = await env.ROOMS.get(env.ROOMS.idFromName(code)).initRematch(code, { name: defaultRoomName(code), look, seats, hostDeviceId });
    if ("ok" in made) return code;
  }
  return null;
}

/**
 * `POST /v1/pounces/{id}/answer` (§12.4): Play (to the table, a new game, or
 * the one picked), In a bit, or Not now. Idempotent, so the app's background
 * retry is safe; Play is never taken back. A link pounce needs its token,
 * which the first answer uses up.
 */
export async function answerPounce(
  env: Env,
  deviceId: string,
  me: string,
  named: string | null,
  id: string,
  body: unknown,
  now: number,
): Promise<Result<{ code?: string }>> {
  const parsed = parseAnswer(body);
  const found = await findPounce(env, id, now);
  if (!found || found.sender === me) return fail(404, "not_found");
  if (!parsed) return fail(400, "bad_request");
  const { sender, row } = found;
  if (row.to === null) {
    const link = parsed.link === null ? null : await links(env).get(parsed.link, now);
    if (!link || link.kind !== "link" || link.pounceId !== id) return fail(404, "not_found");
  } else if (row.to !== me) {
    return fail(404, "not_found");
  }
  if (!answerable(row, now)) return fail(410, "expired");
  const done = (code: string | null): Result<{ code?: string }> => ({ ok: code ? { code } : {} });
  if (!nextAnswer(row, parsed.answer)) return done(row.code);

  let code: string | null = null;
  if (parsed.answer === "play") {
    const choice = typeof row.target === "object" ? row.target.table : row.target === "pick" ? parsed.choice : "new";
    if (choice === null) return fail(400, "bad_request");
    if (choice === "new") {
      const [mine, theirs, person] = await Promise.all([player(env, me).meta(), player(env, sender).meta(), personOn(env, deviceId, me, named)]);
      if (!mine || !theirs || !person) return fail(404, "no_player");
      // The answerer is here now, so they get the first move (seat 1 in Cat Tower).
      const seats: SeatInfo[] = [
        { kind: "human", person: { id: row.fromPerson, name: theirs.name, cat: theirs.cat }, deviceId: row.fromDevice, playerId: sender },
        { kind: "human", person: { id: person, name: mine.name, cat: mine.cat }, deviceId, playerId: me },
      ];
      code = await dealFor(env, seats, sender, deviceId);
      if (!code) return fail(503, "no_room_code");
    } else {
      if (!(await shared(env, me, sender, choice))) return fail(409, "not_shared");
      code = choice;
    }
  }
  if (row.to === null && parsed.link !== null) await links(env).take(parsed.link, now);
  await player(env, sender).answerPounce(id, me, parsed.answer, code, now);

  const [mine, theirs] = await Promise.all([player(env, me).meta(), player(env, sender).meta()]);
  if (mine && theirs) {
    const who: Face = { name: mine.name, cat: mine.cat };
    const pair = await player(env, me).pairWith(sender);
    const push = answeredPush({ id, pair, to: theirs.name, who, answer: parsed.answer, code });
    await player(env, sender).status(push, now).catch(() => false);
  }
  return done(code ?? row.code);
}

/** `GET /v1/pounces/links/{token}` and the `/p/` page: an unused, unexpired link's pounce and sender. */
export async function linkPounce(env: Env, token: string, now: number): Promise<{ id: string; from: Face; target: Target } | null> {
  if (!LINK_TOKEN.test(token)) return null;
  const link = await links(env).get(token, now);
  if (!link || link.kind !== "link") return null;
  const row = await player(env, link.playerId).pounce(link.pounceId);
  const meta = await player(env, link.playerId).meta();
  if (!row || row.to !== null || !meta || meta.forwardTo !== null) return null;
  return { id: row.id, from: { name: meta.name, cat: meta.cat }, target: row.target };
}
