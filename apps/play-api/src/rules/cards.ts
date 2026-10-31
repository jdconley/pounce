/** A card id in 0-107. Ids are the only card representation on the wire. */
export type CardId = number;

export type Coat = "tabby" | "tuxedo" | "calico" | "gray";

export const COATS: readonly Coat[] = ["tabby", "tuxedo", "calico", "gray"];

export type Card =
  | { id: CardId; kind: "number"; value: number; coat: Coat }
  | { id: CardId; kind: "yarn" }
  | { id: CardId; kind: "cucumber" };

const NUMBER_CARDS = 96;
const CUCUMBER_START = 104;
const DECK_SIZE = 108;

/**
 * Ids 0-95 are numbers: coat = floor(id / 24), value = (id % 12) + 1, so each
 * value appears twice per coat. 96-103 are Yarn (wild), 104-107 are Cucumber
 * (skip).
 */
export function card(id: CardId): Card {
  if (!Number.isInteger(id) || id < 0 || id >= DECK_SIZE) {
    throw new RangeError(`invalid card id: ${id}`);
  }
  if (id < NUMBER_CARDS) {
    return {
      id,
      kind: "number",
      value: (id % 12) + 1,
      coat: COATS[Math.floor(id / 24)] as Coat,
    };
  }
  return id < CUCUMBER_START ? { id, kind: "yarn" } : { id, kind: "cucumber" };
}

export const ALL_CARD_IDS: readonly CardId[] = Array.from(
  { length: DECK_SIZE },
  (_, i) => i,
);

/** Scoring: 1-9 = 5, 10-12 = 10, Cucumber = 15, Yarn = 25. */
export function cardPoints(id: CardId): number {
  const c = card(id);
  if (c.kind === "yarn") return 25;
  if (c.kind === "cucumber") return 15;
  return c.value >= 10 ? 10 : 5;
}
