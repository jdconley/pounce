import { BIRD, isBird, SUITS, suitIn, suitOf, type CardId, type Suit } from "../birdwatch/cards";
import { trickWinner, type BirdAction } from "../birdwatch/engine";
import { counterOf, powerOf, RULE_SETS, type RuleSet } from "../birdwatch/rules";

import type { BirdView } from "../birdwatch/view";
import type { Seat } from "../rules/engine";
import type { Rng } from "../rules/rng";

/**
 * House Cat for Birdwatch (design §6): one action per call, for the seat on the move. It reads
 * only that seat's own view, so it can't cheat, and every action it returns is legal. `rng` only
 * nudges how far it bids. Simple greedy rules throughout, well under a millisecond a move.
 */
export function chooseAction(view: BirdView, seat: Seat, rng: Rng): BirdAction {
  const rules = RULE_SETS[view.rules];
  const hand = view.hands[seat] ?? [];
  switch (view.phase) {
    case "bidding":
      return bid(view, seat, hand, rules, rng);
    case "nest":
      return { type: "nest", discard: putBack(hand, view.nestSize, rules) };
    case "trump":
      return { type: "trump", suit: bestSuit(hand, rules) };
    case "partner":
      return { type: "partner", card: callPartner(view, rules) };
    case "play":
      return { type: "play", card: play(view, seat, hand, rules) };
    default:
      return { type: "nextHand" };
  }
}

const bySuit = (hand: readonly CardId[], suit: Suit) => hand.filter((c) => !isBird(c) && suitOf(c) === suit);

/** The suit it holds most of, ties broken by the higher cards. */
export function bestSuit(hand: readonly CardId[], rules: RuleSet): Suit {
  const strength = (suit: Suit) => {
    const cards = bySuit(hand, suit);
    return cards.length * 100 + cards.reduce((sum, c) => sum + powerOf(rules, c), 0);
  };
  return [...SUITS].sort((a, b) => strength(b) - strength(a))[0] as Suit;
}

/** The top rank of a suit under `rules`: 1 where it is in, else 14. */
const topRank = (rules: RuleSet) => rules.order[rules.order.length - 1] as number;

/**
 * What the hand might take, in points (§6): trump length and high trump in its longest suit, the
 * Bird, top cards and long suits, scaled to the rule set's points a hand, plus a share of what a
 * partner usually brings (less with 5 players, where the partner is a gamble).
 */
export function estimate(hand: readonly CardId[], rules: RuleSet, seats: number): number {
  const trump = bestSuit(hand, rules);
  const top = topRank(rules);
  let value = 0;
  for (const c of hand) {
    if (isBird(c)) value += 18;
    else if (suitOf(c) === trump) value += 5 + (rules.order.indexOf((c % 14) + 1) >= rules.order.length - 3 ? 5 : 0);
    else if ((c % 14) + 1 === top) value += 10;
  }
  for (const suit of SUITS) value += Math.max(0, bySuit(hand, suit).length - 4) * 3;
  const share = ((seats === 5 ? 0.5 : 0.9) * rules.total) / seats;
  return Math.round((value * 1.2 * rules.total) / 120 + share);
}

function bid(view: BirdView, seat: Seat, hand: readonly CardId[], rules: RuleSet, rng: Rng): BirdAction {
  const range = view.bidRange;
  if (!range) return { type: "pass" };
  const mates = (view.teams.find((t) => t.includes(seat)) ?? []).filter((s) => s !== seat);
  // Never bid against its own side.
  if (view.high !== null && mates.includes(view.high.seat)) return { type: "pass" };
  const helped = mates.some((m) => view.bids[m] !== null) ? 10 : 0;
  const worth = Math.min(rules.maxBid, estimate(hand, rules, view.seats) + helped + Math.floor(rng() * 3) * 5 - 5);
  return range.min <= worth ? { type: "bid", amount: range.min } : { type: "pass" };
}

/**
 * The cards to put back: short off-suits first, and counters only when nothing else is left
 * (§6). It keeps the Bird, the suit it will name trump and its top cards.
 */
export function putBack(hand: readonly CardId[], count: number, rules: RuleSet): CardId[] {
  const trump = bestSuit(hand, rules);
  const keep = (c: CardId): number => {
    if (isBird(c)) return 10_000;
    if (suitOf(c) === trump) return 5_000 + powerOf(rules, c);
    if (counterOf(rules, c) > 0) return 1_000 + powerOf(rules, c);
    return bySuit(hand, suitOf(c)).length * 20 + powerOf(rules, c);
  };
  return [...hand].sort((a, b) => keep(a) - keep(b) || a - b).slice(0, count);
}

/** The highest trump it doesn't hold, else the highest off-suit top card; never a card it put back. */
function callPartner(view: BirdView, rules: RuleSet): CardId {
  const back = new Set(view.putBack ?? []);
  const choices = (view.partnerChoices ?? []).filter((c) => !back.has(c));
  const trump = view.trump as Suit;
  const trumps = choices.filter((c) => suitIn(c, trump) === trump).sort((a, b) => (isBird(b) ? 1 : 0) - (isBird(a) ? 1 : 0) || powerOf(rules, b) - powerOf(rules, a));
  const tops = choices.filter((c) => !isBird(c) && (c % 14) + 1 === topRank(rules));
  return trumps[0] ?? tops[0] ?? choices[0] ?? (view.partnerChoices as CardId[])[0] as CardId;
}

/** The seats it knows are on its own side this hand. */
function friendsOf(view: BirdView, seat: Seat): Seat[] {
  if (view.seats !== 5) return view.teams.find((t) => t.includes(seat)) ?? [seat];
  const bidder = view.high?.seat;
  if (seat === bidder) return view.partner === null ? [seat] : [seat, view.partner];
  if (view.youArePartner === seat && bidder !== undefined) return [seat, bidder];
  // Against the bid: everyone but the bid winner and a partner it knows of.
  return Array.from({ length: 5 }, (_, s) => s).filter((s) => s !== bidder && s !== view.partner && (view.partner !== null || s === seat));
}

/** How strongly a card holds: trump over everything else, the Bird over all. */
const rank = (c: CardId, trump: Suit, rules: RuleSet) => (isBird(c) ? 100 : (suitOf(c) === trump ? 50 : 0) + powerOf(rules, c));

function play(view: BirdView, seat: Seat, hand: readonly CardId[], rules: RuleSet): CardId {
  const options = view.playable ?? [...hand];
  const trump = view.trump as Suit;
  const low = [...options].sort((a, b) => counterOf(rules, a) - counterOf(rules, b) || rank(a, trump, rules) - rank(b, trump, rules));
  const friends = friendsOf(view, seat);
  const bidding = view.high !== null && friends.includes(view.high.seat);

  if (view.trick.length === 0) {
    // On the bidding side with the top trump left: lead it and draw the others' trumps.
    const topTrump = highestUnplayedTrump(view, trump, rules);
    if (bidding && topTrump !== null && options.includes(topTrump)) return topTrump;
    const offSuit = low.filter((c) => suitIn(c, trump) !== trump);
    return offSuit[0] ?? (low[0] as CardId);
  }

  const winner = trickWinner(view.trick, trump, rules);
  const points = view.trick.reduce((sum, t) => sum + counterOf(rules, t.card), 0);
  if (friends.includes(winner) && winner !== seat) {
    // A friend has it: feed them counters, but not a card that would take it from them.
    const safe = options.filter((c) => trickWinner([...view.trick, { seat, card: c }], trump, rules) === winner);
    const feed = [...safe].sort((a, b) => counterOf(rules, b) - counterOf(rules, a) || rank(a, trump, rules) - rank(b, trump, rules));
    if (feed[0] !== undefined && counterOf(rules, feed[0]) > 0 && !isBird(feed[0])) return feed[0];
    return safe.length > 0 ? (low.find((c) => safe.includes(c)) as CardId) : (low[0] as CardId);
  }
  const winners = options
    .filter((c) => trickWinner([...view.trick, { seat, card: c }], trump, rules) === seat)
    .sort((a, b) => rank(a, trump, rules) - rank(b, trump, rules));
  if (winners[0] !== undefined && (points > 0 || counterOf(rules, winners[0]) > 0)) return winners[0];
  return low[0] as CardId;
}

/** The best trump nobody has played yet (the Bird first), or null when every trump is out. */
function highestUnplayedTrump(view: BirdView, trump: Suit, rules: RuleSet): CardId | null {
  const out = new Set(view.played);
  if (!out.has(BIRD)) return BIRD;
  for (const r of [...rules.order].reverse()) {
    const c = SUITS.indexOf(trump) * 14 + r - 1;
    if (!out.has(c)) return c;
  }
  return null;
}
