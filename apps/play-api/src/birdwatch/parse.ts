import { hasKeys, isInt, isObj } from "../shape";

import { isCardId, isSuit } from "./cards";
import { isRuleSetId } from "./rules";

import type { BirdAction, BirdOptions } from "./engine";

/** More cards than any nest holds (7: Tucker or Friesen with 5 players). */
const MAX_PUT_BACK = 7;
/** Above any rule set's top bid; the engine says which bids are legal, with a reason. */
const MAX_BID = 1000;

/** A Birdwatch action off the wire, or null: the shape only. Whether it is legal now is the engine's to say. */
export function parseAction(a: unknown): BirdAction | null {
  if (!isObj(a)) return null;
  switch (a.type) {
    case "pass":
    case "nextHand":
    case "forfeit":
      return hasKeys(a, ["type"]) ? { type: a.type } : null;
    case "bid":
      return hasKeys(a, ["type", "amount"]) && isInt(a.amount, 0, MAX_BID) ? { type: "bid", amount: a.amount } : null;
    case "trump":
      return hasKeys(a, ["type", "suit"]) && isSuit(a.suit) ? { type: "trump", suit: a.suit } : null;
    case "partner":
    case "play":
      return hasKeys(a, ["type", "card"]) && isCardId(a.card) ? { type: a.type, card: a.card } : null;
    case "nest": {
      if (!hasKeys(a, ["type", "discard"])) return null;
      const { discard } = a;
      if (!Array.isArray(discard) || discard.length < 1 || discard.length > MAX_PUT_BACK || !discard.every(isCardId)) return null;
      return { type: "nest", discard: [...discard] };
    }
    default:
      return null;
  }
}

/** A table's options off the wire (the lobby's rule set), or null. */
export function parseOptions(raw: unknown): BirdOptions | null {
  if (!isObj(raw) || !hasKeys(raw, ["rules"]) || !isRuleSetId(raw.rules)) return null;
  return { rules: raw.rules };
}
