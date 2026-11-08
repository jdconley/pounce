import { pokeWidgets } from "../notify/deliver";
import { statusPush, type Face } from "../notify/pushes";
import { base64url } from "../players/ids";
import { pounceView, type PounceView } from "../pounce/limits";

import { advance, mergeStates, newPair, NO_POUNCE, pairReport, repoint, type PairEvent, type PairPerson, type PairState, type StreakView } from "./pair-core";
import { notifyOn } from "./profile";
import { trophies, type Trophies } from "./trophies";


import type { Env } from "../env";
import type { Pair } from "./pair";
import type { OwnStreak } from "./personal";
import type { StreakBlock } from "../notify/types";
import type { PlayerRpc } from "../players/accounts";
import type { Look, StreakIntent, Unlocks } from "../room/core";
import type { Seed } from "../rules/rng";

export { PAIR_ID } from "../players/ids";
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
async function ensurePair(
  env: Env,
  a: string,
  b: string,
  turnedAt: Record<string, number>,
  now: number,
  requireTurns = true,
): Promise<string | null> {
  const [x, y] = a < b ? [a, b] : [b, a];
  const existing = await player(env, x).pairWith(y);
  if (existing) return existing;
  if (requireTurns && (turnedAt[x] === undefined || turnedAt[y] === undefined)) return null;
  const made = await player(env, x).createPair(y, newPairId(), now);
  if (!made) return null;
  if (!made.created) return made.pairId;
  const [px, py] = await Promise.all([player(env, x).streakProfile(), player(env, y).streakProfile()]);
  const stored = px !== null && py !== null && (await player(env, y).storePair(made.pairId, x, now));
  if (!stored) {
    await player(env, x).dropPair(made.pairId);
    return null;
  }
  const turns: Record<string, number> = {};
  for (const id of [x, y]) if (turnedAt[id] !== undefined) turns[id] = turnedAt[id];
  await pair(env, made.pairId).init(newPair(made.pairId, [px as PairPerson, py as PairPerson], now, cryptoSeed(), turns));
  return made.pairId;
}

/**
 * Connections on accept (trophy room design D2): the pair of a link's sender
 * and the person who answered it Play, made now at 0 without a turn, so both
 * lists show it before the table is dealt. Null when either left the other's
 * streak (the leaver can undo that from the ghosted cat), or is gone.
 */
export async function connect(env: Env, a: string, b: string, now: number): Promise<string | null> {
  if (a === b) return null;
  return ensurePair(env, a, b, {}, now, false);
}

/**
 * A room's report reaches every pair at the table (§13.3): each pair of
 * different players seated there. Returns each player's new views.
 */
export async function reportTable(env: Env, intent: StreakIntent, now: number, awake: string[] = []): Promise<PairViews> {
  const out: PairViews = {};
  const players = [...new Set(intent.players)];
  for (let i = 0; i < players.length; i++) {
    for (let j = i + 1; j < players.length; j++) {
      const [a, b] = [players[i] as string, players[j] as string];
      const r = pairReport(intent, a, b);
      let pairId = await ensurePair(env, a, b, intent.turnedAt, now);
      if (!pairId) continue;
      let views = await pair(env, pairId).report(r, now, awake);
      if (!views) {
        // Both players list a pair whose object has no state (its creation failed part way): start it over.
        await Promise.all([player(env, a).dropPair(pairId), player(env, b).dropPair(pairId)]);
        pairId = await ensurePair(env, a, b, intent.turnedAt, now);
        views = pairId ? await pair(env, pairId).report(r, now, awake) : null;
      }
      if (!pairId || !views) continue;
      const pounces = notifyOn(env) ? await pounceViews(env, a, b, now) : null;
      for (const id of [a, b]) {
        const view = views[id] as StreakView;
        (out[id] ??= []).push({ pair: pairId, view: pounces ? { ...view, pounce: pounces[id] as PounceView } : view });
      }
    }
  }
  return out;
}

/**
 * Both people's `pounce` field for one pair (§12.4, §13.4), from the pounces
 * each has sent the other. Cosmetic: a failure shows none.
 */
export async function pounceViews(env: Env, a: string, b: string, now: number): Promise<Record<string, PounceView>> {
  try {
    const [ab, ba] = await Promise.all([player(env, a).pouncesTo(b, now), player(env, b).pouncesTo(a, now)]);
    return { [a]: pounceView(ab, ba, now), [b]: pounceView(ba, ab, now) };
  } catch {
    return { [a]: NO_POUNCE, [b]: NO_POUNCE };
  }
}

/** `GET /v1/me/streaks`: the top pair first (pinned, else the longest streak, then the latest turn; §7). */
export async function myStreaks(env: Env, me: string, now: number): Promise<(StreakView & { pinned: boolean })[]> {
  const rows = await player(env, me).pairList();
  const views = await Promise.all(
    rows.map(async (row) => {
      const v = await pair(env, row.pairId).view(me, now);
      if (!v) return null;
      const view = notifyOn(env) ? { ...v.view, pounce: (await pounceViews(env, me, row.partnerId, now))[me] as PounceView } : v.view;
      return { view, lastTurnAt: v.lastTurnAt, pinned: row.pinned };
    }),
  );
  return views
    .filter((v) => v !== null)
    .sort(
      (x, y) =>
        Number(y.pinned) - Number(x.pinned) || y.view.count - x.view.count || y.lastTurnAt - x.lastTurnAt,
    )
    .map(({ view, pinned }) => ({ ...view, pinned }));
}

const bestOf = (views: { best: number }[]) => views.reduce((m, v) => Math.max(m, v.best), 0);

/** Your own streak for `GET /v1/me/streaks` (trophy room design §1), raising the kept longest pair streak. */
export async function myOwn(env: Env, me: string, now: number, pairs: { best: number }[]): Promise<OwnStreak | null> {
  return (await player(env, me).ownStreak(now, bestOf(pairs)))?.own ?? null;
}

/** `GET /v1/me/trophies` (trophy room design §3, §5): null for a player that doesn't exist. */
export async function myTrophies(env: Env, me: string, now: number): Promise<Trophies | null> {
  const [connections, rows] = await Promise.all([myStreaks(env, me, now), player(env, me).pairList()]);
  const states = await Promise.all(rows.map((r) => pair(env, r.pairId).exportState().catch(() => null)));
  const pairs = states.filter((s): s is PairState => s !== null);
  // Each is a copy: bringing it up to now here changes nothing stored.
  for (const s of pairs) advance(s, now);
  const own = await player(env, me).ownStreak(now, bestOf(pairs.map((s) => s.streak)));
  if (!own) return null;
  return trophies({ me, own: own.own, pairBest: own.pairBest, pairs, connections });
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

/** The streaks `me` left and can still undo, with the partner's current name and cat (§14's ghosted cat). */
export async function myLeft(env: Env, me: string): Promise<{ pair: string; partner: { name: string; cat: number } }[]> {
  const rows = await player(env, me).leftHandles();
  const listed = await Promise.all(
    rows.map(async (r) => {
      const p = await player(env, r.partnerId).streakProfile();
      return p ? { pair: r.pairId, partner: { name: p.name, cat: p.cat } } : null;
    }),
  );
  return listed.filter((l) => l !== null);
}

/**
 * The ghosted cat's plus: only the leaver can undo a leave. The tombstone
 * goes and a fresh pair at 0 starts at once (or at the next shared turns,
 * if the partner can't pair now). False when `pairId` isn't a leave of `me`'s.
 */
export async function rejoinPair(env: Env, me: string, pairId: string, now: number): Promise<boolean> {
  const partner = await player(env, me).rejoin(pairId);
  if (partner === null) return false;
  await ensurePair(env, me, partner, {}, now, false);
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
  await target.addLeftHandles(await player(env, from).leftHandles());
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

/** One person of a pair, as its pushes need them. */
export type PairTarget = { id: string; face: Face; partner: string; shared: string[]; streak: StreakBlock };

/**
 * What a pair tells its people (§12.1, §11.2): nap, win-back and milestone
 * pushes to both (a milestone skips whoever is looking at the table), the
 * pause to the other person, then widget reloads.
 */
/** What else happened with a save: who's looking at the table, a pause, whose widgets to reload. */
export type PairNotice = { awake?: string[]; paused?: { by: string; days: number }; widgets?: string[] };

export async function notifyPair(
  env: Env,
  n: PairNotice & { pair: string; events: PairEvent[]; targets: PairTarget[] },
  now: number,
): Promise<void> {
  const jobs: Promise<unknown>[] = [];
  const title = (t: PairTarget) => ({ shared: t.shared, partner: t.partner });
  for (const e of n.events) {
    for (const t of n.targets) {
      if (e.kind === "milestone" && n.awake?.includes(t.id)) continue;
      const o = statusPush({ kind: e.kind, pair: n.pair, title: t.partner, count: e.count, streak: t.streak });
      jobs.push(player(env, t.id).status(o, now, title(t)));
    }
  }
  const pauser = n.targets.find((t) => t.id === n.paused?.by);
  const other = n.targets.find((t) => t.id !== n.paused?.by);
  if (n.paused && pauser && other) {
    const o = statusPush({ kind: "paused", pair: n.pair, title: other.partner, count: n.paused.days, who: pauser.face, streak: other.streak });
    jobs.push(player(env, other.id).status(o, now, title(other)));
  }
  await Promise.allSettled(jobs);
  // After the alerts: a device that just got one already reloaded its widgets.
  await Promise.allSettled((n.widgets ?? []).map((id) => pokeWidgets(env, id, now)));
}
