import { hasKeys, isInt, isObj } from "../shape";

import type { Box, Hit } from "./box";
import type { Rot } from "./toys";

/**
 * Toy Tumble's live wire (spec §6.3 to §6.6, `docs/live-protocol.md`). JSON like the rest of the
 * protocol, with events as short arrays. None of it is room state: it is relayed live and never
 * stored.
 */

/** Positions may sit a little outside the box: a toy's cells are offsets in its own k by k box. */
const X_MIN = -3;
const X_MAX = 14;
const Y_MIN = -3;
const Y_MAX = 25;
const MAX_MS = 10 * 60_000;
const MAX_LANDED = 16;
const MAX_EVENTS = 64;
const MAX_SEAT = 5;
const MAX_SLOT = 5;
const MAX_ID = 2 ** 31 - 1;

/**
 * A device's events for its own box, in order:
 * - `["m", n, rot, x, y]` toy `n` is here (only the latest goes in a batch);
 * - `["l", n, rot, x, y, ms, landed]` toy `n` set down here at `ms` on the round clock, then the junk `landed` landed;
 * - `["a", id]` hit `id` applied, or junk `id`'s wait started;
 * - `["u", slot, seat]` the trick in `slot` used on `seat`.
 */
export type ClientEvent =
  | ["m", number, Rot, number, number]
  | ["l", number, Rot, number, number, number, number[]]
  | ["a", number]
  | ["u", number, number];
export type TumbleClient = { t: "tumble"; r: number; ev: ClientEvent[] };

/** One box's checked events, relayed to every other device and screen, `q` counting up per box. */
export type TumbleRelay = { t: "tumble"; r: number; s: number; q: number; ev: ClientEvent[] };
/** A hit's kind: a trick, junk from a clear, or `napped` (a trick spent on a napping box, for the animation only). */
export type HitKind = Hit["k"] | "junk" | "napped";
export type HitWire = { t: "tumbleHit"; r: number; id: number; from: number; to: number; k: HitKind; x?: Record<string, unknown> };
export type BoxSync = {
  s: number;
  box: Box;
  /** The last `q` relayed for this box. */
  q: number;
  /** For each waiting junk, in order, the ms left of its 2-second wait. */
  waitingLeft: number[];
  catnipLeft: number;
  napLeft: number;
  status: "ok" | "lag" | "out";
};
export type TumbleSync = { t: "tumbleSync"; r: number; boxes: BoxSync[] };
export type TumbleSeat = { t: "tumbleSeat"; r: number; s: number; st: "ok" | "lag" };
export type TumbleServer = TumbleRelay | HitWire | TumbleSync | TumbleSeat;

const isRot = (v: unknown): v is Rot => isInt(v, 0, 3);

function parseEvent(e: unknown): ClientEvent | null {
  if (!Array.isArray(e) || e.length === 0) return null;
  switch (e[0]) {
    case "m": {
      const [, n, rot, x, y] = e;
      return e.length === 5 && isInt(n, 0, MAX_ID) && isRot(rot) && isInt(x, X_MIN, X_MAX) && isInt(y, Y_MIN, Y_MAX) ? ["m", n, rot, x, y] : null;
    }
    case "l": {
      const [, n, rot, x, y, ms, landed] = e;
      if (e.length !== 7 || !isInt(n, 0, MAX_ID) || !isRot(rot) || !isInt(x, X_MIN, X_MAX) || !isInt(y, Y_MIN, Y_MAX) || !isInt(ms, 0, MAX_MS)) return null;
      if (!Array.isArray(landed) || landed.length > MAX_LANDED || !landed.every((id) => isInt(id, 0, MAX_ID))) return null;
      return ["l", n, rot, x, y, ms, [...landed] as number[]];
    }
    case "a": {
      const [, id] = e;
      return e.length === 2 && isInt(id, 0, MAX_ID) ? ["a", id] : null;
    }
    case "u": {
      const [, slot, seat] = e;
      return e.length === 3 && isInt(slot, 0, MAX_SLOT) && isInt(seat, 0, MAX_SEAT) ? ["u", slot, seat] : null;
    }
    default:
      return null;
  }
}

/** A client's `tumble` batch, fully checked for shape, or null. Whether its events are legal is the round's to say. */
export function parseTumble(raw: unknown): TumbleClient | null {
  if (!isObj(raw)) return null;
  if (!hasKeys(raw, ["t", "r", "ev"])) return null;
  if (raw.t !== "tumble" || !isInt(raw.r, 0, MAX_ID) || !Array.isArray(raw.ev) || raw.ev.length > MAX_EVENTS) return null;
  const ev: ClientEvent[] = [];
  for (const e of raw.ev) {
    const parsed = parseEvent(e);
    if (!parsed) return null;
    ev.push(parsed);
  }
  return { t: "tumble", r: raw.r, ev };
}
