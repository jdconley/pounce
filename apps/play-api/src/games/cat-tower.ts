import { chooseAction } from "../bots/house-cat";
import {
  applyAction,
  newGame,
  type Action,
  type ApplyError,
  type CatTowerState,
  type GameEvent,
} from "../rules/engine";
import { eventFor, viewFor, type CatTowerView } from "../rules/view";

import type { GameModule } from "./module";

export const catTower: GameModule<CatTowerState, Action, CatTowerView, GameEvent, ApplyError> = {
  id: "cat-tower",
  minSeats: 2,
  maxSeats: 6,
  create: newGame,
  apply: applyAction,
  view: viewFor,
  filterEvent: eventFor,
  currentActor: (s) => (s.status === "playing" ? s.turn : null),
  botAction: (s, seat, rng) => chooseAction(viewFor(s, [seat]), seat, rng),
  // A discard or going out ends a turn; drawing alone doesn't, and a new round's deal isn't anyone's turn.
  endsTurn: (a, events, seat) =>
    a.type !== "nextRound" && events.some((e) => e.kind === "turn" || (e.kind === "roundOver" && e.wentOut === seat)),
};
