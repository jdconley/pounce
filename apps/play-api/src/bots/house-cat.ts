import { card, cardPoints, type CardId } from "../rules/cards";
import { findHits, findPhase, phaseProgress } from "../rules/solver";

import type { Action, Seat } from "../rules/engine";
import type { Rng } from "../rules/rng";
import type { CatTowerView } from "../rules/view";

const pick = <T>(items: readonly T[], rng: Rng): T =>
  items[Math.floor(rng() * items.length)] as T;

/** The items with the smallest `cost`. */
function cheapest<T>(items: readonly T[], cost: (item: T) => number): T[] {
  const lowest = Math.min(...items.map(cost));
  return items.filter((item) => cost(item) === lowest);
}

/**
 * House Cat: one action per call, for a seat whose turn it is in a playing
 * game. `rng` only breaks ties, so play is deterministic for a given seed.
 *
 * Draw: take the discard unless it is a Cucumber or does not help (raise phase
 * progress, or once laid down, fit a laid group). Play: lay down as soon as the phase can be made, then hit one card
 * at a time, then discard (Cucumber first, aimed at the leader).
 */
export function chooseAction(view: CatTowerView, seat: Seat, rng: Rng): Action {
  const hand = view.hands[seat] as CardId[];
  const phase = view.phase[seat] as number;

  const laid = view.laid[seat] !== null;
  if (view.step === "draw") {
    const top = view.discardTop;
    // Before laying down, progress toward the phase decides. Afterwards the
    // phase no longer matters and only a card that can be hit is useful; the
    // progress test would keep swapping cards on the discard pile forever and
    // never draw anything new.
    const useful =
      top !== null &&
      card(top).kind !== "cucumber" &&
      (laid
        ? findHits([top], view.laid).length > 0
        : phaseProgress([...hand, top], phase) > phaseProgress(hand, phase));
    return { type: "draw", from: useful ? "discard" : "deck" };
  }

  if (!laid) {
    const groups = findPhase(hand, phase);
    if (groups !== null) return { type: "layDown", groups };
  } else {
    const [hit] = findHits(hand, view.laid);
    if (hit !== undefined) return { type: "hit", ...hit };
  }
  return discardAction(view, seat, hand, phase, laid, rng);
}

function discardAction(
  view: CatTowerView,
  seat: Seat,
  hand: CardId[],
  phase: number,
  laid: boolean,
  rng: Rng,
): Action {
  const cucumbers = hand.filter((id) => card(id).kind === "cucumber");
  if (cucumbers.length > 0) {
    const cucumber = cucumbers[0] as CardId;
    const target = skipTarget(view, seat, rng);
    return target === null
      ? { type: "discard", card: cucumber }
      : { type: "discard", card: cucumber, skipTarget: target };
  }

  // Yarn are kept unless nothing else is left.
  const nonYarn = hand.filter((id) => card(id).kind !== "yarn");
  const options = nonYarn.length > 0 ? nonYarn : hand;
  // Once laid down the phase no longer matters, so only points decide.
  const base = laid ? 0 : phaseProgress(hand, phase);
  const loss = (id: CardId): number =>
    laid ? 0 : base - phaseProgress(hand.filter((other) => other !== id), phase);
  const leastLoss = cheapest(options, loss);
  const mostPoints = cheapest(leastLoss, (id) => -cardPoints(id));
  return { type: "discard", card: pick(mostPoints, rng) };
}

/**
 * The seat to skip: highest phase, then fewest cards in hand, then the rng.
 * Seats already skipped are not valid targets; null when none remain.
 */
function skipTarget(view: CatTowerView, seat: Seat, rng: Rng): Seat | null {
  const targets = view.phase
    .map((_, other) => other)
    .filter((other) => other !== seat && !view.pendingSkip[other]);
  if (targets.length === 0) return null;
  const leaders = cheapest(targets, (other) => -(view.phase[other] as number));
  const fewest = cheapest(leaders, (other) => view.handCounts[other] as number);
  return pick(fewest, rng);
}
