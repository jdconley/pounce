import { chooseAction } from "../bots/house-cat-tiles";
import {
  applyAction,
  newGame,
  type TilesAction,
  type TilesError,
  type TilesEvent,
  type TilesState,
} from "../tiles/engine";
import { parseAction } from "../tiles/parse";
import { eventFor, viewFor, type TilesView } from "../tiles/view";

import type { GameModule } from "./module";

/** The tile game (working title "Tuna Tiles"). Rooms deal it only while the `GAMES` flag lists it. */
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
  parseAction,
  // One round is one game: there is never a deal to wait for.
  phase: (s) => (s.status === "playing" ? "playing" : "over"),
  betweenAction: null,
  forfeitAction: { type: "forfeit" },
  forfeited: (s) => s.forfeited,
  // A forfeit on the seat's own turn moves the move on without a turn; the room's own count tells those apart.
  turnKey: (s) => String(s.turns),
  startsTurn: (e) => e.kind === "turn",
  fallbackAction: (s) => (s.pool.length > 0 ? { type: "draw" } : { type: "pass" }),
  progress: (s) => s.racks.map((rack) => rack.length),
  progressKind: "pieces",
};
