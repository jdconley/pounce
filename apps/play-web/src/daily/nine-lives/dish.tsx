/**
 * Nine Lives in the Daily Dish (the web host's contract, `../host.tsx`). The host draws the bar,
 * the clock, give up, the end and share; this is the board and its keys, talking to the server
 * only through the run session it is given. The TV's view is `watch.tsx`, loaded on its own.
 */
import { useMemo } from "preact/hooks";

import { NineLivesPlay } from "./play";

import type { NineLivesDriver } from "./local";
import type { BoardState, Puzzle } from "./model";
import type { DailyGame, DailyGameScreenProps } from "../host";
import type { NineLivesMove } from "@pounce/play-api/daily/nine-lives/grid";

/** What a hint reveals: cell `i` holds `d` (the server's `nineLives.hint`). */
export type Reveal = { i: number; d: number };

type Props = DailyGameScreenProps<Puzzle, BoardState, NineLivesMove, Reveal>;

/** The run session as the board's driver. */
export function driverFor(session: Props["session"]): NineLivesDriver {
  return {
    send: (move, urgent) => void session.send(move, { urgent }),
    hint: () => session.hint(),
    resyncs: (listener) =>
      session.subscribe((e) => {
        if (e.kind === "resync") listener(e.state);
      }),
  };
}

function Screen({ session, playing }: Props) {
  const driver = useMemo(() => driverFor(session), [session]);
  return <NineLivesPlay puzzle={session.start.puzzle} state={session.start.state} driver={driver} playing={playing} />;
}

const nineLives: DailyGame<Puzzle, BoardState, NineLivesMove, Reveal> = {
  id: "nine-lives",
  Screen,
  // The share card shows only the time and hints.
  share: () => null,
};

export default nineLives;
