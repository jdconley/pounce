import { base64url } from "../players/ids";

import { mergeStates, newPair, repoint, type PairPerson, type PairState, type StreakView } from "./pair-core";

import type { Env } from "../env";
import type { Pair } from "./pair";
import type { PlayerRpc } from "../players/accounts";
import type { Look, StreakIntent, Unlocks } from "../room/core";
import type { Seed } from "../rules/rng";

/** `pr_` + 16 random bytes, base64url (§13.2). */
export const PAIR_ID = /^pr_[A-Za-z0-9_-]{22}$/;
const PAIR_ID_BYTES = 16;

type PairRpc = {
  [K in keyof Pair]: Pair[K] extends (...args: infer A) => infer R ? (...args: A) => Promise<Awaited<R>> : never;
};

const player = (env: Env, id: string) => env.PLAYERS.get(env.PLAYERS.idFromName(id)) as unknown as PlayerRpc;
const pair = (env: Env, id: string) => env.PAIRS.get(env.PAIRS.idFromName(id)) as unknown as PairRpc;

const newPairId = () => `pr_${base64url(crypto.getRandomValues(new Uint8Array(PAIR_ID_BYTES)))}`;

function cryptoSeed(): Seed {
  // Four words, never all zero (createRng refuses that).
  const words: number[] = Array.from(crypto.getRandomValues(new Uint32Array(4)));
  if (!words.some((w) => w !== 0)) words[0] = 1;
  return words as Seed;
}

export type PairViews = Record<string, { pair: string; view: StreakView }[]>;

/**
 * The pair of `a` and `b`, made now if both have taken a turn at this table
 * (§6.1). The player with the smaller id coordinates, so two rooms can't make
 * two pairs. Null when either left the other's streak, or is gone.
 */
async function ensurePair(env: Env, a: string, b: string, turnedAt: Record<string, number>, now: number): Promise<string | null> {
  const [x, y] = a < b ? [a, b] : [b, a];
  const existing = await player(env, x).pairWith(y);
  if (existing) return existing;
  if (turnedAt[x] === undefined || turnedAt[y] === undefined) return null;
  const made = await player(env, x).createPair(y, newPairId(), now);
  if (!made) return null;
  if (!made.created) return made.pairId;
  const [px, py] = await Promise.all([player(env, x).streakProfile(), player(env, y).streakProfile()]);
  const stored = px !== null && py !== null && (await player(env, y).storePair(made.pairId, x, now));
  if (!stored) {
    await player(env, x).dropPair(made.pairId);
    return null;
  }
  const turns = { [x]: turnedAt[x], [y]: turnedAt[y] };
  await pair(env, made.pairId).init(newPair(made.pairId, [px as PairPerson, py as PairPerson], now, cryptoSeed(), turns));
  return made.pairId;
}

/**
 * A room's report reaches every pair at the table (§13.3): each pair of
 * different players seated there. Returns each player's new views.
 */
export async function reportTable(env: Env, intent: StreakIntent, now: number): Promise<PairViews> {
  const out: PairViews = {};
  const players = [...new Set(intent.players)];
  for (let i = 0; i < players.length; i++) {
    for (let j = i + 1; j < players.length; j++) {
      const [a, b] = [players[i] as string, players[j] as string];
      const pairId = await ensurePair(env, a, b, intent.turnedAt, now);
      if (!pairId) continue;
      const views = await pair(env, pairId).report(
        { code: intent.code, at: intent.at, by: intent.by, holder: intent.holder, over: intent.over },
        now,
      );
      if (!views) continue;
      for (const id of [a, b]) (out[id] ??= []).push({ pair: pairId, view: views[id] as StreakView });
    }
  }
  return out;
}

/** `GET /v1/me/streaks`: the top pair first (pinned, else the longest streak, then the latest turn; §7). */
export async function myStreaks(env: Env, me: string, now: number): Promise<(StreakView & { pinned: boolean })[]> {
  const rows = await player(env, me).pairList();
  const views = await Promise.all(
    rows.map(async (row) => {
      const v = await pair(env, row.pairId).view(me, now);
      return v ? { ...v, pinned: row.pinned } : null;
    }),
  );
  return views
    .filter((v) => v !== null)
    .sort((x, y) => Number(y.pinned) - Number(x.pinned) || y.count - x.count || y.lastTurnAt - x.lastTurnAt);
}

/** Whether `pairId` is one of `me`'s pairs. */
export async function isMine(env: Env, me: string, pairId: string): Promise<boolean> {
  return (await player(env, me).pairList()).some((r) => r.pairId === pairId);
}

export const pairStub = pair;

/** Leaving a streak (§14): gone for both, with no push; the leaver keeps a tombstone. */
export async function leavePair(env: Env, me: string, pairId: string, now: number): Promise<boolean> {
  const partner = await player(env, me).leavePair(pairId, now);
  if (partner === null) return false;
  await player(env, partner).dropPair(pairId);
  await pair(env, pairId).destroy();
  return true;
}

/** Account deletion and guest expiry leave every pair (§14). Touches no pair when there are none. */
export async function leaveAllPairs(env: Env, me: string, rows?: { pairId: string; partnerId: string }[]): Promise<void> {
  for (const row of rows ?? (await player(env, me).pairList())) {
    await player(env, row.partnerId).dropPair(row.pairId);
    await pair(env, row.pairId).destroy();
  }
}

/**
 * The merge rules for pairs (§13.1): each pair of `from` re-points to `to`;
 * a pair with `to` itself is deleted (a player is never their own pair); and
 * when `to` already has a pair with the same partner, the two merge. Each
 * pair is dropped from `from` once handled, so a retried merge resumes.
 */
export async function mergePairs(env: Env, from: string, to: string, now: number): Promise<void> {
  const rows = await player(env, from).pairList();
  if (rows.length === 0) return;
  const target = player(env, to);
  const theirs = await target.pairList();
  for (const row of rows) {
    const q = row.partnerId;
    const same = theirs.find((r) => r.partnerId === q);
    if (q === to) {
      await target.dropPair(row.pairId);
      await pair(env, row.pairId).destroy();
    } else if (same && same.pairId !== row.pairId) {
      const [mine, kept] = await Promise.all([pair(env, row.pairId).exportState(), pair(env, same.pairId).exportState()]);
      if (mine && kept) {
        repoint(mine as PairState, from, to);
        await pair(env, same.pairId).replace(mergeStates(kept as PairState, mine as PairState));
      }
      await player(env, q).dropPair(row.pairId);
      await pair(env, row.pairId).destroy();
    } else if (!same) {
      await pair(env, row.pairId).repoint(from, to);
      if (await target.storePair(row.pairId, q, now)) {
        await player(env, q).repointPair(row.pairId, to);
        if (row.pinned && !theirs.some((r) => r.pinned)) await target.pin(row.pairId);
      } else {
        // `to` left that partner's streak: the guest's streak with them doesn't come back.
        await player(env, q).dropPair(row.pairId);
        await pair(env, row.pairId).destroy();
      }
    }
    await player(env, from).dropPair(row.pairId);
  }
  await target.addTombstones(await player(env, from).tombstones(), now);
  await syncPairPeople(env, to, now);
}

/** Tells a player's pairs their current name, cat, time zone and quiet hours. */
export async function syncPairPeople(env: Env, playerId: string, now: number): Promise<void> {
  const p = player(env, playerId);
  const [profile, rows] = await Promise.all([p.streakProfile(), p.pairList()]);
  if (!profile) return;
  await Promise.all(rows.map((r) => pair(env, r.pairId).setPerson(profile, now)));
}

/** The card backs and rugs these players have unlocked across all their pairs (§9.4). */
export async function unlocksFor(env: Env, playerIds: string[]): Promise<Unlocks> {
  const backs = new Set<string>();
  const rugs = new Set<string>();
  for (const id of playerIds) {
    for (const row of await player(env, id).pairList()) {
      const u = await pair(env, row.pairId).unlocked(id);
      for (const b of u?.backs ?? []) backs.add(b);
      for (const r of u?.rugs ?? []) rugs.add(r);
    }
  }
  return { backs: [...backs], rugs: [...rugs] };
}

/** The look a device's new table starts with: its account's last-used one, else its only person's. */
export async function creatorLook(env: Env, people: Record<string, string>, account: string | null): Promise<Look | null> {
  const ids = Object.values(people);
  const who = account ?? (ids.length === 1 ? (ids[0] as string) : null);
  return who ? player(env, who).lastLook() : null;
}

export async function rememberLook(env: Env, playerIds: string[], look: Look): Promise<void> {
  await Promise.all(playerIds.map((id) => player(env, id).setLastLook(look)));
}
