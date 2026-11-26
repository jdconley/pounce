/**
 * Pickled: a Cucumber's target, from the discard that names them until the turn it cost them is
 * over. The server's `pendingSkip` says so until the skip comes; after it, the turn played in its
 * place still shows who was pickled, so a skip of the next seat (which passes at once) is seen.
 * Read from the events the table already plays: nothing new on the wire.
 */
import { useEffect, useState } from "preact/hooks";

import type { RoomStore } from "../store/room";
import type { GameEvent } from "@pounce/play-api/rules/engine";

/** The seats skipped, each with the turn played in its place (null until that turn starts). */
export type PickleWatch = ReadonlyMap<number, number | null>;

export const NO_PICKLES: PickleWatch = new Map();

/** The watch after `e`. */
export function pickleWatch(w: PickleWatch, e: GameEvent): PickleWatch {
  switch (e.kind) {
    case "skipped":
      return new Map(w).set(e.seat, null);
    case "turn": {
      if (w.size === 0) return w;
      // The first turn after a skip stands in for it; the next one ends it.
      const next = new Map<number, number | null>();
      for (const [seat, during] of w) if (during === null) next.set(seat, e.seat);
      return next;
    }
    case "forfeited": {
      if (!w.has(e.seat)) return w;
      const next = new Map(w);
      next.delete(e.seat);
      return next;
    }
    case "roundStarted":
    case "roundOver":
    case "gameOver":
      return w.size === 0 ? w : NO_PICKLES;
    default:
      return w;
  }
}

/** Who is pickled: waiting for their skip (`pendingSkip`), or in the turn played in its place. */
export const pickledSeats = (pendingSkip: readonly boolean[], w: PickleWatch): boolean[] => pendingSkip.map((p, s) => p || w.has(s));

/** Who is pickled at this table now, for anyone who draws its seats. */
export function usePickled(store: RoomStore, pendingSkip: readonly boolean[]): boolean[] {
  const [watch, setWatch] = useState<PickleWatch>(NO_PICKLES);
  useEffect(
    () =>
      store.subscribe({
        event: ({ event: e }) => {
          if (e.kind === "game") setWatch((w) => pickleWatch(w, e.event));
        },
      }),
    [store],
  );
  return pickledSeats(pendingSkip, watch);
}
