import { hasKeys, isInt, isObj } from "../shape";

import type { PurrAction, PurrOptions } from "./engine";

export const DEFAULT_OPTIONS: PurrOptions = { timer: 60 };

/** Actions only the room sends: refused from a client. */
const ROOM_ONLY = new Set<PurrAction["type"]>(["timeUp", "nextTurn"]);

export const isRoomOnly = (a: PurrAction): boolean => ROOM_ONLY.has(a.type);

/**
 * Any Purrtrait action off the wire, room-only ones included (the room's own timers build theirs
 * as objects, but a test or a replay may need to parse them). Shape only.
 */
export function parseRoomAction(a: unknown): PurrAction | null {
  if (!isObj(a)) return null;
  switch (a.type) {
    case "giveUp":
    case "forfeit":
    case "timeUp":
    case "nextTurn":
      return hasKeys(a, ["type"]) ? { type: a.type } : null;
    case "choose":
      return hasKeys(a, ["type", "level"]) && (a.level === "easy" || a.level === "tricky") ? { type: "choose", level: a.level } : null;
    case "gotIt":
      return hasKeys(a, ["type", "seat"]) && isInt(a.seat, 0, 9) ? { type: "gotIt", seat: a.seat } : null;
    default:
      return null;
  }
}

/** A client's action: `timeUp` and `nextTurn` are the room's alone, so they are not actions here. */
export function parseAction(a: unknown): PurrAction | null {
  const parsed = parseRoomAction(a);
  return parsed !== null && !isRoomOnly(parsed) ? parsed : null;
}

/** A table's options off the wire (the lobby's timer), or null. */
export function parseOptions(raw: unknown): PurrOptions | null {
  if (!isObj(raw) || !hasKeys(raw, ["timer"])) return null;
  const { timer } = raw;
  return timer === 45 || timer === 60 || timer === 90 ? { timer } : null;
}
