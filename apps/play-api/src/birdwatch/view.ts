import { actor, minBid, playable, rulesOf, type BirdEvent, type BirdPhase, type BirdState, type HandResult, type TrickCard } from "./engine";
import { dealFor, deckFor, type RuleSetId } from "./rules";

import type { CardId, Suit } from "./cards";
import type { Seat } from "../rules/engine";

/** What one device may see (design §7). Every array is a fresh copy, never a reference into the state. */
export type BirdView = {
  rules: RuleSetId;
  seats: number;
  target: number;
  minBid: number;
  maxBid: number;
  /** How many cards the nest holds, and so how many the bid winner puts back. */
  nestSize: number;
  teams: Seat[][];
  /** Per team. */
  scores: number[];
  history: HandResult[];
  status: BirdState["status"];
  phase: BirdPhase;
  hand: number;
  dealer: Seat;
  /** Whose move it is; null between hands and once over. */
  turn: Seat | null;
  handCounts: number[];
  /** Only the seats this device controls. */
  hands: Record<Seat, CardId[]>;
  /** Per seat: its last bid this hand. */
  bids: (number | null)[];
  passed: boolean[];
  /** The high bid; after bidding, the hand's bid and who holds it. */
  high: { seat: Seat; amount: number } | null;
  trump: Suit | null;
  /** 5 players: the card the bid winner called. */
  called: CardId | null;
  /** 5 players: the partner, once the called card has been played (or the hand is over). */
  partner: Seat | null;
  trick: TrickCard[];
  leader: Seat | null;
  lastTrick: { cards: TrickCard[]; winner: Seat } | null;
  /** Every card played this hand, in order. */
  played: CardId[];
  /** Per seat, this hand: counters won, and tricks won. */
  points: number[];
  tricks: number[];
  winners: Seat[];
  /** The cards the seat on the move may play, when this device controls it. */
  playable?: CardId[];
  /** The bids the seat on the move may make (or pass), when this device controls it. */
  bidRange?: { min: number; max: number; step: number };
  /** The nest the bid winner just took, while they choose what to put back: their device only. */
  fromNest?: CardId[];
  /** What the bid winner put back: their device only, until the hand is over, then everyone. */
  putBack?: CardId[];
  /** 5 players: the cards the bid winner may call, when this device controls them. */
  partnerChoices?: CardId[];
  /** 5 players: the seat this device controls that holds the called card. */
  youArePartner?: Seat;
  endReason?: BirdState["endReason"];
};

/** The hand being shown has been scored: its put-back cards and partner are now public. */
const scored = (s: BirdState): boolean => s.history.length >= s.hand;

/**
 * Builds a device's view. Another seat's hand, the nest, the put-back cards and who holds the
 * called card stay on the server, except as the fields above allow.
 */
export function viewFor(s: BirdState, controlled: readonly Seat[]): BirdView {
  const rules = rulesOf(s);
  const mine = (seat: Seat | null): seat is Seat => seat !== null && controlled.includes(seat);
  const turn = actor(s);
  const bidWinner = s.phase === "bidding" ? null : (s.high?.seat ?? null);
  const hands: Record<Seat, CardId[]> = {};
  for (const seat of controlled) {
    const hand = Number.isInteger(seat) ? s.hands[seat] : undefined;
    if (hand) hands[seat] = [...hand];
  }
  const afterNest = s.phase === "trump" || s.phase === "partner" || s.phase === "play";
  const putBack = scored(s) || (afterNest && mine(bidWinner)) ? { putBack: [...s.putBack] } : {};
  return {
    rules: s.rules,
    seats: s.seats,
    target: rules.target,
    minBid: rules.minBid,
    maxBid: rules.maxBid,
    nestSize: dealFor(rules, s.seats).nest,
    teams: s.teams.map((t) => [...t]),
    scores: [...s.scores],
    history: structuredClone(s.history),
    status: s.status,
    phase: s.phase,
    hand: s.hand,
    dealer: s.dealer,
    turn,
    handCounts: s.hands.map((h) => h.length),
    hands,
    bids: [...s.bids],
    passed: [...s.passed],
    high: s.high ? { ...s.high } : null,
    trump: s.trump,
    called: s.called,
    partner: s.partner,
    trick: s.trick.map((t) => ({ ...t })),
    leader: s.leader,
    lastTrick: s.lastTrick ? { cards: s.lastTrick.cards.map((t) => ({ ...t })), winner: s.lastTrick.winner } : null,
    played: [...s.played],
    points: [...s.points],
    tricks: [...s.tricks],
    winners: [...s.winners],
    ...(s.phase === "play" && mine(turn) ? { playable: playable(s, turn) } : {}),
    ...(s.phase === "bidding" && mine(turn) ? { bidRange: { min: minBid(s), max: rules.maxBid, step: rules.bidStep } } : {}),
    ...(s.phase === "nest" && mine(bidWinner) ? { fromNest: [...s.fromNest] } : {}),
    ...putBack,
    ...(s.phase === "partner" && mine(turn)
      ? { partnerChoices: deckFor(rules, s.seats).filter((c) => !(s.hands[turn] as CardId[]).includes(c)) }
      : {}),
    ...(mine(s.holder) ? { youArePartner: s.holder } : {}),
    ...(s.endReason === undefined ? {} : { endReason: s.endReason }),
  };
}

/**
 * A copy of `event` safe for a device controlling `controlled`: a deal shows only its own hands,
 * and the nest and the put-back cards only to the bid winner's device.
 */
export function eventFor(event: BirdEvent, controlled: readonly Seat[]): BirdEvent {
  const copy = structuredClone(event);
  if (copy.kind === "dealt") {
    copy.hands = Object.fromEntries(Object.entries(copy.hands).filter(([seat]) => controlled.includes(Number(seat))));
  } else if ((copy.kind === "nest" || copy.kind === "putBack") && !controlled.includes(copy.seat)) {
    delete copy.cards;
  }
  return copy;
}
