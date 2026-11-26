import { BIRD, cardFor, isBird, rankOf, SUITS, type CardId } from "./cards";

/** The three ways a table plays (design §4.1). A fourth is one more entry in `RULE_SETS`. */
export type RuleSetId = "official" | "tucker" | "friesen";

export const RULE_SET_IDS: readonly RuleSetId[] = ["official", "tucker", "friesen"];

export const isRuleSetId = (v: unknown): v is RuleSetId => typeof v === "string" && (RULE_SET_IDS as readonly string[]).includes(v);

/** The player counts Birdwatch is played at. */
export type SeatCount = 4 | 5 | 6;

/** One player count's deal: the ranks in the deck (in every suit, plus the Bird), each hand, and the nest. */
export type Deal = { ranks: readonly number[]; hand: number; nest: number };

export type RuleSet = {
  id: RuleSetId;
  deals: Readonly<Record<SeatCount, Deal>>;
  /** Ranks from lowest to highest. */
  order: readonly number[];
  /** What each rank is worth; a rank not listed is worth nothing. */
  counters: Readonly<Partial<Record<number, number>>>;
  /** What the Bird is worth. */
  bird: number;
  /** The Bird may be played at any time (official, tucker), or only as a trump (friesen). */
  birdWild: boolean;
  minBid: number;
  maxBid: number;
  /** Every bid is a multiple of this, and raises the high bid by at least this. */
  bidStep: number;
  /** A game ends after the hand in which a side reaches this. */
  target: number;
  /** The counters in the deck: what every hand is worth, all sides together. */
  total: number;
};

const range = (from: number, to: number): number[] => Array.from({ length: to - from + 1 }, (_, i) => from + i);

const COUNTERS = { 5: 5, 10: 10, 14: 10 };
const LOW_OUT = range(5, 14);
const LOW_IN = range(2, 14);

const official: RuleSet = {
  id: "official",
  deals: {
    4: { ranks: LOW_OUT, hand: 9, nest: 5 },
    5: { ranks: LOW_IN, hand: 10, nest: 3 },
    6: { ranks: LOW_IN, hand: 8, nest: 5 },
  },
  order: LOW_IN,
  counters: COUNTERS,
  bird: 20,
  birdWild: true,
  minBid: 70,
  maxBid: 120,
  bidStep: 5,
  target: 300,
  total: 120,
};

const tucker: RuleSet = {
  id: "tucker",
  deals: {
    4: { ranks: [1, ...LOW_OUT], hand: 10, nest: 5 },
    5: { ranks: range(1, 14), hand: 10, nest: 7 },
    6: { ranks: range(1, 14), hand: 9, nest: 3 },
  },
  order: [...LOW_IN, 1],
  counters: { ...COUNTERS, 1: 15 },
  bird: 20,
  birdWild: true,
  minBid: 70,
  maxBid: 180,
  bidStep: 5,
  target: 500,
  total: 180,
};

/** Tucker with one change: the Bird is not wild (design §4.1). */
const friesen: RuleSet = { ...tucker, id: "friesen", birdWild: false };

export const RULE_SETS: Readonly<Record<RuleSetId, RuleSet>> = { official, tucker, friesen };

export const isSeatCount = (n: number): n is SeatCount => n === 4 || n === 5 || n === 6;

/** The deal for `seats` players. Throws for a player count Birdwatch isn't played at. */
export function dealFor(rules: RuleSet, seats: number): Deal {
  if (!isSeatCount(seats)) throw new RangeError(`seats must be 4-6: ${seats}`);
  return rules.deals[seats];
}

/** The deck for `seats` players, in id order. */
export function deckFor(rules: RuleSet, seats: number): CardId[] {
  const { ranks } = dealFor(rules, seats);
  return [...SUITS.flatMap((suit) => ranks.map((rank) => cardFor(suit, rank))).sort((a, b) => a - b), BIRD];
}

/** A card's counter value under `rules`. */
export const counterOf = (rules: RuleSet, id: CardId): number => (isBird(id) ? rules.bird : (rules.counters[rankOf(id)] ?? 0));

/** How a suited card ranks within its suit under `rules`: higher beats lower. */
export const powerOf = (rules: RuleSet, id: CardId): number => rules.order.indexOf(rankOf(id));
