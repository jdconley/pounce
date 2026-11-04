import { IDENTITIES_NAME } from "./identities";
import { newPlayerId, sha256Hex, subjectHash } from "./ids";
import { parseLink, parseSignIn } from "./parse";
import { provider } from "./providers";

import type { Env } from "../env";
import type { Profile } from "./parse";
import type { HouseholdPerson, Player } from "./player";
import type { TableEntry } from "../room/tables";

/** A flow's outcome: the JSON to answer with, or an error status and body. */
export type Result<T> = { ok: T } | { status: number; error: string; extra?: Record<string, unknown> };

const fail = (status: number, error: string, extra?: Record<string, unknown>): Result<never> => ({
  status,
  error,
  ...(extra ? { extra } : {}),
});

const identities = (env: Env) => env.IDENTITIES.get(env.IDENTITIES.idFromName(IDENTITIES_NAME));
/**
 * The `Player` stub with each method's plain return type. The generated RPC
 * types recurse through `Json` past TypeScript's depth limit.
 */
type PlayerRpc = {
  [K in keyof Player]: Player[K] extends (...args: infer A) => infer R ? (...args: A) => Promise<Awaited<R>> : never;
};
export const player = (env: Env, id: string) => env.PLAYERS.get(env.PLAYERS.idFromName(id)) as unknown as PlayerRpc;
const device = (env: Env, id: string) => env.DEVICES.get(env.DEVICES.idFromName(id));
const room = (env: Env, code: string) => env.ROOMS.get(env.ROOMS.idFromName(code));

const nowSec = (now: number) => Math.floor(now / 1000);

/** Best effort: a room that misses a backfill gets it again on the next profile upload. */
async function eachRoom(codes: string[], run: (code: string) => Promise<unknown>): Promise<void> {
  await Promise.all(
    codes.map((code) =>
      run(code).catch((error: unknown) => {
        console.error("room_update_failed", String(error));
      }),
    ),
  );
}

/**
 * Binds each person on the device to a player, creating guest players for
 * new ones (§13.1). A person whose key doesn't match the one first seen for
 * that id is rejected. Rooms the device sits in learn the new players.
 */
export async function uploadProfile(
  env: Env,
  deviceId: string,
  profile: Profile,
  now: number,
): Promise<{ players: Record<string, string>; rejected: string[] }> {
  const players: Record<string, string> = {};
  const rejected: string[] = [];
  for (const person of profile.people) {
    // A person without a band is the device's owner's age (§14.1).
    const ageBand = person.ageBand ?? profile.ageBand;
    const hash = await subjectHash("device", person.id);
    const bound = await identities(env).bind("device", hash, newPlayerId(), await sha256Hex(person.key));
    if ("mismatch" in bound) {
      rejected.push(person.id);
      continue;
    }
    const p = player(env, bound.playerId);
    await p.touch({
      playerId: bound.playerId,
      deviceId,
      name: person.name,
      cat: person.cat,
      ...(ageBand ? { ageBand } : {}),
      at: person.at ?? now,
      now,
    });
    await p.addIdentity({ provider: "device", subjectHash: hash, deviceId, secret: null });
    players[person.id] = bound.playerId;
  }

  const index = device(env, deviceId);
  const { tables } = await index.setProfile({
    timeZone: profile.timeZone,
    ageBand: profile.ageBand ?? null,
    people: players,
  });
  await eachRoom(tables, (code) => room(env, code).adopt({ person: players, deviceId }));

  const { account } = await index.players();
  if (account) {
    const household: HouseholdPerson[] = profile.people
      .filter((person) => players[person.id] !== undefined && players[person.id] !== account)
      .map((person) => ({ personId: person.id, playerId: players[person.id] as string, name: person.name, cat: person.cat }));
    await player(env, account).setHousehold(deviceId, household);
  }
  return { players, rejected };
}

/** personId → playerId for everyone the device speaks for: its own people, plus its account's household. */
export async function devicePlayers(env: Env, deviceId: string): Promise<Record<string, string>> {
  const { people, account } = await device(env, deviceId).players();
  const map = { ...people };
  if (account) {
    for (const h of await player(env, account).household()) map[h.personId] ??= h.playerId;
  }
  return map;
}

/** The player a `/v1/me` request acts for: the named person if the device speaks for them, else its account. */
export async function resolveMe(env: Env, deviceId: string, personId: string | null): Promise<string | null> {
  if (personId !== null) return (await devicePlayers(env, deviceId))[personId] ?? null;
  return (await device(env, deviceId).players()).account;
}

/** The device's own tables and every one of its players', newest report per table first. */
export async function deviceTables(env: Env, deviceId: string): Promise<TableEntry[]> {
  const { people, account } = await device(env, deviceId).players();
  const ids = new Set([...Object.values(people), ...(account ? [account] : [])]);
  const lists = await Promise.all([device(env, deviceId).listTables(), ...[...ids].map((id) => player(env, id).listTables())]);
  const byCode = new Map<string, TableEntry>();
  for (const entry of lists.flat()) {
    const seen = byCode.get(entry.code);
    if (!seen || entry.updatedAt > seen.updatedAt) byCode.set(entry.code, entry);
  }
  return [...byCode.values()].sort((a, b) => b.updatedAt - a.updatedAt).slice(0, 50);
}

/**
 * Folds `from` into `to`: synced state, devices and tables move, rooms hand
 * over `from`'s seats, and `from` becomes a forwarding stub. Repointing the
 * identities commits it: until then `from`'s device identity still names
 * `from`, so a sign-in retried after a failure runs the whole merge again,
 * and every step before is idempotent.
 */
export async function merge(env: Env, from: string, to: string, now: number): Promise<void> {
  const exported = await player(env, from).exportForMerge();
  await player(env, to).absorb(exported, now);
  await Promise.all(exported.devices.map((d) => device(env, d).repointPlayer(from, to)));
  await Promise.all(exported.tables.map((t) => room(env, t.code).adopt({ from, to })));
  await identities(env).repoint(from, to);
  await player(env, from).becomeStub(to, now);
}

/** One device stops speaking for a player: its device identities for that player go, and the link. */
async function detach(env: Env, deviceId: string, playerId: string): Promise<void> {
  const p = player(env, playerId);
  const removed = await p.removeIdentities("device", deviceId);
  await Promise.all(removed.map((r) => identities(env).remove("device", r.subjectHash, playerId)));
  await device(env, deviceId).forgetPlayer(playerId);
  await p.detachDevice(deviceId);
}

type SignedIn = { playerId: string; outcome: "upgraded" | "merged" | "same"; account: boolean; profile: { name: string; cat: number } };

/**
 * Sign in for one person on this device (§13.1): the anonymous upgrade when
 * the identity is new, a merge into its owner when it isn't.
 */
export async function signIn(
  env: Env,
  deviceId: string,
  providerId: string,
  body: unknown,
  now: number,
  fetcher: typeof fetch,
): Promise<Result<SignedIn>> {
  const p = provider(providerId);
  if (!p?.signIn) return fail(404, "not_found");
  const parsed = parseSignIn(body);
  if (!parsed) return fail(400, "bad_request");
  const verified = await p.verify(parsed.proof, env, fetcher, nowSec(now));
  if (!verified) return fail(401, "bad_proof");
  if (verified.nonce && !(await identities(env).useNonce(verified.nonce.hash, verified.nonce.expiresAt, now))) {
    return fail(401, "bad_proof");
  }

  const binding = await identities(env).lookup("device", await subjectHash("device", parsed.person.id));
  if (!binding || binding.verifier !== (await sha256Hex(parsed.person.key))) return fail(404, "unknown_person");
  const guestId = binding.playerId;
  const guest = await player(env, guestId).meta();
  if (!guest) return fail(404, "unknown_person");
  if (guest.ageBand === "kitten" || (await device(env, deviceId).ageBand()) === "kitten") return fail(403, "not_allowed");

  const hash = await subjectHash(p.id, verified.subject);
  if (guest.signedIn) {
    const own = (await player(env, guestId).identities()).some((r) => r.provider === p.id && r.subjectHash === hash);
    if (!own) return fail(409, "already_signed_in");
  }
  const secret = (await p.secret?.(parsed.proof, env, fetcher, nowSec(now))) ?? null;
  const identity = { provider: p.id, subjectHash: hash, deviceId, secret };
  const bound = await identities(env).bind(p.id, hash, guestId);
  // A sign-in identity is bound without a verifier, so `bind` never reports a mismatch for one.
  const owner = (bound as { playerId: string; created: boolean }).playerId;
  let outcome: SignedIn["outcome"];
  if (owner === guestId) {
    outcome = (bound as { created: boolean }).created ? "upgraded" : "same";
    await player(env, guestId).addIdentity(identity);
  } else {
    await player(env, owner).addIdentity(identity);
    await merge(env, guestId, owner, now);
    outcome = "merged";
  }

  const index = device(env, deviceId);
  const { account } = await index.players();
  if (account === null) await index.setAccount(owner);
  await player(env, owner).attachDevice(deviceId, now);
  const meta = await player(env, owner).meta();
  return {
    ok: {
      playerId: owner,
      outcome,
      account: account === null || account === owner,
      profile: { name: meta?.name ?? guest.name, cat: meta?.cat ?? guest.cat },
    },
  };
}

/** Adds a provider to a player. If someone else has that identity, merging takes a yes from the app first. */
export async function linkIdentity(
  env: Env,
  deviceId: string,
  me: string,
  providerId: string,
  body: unknown,
  now: number,
  fetcher: typeof fetch,
): Promise<Result<{ linked: true; merged: boolean }>> {
  const p = provider(providerId);
  if (!p?.signIn) return fail(404, "not_found");
  const parsed = parseLink(body);
  if (!parsed) return fail(400, "bad_request");
  const self = player(env, me);
  const meta = await self.meta();
  if (!meta) return fail(404, "no_player");
  if (meta.ageBand === "kitten" || (await device(env, deviceId).ageBand()) === "kitten") return fail(403, "not_allowed");
  if ((await self.identities()).some((r) => r.provider === p.id)) return fail(409, "already_linked");
  const verified = await p.verify(parsed.proof, env, fetcher, nowSec(now));
  if (!verified) return fail(401, "bad_proof");

  const hash = await subjectHash(p.id, verified.subject);
  const existing = await identities(env).lookup(p.id, hash);
  if (existing && existing.playerId !== me && !parsed.confirmMerge) {
    const other = await player(env, existing.playerId).meta();
    return fail(409, "merge_needed", { otherPlayer: { name: other?.name ?? "", cat: other?.cat ?? 0 } });
  }
  // Used only once the request goes through, so a merge confirmed with the same token still works.
  if (verified.nonce && !(await identities(env).useNonce(verified.nonce.hash, verified.nonce.expiresAt, now))) {
    return fail(401, "bad_proof");
  }
  const secret = (await p.secret?.(parsed.proof, env, fetcher, nowSec(now))) ?? null;
  await self.addIdentity({ provider: p.id, subjectHash: hash, deviceId: null, secret });
  if (existing && existing.playerId !== me) {
    await merge(env, existing.playerId, me, now);
    return { ok: { linked: true, merged: true } };
  }
  await identities(env).bind(p.id, hash, me);
  return { ok: { linked: true, merged: false } };
}

/**
 * Removes a provider and revokes its tokens. Unlinking the last sign-in
 * leaves a guest on this device: every other device is detached.
 */
export async function unlinkIdentity(
  env: Env,
  deviceId: string,
  me: string,
  providerId: string,
  now: number,
  fetcher: typeof fetch,
): Promise<Result<null>> {
  const p = provider(providerId);
  if (!p?.signIn) return fail(404, "not_found");
  const self = player(env, me);
  const removed = await self.removeIdentities(p.id);
  if (removed.length === 0) return fail(404, "not_linked");
  for (const row of removed) {
    await identities(env).remove(p.id, row.subjectHash, me);
    if (row.secret) await p.revoke?.(row.secret, env, fetcher, nowSec(now));
  }
  if (!(await self.meta())?.signedIn) {
    const others = (await self.deviceIds()).filter((d) => d !== deviceId);
    await Promise.all(others.map((d) => detach(env, d, me)));
    // A household person unlinking leaves the phone signed in to its owner.
    const index = device(env, deviceId);
    if ((await index.players()).account === me) await index.setAccount(null);
  }
  return { ok: null };
}

/** This device signs out: it stops speaking for its account, which keeps its data. */
export async function signOut(env: Env, deviceId: string): Promise<void> {
  const { account } = await device(env, deviceId).players();
  if (account) await detach(env, deviceId, account);
}

/**
 * Deletes a player and everything about them (§14): tokens revoked,
 * identities and device links gone, seats handed back to their devices.
 */
export async function deleteMe(env: Env, me: string, now: number, fetcher: typeof fetch): Promise<void> {
  const self = player(env, me);
  const exported = await self.exportForMerge();
  for (const row of exported.identities) {
    if (row.secret) await provider(row.provider)?.revoke?.(row.secret, env, fetcher, nowSec(now));
  }
  await identities(env).removePlayer(me);
  await Promise.all(exported.devices.map((d) => device(env, d).forgetPlayer(me)));
  await eachRoom(
    exported.tables.map((t) => t.code),
    (code) => room(env, code).adopt({ from: me, to: null }),
  );
  await self.destroy();
}
