import { SUITS, type Suit } from "../tiles/pieces";

export { SUITS, type Suit };

/**
 * A card id in 0-56. Ids are the only card form on the wire. 0-55 are the suited cards: suit
 * `floor(id / 14)` in the order fish, mouse, feather, bell (the tile game's suits), rank
 * `id % 14 + 1`. 56 is the Bird.
 */
export type CardId = number;

/** Ranks run 1 to 14 in every suit. Which of them are in the deck is the rule set's to say. */
export const RANKS_PER_SUIT = 14;
export const BIRD: CardId = SUITS.length * RANKS_PER_SUIT;
const DECK_SIZE = BIRD + 1;

export const isCardId = (v: unknown): v is CardId =>
  typeof v === "number" && Number.isInteger(v) && v >= 0 && v < DECK_SIZE;

export const isBird = (id: CardId): boolean => id === BIRD;

/** The printed suit of a suited card. The Bird has none: see `suitIn`. */
export const suitOf = (id: CardId): Suit => SUITS[Math.floor(id / RANKS_PER_SUIT)] as Suit;

/** The printed rank of a suited card, 1-14. */
export const rankOf = (id: CardId): number => (id % RANKS_PER_SUIT) + 1;

export const cardFor = (suit: Suit, rank: number): CardId => SUITS.indexOf(suit) * RANKS_PER_SUIT + rank - 1;

/** The suit a card counts as once trump is named: the Bird is always trump. */
export const suitIn = (id: CardId, trump: Suit): Suit => (isBird(id) ? trump : suitOf(id));

export const isSuit = (v: unknown): v is Suit => typeof v === "string" && (SUITS as readonly string[]).includes(v);

/** Every card id, in id order. */
export const ALL_CARDS: readonly CardId[] = Array.from({ length: DECK_SIZE }, (_, i) => i);
