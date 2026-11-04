import { ALL_CARD_IDS, card, cardPoints, type CardId } from "./cards";
import { canHit, type Group, type HitSide } from "./groups";
import { matchPhase } from "./phases";
import { createRng, shuffle, type Seed } from "./rng";

/** A 0-based seat index. */
export type Seat = number;

export type CatTowerState = {
  seats: number;
  /** Phase being played per seat, 0..10 (10 = finished all). */
  phase: number[];
  scores: number[];
  round: number;
  dealer: Seat;
  /** Draw pile; the last element is the top. */
  deck: CardId[];
  /** Discard pile; the last element is the top. */
  discard: CardId[];
  hands: CardId[][];
  laid: (Group[] | null)[];
  turn: Seat;
  step: "draw" | "play";
  pendingSkip: boolean[];
  status: "playing" | "roundOver" | "gameOver";
  winners: Seat[];
  /** Server-only: 128 bits from a crypto source. Never sent to a device. */
  seed: Seed;
  /** How many values of the seeded rng stream have been consumed. */
  rngCalls: number;
};

export type Action =
  | { type: "draw"; from: "deck" | "discard" }
  | { type: "layDown"; groups: { cards: CardId[]; runStart?: number }[] }
  | { type: "hit"; card: CardId; target: { seat: Seat; group: number }; side?: HitSide }
  | { type: "discard"; card: CardId; skipTarget?: Seat }
  | { type: "nextRound" };

export type GameEvent =
  | { kind: "roundStarted"; round: number; dealer: Seat }
  | { kind: "drew"; seat: Seat; from: "deck" | "discard"; card?: CardId }
  | { kind: "laidDown"; seat: Seat; groups: Group[] }
  | {
      kind: "hit";
      seat: Seat;
      card: CardId;
      target: { seat: Seat; group: number };
      group: Group;
    }
  | { kind: "discarded"; seat: Seat; card: CardId; skipTarget?: Seat }
  | { kind: "skipped"; seat: Seat }
  | { kind: "turn"; seat: Seat }
  | { kind: "reshuffled"; deckCount: number }
  | {
      kind: "roundOver";
      wentOut: Seat | null;
      points: number[];
      advanced: Seat[];
      scores: number[];
      phase: number[];
    }
  | { kind: "gameOver"; winners: Seat[] };

export type ApplyError =
  | "not_your_turn"
  | "bad_step"
  | "bad_card"
  | "bad_groups"
  | "already_laid"
  | "not_laid"
  | "bad_target"
  | "empty_discard"
  | "cucumber_from_discard"
  | "round_not_over";

export type ApplyResult =
  | { ok: true; state: CatTowerState; events: GameEvent[] }
  | { ok: false; error: ApplyError };

const HAND_SIZE = 10;
const MIN_SEATS = 2;
const MAX_SEATS = 6;
const FINAL_PHASE = 10;

const fail = (error: ApplyError): ApplyResult => ({ ok: false, error });

/**
 * Shuffle `items` with the game's seeded rng. Every shuffle (deal and
 * reshuffle) goes through here: the stream is recreated from `seed`, the
 * `rngCalls` values already consumed are discarded, and the new count is
 * stored back so the state stays JSON-serializable and replayable.
 */
function shuffleSeeded(state: CatTowerState, items: readonly CardId[]): CardId[] {
  const rng = createRng(state.seed);
  for (let i = 0; i < state.rngCalls; i++) rng();
  let used = 0;
  const out = shuffle(items, () => {
    used++;
    return rng();
  });
  state.rngCalls += used;
  return out;
}

/** Create a game: dealer is seat 0 and round 1 is dealt. */
export function newGame(seats: number, seed: Readonly<Seed>): CatTowerState {
  if (!Number.isInteger(seats) || seats < MIN_SEATS || seats > MAX_SEATS) {
    throw new RangeError(`seats must be ${MIN_SEATS}-${MAX_SEATS}: ${seats}`);
  }
  const initial: CatTowerState = {
    seats,
    phase: new Array<number>(seats).fill(0),
    scores: new Array<number>(seats).fill(0),
    round: 0,
    dealer: 0,
    deck: [],
    discard: [],
    hands: Array.from({ length: seats }, () => [] as CardId[]),
    laid: new Array<null>(seats).fill(null),
    turn: 0,
    step: "draw",
    pendingSkip: new Array<boolean>(seats).fill(false),
    status: "playing",
    winners: [],
    seed: [...seed],
    rngCalls: 0,
  };
  return dealRound(initial, 0, 1).state;
}

/**
 * Deal a fresh round on top of `prev` (phases, scores, seed and rng position
 * carry over): shuffle the whole deck, deal 10 each starting left of the
 * dealer, flip one card, and start the turn after the dealer. A flipped
 * Cucumber skips that first seat through the normal pending-skip mechanism.
 */
export function dealRound(
  prev: CatTowerState,
  dealer: Seat,
  round: number,
): { state: CatTowerState; events: GameEvent[] } {
  const s = structuredClone(prev);
  const n = s.seats;
  const shuffled = shuffleSeeded(s, ALL_CARD_IDS);
  s.hands = Array.from({ length: n }, () => [] as CardId[]);
  for (let i = 0; i < HAND_SIZE * n; i++) {
    (s.hands[(dealer + 1 + (i % n)) % n] as CardId[]).push(shuffled[i] as CardId);
  }
  s.discard = [shuffled[HAND_SIZE * n] as CardId];
  s.deck = shuffled.slice(HAND_SIZE * n + 1);
  s.laid = new Array<null>(n).fill(null);
  s.pendingSkip = new Array<boolean>(n).fill(false);
  s.status = "playing";
  s.round = round;
  s.dealer = dealer;

  const events: GameEvent[] = [{ kind: "roundStarted", round, dealer }];
  const first = (dealer + 1) % n;
  s.turn = dealer;
  if (card(s.discard[0] as CardId).kind === "cucumber") {
    s.pendingSkip[first] = true;
  }
  advanceTurn(s, events);
  return { state: s, events };
}

/**
 * Move to the next seat, clearing and announcing any pending skips on the way.
 * Terminates because a pending seat is never the seat whose turn is ending.
 */
function advanceTurn(s: CatTowerState, events: GameEvent[]): void {
  let next = (s.turn + 1) % s.seats;
  while (s.pendingSkip[next]) {
    s.pendingSkip[next] = false;
    events.push({ kind: "skipped", seat: next });
    next = (next + 1) % s.seats;
  }
  s.turn = next;
  s.step = "draw";
  events.push({ kind: "turn", seat: next });
}

/**
 * Close the round (mutates `s`): score the remaining hands and advance every
 * seat that laid down its phase. `wentOut` is null when nobody emptied their
 * hand. If that finishes phase 10 for anyone, the game is over too.
 */
function endRound(s: CatTowerState, wentOut: Seat | null, events: GameEvent[]): void {
  const points = s.hands.map((hand) => hand.reduce((sum, id) => sum + cardPoints(id), 0));
  const advanced: Seat[] = [];
  for (let seat = 0; seat < s.seats; seat++) {
    s.scores[seat] = (s.scores[seat] as number) + (points[seat] as number);
    if (s.laid[seat] !== null) {
      s.phase[seat] = (s.phase[seat] as number) + 1;
      advanced.push(seat);
    }
  }
  s.status = "roundOver";
  events.push({
    kind: "roundOver",
    wentOut,
    points,
    advanced,
    scores: [...s.scores],
    phase: [...s.phase],
  });

  // The game ends as soon as any seat finishes phase 10. Only seats that
  // finished it can win; the lowest score among them takes it, ties share.
  const finished: Seat[] = [];
  for (let seat = 0; seat < s.seats; seat++) {
    if (s.phase[seat] === FINAL_PHASE) finished.push(seat);
  }
  if (finished.length > 0) {
    const best = Math.min(...finished.map((seat) => s.scores[seat] as number));
    s.winners = finished.filter((seat) => s.scores[seat] === best);
    s.status = "gameOver";
    events.push({ kind: "gameOver", winners: [...s.winners] });
  }
}

/** Apply `action` by `seat`. Pure: `state` is never mutated. */
export function applyAction(
  state: CatTowerState,
  seat: Seat,
  action: Action,
): ApplyResult {
  if (action.type === "nextRound") {
    // Any seat may start the next round, whoever's turn it was.
    if (state.status !== "roundOver") return fail("round_not_over");
    const dealt = dealRound(state, (state.dealer + 1) % state.seats, state.round + 1);
    return { ok: true, state: dealt.state, events: dealt.events };
  }
  if (state.status !== "playing") return fail("bad_step");
  if (seat !== state.turn) return fail("not_your_turn");

  const s = structuredClone(state);
  const events: GameEvent[] = [];
  const error = dispatch(s, action, events);
  return error === null ? { ok: true, state: s, events } : fail(error);
}

function dispatch(
  s: CatTowerState,
  action: Exclude<Action, { type: "nextRound" }>,
  events: GameEvent[],
): ApplyError | null {
  switch (action.type) {
    case "draw":
      return draw(s, action.from, events);
    case "layDown":
      return layDown(s, action, events);
    case "hit":
      return hit(s, action, events);
    case "discard":
      return discard(s, action, events);
  }
}

function draw(
  s: CatTowerState,
  from: "deck" | "discard",
  events: GameEvent[],
): ApplyError | null {
  if (s.step !== "draw") return "bad_step";
  const hand = s.hands[s.turn] as CardId[];

  if (from === "discard") {
    const top = s.discard.at(-1);
    if (top === undefined) return "empty_discard";
    if (card(top).kind === "cucumber") return "cucumber_from_discard";
    s.discard.pop();
    hand.push(top);
    events.push({ kind: "drew", seat: s.turn, from, card: top });
    s.step = "play";
    return null;
  }

  if (s.deck.length === 0) {
    // Reshuffle everything under the discard's top card into a new deck.
    const top = s.discard.at(-1);
    const rest = s.discard.slice(0, -1);
    if (top === undefined || rest.length === 0) {
      // Nothing left to draw: the round ends with nobody going out.
      endRound(s, null, events);
      return null;
    }
    s.deck = shuffleSeeded(s, rest);
    s.discard = [top];
    events.push({ kind: "reshuffled", deckCount: s.deck.length });
  }
  const drawn = s.deck.pop() as CardId;
  hand.push(drawn);
  events.push({ kind: "drew", seat: s.turn, from, card: drawn });
  s.step = "play";
  return null;
}

function discard(
  s: CatTowerState,
  action: Extract<Action, { type: "discard" }>,
  events: GameEvent[],
): ApplyError | null {
  if (s.step !== "play") return "bad_step";
  const hand = s.hands[s.turn] as CardId[];
  const index = hand.indexOf(action.card);
  if (index === -1) return "bad_card";

  let skipTarget: Seat | undefined;
  if (card(action.card).kind === "cucumber") {
    const candidates: Seat[] = [];
    for (let other = 0; other < s.seats; other++) {
      if (other !== s.turn && !s.pendingSkip[other]) candidates.push(other);
    }
    if (candidates.length > 0) {
      if (action.skipTarget === undefined || !candidates.includes(action.skipTarget)) {
        return "bad_target";
      }
      skipTarget = action.skipTarget;
    } else if (action.skipTarget !== undefined) {
      return "bad_target";
    }
  }

  hand.splice(index, 1);
  s.discard.push(action.card);
  events.push(
    skipTarget === undefined
      ? { kind: "discarded", seat: s.turn, card: action.card }
      : { kind: "discarded", seat: s.turn, card: action.card, skipTarget },
  );
  if (hand.length === 0) {
    // Going out: the round ends here, so a Cucumber's skip never takes effect.
    endRound(s, s.turn, events);
    return null;
  }
  if (skipTarget !== undefined) s.pendingSkip[skipTarget] = true;
  advanceTurn(s, events);
  return null;
}

function layDown(
  s: CatTowerState,
  action: Extract<Action, { type: "layDown" }>,
  events: GameEvent[],
): ApplyError | null {
  if (s.step !== "play") return "bad_step";
  const seat = s.turn;
  if (s.laid[seat] !== null) return "already_laid";
  const hand = s.hands[seat] as CardId[];
  for (const group of action.groups) {
    if (!group.cards.every((id) => hand.includes(id))) return "bad_card";
  }
  const groups = matchPhase(s.phase[seat] as number, action.groups);
  if (groups === null) return "bad_groups";

  const used = new Set(groups.flatMap((g) => g.cards));
  const remaining = hand.filter((id) => !used.has(id));
  s.hands[seat] = remaining;
  s.laid[seat] = groups;
  events.push({ kind: "laidDown", seat, groups });
  if (remaining.length === 0) endRound(s, seat, events);
  return null;
}

function hit(
  s: CatTowerState,
  action: Extract<Action, { type: "hit" }>,
  events: GameEvent[],
): ApplyError | null {
  if (s.step !== "play") return "bad_step";
  const seat = s.turn;
  if (s.laid[seat] === null) return "not_laid";
  const hand = s.hands[seat] as CardId[];
  const index = hand.indexOf(action.card);
  if (index === -1) return "bad_card";

  const { target } = action;
  const group = s.laid[target.seat]?.[target.group];
  if (group === undefined) return "bad_target";
  const hitResult = canHit(group, action.card, action.side);
  if (!hitResult.ok) return "bad_target";

  hand.splice(index, 1);
  (s.laid[target.seat] as Group[])[target.group] = hitResult.group;
  events.push({
    kind: "hit",
    seat,
    card: action.card,
    target: { seat: target.seat, group: target.group },
    group: hitResult.group,
  });
  if (hand.length === 0) endRound(s, seat, events);
  return null;
}
