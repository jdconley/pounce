import { cardFor, SUITS, type CardId } from "../src/birdwatch/cards";
import { actor, minBid, newGame, playable, type ApplyResult, type BirdAction, type BirdEvent, type BirdState } from "../src/birdwatch/engine";
import { deckFor, RULE_SETS, type RuleSetId } from "../src/birdwatch/rules";

/* Cards by suit and rank, for tests. */
export const fish = (rank: number): CardId => cardFor("fish", rank);
export const mouse = (rank: number): CardId => cardFor("mouse", rank);
export const feather = (rank: number): CardId => cardFor("feather", rank);
export const bell = (rank: number): CardId => cardFor("bell", rank);

export const SEED: [number, number, number, number] = [11, 22, 33, 44];

export function deepFreeze<T>(value: T): T {
  if (typeof value === "object" && value !== null && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const v of Object.values(value)) deepFreeze(v);
  }
  return value;
}

/** A fresh game, with any fields replaced, frozen so a test catches a mutated state. */
export function game(seats: number, rules: RuleSetId = "official", over: Partial<BirdState> = {}): BirdState {
  return deepFreeze({ ...newGame(seats, SEED, { rules }), ...over });
}

/**
 * A hand in play with trump named and `high.seat` as the bid winner: the given hands, an empty
 * trick, `leader` to lead. Everything else as a fresh game has it.
 */
export function inPlay(o: {
  seats?: number;
  rules?: RuleSetId;
  hands: CardId[][];
  trump?: BirdState["trump"];
  bidder?: number;
  bid?: number;
  leader?: number;
  over?: Partial<BirdState>;
}): BirdState {
  const seats = o.seats ?? o.hands.length;
  const bidder = o.bidder ?? 0;
  const leader = o.leader ?? bidder;
  return game(seats, o.rules, {
    phase: "play",
    hands: o.hands.map((h) => [...h].sort((a, b) => a - b)),
    nest: [],
    trump: o.trump ?? "fish",
    high: { seat: bidder, amount: o.bid ?? 70 },
    leader,
    turn: leader,
    ...o.over,
  });
}

export function ok(result: ApplyResult): { state: BirdState; events: BirdEvent[] } {
  if (!result.ok) throw new Error(`expected ok, got ${result.error}`);
  return result;
}

export function errorOf(result: ApplyResult): string {
  if (result.ok) throw new Error("expected an error, got ok");
  return result.error;
}

/**
 * A random legal action for whoever is to act (the next hand between hands), from `rng`: raise or
 * pass, put back any cards, any suit, any card not held, any playable card.
 */
export function randomAction(s: BirdState, rng: () => number): { seat: number; action: BirdAction } {
  const pick = <T>(items: readonly T[]): T => items[Math.floor(rng() * items.length)] as T;
  const seat = actor(s);
  if (seat === null) return { seat: 0, action: { type: "nextHand" } };
  const hand = s.hands[seat] as CardId[];
  switch (s.phase) {
    case "bidding": {
      const min = minBid(s);
      return { seat, action: rng() < 0.45 && min <= RULE_SETS[s.rules].maxBid ? { type: "bid", amount: min } : { type: "pass" } };
    }
    case "nest": {
      const discard = [...hand].sort(() => rng() - 0.5).slice(0, s.fromNest.length);
      return { seat, action: { type: "nest", discard } };
    }
    case "trump":
      return { seat, action: { type: "trump", suit: pick(SUITS) } };
    case "partner":
      return { seat, action: { type: "partner", card: pick(deckFor(RULE_SETS[s.rules], s.seats).filter((c) => !hand.includes(c))) } };
    default:
      return { seat, action: { type: "play", card: pick(playable(s, seat)) } };
  }
}
