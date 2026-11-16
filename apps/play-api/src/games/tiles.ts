import { chooseAction } from "../bots/house-cat-tiles";
import { hasKeys, isObj } from "../shape";
import {
  applyAction,
  newGame,
  type TilesAction,
  type TilesError,
  type TilesEvent,
  type TilesState,
} from "../tiles/engine";
import { parseAction } from "../tiles/parse";
import { isTileId, MAX_VALUE, type TileId } from "../tiles/pieces";
import { eventFor, viewFor, type TilesView } from "../tiles/view";

import type { GameModule } from "./module";
import type { TilesAim } from "../protocol";

/** A draft may hold loose pieces too, so it can pass the 35 sets a played table is held to. */
const MAX_AIM_SETS = 60;

/**
 * A tile aim off the wire, or null: a draft table, sets of piece ids with none twice. Pieces
 * can't repeat, so the total can't pass the number of pieces there are.
 */
function parseAim(raw: unknown): TilesAim | null {
  if (!isObj(raw) || !hasKeys(raw, ["table"])) return null;
  const { table } = raw;
  if (!Array.isArray(table) || table.length > MAX_AIM_SETS) return null;
  const seen = new Set<TileId>();
  const sets: TileId[][] = [];
  for (const set of table as unknown[]) {
    if (!Array.isArray(set) || set.length < 1 || set.length > MAX_VALUE || !set.every(isTileId)) return null;
    for (const id of set) {
      if (seen.has(id)) return null;
      seen.add(id);
    }
    sets.push([...set]);
  }
  return { table: sets };
}

/** The tile game (working title "Tuna Tiles"). Rooms deal it only while the `GAMES` flag lists it. */
export const tiles: GameModule<TilesState, TilesAction, TilesView, TilesEvent, TilesError> = {
  id: "tiles",
  minSeats: 2,
  maxSeats: 4,
  create: newGame,
  apply: applyAction,
  view: viewFor,
  filterEvent: eventFor,
  currentActor: (s) => (s.status === "playing" ? s.turn : null),
  botAction: (s, seat, rng) => chooseAction(viewFor(s, [seat]), seat, rng),
  // Every turn is one submission, so a play, a draw and a pass each end it. A forfeit moves the
  // turn on too, but nobody played.
  endsTurn: (a, events, seat) =>
    a.type !== "forfeit" &&
    events.some((e) => (e.kind === "played" || e.kind === "drew" || e.kind === "passed") && e.seat === seat),
  parseAction,
  parseAim,
  // A draft may use the table and this seat's own rack: never another seat's rack or the pool.
  aimAllowed: (s, seat, aim) => {
    const here = new Set<TileId>([...s.table.flat(), ...(s.racks[seat] as TileId[])]);
    return (aim as TilesAim).table.every((set) => set.every((id) => here.has(id)));
  },
  // One round is one game: there is never a deal to wait for.
  phase: (s) => (s.status === "playing" ? "playing" : "over"),
  betweenAction: null,
  forfeitAction: { type: "forfeit" },
  forfeited: (s) => s.forfeited,
  // A forfeit on the seat's own turn moves the move on without a turn; the room's own count tells those apart.
  turnKey: (s) => String(s.turns),
  startsTurn: (e) => e.kind === "turn",
  fallbackAction: (s) => (s.pool.length > 0 ? { type: "draw" } : { type: "pass" }),
  progress: (s) => s.racks.map((rack) => rack.length),
  progressKind: "pieces",
};
