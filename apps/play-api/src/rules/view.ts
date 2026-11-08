import type { CardId } from "./cards";
import type { CatTowerState, GameEvent, Seat } from "./engine";
import type { Group } from "./groups";

/** What one device may see: public table state plus the hands it controls. */
export type CatTowerView = {
  round: number;
  dealer: Seat;
  turn: Seat;
  step: "draw" | "play";
  status: CatTowerState["status"];
  deckCount: number;
  discardTop: CardId | null;
  discardCount: number;
  phase: number[];
  scores: number[];
  laid: (Group[] | null)[];
  handCounts: number[];
  /** Only the seats this device controls. */
  hands: Record<Seat, CardId[]>;
  pendingSkip: boolean[];
  winners: Seat[];
  /** Only on a game that ended early; see `CatTowerState.endReason`. */
  endReason?: CatTowerState["endReason"];
};

function copyGroup(group: Group): Group {
  return { ...group, cards: [...group.cards] };
}

/** Builds a device's view. Every array is a fresh copy, never a reference into `state`. */
export function viewFor(
  state: CatTowerState,
  controlled: readonly Seat[],
): CatTowerView {
  const hands: Record<Seat, CardId[]> = {};
  for (const seat of controlled) {
    const hand = Number.isInteger(seat) ? state.hands[seat] : undefined;
    if (hand) hands[seat] = [...hand];
  }
  return {
    round: state.round,
    dealer: state.dealer,
    turn: state.turn,
    step: state.step,
    status: state.status,
    deckCount: state.deck.length,
    discardTop: state.discard.at(-1) ?? null,
    discardCount: state.discard.length,
    phase: [...state.phase],
    scores: [...state.scores],
    laid: state.laid.map((groups) => (groups ? groups.map(copyGroup) : null)),
    handCounts: state.hands.map((hand) => hand.length),
    hands,
    pendingSkip: [...state.pendingSkip],
    winners: [...state.winners],
    ...(state.endReason === undefined ? {} : { endReason: state.endReason }),
  };
}

/**
 * Returns a copy of `event` safe to send to a device controlling `controlled`.
 * A card drawn from the deck is private to the drawer, so the `card` key is
 * omitted for everyone else. All other events carry only public information.
 */
export function eventFor(
  event: GameEvent,
  controlled: readonly Seat[],
): GameEvent {
  const copy = structuredClone(event);
  if (
    copy.kind === "drew" &&
    copy.from === "deck" &&
    !controlled.includes(copy.seat)
  ) {
    delete copy.card;
  }
  return copy;
}
