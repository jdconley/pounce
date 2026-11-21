/**
 * Cat Nap in the Daily Dish (the web host's contract, `../host.tsx`): the quilt to play, and no
 * share grid (Cat Nap's card shows only the time and hints). Loaded in its own chunk by the
 * registry; the TV's watch view is `watch.tsx`, loaded apart.
 */
import { useCallback, useState } from "preact/hooks";

import { CatNapPlay, type NapEvent } from "./play";

import type { DailyGame, DailyGameScreenProps } from "./host-contract";
import type { NapMove, NapState, Quilt } from "@pounce/play-api/daily/cat-nap/rules";

/** What a hint reveals: the cell of its cat (`module.ts`). Moves reveal nothing. */
export type NapReveal = { cell: number };

type Props = DailyGameScreenProps<Quilt, NapState, NapMove, NapReveal>;

function CatNapScreen({ session, playing }: Props) {
  const [asking, setAsking] = useState(false);

  const subscribe = useCallback(
    (listener: (e: NapEvent) => void) =>
      session.subscribe((e) => {
        if (e.kind === "hint") listener({ kind: "hint", cell: e.reveal.cell });
        else if (e.kind === "resync") listener({ kind: "resync", state: e.state });
      }),
    [session],
  );

  const onMove = useCallback((m: NapMove) => void session.send(m), [session]);

  const hint = () => {
    if (asking) return;
    setAsking(true);
    void session.hint().finally(() => setAsking(false));
  };

  return (
    <CatNapPlay
      quilt={session.start.puzzle}
      state={session.start.state}
      onMove={onMove}
      subscribe={subscribe}
      playing={playing}
      controls={
        <button type="button" class="btn small magenta" disabled={!playing || asking} onClick={hint} data-testid="catnap-hint">
          Hint<span class="cn-hint-cost">+30s</span>
        </button>
      }
    />
  );
}

const catNap: DailyGame<Quilt, NapState, NapMove, NapReveal> = {
  id: "cat-nap",
  Screen: CatNapScreen,
  share: () => null,
};

export default catNap;
