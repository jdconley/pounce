/**
 * A Tuna Tiles turn being built on this device (TilesDraft.swift): the table as the player is
 * rearranging it and what is left on their rack. Whether it can be played is the server's own
 * `checkPlay`, imported, so the web player never disagrees with the room.
 */
import { checkPlay, OPENING_POINTS, type PlayCheck } from "@pounce/play-api/tiles/engine";
import { tile, type TileId } from "@pounce/play-api/tiles/pieces";
import { readSet, sameSet } from "@pounce/play-api/tiles/sets";

import type { TilesAim } from "@pounce/play-api/protocol";

export type Draft = { table: TileId[][]; rack: TileId[] };

export const sameDraft = (a: Draft, b: Draft): boolean => JSON.stringify(a) === JSON.stringify(b);

/** Without empty sets. */
const tidy = (table: TileId[][]): TileId[][] => table.filter((set) => set.length > 0);

/** True for a piece that came from the rack this turn (it may go back). */
export const placedThisTurn = (base: readonly (readonly TileId[])[], id: TileId): boolean => !base.some((set) => set.includes(id));

/** Takes `id` out of wherever it is in the draft. */
function lift(d: Draft, id: TileId): Draft {
  return { table: d.table.map((set) => set.filter((x) => x !== id)), rack: d.rack.filter((x) => x !== id) };
}

/** Puts `id` into set `set` at `index` (the end when past it). */
export function toSet(d: Draft, id: TileId, set: number, index: number): Draft {
  const out = lift(d, id);
  const target = out.table[set];
  if (!target) return toNewSet(d, id);
  const at = Math.min(Math.max(index, 0), target.length);
  // Taking the piece out of the same set shifts the spot one left.
  const was = d.table[set]?.indexOf(id) ?? -1;
  const fixed = was >= 0 && was < at ? at - 1 : at;
  out.table[set] = [...target.slice(0, fixed), id, ...target.slice(fixed)];
  return { ...out, table: tidy(out.table) };
}

export function toNewSet(d: Draft, id: TileId): Draft {
  const out = lift(d, id);
  return { table: [...tidy(out.table), [id]], rack: out.rack };
}

export function toRack(d: Draft, id: TileId, index = Number.MAX_SAFE_INTEGER): Draft {
  const out = lift(d, id);
  const at = Math.min(Math.max(index, 0), out.rack.length);
  return { table: tidy(out.table), rack: [...out.rack.slice(0, at), id, ...out.rack.slice(at)] };
}

export function sortRack(rack: readonly TileId[], by: "number" | "toy"): TileId[] {
  const key = (id: TileId) => {
    const t = tile(id);
    if (t.kind === "yarn") return [99, 99, id];
    const suit = ["fish", "mouse", "feather", "bell"].indexOf(t.suit);
    return by === "number" ? [t.value, suit, id] : [suit, t.value, id];
  };
  return [...rack].sort((a, b) => {
    const [x, y] = [key(a), key(b)];
    return x[0] - y[0] || x[1] - y[1] || x[2] - y[2];
  });
}

export type DraftCheck = {
  changed: boolean;
  check: PlayCheck | null;
  /** Points of the sets this turn adds, while the player hasn't opened. */
  opening: number | null;
  /** Per set: valid, invalid, or as it was. */
  marks: ("good" | "bad" | "kept")[];
};

/** What the draft amounts to: changed or not, playable or why not, the opening's points. */
export function checkDraft(base: readonly (readonly TileId[])[], startRack: readonly TileId[], opened: boolean, d: Draft): DraftCheck {
  const changed = JSON.stringify(base) !== JSON.stringify(d.table);
  const marks = d.table.map((set) => {
    if (base.some((old) => sameSet(old, set))) return "kept" as const;
    return readSet(set) ? ("good" as const) : ("bad" as const);
  });
  let opening: number | null = null;
  if (!opened) {
    opening = d.table.reduce((sum, set) => (base.some((old) => sameSet(old, set)) ? sum : sum + (readSet(set)?.points ?? 0)), 0);
  }
  return { changed, check: changed ? checkPlay(base, startRack, opened, d.table) : null, opening, marks };
}

export { OPENING_POINTS };

/** The number a Yarn stands for where it sits, if its set says. */
export function ghostOf(set: readonly TileId[], index: number): number | null {
  const reading = readSet(set);
  if (!reading) return null;
  return reading.kind === "run" ? reading.start + index : reading.value;
}

/** The most sets, and pieces in a set, an aim may carry (docs/tv-protocol.md, `aim`). */
export const AIM_MAX_SETS = 60;
export const AIM_MAX_SET = 13;
/** Piece ids run 0 to this. */
const MAX_ID = 105;

/**
 * What the draft tells the TV: the whole table as the player is arranging it, without empty
 * sets. Null when it is the table as played (nothing to show), and null for anything the wire
 * refuses: more than 60 sets, a set over 13, a piece twice or no piece at all. Such a draft is
 * never sent; the last one sent stands.
 */
export function tilesAimOf(draft: readonly (readonly TileId[])[], server: readonly (readonly TileId[])[]): TilesAim | null {
  const table = draft.filter((set) => set.length > 0).map((set) => [...set]);
  if (JSON.stringify(table) === JSON.stringify(tidy(server.map((s) => [...s])))) return null;
  if (table.length > AIM_MAX_SETS) return null;
  const seen = new Set<TileId>();
  for (const set of table) {
    if (set.length > AIM_MAX_SET) return null;
    for (const id of set) {
      if (!Number.isInteger(id) || id < 0 || id > MAX_ID || seen.has(id)) return null;
      seen.add(id);
    }
  }
  return { table };
}
