import {
  BACKS,
  CONDO,
  condoStage,
  DEFAULT_BACK,
  DEFAULT_RUG,
  FULL_SET_BACK,
  isBigMilestone,
  nextMilestone,
  NORMAL_BACKS,
  RUGS,
  TOYS,
  type Rarity,
} from "./catalog";

import type { PairState, StreakView } from "./pair-core";
import type { OwnStreak } from "./personal";

/**
 * The trophy room's payload (trophy room design §3, §5): your own streak,
 * personal records, what you've earned across your pairs, the catalog with
 * where each item unlocks (D4) and your connections. Pure: the glue hands in
 * the pair states, already brought up to now.
 */

export type TrophyInput = {
  me: string;
  own: OwnStreak;
  /** The longest pair streak this player has seen, kept on the player so a left pair still counts. */
  pairBest: number;
  pairs: PairState[];
  connections: (StreakView & { pinned: boolean })[];
};

export type CatalogKind = "condo" | "back" | "rug" | "toy";

/** One thing to earn: `at` is the numeral on its ring, `progress` how far along (1 once earned). */
export type CatalogItem = { id: string; kind: CatalogKind; at: number; progress: number };

export type Trophies = {
  own: OwnStreak;
  records: { current: number; best: number; longestPair: number; totalDays: number; perfectWeeks: number };
  earned: { toys: string[]; backs: string[]; rugs: string[]; condoStage: number };
  catalog: CatalogItem[];
  connections: (StreakView & { pinned: boolean })[];
};

/** Kept days within which each rarity is sure to drop (§9.3). */
const GUARANTEE: Record<Rarity, number> = { common: 1, shiny: 7, golden: 30 };
const LAST_LISTED = 365;
/** A first milestone of the small tier: a fresh start's first gift. */
const FIRST_SMALL = 3;

/** The next milestone above `n` whose gift comes from the big tier (or the small one); null when the tier has none left. */
function nextOfTier(n: number, big: boolean): number | null {
  let m = nextMilestone(n);
  while (isBigMilestone(m) !== big) {
    if (m > LAST_LISTED) return null;
    m = nextMilestone(m);
  }
  return m;
}

/** What this person has from one pair: its items less the gifts they haven't opened yet. */
function mineFrom(s: PairState, me: string): string[] {
  const wrapped = new Set(s.gifts.filter((g) => !g.openedBy.includes(me)).map((g) => g.item));
  return s.owned.filter((id) => !wrapped.has(id));
}

const ratio = (measure: number, at: number) => Math.min(1, measure / at);
const max = (xs: number[]) => xs.reduce((a, b) => Math.max(a, b), 0);

export function trophies(t: TrophyInput): Trophies {
  const items = new Set(t.pairs.flatMap((s) => mineFrom(s, t.me)));
  const stage = max(t.pairs.map((s) => condoStage(s.streak.lifetimeKept)));
  const earned = {
    toys: TOYS.map((x) => x.id).filter((id) => items.has(id)),
    backs: BACKS.filter((id) => id !== DEFAULT_BACK && items.has(id)),
    rugs: RUGS.filter((id) => id !== DEFAULT_RUG && items.has(id)),
    condoStage: stage,
  };
  const days = max(t.pairs.map((s) => s.streak.lifetimeKept));
  const count = max(t.pairs.map((s) => s.streak.count));
  const toyCount = max(t.pairs.map((s) => s.owned.filter((id) => id.startsWith("toy-")).length));
  const pity = { shiny: max(t.pairs.map((s) => s.pity.shiny)), golden: max(t.pairs.map((s) => s.pity.golden)) };

  const gift = (id: string, kind: CatalogKind, big: boolean): CatalogItem => {
    const at = nextOfTier(count, big);
    const progress = items.has(id) ? 1 : at === null ? 0 : ratio(count, at);
    return { id, kind, at: at ?? FIRST_SMALL, progress };
  };
  const back = (id: string): CatalogItem => {
    if (id === FULL_SET_BACK) return { id, kind: "back", at: TOYS.length, progress: items.has(id) ? 1 : ratio(toyCount, TOYS.length) };
    return gift(id, "back", !NORMAL_BACKS.includes(id));
  };
  const toy = ({ id, rarity }: { id: string; rarity: Rarity }): CatalogItem => {
    const at = GUARANTEE[rarity];
    const measure = rarity === "common" ? 0 : pity[rarity];
    return { id, kind: "toy", at, progress: items.has(id) ? 1 : ratio(measure, at) };
  };

  const catalog: CatalogItem[] = [
    ...CONDO.map((at, i) => ({ id: `condo-${i + 1}`, kind: "condo" as const, at, progress: i < stage ? 1 : ratio(days, at) })),
    ...BACKS.filter((id) => id !== DEFAULT_BACK).map(back),
    ...RUGS.filter((id) => id !== DEFAULT_RUG).map((id) => gift(id, "rug", true)),
    ...TOYS.map(toy),
  ];

  return {
    own: t.own,
    records: {
      current: t.own.count,
      best: t.own.best,
      longestPair: Math.max(t.pairBest, max(t.pairs.map((s) => s.streak.best))),
      totalDays: t.own.lifetimeKept,
      perfectWeeks: t.own.perfectWeeks,
    },
    earned,
    catalog,
    connections: t.connections,
  };
}
