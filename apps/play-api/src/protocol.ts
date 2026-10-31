import { ROOM_CODE_ALPHABET } from "./room/codes";

import type { Action, ApplyError, GameEvent, Seat } from "./rules/engine";
import type { CatTowerView } from "./rules/view";

export { ROOM_CODE_ALPHABET };

export const PROTOCOL_VERSION = 1;

/** Largest accepted client message, in UTF-8 bytes. */
const MAX_MESSAGE_BYTES = 8192;

export type Person = {
  /** UUID generated on the device. */
  id: string;
  /** 1-20 characters, trimmed. */
  name: string;
  /** Cat avatar, 0-7. */
  cat: number;
};

export type Presence = "awake" | "away" | "asleep";
export type SeatKind = "open" | "closed" | "human" | "bot";
export type RoomStatus = "lobby" | "playing" | "over";

export type RoomView = {
  code: string;
  status: RoomStatus;
  youAreHost: boolean;
  seats: {
    kind: SeatKind;
    person?: Person;
    yours: boolean;
    presence: Presence | null;
  }[];
  game: CatTowerView | null;
};

export type RoomEvent =
  | { kind: "presence"; seat: Seat; presence: Presence }
  | { kind: "game"; event: GameEvent };

export type ClientMessage =
  | { t: "claim"; seat: Seat; person: Person }
  | { t: "configure"; seat: Seat; kind: "open" | "bot" | "closed" }
  | { t: "start" }
  | { t: "act"; seat: Seat; action: Action }
  | { t: "presence"; state: "active" | "background" }
  | { t: "moveSeat"; seat: Seat }
  | { t: "claimMove"; code: string }
  | { t: "leave"; seat: Seat };

/** Every `error` code the server sends. */
export type ErrorCode =
  // Any message.
  | "bad_message"
  | "internal"
  // Lobby and seats.
  | "not_lobby"
  | "in_game"
  | "bad_seat"
  | "seat_taken"
  | "person_seated"
  | "not_seated"
  | "not_your_seat"
  | "seats_open"
  | "not_enough_players"
  // Moving a seat to another device.
  | "game_over"
  | "bad_code"
  | "too_many_attempts"
  // Playing.
  | "not_playing"
  | ApplyError
  // Sent to the whole room, unprompted.
  | "bot_stalled"
  | "room_closed";

export type ServerMessage =
  | { t: "snapshot"; protocol: typeof PROTOCOL_VERSION; seq: number; room: RoomView }
  | { t: "event"; seq: number; event: RoomEvent }
  | { t: "moveCode"; seat: Seat; code: string }
  | { t: "error"; code: ErrorCode };

export type BadMessage = { error: "bad_message" };

const BAD: BadMessage = { error: "bad_message" };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MOVE_CODE_LENGTH = 6;
const MAX_CARD = 107;
const MAX_GROUPS = 2;
const MAX_GROUP_CARDS = 12;
const MAX_NAME = 20;
const MAX_CAT = 7;

type Obj = Record<string, unknown>;

const isObj = (v: unknown): v is Obj =>
  typeof v === "object" && v !== null && !Array.isArray(v);

/** True when `o` has every `required` key and no keys beyond `required` + `optional`. */
function hasKeys(o: Obj, required: string[], optional: string[] = []): boolean {
  const keys = Object.keys(o);
  return (
    required.every((k) => keys.includes(k)) &&
    keys.every((k) => required.includes(k) || optional.includes(k))
  );
}

const isInt = (v: unknown, min: number, max = Number.MAX_SAFE_INTEGER): v is number =>
  typeof v === "number" && Number.isInteger(v) && v >= min && v <= max;

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

function parseAction(a: unknown): Action | null {
  if (!isObj(a)) return null;
  switch (a.type) {
    case "draw":
      if (!hasKeys(a, ["type", "from"]) || (a.from !== "deck" && a.from !== "discard")) return null;
      return { type: "draw", from: a.from };
    case "nextRound":
      return hasKeys(a, ["type"]) ? { type: "nextRound" } : null;
    case "discard": {
      if (!hasKeys(a, ["type", "card"], ["skipTarget"]) || !isCard(a.card)) return null;
      if (!("skipTarget" in a)) return { type: "discard", card: a.card };
      if (!isInt(a.skipTarget, 0)) return null;
      return { type: "discard", card: a.card, skipTarget: a.skipTarget };
    }
    case "hit": {
      if (!hasKeys(a, ["type", "card", "target"]) || !isCard(a.card)) return null;
      const t = a.target;
      if (!isObj(t) || !hasKeys(t, ["seat", "group"]) || !isInt(t.seat, 0) || !isInt(t.group, 0)) return null;
      return { type: "hit", card: a.card, target: { seat: t.seat, group: t.group } };
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

function parsePerson(p: unknown): Person | null {
  if (!isObj(p) || !hasKeys(p, ["id", "name", "cat"])) return null;
  const { id, name, cat } = p;
  if (typeof id !== "string" || !UUID.test(id)) return null;
  if (typeof name !== "string") return null;
  const trimmed = name.trim();
  if (trimmed.length < 1 || trimmed.length > MAX_NAME) return null;
  if (!isInt(cat, 0, MAX_CAT)) return null;
  return { id, name: trimmed, cat };
}

function isMoveCode(code: unknown): code is string {
  return (
    typeof code === "string" &&
    code.length === MOVE_CODE_LENGTH &&
    [...code].every((ch) => ROOM_CODE_ALPHABET.includes(ch))
  );
}

function parseObject(o: Obj): ClientMessage | null {
  switch (o.t) {
    case "start":
      return hasKeys(o, ["t"]) ? { t: "start" } : null;
    case "presence":
      if (!hasKeys(o, ["t", "state"]) || (o.state !== "active" && o.state !== "background")) return null;
      return { t: "presence", state: o.state };
    case "leave":
    case "moveSeat":
      if (!hasKeys(o, ["t", "seat"]) || !isInt(o.seat, 0)) return null;
      return { t: o.t, seat: o.seat };
    case "configure":
      if (!hasKeys(o, ["t", "seat", "kind"]) || !isInt(o.seat, 0)) return null;
      if (o.kind !== "open" && o.kind !== "bot" && o.kind !== "closed") return null;
      return { t: "configure", seat: o.seat, kind: o.kind };
    case "claim": {
      if (!hasKeys(o, ["t", "seat", "person"]) || !isInt(o.seat, 0)) return null;
      const person = parsePerson(o.person);
      return person ? { t: "claim", seat: o.seat, person } : null;
    }
    case "claimMove":
      if (!hasKeys(o, ["t", "code"]) || !isMoveCode(o.code)) return null;
      return { t: "claimMove", code: o.code };
    case "act": {
      if (!hasKeys(o, ["t", "seat", "action"]) || !isInt(o.seat, 0)) return null;
      const action = parseAction(o.action);
      return action ? { t: "act", seat: o.seat, action } : null;
    }
    default:
      return null;
  }
}

/**
 * Parses and fully validates a client frame. This is the only guard in front
 * of the rules engine, which trusts the shape of every action it receives.
 */
export function parseClientMessage(raw: string): ClientMessage | BadMessage {
  if (new TextEncoder().encode(raw).length > MAX_MESSAGE_BYTES) return BAD;
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return BAD;
  }
  if (!isObj(value)) return BAD;
  return parseObject(value) ?? BAD;
}
