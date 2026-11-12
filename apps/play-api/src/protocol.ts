import { parseAction as parseCatTowerAction } from "./games/cat-tower";
import { nameAllowed } from "./names/filter";
import { ROOM_CODE_ALPHABET } from "./room/codes";
import { parseRoomName } from "./room/names";
import { hasKeys, isInt, isObj, type Obj } from "./shape";
import { isBack, isRug } from "./streaks/catalog";

import type { GameAction, GameError, GameId } from "./games";
import type { GameEvent, Seat } from "./rules/engine";
import type { CatTowerView } from "./rules/view";
import type { StreakView } from "./streaks/pair-core";
import type { TilesEvent } from "./tiles/engine";
import type { TilesView } from "./tiles/view";

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
/** A seat whose phone's connection is poor ("weak") or gone mid-game ("lost"). Absent: fine. */
export type SeatLink = "weak" | "lost";
export type SeatKind = "open" | "closed" | "human" | "bot";
export type RoomStatus = "lobby" | "playing" | "over";

export type RoomView = {
  code: string;
  /** The table's name, shown on every phone: 1-30 characters (see `parseRoomName`). */
  name: string;
  status: RoomStatus;
  youAreHost: boolean;
  seats: {
    kind: SeatKind;
    person?: Person;
    yours: boolean;
    presence: Presence | null;
    /** Only with `LINK` on, while playing, and only when not fine. */
    link?: SeatLink;
  }[];
  /** Cat Tower's view of the game. Null in the lobby, and in a room of any other game. */
  game: CatTowerView | null;
  /**
   * The room's game, in a room of any game but Cat Tower: its view is then under the key of the
   * same name (`tiles`), never under `game`. Absent in a Cat Tower room, whose snapshots are as
   * they always were. Only an app that lists the game (`X-Pounce-Games`) is let into such a room.
   */
  gameId?: Exclude<GameId, "cat-tower">;
  /** The tile game's view, in a `tiles` room once it is dealt. */
  tiles?: TilesView;
  /** The table's rug and card back (§9.4). Only while streaks are on. */
  look?: { rug: string; back: string };
  /** The code of the table "Play again" dealt (§10.4), once there is one. */
  rematch?: string;
  /**
   * With `LINK` on: the server takes `{"t":"ping"}` heartbeats every `ping` ms
   * and move ids, and `acks` are the ids of this device's moves it applied
   * lately (oldest first), so an app can tell a move that got through from one
   * to send again after a reconnect.
   */
  link?: { ping: number; acks: string[] };
  /**
   * With `NUDGE` on, while a person on another phone holds the move: whether this device may
   * nudge them (`ClientMessage` `nudge`). `sent`: it already did this turn. `wait`: ms until it
   * may (0: now), counted from when this snapshot was sent.
   */
  nudge?: NudgeView;
  /**
   * While a person on another phone holds the move: the seat this device may retire once the
   * move has waited long enough (`ClientMessage` `retire`). `wait`: ms until it may (0: now),
   * counted from when this snapshot was sent.
   */
  retire?: RetireView;
};

export type NudgeView = { seat: Seat; sent: boolean; wait: number };
export type RetireView = { seat: Seat; wait: number };

export type RoomEvent =
  | { kind: "presence"; seat: Seat; presence: Presence }
  /** A Cat Tower event. */
  | { kind: "game"; event: GameEvent }
  /** A tile game event. The two games share event names, so each has a kind of its own. */
  | { kind: "tiles"; event: TilesEvent }
  /** Someone at the table changed its look; `seat` is theirs, for the pill with their cat (§9.4). */
  | { kind: "look"; seat: Seat; rug: string; back: string };

export type ClientMessage =
  | { t: "claim"; seat: Seat; person: Person }
  | { t: "configure"; seat: Seat; kind: "open" | "bot" | "closed" }
  | { t: "start" }
  /** `id`: the app's move id, so a move sent twice (after a reconnect) is applied once. */
  | { t: "act"; seat: Seat; action: GameAction; id?: string }
  | { t: "presence"; state: "active" | "background" }
  | { t: "moveSeat"; seat: Seat }
  | { t: "claimMove"; code: string }
  | { t: "leave"; seat: Seat }
  | { t: "rename"; name: string }
  | { t: "renameSeat"; seat: Seat; name: string }
  | { t: "rematch" }
  | { t: "setLook"; rug?: string; back?: string }
  /** A heartbeat. The room answers `{"t":"pong"}` without waking (WebSocket auto-response). */
  | { t: "ping" }
  /** The app's own view of its connection: round trips slow or not. */
  | { t: "link"; state: "weak" | "good" }
  /** Asks the person in `seat`, whose move it is, to take it (`NUDGE`). */
  | { t: "nudge"; seat: Seat }
  /**
   * Forfeits `seat` for its holder, whose move has waited days: from anyone else still in the
   * game. Errors: `not_their_turn`, `too_soon`.
   */
  | { t: "retire"; seat: Seat };

/** Every `error` code the server sends. */
export type ErrorCode =
  // Any message.
  | "bad_message"
  // A person's or a table's name the name filter refuses (or, from a kitten, one that isn't generated).
  | "bad_name"
  // Not for this device: a kitten renaming the table.
  | "not_allowed"
  // The table's host blocked this player.
  | "blocked"
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
  | GameError
  // Sent to the whole room, unprompted.
  | "bot_stalled"
  | "room_closed"
  // Play again and table looks.
  | "not_over"
  | "too_soon"
  | "not_unlocked"
  // Nudges ("too_soon" too: the wait or the cooldown isn't over, or this turn's is sent).
  | "not_their_turn";

export type ServerMessage =
  | { t: "snapshot"; protocol: typeof PROTOCOL_VERSION; seq: number; room: RoomView }
  | { t: "event"; seq: number; event: RoomEvent }
  | { t: "moveCode"; seat: Seat; code: string }
  | { t: "error"; code: ErrorCode }
  /** A pair's streak after a turn (§13.3), for `person`, one of the people this device speaks for. */
  | { t: "streak"; pair: string; person: string; view: StreakView }
  /** "Play again" dealt a new table (§10.4). */
  | { t: "rematch"; code: string }
  /** The answer to `{"t":"ping"}`. */
  | { t: "pong" }
  /** Every seat's link (null: fine) whenever one changes; not a state change, so no seq. */
  | { t: "link"; seats: (SeatLink | null)[] }
  /** To the nudging device: the nudge to `seat` went (not a state change, so no seq). */
  | { t: "nudgeSent"; seat: Seat }
  /** To the devices of the person in `seat`: the person in `from` nudged them (no seq). */
  | { t: "nudged"; seat: Seat; from: Seat };

export type BadMessage = { error: "bad_message" | "bad_name" };

const BAD: BadMessage = { error: "bad_message" };
const BAD_NAME: BadMessage = { error: "bad_name" };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MOVE_CODE_LENGTH = 6;
const MAX_NAME = 20;
const MAX_CAT = 7;
/** A move id: what the app makes (a UUID), or anything short and plain. */
const MOVE_ID = /^[A-Za-z0-9_-]{1,64}$/;

/** Control characters, line and paragraph separators, and bidi overrides and isolates. */
const FORBIDDEN = /[\p{Cc}\u2028\u2029\u202A-\u202E\u2066-\u2069]/u;

/**
 * A person's name trimmed, or null when it is not a string of 1-20 characters after trimming, or
 * has a control character. The name filter (`nameAllowed`) is a separate check, so a refused name
 * gets its own error.
 */
export function parseName(name: unknown): string | null {
  if (typeof name !== "string") return null;
  const trimmed = name.trim();
  return trimmed.length < 1 || trimmed.length > MAX_NAME || FORBIDDEN.test(trimmed) ? null : trimmed;
}

function parsePerson(p: unknown): Person | null {
  if (!isObj(p) || !hasKeys(p, ["id", "name", "cat"])) return null;
  const { id, cat } = p;
  if (typeof id !== "string" || !UUID.test(id)) return null;
  const name = parseName(p.name);
  if (name === null) return null;
  if (!isInt(cat, 0, MAX_CAT)) return null;
  return { id, name, cat };
}

function isMoveCode(code: unknown): code is string {
  return (
    typeof code === "string" &&
    code.length === MOVE_CODE_LENGTH &&
    [...code].every((ch) => ROOM_CODE_ALPHABET.includes(ch))
  );
}

/** `message` unless one of its names is refused by the name filter. */
function named(message: ClientMessage | null, name: string | undefined): ClientMessage | BadMessage | null {
  return message && name !== undefined && !nameAllowed(name) ? BAD_NAME : message;
}

function parseObject(o: Obj, parseAction: ActionParser): ClientMessage | BadMessage | null {
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
      return named(person ? { t: "claim", seat: o.seat, person } : null, person?.name);
    }
    case "rename": {
      if (!hasKeys(o, ["t", "name"])) return null;
      const name = parseRoomName(o.name);
      return named(name === null ? null : { t: "rename", name }, name ?? undefined);
    }
    case "renameSeat": {
      if (!hasKeys(o, ["t", "seat", "name"]) || !isInt(o.seat, 0)) return null;
      const name = parseName(o.name);
      return named(name === null ? null : { t: "renameSeat", seat: o.seat, name }, name ?? undefined);
    }
    case "rematch":
      return hasKeys(o, ["t"]) ? { t: "rematch" } : null;
    case "setLook": {
      if (!hasKeys(o, ["t"], ["rug", "back"]) || !("rug" in o || "back" in o)) return null;
      const { rug, back } = o;
      if ("rug" in o && !(typeof rug === "string" && isRug(rug))) return null;
      if ("back" in o && !(typeof back === "string" && isBack(back))) return null;
      return { t: "setLook", ...(typeof rug === "string" ? { rug } : {}), ...(typeof back === "string" ? { back } : {}) };
    }
    case "claimMove":
      if (!hasKeys(o, ["t", "code"]) || !isMoveCode(o.code)) return null;
      return { t: "claimMove", code: o.code };
    case "act": {
      if (!hasKeys(o, ["t", "seat", "action"], ["id"]) || !isInt(o.seat, 0)) return null;
      const action = parseAction(o.action);
      if (!action) return null;
      if (!("id" in o)) return { t: "act", seat: o.seat, action };
      // Older apps send no id.
      if (typeof o.id !== "string" || !MOVE_ID.test(o.id)) return null;
      return { t: "act", seat: o.seat, action, id: o.id };
    }
    case "ping":
      return hasKeys(o, ["t"]) ? { t: "ping" } : null;
    case "nudge":
      if (!hasKeys(o, ["t", "seat"]) || !isInt(o.seat, 0)) return null;
      return { t: "nudge", seat: o.seat };
    case "retire":
      if (!hasKeys(o, ["t", "seat"]) || !isInt(o.seat, 0)) return null;
      return { t: "retire", seat: o.seat };
    case "link":
      if (!hasKeys(o, ["t", "state"]) || (o.state !== "weak" && o.state !== "good")) return null;
      return { t: "link", state: o.state };
    default:
      return null;
  }
}

/** A game's own check of an `act` message's `action` (`GameModule.parseAction`). */
export type ActionParser = (raw: unknown) => GameAction | null;

/**
 * Parses and fully validates a client frame. This is the only guard in front
 * of the rules engine, which trusts the shape of every action it receives.
 * An `act` message's action is checked by `parseAction`, the room's game's own
 * parser; left out, Cat Tower's.
 * `bad_name`: well-formed, but a name in it is refused by the name filter.
 */
export function parseClientMessage(raw: string, parseAction: ActionParser = parseCatTowerAction): ClientMessage | BadMessage {
  if (new TextEncoder().encode(raw).length > MAX_MESSAGE_BYTES) return BAD;
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return BAD;
  }
  if (!isObj(value)) return BAD;
  return parseObject(value, parseAction) ?? BAD;
}
