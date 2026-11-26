import { createRng, shuffle, type Seed } from "../rules/rng";

import { BIRD, isBird, suitIn, suitOf, type CardId, type Suit } from "./cards";
import { counterOf, dealFor, deckFor, isRuleSetId, powerOf, RULE_SETS, type RuleSet, type RuleSetId } from "./rules";

import type { Seat } from "../rules/engine";

/** What a table chooses in the lobby. Every Birdwatch table has a rule set. */
export type BirdOptions = { rules: RuleSetId };

export const DEFAULT_OPTIONS: BirdOptions = { rules: "official" };

/**
 * Where a game stands. Inside a hand: bidding, the bid winner's nest, their trump and (5 players
 * only) their partner call, then play. `between`: the hand's summary, until the room deals the next.
 */
export type BirdPhase = "bidding" | "nest" | "trump" | "partner" | "play" | "between" | "over";

/** The phases in which one seat is to act. */
const ACTING: ReadonlySet<BirdPhase> = new Set(["bidding", "nest", "trump", "partner", "play"]);

export type TrickCard = { seat: Seat; card: CardId };

/** One line of the score sheet. Everything in it is public once the hand is over. */
export type HandResult = {
  hand: number;
  bidder: Seat;
  bid: number;
  /** 5 players only: the bid winner's partner, or null when they played alone (and always null with 4 or 6). */
  partner: Seat | null;
  trump: Suit;
  made: boolean;
  /** Per team: the counters its side took this hand, the put-back cards included. */
  taken: number[];
  /** Per team: what the hand did to its score. */
  change: number[];
  /** Per team: its score after the hand. */
  totals: number[];
};

export type EndReason = "target" | "left";

export type BirdState = {
  rules: RuleSetId;
  seats: number;
  /** The deal's random stream (Cat Tower's pattern): server-only. */
  seed: Seed;
  rngCalls: number;
  /** The sides by seat: across the table with 4 or 6 players, one each with 5. */
  teams: Seat[][];
  /** Per team. */
  scores: number[];
  history: HandResult[];
  /** 1-based. */
  hand: number;
  dealer: Seat;
  phase: BirdPhase;
  /** The seat to act, in an acting phase. */
  turn: Seat;
  /** Actions applied so far, for telling one turn from the next. */
  moves: number;
  /** Each seat's cards, in id order. Server-only except to the seat itself. */
  hands: CardId[][];
  /** The face-down nest, until the bid winner takes it. Server-only. */
  nest: CardId[];
  /** What the bid winner took from the nest, during the nest step: theirs only. */
  fromNest: CardId[];
  /** What the bid winner put back: theirs only until the hand ends. */
  putBack: CardId[];
  /** Per seat: its last bid this hand. */
  bids: (number | null)[];
  passed: boolean[];
  /** The high bid; once bidding is over, the hand's bid. */
  high: { seat: Seat; amount: number } | null;
  trump: Suit | null;
  /** 5 players: the card the bid winner called, public once called. */
  called: CardId | null;
  /** Who holds the called card (null: it was put back). Server-only: never in a view. */
  holder: Seat | null;
  /** The partner, once the called card has been played. */
  partner: Seat | null;
  trick: TrickCard[];
  leader: Seat | null;
  lastTrick: { cards: TrickCard[]; winner: Seat } | null;
  /** Every card played this hand, in order. */
  played: CardId[];
  /** Per seat, this hand: the counters in the tricks it won, and how many it won. */
  points: number[];
  tricks: number[];
  status: "playing" | "over";
  winners: Seat[];
  endReason?: EndReason;
};

export type BirdAction =
  | { type: "bid"; amount: number }
  | { type: "pass" }
  /** The bid winner puts back as many cards as the nest held. */
  | { type: "nest"; discard: CardId[] }
  | { type: "trump"; suit: Suit }
  /** 5 players: the card whose holder is the bid winner's partner this hand. */
  | { type: "partner"; card: CardId }
  | { type: "play"; card: CardId }
  /** Deal the next hand, from `between`. The room sends it after a pause. */
  | { type: "nextHand" }
  /** Only the room sends it, once no person is left at the table: the game ends. */
  | { type: "forfeit" };

export type BirdEvent =
  /** `hands`: every seat's here; `eventFor` keeps only the seats a device controls. */
  | { kind: "dealt"; hand: number; dealer: Seat; handCounts: number[]; hands: Record<Seat, CardId[]> }
  | { kind: "bid"; seat: Seat; amount: number }
  | { kind: "passed"; seat: Seat }
  | { kind: "bidWon"; seat: Seat; amount: number }
  /** The bid winner takes the nest. `cards`: the bid winner's device only. */
  | { kind: "nest"; seat: Seat; cards?: CardId[] }
  /** The bid winner put `count` cards back. `cards`: the bid winner's device only. */
  | { kind: "putBack"; seat: Seat; count: number; cards?: CardId[] }
  | { kind: "trump"; seat: Seat; suit: Suit }
  | { kind: "called"; seat: Seat; card: CardId }
  | { kind: "turn"; seat: Seat }
  | { kind: "played"; seat: Seat; card: CardId }
  /** The called card was just played: `seat` is the bid winner's partner. */
  | { kind: "partner"; seat: Seat }
  | { kind: "trick"; winner: Seat; cards: TrickCard[]; points: number }
  | { kind: "handOver"; result: HandResult; putBack: CardId[] }
  | { kind: "gameOver"; winners: Seat[]; scores: number[]; reason: EndReason };

export type BirdError =
  | "game_over"
  | "bad_action"
  | "not_your_turn"
  | "bad_seat"
  /** An action for another step of the hand. */
  | "wrong_phase"
  /** Under the minimum, or under the high bid plus 5. */
  | "bid_too_low"
  | "bid_too_high"
  /** Not a multiple of 5. */
  | "bad_bid"
  /** Not a card in this game's deck. */
  | "bad_card"
  | "not_your_card"
  /** Putting back a different number of cards than the nest held. */
  | "wrong_count"
  | "duplicate_card"
  /** Calling a card the bid winner holds. */
  | "own_card"
  /** A card that doesn't follow the suit that was led. */
  | "must_follow";

export type ApplyResult = { ok: true; state: BirdState; events: BirdEvent[] } | { ok: false; error: BirdError };

const fail = (error: BirdError): ApplyResult => ({ ok: false, error });

export const rulesOf = (s: BirdState): RuleSet => RULE_SETS[s.rules];

/** The sides by seat order (design §5.1): teammates sit across the table. */
export function teamsFor(seats: number): Seat[][] {
  if (seats === 5) return Array.from({ length: 5 }, (_, seat) => [seat]);
  const half = seats / 2;
  return Array.from({ length: half }, (_, i) => [i, i + half]);
}

export const teamOf = (s: BirdState, seat: Seat): number => s.teams.findIndex((team) => team.includes(seat));

/** The seat that must act now, or null between hands and once over. */
export function actor(s: BirdState): Seat | null {
  return s.status === "playing" && ACTING.has(s.phase) ? s.turn : null;
}

/** Runs `use` with the game's random stream, from where it last stopped. */
function withRng<T>(s: BirdState, use: (rng: () => number) => T): T {
  const rng = createRng(s.seed);
  for (let i = 0; i < s.rngCalls; i++) rng();
  let used = 0;
  const out = use(() => {
    used++;
    return rng();
  });
  s.rngCalls += used;
  return out;
}

const byId = (a: CardId, b: CardId) => a - b;

/** Shuffles and deals hand `s.hand` (mutates `s`): new hands and nest, and bidding starts left of the dealer. */
function deal(s: BirdState): void {
  const { hand: size } = dealFor(rulesOf(s), s.seats);
  const deck = withRng(s, (rng) => shuffle(deckFor(rulesOf(s), s.seats), rng));
  s.hands = Array.from({ length: s.seats }, (_, seat) => deck.slice(seat * size, (seat + 1) * size).sort(byId));
  s.nest = deck.slice(s.seats * size).sort(byId);
  s.fromNest = [];
  s.putBack = [];
  s.bids = new Array<number | null>(s.seats).fill(null);
  s.passed = new Array<boolean>(s.seats).fill(false);
  s.high = null;
  s.trump = null;
  s.called = null;
  s.holder = null;
  s.partner = null;
  s.trick = [];
  s.leader = null;
  s.lastTrick = null;
  s.played = [];
  s.points = new Array<number>(s.seats).fill(0);
  s.tricks = new Array<number>(s.seats).fill(0);
  s.phase = "bidding";
  s.turn = (s.dealer + 1) % s.seats;
}

const dealtEvent = (s: BirdState): BirdEvent => ({
  kind: "dealt",
  hand: s.hand,
  dealer: s.dealer,
  handCounts: s.hands.map((h) => h.length),
  hands: Object.fromEntries(s.hands.map((h, seat) => [seat, [...h]])),
});

/**
 * A new game: 4 to 6 seats under `options.rules`. The seeded stream picks the first dealer and
 * shuffles every hand, so a game is the same for the same seed.
 */
export function newGame(seats: number, seed: Readonly<Seed>, options: BirdOptions = DEFAULT_OPTIONS): BirdState {
  if (!isRuleSetId(options.rules)) throw new RangeError(`unknown rule set: ${String(options.rules)}`);
  dealFor(RULE_SETS[options.rules], seats);
  const teams = teamsFor(seats);
  const s: BirdState = {
    rules: options.rules,
    seats,
    seed: [...seed],
    rngCalls: 0,
    teams,
    scores: new Array<number>(teams.length).fill(0),
    history: [],
    hand: 1,
    dealer: 0,
    phase: "bidding",
    turn: 0,
    moves: 0,
    hands: [],
    nest: [],
    fromNest: [],
    putBack: [],
    bids: [],
    passed: [],
    high: null,
    trump: null,
    called: null,
    holder: null,
    partner: null,
    trick: [],
    leader: null,
    lastTrick: null,
    played: [],
    points: [],
    tricks: [],
    status: "playing",
    winners: [],
  };
  s.dealer = withRng(s, (rng) => Math.floor(rng() * seats));
  deal(s);
  return s;
}

/** The smallest bid `seat` may make now. */
export function minBid(s: BirdState): number {
  const rules = rulesOf(s);
  return s.high === null ? rules.minBid : s.high.amount + rules.bidStep;
}

/**
 * The cards `seat` may play now: none unless it is the seat's move in play. Follow the suit that
 * was led if you can (the Bird counts as trump); with the Bird wild it may also go on anything.
 */
export function playable(s: BirdState, seat: Seat): CardId[] {
  if (actor(s) !== seat || s.phase !== "play") return [];
  const hand = s.hands[seat] as CardId[];
  const lead = s.trick[0];
  if (lead === undefined) return [...hand];
  const trump = s.trump as Suit;
  const led = suitIn(lead.card, trump);
  const follow = hand.filter((c) => suitIn(c, trump) === led);
  if (follow.length === 0) return [...hand];
  if (rulesOf(s).birdWild && hand.includes(BIRD) && !follow.includes(BIRD)) return [...follow, BIRD].sort(byId);
  return follow;
}

/** The seat that takes `trick`: the Bird, else the highest trump, else the highest card of the suit led. */
export function trickWinner(trick: readonly TrickCard[], trump: Suit, rules: RuleSet): Seat {
  const beats = (c: CardId, best: CardId): boolean => {
    if (isBird(c)) return true;
    if (isBird(best)) return false;
    const cTrump = suitOf(c) === trump;
    const bestTrump = suitOf(best) === trump;
    if (cTrump !== bestTrump) return cTrump;
    return suitOf(c) === suitOf(best) && powerOf(rules, c) > powerOf(rules, best);
  };
  let best = trick[0] as TrickCard;
  for (const t of trick.slice(1)) if (beats(t.card, best.card)) best = t;
  return best.seat;
}

/** Apply `action` by `seat`. Pure: `state` is never mutated. */
export function applyAction(state: BirdState, seat: Seat, action: BirdAction): ApplyResult {
  if (state.status !== "playing") return fail("game_over");
  if (!Number.isInteger(seat) || seat < 0 || seat >= state.seats) return fail("bad_seat");
  const s = structuredClone(state);
  const events: BirdEvent[] = [];
  if (action.type === "forfeit") {
    finish(s, [], "left", events);
    return done(s, events);
  }
  if (action.type === "nextHand") {
    if (s.phase !== "between") return fail("wrong_phase");
    s.hand++;
    s.dealer = (s.dealer + 1) % s.seats;
    deal(s);
    events.push(dealtEvent(s));
    return done(s, events);
  }
  if (actor(s) !== seat) return fail("not_your_turn");
  const error = step(s, seat, action, events);
  return error === null ? done(s, events) : fail(error);
}

/** After an applied action: the count moves on, and whoever is to act next is told. */
function done(s: BirdState, events: BirdEvent[]): ApplyResult {
  s.moves++;
  const next = actor(s);
  if (next !== null) events.push({ kind: "turn", seat: next });
  return { ok: true, state: s, events };
}

const PHASE_OF: Record<string, BirdPhase> = { bid: "bidding", pass: "bidding", nest: "nest", trump: "trump", partner: "partner", play: "play" };

/** One seat's action on its own move (mutates `s`); the error, or null when it was applied. */
function step(s: BirdState, seat: Seat, action: BirdAction, events: BirdEvent[]): BirdError | null {
  const phase = PHASE_OF[action.type];
  if (phase === undefined) return "bad_action";
  if (phase !== s.phase) return "wrong_phase";
  switch (action.type) {
    case "bid":
      return bid(s, seat, action.amount, events);
    case "pass":
      s.passed[seat] = true;
      events.push({ kind: "passed", seat });
      nextBidder(s, events);
      return null;
    case "nest":
      return putBack(s, seat, action.discard, events);
    case "trump":
      s.trump = action.suit;
      events.push({ kind: "trump", seat, suit: action.suit });
      if (s.seats === 5) s.phase = "partner";
      else startPlay(s);
      return null;
    case "partner":
      return callPartner(s, seat, action.card, events);
    default:
      return play(s, seat, (action as { card: CardId }).card, events);
  }
}

function bid(s: BirdState, seat: Seat, amount: number, events: BirdEvent[]): BirdError | null {
  const rules = rulesOf(s);
  if (!Number.isInteger(amount) || amount % rules.bidStep !== 0) return "bad_bid";
  if (amount > rules.maxBid) return "bid_too_high";
  if (amount < minBid(s)) return "bid_too_low";
  s.bids[seat] = amount;
  s.high = { seat, amount };
  events.push({ kind: "bid", seat, amount });
  // Nobody can go over the top: bidding ends at once.
  if (amount === rules.maxBid) wonBid(s, seat, events);
  else nextBidder(s, events);
  return null;
}

/** On round the table to the next seat still in, or, with one seat left, that seat has won the bid. */
function nextBidder(s: BirdState, events: BirdEvent[]): void {
  const left = s.passed.flatMap((out, seat) => (out ? [] : [seat]));
  if (left.length === 1) return wonBid(s, left[0] as Seat, events);
  let next = (s.turn + 1) % s.seats;
  while (s.passed[next]) next = (next + 1) % s.seats;
  s.turn = next;
}

/** Bidding is over: `seat` takes the nest into their hand. With no bid at all, they hold the minimum. */
function wonBid(s: BirdState, seat: Seat, events: BirdEvent[]): void {
  s.high ??= { seat, amount: rulesOf(s).minBid };
  events.push({ kind: "bidWon", seat, amount: s.high.amount });
  s.fromNest = s.nest;
  s.nest = [];
  s.hands[seat] = [...(s.hands[seat] as CardId[]), ...s.fromNest].sort(byId);
  events.push({ kind: "nest", seat, cards: [...s.fromNest] });
  s.phase = "nest";
  s.turn = seat;
}

function putBack(s: BirdState, seat: Seat, discard: readonly CardId[], events: BirdEvent[]): BirdError | null {
  if (discard.length !== s.fromNest.length) return "wrong_count";
  if (new Set(discard).size !== discard.length) return "duplicate_card";
  const hand = s.hands[seat] as CardId[];
  if (!discard.every((c) => hand.includes(c))) return "not_your_card";
  s.hands[seat] = hand.filter((c) => !discard.includes(c));
  s.putBack = [...discard].sort(byId);
  s.fromNest = [];
  events.push({ kind: "putBack", seat, count: discard.length, cards: [...s.putBack] });
  s.phase = "trump";
  return null;
}

function callPartner(s: BirdState, seat: Seat, card: CardId, events: BirdEvent[]): BirdError | null {
  if (!deckFor(rulesOf(s), s.seats).includes(card)) return "bad_card";
  if ((s.hands[seat] as CardId[]).includes(card)) return "own_card";
  s.called = card;
  const holder = s.hands.findIndex((h) => h.includes(card));
  // Not in any hand: the bid winner put it back, and plays alone.
  s.holder = holder === -1 ? null : holder;
  events.push({ kind: "called", seat, card });
  startPlay(s);
  return null;
}

/** The bid winner leads the first trick. */
function startPlay(s: BirdState): void {
  const bidder = (s.high as { seat: Seat }).seat;
  s.phase = "play";
  s.leader = bidder;
  s.turn = bidder;
}

function play(s: BirdState, seat: Seat, card: CardId, events: BirdEvent[]): BirdError | null {
  const hand = s.hands[seat] as CardId[];
  if (!hand.includes(card)) return "not_your_card";
  if (!playable(s, seat).includes(card)) return "must_follow";
  s.hands[seat] = hand.filter((c) => c !== card);
  s.trick.push({ seat, card });
  s.played.push(card);
  events.push({ kind: "played", seat, card });
  if (card === s.called && s.holder === seat) {
    s.partner = seat;
    events.push({ kind: "partner", seat });
  }
  if (s.trick.length < s.seats) {
    s.turn = (seat + 1) % s.seats;
    return null;
  }
  const rules = rulesOf(s);
  const winner = trickWinner(s.trick, s.trump as Suit, rules);
  const points = s.trick.reduce((sum, t) => sum + counterOf(rules, t.card), 0);
  s.points[winner] = (s.points[winner] as number) + points;
  s.tricks[winner] = (s.tricks[winner] as number) + 1;
  s.lastTrick = { cards: s.trick, winner };
  events.push({ kind: "trick", winner, cards: s.trick.map((t) => ({ ...t })), points });
  s.trick = [];
  s.leader = winner;
  s.turn = winner;
  if ((s.hands[winner] as CardId[]).length === 0) endHand(s, winner, events);
  return null;
}

/**
 * The last trick is in (mutates `s`): its winner takes the put-back cards too, the hand is scored
 * (design §4.7), and the game ends when one side is the highest of those that reached the target
 * without missing their bid this hand (§4.8). Otherwise it waits between hands.
 */
function endHand(s: BirdState, lastWinner: Seat, events: BirdEvent[]): void {
  const rules = rulesOf(s);
  s.points[lastWinner] = (s.points[lastWinner] as number) + s.putBack.reduce((sum, c) => sum + counterOf(rules, c), 0);
  const high = s.high as { seat: Seat; amount: number };
  const sideOf = (seat: Seat): Seat[] =>
    s.seats === 5 ? [high.seat, ...(s.holder === null ? [] : [s.holder])] : (s.teams[teamOf(s, seat)] as Seat[]);
  const bidding = sideOf(high.seat);
  const sum = (seats: readonly Seat[]) => seats.reduce((total, seat) => total + (s.points[seat] as number), 0);
  const biddingTook = sum(bidding);
  const made = biddingTook >= high.amount;
  const others = Array.from({ length: s.seats }, (_, seat) => seat).filter((seat) => !bidding.includes(seat));

  const taken = s.teams.map((team) => {
    const first = team[0] as Seat;
    if (bidding.includes(first)) return biddingTook;
    return s.seats === 5 ? sum(others) : sum(team);
  });
  const change = s.teams.map((team, i) => (bidding.includes(team[0] as Seat) ? (made ? biddingTook : -high.amount) : (taken[i] as number)));
  s.scores = s.scores.map((score, i) => score + (change[i] as number));
  const result: HandResult = {
    hand: s.hand,
    bidder: high.seat,
    bid: high.amount,
    partner: s.seats === 5 ? s.holder : null,
    trump: s.trump as Suit,
    made,
    taken,
    change,
    totals: [...s.scores],
  };
  s.history.push(result);
  if (s.seats === 5 && s.holder !== null) s.partner = s.holder;
  events.push({ kind: "handOver", result: structuredClone(result), putBack: [...s.putBack] });

  const missed = new Set(made ? [] : bidding.map((seat) => teamOf(s, seat)));
  const eligible = s.scores.flatMap((score, i) => (score >= rules.target && !missed.has(i) ? [i] : []));
  const best = Math.max(...eligible.map((i) => s.scores[i] as number));
  const top = eligible.filter((i) => s.scores[i] === best);
  if (top.length === 1) finish(s, [...(s.teams[top[0] as number] as Seat[])], "target", events);
  else s.phase = "between";
}

function finish(s: BirdState, winners: Seat[], reason: EndReason, events: BirdEvent[]): void {
  s.status = "over";
  s.phase = "over";
  s.winners = winners;
  s.endReason = reason;
  events.push({ kind: "gameOver", winners: [...winners], scores: [...s.scores], reason });
}

/**
 * A plain legal action for the seat on the move, for when a bot's is refused: pass, put the nest
 * back as it came, the first suit, the first card the bid winner doesn't hold, the first card
 * that may be played, or the next hand.
 */
export function plainAction(s: BirdState, seat: Seat): BirdAction {
  switch (s.phase) {
    case "bidding":
      return { type: "pass" };
    case "nest":
      return { type: "nest", discard: [...s.fromNest] };
    case "trump":
      return { type: "trump", suit: "fish" };
    case "partner":
      return { type: "partner", card: deckFor(rulesOf(s), s.seats).find((c) => !(s.hands[seat] as CardId[]).includes(c)) as CardId };
    case "play":
      return { type: "play", card: playable(s, seat)[0] as CardId };
    default:
      return { type: "nextHand" };
  }
}
