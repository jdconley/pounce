import {
  apply,
  finish,
  create,
  CHOOSE_MS,
  endsTurn,
  type PurrAction,
  type PurrError,
  type PurrEvent,
  type PurrOptions,
  type PurrState,
} from "../purrtrait/engine";
import { checkInk, compact, freshEasel, INK_PER_SECOND, wipes, type InkEasel, type InkOp } from "../purrtrait/ink";
import { DEFAULT_OPTIONS, isRoomOnly, parseAction, parseOptions, parseRoomAction } from "../purrtrait/parse";
import { turnKey, view, type PurrView } from "../purrtrait/view";

import type { GameModule } from "./module";

/** Purrtrait, the draw-and-guess game for a TV and phones (design 2026-11-26). Dealt only while `GAMES` lists it. */
export const purrtrait: GameModule<PurrState, PurrAction, PurrView, PurrEvent, PurrError, PurrOptions> = {
  id: "purrtrait",
  minSeats: 2,
  maxSeats: 10,
  create: (seats, seed, options) => create(seats, seed, options ?? DEFAULT_OPTIONS),
  defaultOptions: DEFAULT_OPTIONS,
  parseOptions,
  apply,
  view,
  kittenAware: true,
  sameRoom: true,
  stream: {
    perSecond: INK_PER_SECOND,
    audience: "screens+owner",
    key: (s) => (s.phase === "drawing" ? turnKey(s) : null),
    start: freshEasel,
    check(ops: readonly InkOp[], easel: InkEasel) {
      const r = checkInk(ops, easel);
      return r.ok ? { ok: true as const, tally: r.easel } : r;
    },
    compact,
    wipes,
  },
  // The word is in no event until the reveal, so every event is for everyone.
  filterEvent: (e) => e,
  currentActor: (s) => (s.phase === "choosing" || s.phase === "drawing" ? s.drawer : null),
  // There are no House Cats at this table; a room never asks.
  botAction: (s) => fallbackAction(s),
  endsTurn: (a, events) => endsTurn(a, events),
  parseAction,
  parseRoomAction,
  isRoomOnly,
  stall: (s) => finish(s, "stalled"),
  parseAim: () => null,
  aimAllowed: () => false,
  phase: (s) => (s.phase === "over" ? "over" : s.phase === "reveal" ? "between" : "playing"),
  turnLimitMs: (s) => (s.phase === "choosing" ? CHOOSE_MS : s.phase === "drawing" ? s.timer * 1000 : null),
  timeUpAction: { type: "timeUp" },
  betweenAction: { type: "nextTurn" },
  forfeitAction: { type: "forfeit" },
  forfeited: (s) => [...s.out],
  turnKey,
  startsTurn: (e) => e.type === "turn",
  fallbackAction: (s) => fallbackAction(s),
  progress: (s) => [...s.scores],
  progressKind: "score",
};

/** For the drawer seat. The drawer gives up; a drawer who has yet to pick takes the Easy word. */
function fallbackAction(s: PurrState): PurrAction {
  return s.phase === "choosing" ? { type: "choose", level: "easy" } : { type: "giveUp" };
}
