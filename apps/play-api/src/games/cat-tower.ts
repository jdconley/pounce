import { chooseAction } from "../bots/house-cat";
import { card } from "../rules/cards";
import {
  applyAction,
  newGame,
  type Action,
  type ApplyError,
  type CatTowerState,
  type GameEvent,
  type Seat,
} from "../rules/engine";
import { eventFor, viewFor, type CatTowerView } from "../rules/view";
import { hasKeys, isInt, isObj } from "../shape";

import type { GameModule } from "./module";

const MAX_CARD = 107;
const MAX_GROUPS = 2;
const MAX_GROUP_CARDS = 12;

const isCard = (v: unknown): v is number => isInt(v, 0, MAX_CARD);

function parseGroup(g: unknown): { cards: number[]; runStart?: number } | null {
  if (!isObj(g) || !hasKeys(g, ["cards"], ["runStart"])) return null;
  const { cards, runStart } = g;
  if (!Array.isArray(cards) || cards.length < 1 || cards.length > MAX_GROUP_CARDS) return null;
  if (!cards.every(isCard)) return null;
  if (!("runStart" in g)) return { cards: [...cards] };
  if (!isInt(runStart, 1, 12)) return null;
  return { cards: [...cards], runStart };
}

/** A Cat Tower action off the wire, or null. The engine trusts the shape of what this returns. */
export function parseAction(a: unknown): Action | null {
  if (!isObj(a)) return null;
  switch (a.type) {
    case "draw":
      if (!hasKeys(a, ["type", "from"]) || (a.from !== "deck" && a.from !== "discard")) return null;
      return { type: "draw", from: a.from };
    case "nextRound":
      return hasKeys(a, ["type"]) ? { type: "nextRound" } : null;
    case "forfeit":
      return hasKeys(a, ["type"]) ? { type: "forfeit" } : null;
    case "discard": {
      if (!hasKeys(a, ["type", "card"], ["skipTarget"]) || !isCard(a.card)) return null;
      if (!("skipTarget" in a)) return { type: "discard", card: a.card };
      if (!isInt(a.skipTarget, 0)) return null;
      return { type: "discard", card: a.card, skipTarget: a.skipTarget };
    }
    case "hit": {
      if (!hasKeys(a, ["type", "card", "target"], ["side"]) || !isCard(a.card)) return null;
      const t = a.target;
      if (!isObj(t) || !hasKeys(t, ["seat", "group"]) || !isInt(t.seat, 0) || !isInt(t.group, 0)) return null;
      const hit = { type: "hit" as const, card: a.card, target: { seat: t.seat, group: t.group } };
      if (!("side" in a)) return hit;
      // Which end of a run the card goes on; older clients leave it out.
      if (a.side !== "start" && a.side !== "end") return null;
      return { ...hit, side: a.side };
    }
    case "layDown": {
      if (!hasKeys(a, ["type", "groups"])) return null;
      const { groups } = a;
      if (!Array.isArray(groups) || groups.length < 1 || groups.length > MAX_GROUPS) return null;
      const parsed = groups.map(parseGroup);
      if (parsed.some((g) => g === null)) return null;
      return { type: "layDown", groups: parsed as { cards: number[]; runStart?: number }[] };
    }
    default:
      return null;
  }
}

/**
 * Draw from the deck; when playing, discard a number card, else Yarn, else
 * whatever is left (a Cucumber, aimed the way the engine requires).
 */
function fallbackAction(game: CatTowerState, seat: Seat): Action {
  if (game.step === "draw") return { type: "draw", from: "deck" };
  const hand = game.hands[seat] as number[];
  const pick =
    hand.find((id) => card(id).kind === "number") ??
    hand.find((id) => card(id).kind === "yarn") ??
    (hand[0] as number);
  const target = Array.from({ length: game.seats }, (_, i) => i).find(
    (i) => i !== seat && !game.pendingSkip[i] && game.forfeited?.[i] !== true,
  );
  return card(pick).kind === "cucumber" && target !== undefined
    ? { type: "discard", card: pick, skipTarget: target }
    : { type: "discard", card: pick };
}

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
  // Nor is a forfeit: it moves the turn on, but nobody played (§5.13).
  endsTurn: (a, events, seat) =>
    a.type !== "nextRound" &&
    a.type !== "forfeit" && events.some((e) => e.kind === "turn" || (e.kind === "roundOver" && e.wentOut === seat)),
  parseAction,
  phase: (s) => (s.status === "playing" ? "playing" : s.status === "roundOver" ? "between" : "over"),
  // Any seat may deal the next round; the room does it after a pause.
  betweenAction: { type: "nextRound" },
  forfeitAction: { type: "forfeit" },
  forfeited: (s) => s.forfeited ?? [],
  turnKey: (s) => `${s.round}:${s.turn}`,
  startsTurn: (e) => e.kind === "turn" || e.kind === "roundStarted",
  fallbackAction,
  progress: (s) => s.phase,
  progressKind: "shelf",
};
