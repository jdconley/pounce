import { card, cardPoints, type CardId } from "../rules/cards";
import { PHASES } from "../rules/phases";
import { findHits, findPhase, phaseProgress } from "../rules/solver";

import type { Action, DiscardLog, GameEvent, Seat } from "../rules/engine";
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
 *
 * `log` is what the table has seen done with the discard pile this round (`noteDiscards`).
 * With it the discard also stays away from what the next player to draw is collecting.
 */
export function chooseAction(view: CatTowerView, seat: Seat, rng: Rng, log?: DiscardLog): Action {
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
  return discardAction(view, seat, hand, phase, laid, rng, log);
}

function discardAction(
  view: CatTowerView,
  seat: Seat,
  hand: CardId[],
  phase: number,
  laid: boolean,
  rng: Rng,
  log: DiscardLog | undefined,
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
  // Its own phase comes first: among the cards it can spare, it gives the next
  // player the one they are least likely to want, then sheds the most points.
  const taker = nextDrawer(view, seat);
  const notes = taker !== null && log?.round === view.round ? (log.seats[taker] ?? []) : [];
  const safest = taker === null ? leastLoss : cheapest(leastLoss, (id) => danger(view, taker, notes, id));
  const mostPoints = cheapest(safest, (id) => -cardPoints(id));
  return { type: "discard", card: pick(mostPoints, rng) };
}

const MAX_VALUE = 12;

/** What a card that fits a laid group is worth to a seat that has laid down: it takes it to hit. */
const HIT = 3;

/**
 * The seat that draws after `seat`, and so the only one that can take its
 * discard: the next one round that is neither skipped nor out, as the engine
 * passes the turn on. Null when the turn comes back round to `seat`.
 */
function nextDrawer(view: CatTowerView, seat: Seat): Seat | null {
  const seats = view.phase.length;
  for (let step = 1; step < seats; step++) {
    const other = (seat + step) % seats;
    if (!view.pendingSkip[other] && !view.forfeited[other]) return other;
  }
  return null;
}

/**
 * How much `taker` wants the card `id`, judged only from the table: 0 when
 * nothing points either way. A seat that has laid down wants anything it can
 * hit. One still building its phase is collecting what it took from the
 * discard pile: copies of a value for a set, values near the ones it took for
 * a run, one coat for a coat phase. A value (or coat) it passed up or threw
 * away since it last took one is -1, the safest card to give it.
 */
function danger(view: CatTowerView, taker: Seat, notes: readonly { card: CardId; took: boolean }[], id: CardId): number {
  const c = card(id);
  if (c.kind !== "number") return 0;
  if (view.laid[taker] !== null) return findHits([id], view.laid).length > 0 ? HIT : 0;
  const reqs = PHASES[view.phase[taker] as number] ?? [];
  if (reqs.length === 0) return 0;
  // Per value and per coat: how many taken since the last one given up (0 = given up).
  const values = new Map<number, number>();
  const coats = new Map<string, number>();
  for (const note of notes) {
    const seen = card(note.card);
    if (seen.kind !== "number") continue;
    values.set(seen.value, note.took ? (values.get(seen.value) ?? 0) + 1 : 0);
    coats.set(seen.coat, note.took ? (coats.get(seen.coat) ?? 0) + 1 : 0);
  }
  const known = (count: number | undefined): number => (count === 0 ? -1 : (count ?? 0));
  const wants = reqs.map((req) => {
    if (req.kind === "set") return known(values.get(c.value));
    if (req.kind === "coat") return known(coats.get(c.coat));
    return values.get(c.value) === 0 ? -1 : runFit(values, c.value, req.size);
  });
  return Math.max(...wants);
}

/**
 * For a run of `size`: the most values the seat collected that fit one run
 * with `value`. 0 when it already took that value: a run needs only one.
 */
function runFit(values: ReadonlyMap<number, number>, value: number, size: number): number {
  if (values.has(value)) return 0;
  let most = 0;
  for (let start = Math.max(1, value - size + 1); start <= Math.min(value, MAX_VALUE + 1 - size); start++) {
    let fit = 0;
    for (let v = start; v < start + size; v++) if ((values.get(v) ?? 0) > 0) fit++;
    most = Math.max(most, fit);
  }
  return most;
}

/** How many notes each seat's log keeps: the recent table, the way a person remembers it. */
export const LOG_PER_SEAT = 24;

/**
 * `log` after one accepted action. It reads only what everyone at the table
 * saw: `top`, the face-up discard before the action, and the action's events
 * as any device receives them. A seat that takes the discard took it; one that
 * draws from the deck instead passed `top` up; a discard is thrown away. Only
 * number cards are noted. A new round starts a new log; undefined while a
 * round has nothing in it.
 */
export function noteDiscards(
  log: DiscardLog | undefined,
  round: number,
  seats: number,
  top: CardId | null,
  events: readonly GameEvent[],
): DiscardLog | undefined {
  let out = log?.round === round ? log : undefined;
  let copied = false;
  const note = (seat: Seat, id: CardId | null | undefined, took: boolean): void => {
    if (id === null || id === undefined || card(id).kind !== "number") return;
    if (!copied) {
      out = { round, seats: Array.from({ length: seats }, (_, s) => [...(out?.seats[s] ?? [])]) };
      copied = true;
    }
    const mine = (out as DiscardLog).seats[seat] as { card: CardId; took: boolean }[];
    mine.push({ card: id, took });
    if (mine.length > LOG_PER_SEAT) mine.shift();
  };
  for (const event of events) {
    if (event.kind === "drew") note(event.seat, event.from === "discard" ? event.card : top, event.from === "discard");
    else if (event.kind === "discarded") note(event.seat, event.card, false);
  }
  return out;
}

/**
 * The seat to skip: highest phase, then fewest cards in hand, then the rng.
 * Seats already skipped are not valid targets; null when none remain.
 */
function skipTarget(view: CatTowerView, seat: Seat, rng: Rng): Seat | null {
  const targets = view.phase
    .map((_, other) => other)
    .filter((other) => other !== seat && !view.pendingSkip[other] && !view.forfeited[other]);
  if (targets.length === 0) return null;
  const leaders = cheapest(targets, (other) => -(view.phase[other] as number));
  const fewest = cheapest(leaders, (other) => view.handCounts[other] as number);
  return pick(fewest, rng);
}
