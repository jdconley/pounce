/** A piece id in 0-105. Ids are the only piece representation on the wire. */
export type TileId = number;

/** The four suits: cat things, each with its own silhouette and colour (design spec §3). */
export type Suit = "fish" | "mouse" | "feather" | "bell";

export const SUITS: readonly Suit[] = ["fish", "mouse", "feather", "bell"];

export type Tile =
  | { id: TileId; kind: "number"; value: number; suit: Suit }
  | { id: TileId; kind: "yarn" };

/** The highest number on a piece. Runs stop here: nothing follows 13. */
export const MAX_VALUE = 13;
/** What a Yarn left on a rack costs at the end of the game. */
export const YARN_PENALTY = 30;

const PER_SUIT = 2 * MAX_VALUE;
const NUMBER_TILES = SUITS.length * PER_SUIT;
const SET_SIZE = NUMBER_TILES + 2;

/**
 * Ids 0-103 are numbers: suit = floor(id / 26), value = (id % 13) + 1, so each
 * number appears twice per suit (ids `n` and `n + 13` within a suit are twins).
 * 104 and 105 are Yarn (wild).
 */
export function tile(id: TileId): Tile {
  if (!isTileId(id)) throw new RangeError(`invalid piece id: ${String(id)}`);
  if (id >= NUMBER_TILES) return { id, kind: "yarn" };
  return {
    id,
    kind: "number",
    value: (id % MAX_VALUE) + 1,
    suit: SUITS[Math.floor(id / PER_SUIT)] as Suit,
  };
}

/** True for an integer that names one of the 106 pieces. */
export function isTileId(id: unknown): id is TileId {
  return typeof id === "number" && Number.isInteger(id) && id >= 0 && id < SET_SIZE;
}

export const isYarn = (id: TileId): boolean => id >= NUMBER_TILES;

export const ALL_TILE_IDS: readonly TileId[] = Array.from({ length: SET_SIZE }, (_, i) => i);

/** What a piece costs when it is left on a rack: its number, or 30 for a Yarn. */
export function rackPoints(id: TileId): number {
  const t = tile(id);
  return t.kind === "yarn" ? YARN_PENALTY : t.value;
}

/** A rack's total at the end of the game. */
export function rackTotal(rack: readonly TileId[]): number {
  return rack.reduce((sum, id) => sum + rackPoints(id), 0);
}
