import { chooseAction } from "../bots/house-cat-tiles";
import {
  applyAction,
  newGame,
  type TilesAction,
  type TilesError,
  type TilesEvent,
  type TilesState,
} from "../tiles/engine";
import { eventFor, viewFor, type TilesView } from "../tiles/view";

import type { GameModule } from "./module";

/** The tile game (working title "Tuna Tiles"). Not registered with rooms yet: nothing calls it. */
export const tiles: GameModule<TilesState, TilesAction, TilesView, TilesEvent, TilesError> = {
  id: "tiles",
  minSeats: 2,
  maxSeats: 4,
  create: newGame,
  apply: applyAction,
  view: viewFor,
  filterEvent: eventFor,
  currentActor: (s) => (s.status === "playing" ? s.turn : null),
  botAction: (s, seat, rng) => chooseAction(viewFor(s, [seat]), seat, rng),
  // Every turn is one submission, so a play, a draw and a pass each end it. A forfeit moves the
  // turn on too, but nobody played.
  endsTurn: (a, events, seat) =>
    a.type !== "forfeit" &&
    events.some((e) => (e.kind === "played" || e.kind === "drew" || e.kind === "passed") && e.seat === seat),
};
