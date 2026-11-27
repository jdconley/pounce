/**
 * Nine Lives in the Daily Dish (the web host's contract, `../host.tsx`). The host draws the bar,
 * the clock, give up, the end and share; this is the board and its keys, talking to the server
 * only through the run session it is given. The TV's view is `watch.tsx`, loaded on its own.
 */
import { useMemo } from "preact/hooks";

import { NineLivesPlay } from "./play";

import type { NineLivesDriver } from "./local";
import type { BoardState, MoveReveal, Puzzle } from "./model";
import type { DailyGame, DailyGameScreenProps } from "../host";
import type { NineLivesMove } from "@pounce/play-api/daily/nine-lives/grid";

/** What a hint reveals: cell `i` holds `d` (the server's `nineLives.hint`). A move's: `MoveReveal`. */
export type Reveal = { i: number; d: number } | MoveReveal;

type Props = DailyGameScreenProps<Puzzle, BoardState, NineLivesMove, Reveal>;

const isMoveReveal = (r: Reveal): r is MoveReveal => "k" in r;

/** The run session as the board's driver. */
export function driverFor(session: Props["session"]): NineLivesDriver {
  return {
    send: (move, urgent) => session.send(move, { urgent }),
    hint: async () => {
      const r = await session.hint();
      return r && !isMoveReveal(r) ? r : null;
    },
    resyncs: (listener) =>
      session.subscribe((e) => {
        if (e.kind === "resync") listener(e.state);
      }),
    reveals: (listener) =>
      session.subscribe((e) => {
        if (e.kind === "accepted") for (const r of e.reveals) if (isMoveReveal(r)) listener(r);
      }),
  };
}

function Screen({ session, playing }: Props) {
  const driver = useMemo(() => driverFor(session), [session]);
  return <NineLivesPlay puzzle={session.start.puzzle} state={session.start.state} driver={driver} playing={playing} />;
}

/** Out of lives: the board fills in the solution for a moment before the end comes up. */
const OUT_OF_LIVES_MS = 2000;

const nineLives: DailyGame<Puzzle, BoardState, NineLivesMove, Reveal> = {
  id: "nine-lives",
  Screen,
  // The share card shows only the time and hints.
  share: () => null,
  endDelayMs: (result) => (result.outcome === "missed" ? OUT_OF_LIVES_MS : 0),
};

export default nineLives;
