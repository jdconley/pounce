/**
 * Nine Lives in the Daily Dish (the web host's contract, `../host.tsx`). The host draws the bar,
 * the clock, give up, the end and share; this is the board and its keys, talking to the server
 * only through the run session it is given.
 */
import { useMemo } from "preact/hooks";

import { NineLivesPlay } from "./play";
import { NineLivesWatch } from "./watch";

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

/**
 * The TV's view of a run. The server sends the puzzle (its givens) with every watch frame; until a
 * frame has it, every digit draws as a player's.
 */
function Watch({ state, puzzle }: { state: BoardState; puzzle?: Puzzle }) {
  return <NineLivesWatch puzzle={puzzle ?? { givens: new Array<number>(81).fill(0) }} state={state} />;
}

const nineLives: DailyGame<Puzzle, BoardState, NineLivesMove, Reveal> = {
  id: "nine-lives",
  Screen,
  Watch,
  // The share card shows only the time and hints.
  share: () => null,
};

export default nineLives;
