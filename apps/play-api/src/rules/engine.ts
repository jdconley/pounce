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
  /**
   * Seats that forfeited (spec §5.13): out for the rest of the game, last place, never dealt
   * in or given a turn. Absent in games saved before forfeits, and until someone forfeits.
   */
  forfeited?: boolean[];
  /**
   * Set only when the game ended before the hand was played out: "decided"
   * means the rest of the hand could not change anyone's finishing place.
   * Absent on a game that ended the usual way (and on older stored states).
   */
  endReason?: EndReason;
  /** Server-only: 128 bits from a crypto source. Never sent to a device. */
  seed: Seed;
  /** How many values of the seeded rng stream have been consumed. */
  rngCalls: number;
};

/**
 * Why a game ended early: "decided", see `outcomeDecided`; "forfeit", every
 * other seat forfeited (§5.13).
 */
export type EndReason = "decided" | "forfeit";

export type Action =
  | { type: "draw"; from: "deck" | "discard" }
  | { type: "layDown"; groups: { cards: CardId[]; runStart?: number }[] }
  | { type: "hit"; card: CardId; target: { seat: Seat; group: number }; side?: HitSide }
  | { type: "discard"; card: CardId; skipTarget?: Seat }
  | { type: "nextRound" }
  /** Leave the game for good (§5.13): any time before it is over, on anyone's turn. */
  | { type: "forfeit" };

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
  | { kind: "forfeited"; seat: Seat }
  | { kind: "gameOver"; winners: Seat[]; reason?: EndReason };

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
  | "round_not_over"
  /** The seat already forfeited. */
  | "forfeited";

export type ApplyResult =
  | { ok: true; state: CatTowerState; events: GameEvent[] }
  | { ok: false; error: ApplyError };

const HAND_SIZE = 10;
const MIN_SEATS = 2;
const MAX_SEATS = 6;
const FINAL_PHASE = 10;
/** The most a single card in hand can score (Yarn). */
const MAX_CARD_POINTS = 25;

const fail = (error: ApplyError): ApplyResult => ({ ok: false, error });

/** True when `seat` forfeited. */
export function isOut(s: CatTowerState, seat: Seat): boolean {
  return s.forfeited?.[seat] === true;
}

/** The seats still in the game, in seat order. */
export function activeSeats(s: CatTowerState): Seat[] {
  return Array.from({ length: s.seats }, (_, seat) => seat).filter((seat) => !isOut(s, seat));
}

/** The first seat after `from`, going round, that is still in the game. */
function nextActive(s: CatTowerState, from: Seat): Seat {
  let next = (from + 1) % s.seats;
  while (isOut(s, next) && next !== from) next = (next + 1) % s.seats;
  return next;
}

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
  // Dealt in seat order from the dealer's left, skipping seats that forfeited.
  const order = Array.from({ length: n }, (_, i) => (dealer + 1 + i) % n).filter((seat) => !isOut(s, seat));
  const dealt = HAND_SIZE * order.length;
  for (let i = 0; i < dealt; i++) {
    (s.hands[order[i % order.length] as Seat] as CardId[]).push(shuffled[i] as CardId);
  }
  s.discard = [shuffled[dealt] as CardId];
  s.deck = shuffled.slice(dealt + 1);
  s.laid = new Array<null>(n).fill(null);
  s.pendingSkip = new Array<boolean>(n).fill(false);
  s.status = "playing";
  s.round = round;
  s.dealer = dealer;

  const events: GameEvent[] = [{ kind: "roundStarted", round, dealer }];
  const first = nextActive(s, dealer);
  s.turn = dealer;
  if (card(s.discard[0] as CardId).kind === "cucumber") {
    s.pendingSkip[first] = true;
  }
  advanceTurn(s, events);
  return { state: s, events };
}

/**
 * Move to the next seat, clearing and announcing any pending skips on the way
 * and passing over seats that forfeited. Terminates because each skip is
 * cleared as it is passed and at least two seats are still in the game.
 */
function advanceTurn(s: CatTowerState, events: GameEvent[]): void {
  let next = (s.turn + 1) % s.seats;
  while (s.pendingSkip[next] || isOut(s, next)) {
    if (s.pendingSkip[next]) {
      s.pendingSkip[next] = false;
      events.push({ kind: "skipped", seat: next });
    }
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
function endRound(
  s: CatTowerState,
  wentOut: Seat | null,
  events: GameEvent[],
  reason?: EndReason,
): void {
  const points = s.hands.map((hand) => hand.reduce((sum, id) => sum + cardPoints(id), 0));
  const advanced: Seat[] = [];
  for (let seat = 0; seat < s.seats; seat++) {
    s.scores[seat] = (s.scores[seat] as number) + (points[seat] as number);
    if (s.laid[seat] !== null && !isOut(s, seat)) {
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
    if (s.phase[seat] === FINAL_PHASE && !isOut(s, seat)) finished.push(seat);
  }
  if (finished.length > 0) {
    const best = Math.min(...finished.map((seat) => s.scores[seat] as number));
    s.winners = finished.filter((seat) => s.scores[seat] === best);
    s.status = "gameOver";
    if (reason === undefined) {
      events.push({ kind: "gameOver", winners: [...s.winners] });
    } else {
      s.endReason = reason;
      events.push({ kind: "gameOver", winners: [...s.winners], reason });
    }
  }
}

/** The range a seat's end-of-game phase and score can still land in. */
type Bounds = { phaseLo: number; phaseHi: number; scoreLo: number; scoreHi: number };

/**
 * Whether `a` finishes strictly ahead of `b` under every outcome in the
 * bounds: more phases completed, or the same phase and a lower score.
 */
function surelyAhead(a: Bounds, b: Bounds): boolean {
  if (a.phaseLo > b.phaseHi) return true;
  return a.phaseLo === b.phaseHi && a.scoreHi < b.scoreLo;
}

/**
 * True when the game will end with this hand and nothing left in it can
 * change anyone's finishing place (phases completed, then lowest score; the
 * order the game-over screen shows and `winners` takes the top of).
 *
 * This hand ends the game once any seat has laid down phase 10. Each seat's
 * outcome is then bounded independently, which over-counts what can happen
 * and so only ever errs toward playing on:
 * - phase: a seat that laid down finishes one up; one that has not may still
 *   lay down, so either its phase or one up.
 * - score: its score now plus 0 (it may still go out) up to 25 per card it
 *   holds. A hand never ends holding more cards than it holds now: a draw is
 *   always followed by a discard, and a hand ends mid-turn only by going out.
 *   The bound includes the cards held now, so scoring the hand as it stands
 *   lands inside it (see `applyAction`).
 * The order is decided when every pair of seats is surely ordered. A tie is
 * never surely kept (it needs empty hands), so a decided game has one winner.
 */
export function outcomeDecided(s: CatTowerState): boolean {
  if (s.status !== "playing") return false;
  // A seat that forfeited (§5.13) never advances or wins and finishes last: it
  // neither finishes the game nor leaves a place open.
  const finishing = s.laid.some(
    (groups, seat) => groups !== null && s.phase[seat] === FINAL_PHASE - 1 && !isOut(s, seat),
  );
  if (!finishing) return false;
  const bounds: Bounds[] = s.hands.map((hand, seat) => {
    const phase = s.phase[seat] as number;
    const score = s.scores[seat] as number;
    return {
      phaseLo: s.laid[seat] !== null ? phase + 1 : phase,
      phaseHi: phase + 1,
      scoreLo: score,
      scoreHi: score + MAX_CARD_POINTS * hand.length,
    };
  });
  for (let a = 0; a < s.seats; a++) {
    if (isOut(s, a)) continue;
    for (let b = a + 1; b < s.seats; b++) {
      if (isOut(s, b)) continue;
      const x = bounds[a] as Bounds;
      const y = bounds[b] as Bounds;
      if (!surelyAhead(x, y) && !surelyAhead(y, x)) return false;
    }
  }
  return true;
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
    const dealt = dealRound(state, nextActive(state, state.dealer), state.round + 1);
    return { ok: true, state: dealt.state, events: dealt.events };
  }
  if (action.type === "forfeit") {
    const result = forfeit(state, seat);
    // With the forfeiter's place no longer open, the rest of the hand may not matter any more.
    if (result.ok && outcomeDecided(result.state)) endRound(result.state, null, result.events, "decided");
    return result;
  }
  if (state.status !== "playing") return fail("bad_step");
  if (seat !== state.turn) return fail("not_your_turn");

  const s = structuredClone(state);
  const events: GameEvent[] = [];
  const error = dispatch(s, action, events);
  if (error !== null) return fail(error);
  // Once the rest of the hand cannot change anyone's place, stop it here:
  // score the hands as they stand (nobody went out) and end the game. The
  // standing scores lie inside the bounds `outcomeDecided` proved the order
  // for, so the places come out exactly as they would have.
  if (outcomeDecided(s)) endRound(s, null, events, "decided");
  return { ok: true, state: s, events };
}

function dispatch(
  s: CatTowerState,
  action: Exclude<Action, { type: "nextRound" | "forfeit" }>,
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

/**
 * A seat leaves the game (§5.13). With one seat left in, that seat wins and
 * the game is over. Otherwise the seat is out: its hand leaves play (not to
 * the discard), it is never dealt in or given a turn again, it can't win, and
 * on its own turn the turn moves on. Laid groups stay on the table to hit on.
 */
function forfeit(state: CatTowerState, seat: Seat): ApplyResult {
  if (state.status === "gameOver") return fail("bad_step");
  if (!Number.isInteger(seat) || seat < 0 || seat >= state.seats) return fail("bad_target");
  if (isOut(state, seat)) return fail("forfeited");

  const s = structuredClone(state);
  const out = s.forfeited ?? new Array<boolean>(s.seats).fill(false);
  out[seat] = true;
  s.forfeited = out;
  s.hands[seat] = [];
  s.pendingSkip[seat] = false;
  const events: GameEvent[] = [{ kind: "forfeited", seat }];

  const left = activeSeats(s);
  if (left.length <= 1) {
    s.winners = left;
    s.status = "gameOver";
    s.endReason = "forfeit";
    events.push({ kind: "gameOver", winners: [...left], reason: "forfeit" });
    return { ok: true, state: s, events };
  }
  if (s.status === "playing" && s.turn === seat) advanceTurn(s, events);
  return { ok: true, state: s, events };
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
      if (other !== s.turn && !s.pendingSkip[other] && !isOut(s, other)) candidates.push(other);
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
