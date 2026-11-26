import {
  actor,
  applyAction,
  DEFAULT_OPTIONS,
  newGame,
  plainAction,
  teamOf,
  type BirdAction,
  type BirdError,
  type BirdEvent,
  type BirdOptions,
  type BirdState,
} from "../birdwatch/engine";
import { parseAction, parseOptions } from "../birdwatch/parse";
import { eventFor, viewFor, type BirdView } from "../birdwatch/view";
import { chooseAction } from "../bots/house-cat-birdwatch";

import type { GameModule } from "./module";

/** Birdwatch, the trick-taking game with a nest and the Bird (design 2026-11-25). Dealt only while `GAMES` lists it. */
export const birdwatch: GameModule<BirdState, BirdAction, BirdView, BirdEvent, BirdError, BirdOptions> = {
  id: "birdwatch",
  minSeats: 4,
  maxSeats: 6,
  create: (seats, seed, options) => newGame(seats, seed, options ?? DEFAULT_OPTIONS),
  defaultOptions: DEFAULT_OPTIONS,
  parseOptions,
  apply: applyAction,
  view: viewFor,
  filterEvent: eventFor,
  currentActor: actor,
  botAction: (s, seat, rng) => chooseAction(viewFor(s, [seat]), seat, rng),
  // Every bid, pass, nest, trump, call and card is a whole turn; dealing the next hand is nobody's.
  endsTurn: (a) => a.type !== "nextHand" && a.type !== "forfeit",
  parseAction,
  // Nothing to point at yet: a screen shows the trick as it is played.
  parseAim: () => null,
  aimAllowed: () => false,
  phase: (s) => (s.status === "over" ? "over" : s.phase === "between" ? "between" : "playing"),
  betweenAction: { type: "nextHand" },
  forfeitAction: { type: "forfeit" },
  // A team game: a seat that leaves goes to a House Cat, and the room ends it only when nobody is left (§4.9).
  leaveTakeover: true,
  forfeited: (s) => new Array<boolean>(s.seats).fill(false),
  turnKey: (s) => `${s.hand}:${s.moves}`,
  startsTurn: (e) => e.kind === "turn",
  fallbackAction: plainAction,
  // Each seat's side's score: teammates show the same number (§8).
  progress: (s) => Array.from({ length: s.seats }, (_, seat) => s.scores[teamOf(s, seat)] as number),
  progressKind: "score",
};
