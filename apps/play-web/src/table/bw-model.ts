/**
 * What the Birdwatch table says, worked out from the room: pure, so it is tested without a page.
 * The rules stay on the server (it sends `playable`, `bidRange` and `partnerChoices`); this only
 * reads the deck's data to sort, name and score cards on show.
 */
import { isBird, rankOf, suitOf, SUITS, type CardId, type Suit } from "@pounce/play-api/birdwatch/cards";
import { teamsFor } from "@pounce/play-api/birdwatch/engine";
import { counterOf, powerOf, RULE_SETS, type RuleSetId } from "@pounce/play-api/birdwatch/rules";

import { playing, seatName, type SeatInfo } from "./seat-names";

import type { BirdView } from "@pounce/play-api/birdwatch/view";
import type { RoomView } from "@pounce/play-api/protocol";

export { SUITS, type CardId, type Suit, type RuleSetId };

/** Each rule set's name and its one line under the lobby's pill (design §5.1). */
export const RULE_COPY: Record<RuleSetId, { name: string; line: string }> = {
  official: { name: "Official", line: "1s out, Bird wild." },
  tucker: { name: "Tucker", line: "1s high, worth 15." },
  friesen: { name: "Friesen", line: "1s high, Bird follows suit." },
};

export const RULES_ORDER: readonly RuleSetId[] = ["official", "tucker", "friesen"];

export const SUIT_WORD: Record<Suit, string> = { fish: "fish", mouse: "mouse", feather: "feather", bell: "bell" };

/** Ribbon colours, one per side: gold, teal, pink. Not the seats' ring colours, so a ribbon reads as a team. */
export const RIBBONS = ["#FFC21A", "#00E0C6", "#FF5CA8"] as const;

export const rulesOf = (v: Pick<BirdView, "rules">): RuleSetId => v.rules;

/** A card's points under `rules`. */
export const pointsOf = (id: CardId, rules: RuleSetId): number => counterOf(RULE_SETS[rules], id);

export type CardFacts = { bird: boolean; suit: Suit | null; rank: number | null; points: number };

export function cardFacts(id: CardId, rules: RuleSetId): CardFacts {
  if (isBird(id)) return { bird: true, suit: null, rank: null, points: pointsOf(id, rules) };
  return { bird: false, suit: suitOf(id), rank: rankOf(id), points: pointsOf(id, rules) };
}

/** What a screen reader hears: "10, fish, 10 points", "7, mouse", "Bird, 20 points, top trump". */
export function cardLabel(id: CardId, rules: RuleSetId): string {
  const f = cardFacts(id, rules);
  if (f.bird) return `Bird, ${f.points} points, top trump`;
  return `${f.rank}, ${SUIT_WORD[f.suit!]}${f.points ? `, ${f.points} points` : ""}`;
}

/** Suits in hand order: the printed order, with trump moved to the right once it is named. */
export function suitOrder(trump: Suit | null): Suit[] {
  return trump ? [...SUITS.filter((s) => s !== trump), trump] : [...SUITS];
}

/**
 * A hand as it is held (design §5.2): grouped by suit, trump on the right once named, low to
 * high within a suit by the rule set's order (a 1 above the 14 in Tucker and Friesen), and the
 * Bird, the top trump, last of all.
 */
export function sortHand(cards: readonly CardId[], trump: Suit | null, rules: RuleSetId): CardId[] {
  const order = suitOrder(trump);
  const set = RULE_SETS[rules];
  const key = (id: CardId): number => (isBird(id) ? 1e6 : order.indexOf(suitOf(id)) * 100 + powerOf(set, id));
  return [...cards].sort((a, b) => key(a) - key(b));
}

/** The suit worth naming trump: the one held most, ties broken by its higher cards. Null with no suited card. */
export function suggestTrump(hand: readonly CardId[], rules: RuleSetId): Suit | null {
  const set = RULE_SETS[rules];
  let best: Suit | null = null;
  let bestScore = -1;
  for (const suit of SUITS) {
    const cards = hand.filter((c) => !isBird(c) && suitOf(c) === suit);
    if (cards.length === 0) continue;
    const score = cards.length * 1000 + cards.reduce((n, c) => n + powerOf(set, c), 0);
    if (score > bestScore) {
      best = suit;
      bestScore = score;
    }
  }
  return best;
}

/** The partner picker's rows (design §5.3): one per suit, trump's first and led by the Bird, high to low. */
export function partnerRows(choices: readonly CardId[], trump: Suit | null, rules: RuleSetId): { suit: Suit; cards: CardId[] }[] {
  const set = RULE_SETS[rules];
  const order = trump ? [trump, ...SUITS.filter((s) => s !== trump)] : [...SUITS];
  return order
    .map((suit) => {
      const cards = choices.filter((c) => !isBird(c) && suitOf(c) === suit).sort((a, b) => powerOf(set, b) - powerOf(set, a));
      return { suit, cards: suit === order[0] && choices.some(isBird) ? [choices.find(isBird)!, ...cards] : cards };
    })
    .filter((row) => row.cards.length > 0);
}

/** The side a seat plays for this hand: its team, or with 5 players the bid winner's side once its partner is known. */
export function sideOf(v: Pick<BirdView, "teams">, seat: number): number {
  return v.teams.findIndex((t) => t.includes(seat));
}

export type Side = {
  team: number;
  seats: number[];
  score: number;
  /** Points its seats took this hand. */
  taken: number;
  /** The side holding the hand's bid (bid winner, and partner once known). */
  bidding: boolean;
  ribbon: string | null;
};

const biddingOver = (v: BirdView): boolean => v.phase !== "bidding" && v.high !== null;

/** The bid winner's side this hand: their team, or with 5 players the bid winner and the partner once known. */
export function biddingSeats(v: BirdView): number[] {
  if (!biddingOver(v)) return [];
  const bidder = v.high!.seat;
  if (v.seats === 5) return v.partner !== null && v.partner !== bidder ? [bidder, v.partner] : [bidder];
  return v.teams[sideOf(v, bidder)] ?? [bidder];
}

/** One score chip per side (design §5.2): its score and what it has taken this hand. */
export function sides(v: BirdView): Side[] {
  const bidders = biddingSeats(v);
  return v.teams.map((seats, team) => ({
    team,
    seats,
    score: v.scores[team] ?? 0,
    taken: seats.reduce((n, s) => n + (v.points[s] ?? 0), 0),
    bidding: seats.some((s) => bidders.includes(s)),
    ribbon: ribbonOf(v, seats[0]!),
  }));
}

/**
 * A seat's ribbon: its team's colour with 4 or 6 players. With 5, only the bid winner's side
 * wears one (gold), and the partner only once the called card is played: never before (§4.6).
 */
export function ribbonOf(v: BirdView, seat: number): string | null {
  if (v.seats !== 5) return RIBBONS[sideOf(v, seat) % RIBBONS.length] ?? null;
  return biddingSeats(v).includes(seat) ? RIBBONS[0] : null;
}

/** The lobby's ribbons: teams by seat order among the seated (the room compacts seats at start). */
export function lobbyRibbons(room: RoomView): Map<number, string> {
  const seated = room.seats.flatMap((s, i) => (playing(s) ? [i] : []));
  const out = new Map<number, string>();
  if (seated.length !== 4 && seated.length !== 6) return out;
  teamsFor(seated.length).forEach((team, t) => {
    for (const k of team) out.set(seated[k]!, RIBBONS[t % RIBBONS.length]!);
  });
  return out;
}

/** "Alice and Ben"; two House Cats are "House Cats". */
export function sideName(room: RoomView, seats: readonly number[]): string {
  const names = seats.map((s) => seatName(room.seats[s]));
  if (names.length > 1 && names.every((n) => n === "House Cat")) return "House Cats";
  return names.join(" and ");
}

/** What this device does now. "wait": someone else's move, or this device holds no seat. */
export type BwStep = "bid" | "nest" | "trump" | "partner" | "play" | "wait" | "between" | "over";

export function stepFor(v: BirdView, seat: number | null): BwStep {
  if (v.status === "over" || v.phase === "over") return "over";
  if (v.phase === "between") return "between";
  if (seat === null || v.turn !== seat) return "wait";
  return v.phase === "bidding" ? "bid" : v.phase;
}

/**
 * Whose hand is on show on this device (PassAndPlay.swift): its one seat, or on a device holding
 * several, the seat on the move once its holder has taken the device. The curtain rises for a
 * different seat than the last one shown, and at every new hand.
 */
export function seatOnShow(room: RoomView, revealed: { seat: number; hand: number } | null) {
  const v = room.birdwatch!;
  const mine = room.seats.flatMap((s, i) => (s.yours && s.kind === "human" ? [i] : []));
  const shared = mine.length > 1;
  const live = v.status === "playing" && v.phase !== "between";
  const acting = !shared ? (mine[0] ?? null) : live && v.turn !== null && mine.includes(v.turn) ? v.turn : null;
  const showHand = acting !== null && (!shared || (revealed?.seat === acting && revealed.hand === v.hand));
  return {
    mine,
    seat: acting,
    showHand,
    curtainSeat: shared && acting !== null && !showHand ? acting : null,
    myTurn: acting !== null && v.turn === acting && live,
  };
}

/** "Partner" on this hand: the seat on show holds the called card (§4.6), behind the curtain on a shared device. */
export const isSecretPartner = (v: BirdView, seat: number | null, showHand: boolean): boolean => showHand && seat !== null && v.youArePartner === seat && v.partner === null;

export type HandSummary = {
  hand: number;
  bidder: number;
  bid: number;
  made: boolean;
  trump: Suit;
  rows: { team: number; name: string; change: number; total: number; bidding: boolean; ribbon: string | null }[];
};

/** The between-hands summary (§5.4): the bid, made or missed, each side's points and totals. */
export function lastHand(room: RoomView): HandSummary | null {
  const v = room.birdwatch;
  const r = v?.history.at(-1);
  if (!v || !r) return null;
  const bidders = v.seats === 5 ? [r.bidder, ...(r.partner !== null ? [r.partner] : [])] : (v.teams[sideOf(v, r.bidder)] ?? []);
  return {
    hand: r.hand,
    bidder: r.bidder,
    bid: r.bid,
    made: r.made,
    trump: r.trump,
    rows: v.teams.map((seats, team) => ({
      team,
      name: sideName(room, seats),
      change: r.change[team] ?? 0,
      total: r.totals[team] ?? 0,
      bidding: seats.some((s) => bidders.includes(s)),
      ribbon: v.seats === 5 ? (seats.some((s) => bidders.includes(s)) ? RIBBONS[0] : null) : (RIBBONS[team % RIBBONS.length] ?? null),
    })),
  };
}

export const signed = (n: number): string => (n > 0 ? `+${n}` : String(n));

export type SideStanding = { team: number; seats: number[]; name: string; score: number; won: boolean; left: boolean };

/** Every side, winners first, then by score: game over's list and the score sheet's. */
export function bwStandings(room: RoomView): SideStanding[] {
  const v = room.birdwatch;
  if (!v) return [];
  const rows = v.teams.map((seats, team) => ({
    team,
    seats,
    name: sideName(room, seats),
    score: v.scores[team] ?? 0,
    won: seats.some((s) => v.winners.includes(s)),
    left: seats.every((s) => (room.seats[s] as SeatInfo | undefined)?.left === true),
  }));
  return rows.sort((a, b) => Number(b.won) - Number(a.won) || b.score - a.score || a.team - b.team);
}

/** Game over's title: "Alice and Ben win", "Alice wins", or "Game over" when everyone left. */
export function bwOverTitle(room: RoomView): string {
  const v = room.birdwatch;
  const winners = v?.winners ?? [];
  if (winners.length === 0) return "Game over";
  const won = bwStandings(room).filter((s) => s.won);
  const seats = won.flatMap((s) => s.seats);
  if (seats.length === 1) return `${seatName(room.seats[seats[0]!])} wins`;
  return `${won.map((s) => s.name).join(" and ")} win`;
}

/** The sign over a seat's cat: its bid, "Pass", "Missed" after a missed hand, or nothing. */
export function signOf(v: BirdView, seat: number): { text: string; kind: "bid" | "high" | "pass" | "missed" } | null {
  if (v.phase === "between" || v.phase === "over") {
    const r = v.history.at(-1);
    if (r && r.bidder === seat) return r.made ? { text: String(r.bid), kind: "high" } : { text: "Missed", kind: "missed" };
    return null;
  }
  if (v.phase !== "bidding") return v.high?.seat === seat ? { text: String(v.high.amount), kind: "high" } : null;
  if (v.passed[seat]) return { text: "Pass", kind: "pass" };
  const bid = v.bids[seat];
  if (bid === null || bid === undefined) return null;
  return { text: String(bid), kind: v.high?.seat === seat ? "high" : "bid" };
}

/** Seats around the window, in play order starting left of `me` (or of seat 0 for a TV or a spectator). */
export function othersInOrder(v: Pick<BirdView, "seats">, me: number | null): number[] {
  const n = v.seats;
  const from = me ?? -1;
  const out: number[] = [];
  for (let k = 1; k <= n; k++) {
    const s = (((from + k) % n) + n) % n;
    if (s !== me) out.push(s);
  }
  return out;
}
