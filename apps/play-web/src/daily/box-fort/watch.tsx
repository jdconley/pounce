/**
 * Someone's Box Fort run as the server sees it, for a TV that pressed Watch (spec §8): the score
 * row, the rug and the set in play, read only, drawn with the play screen's own parts. The TV
 * loads this module alone (registry `watch`), so it imports drawing code only: no play screen,
 * host, Dish, run session or store.
 */
import { useRef } from "preact/hooks";

import { Header, Rug, Stamp, TrayPiece, at, useLayout } from "./parts";

import type { DailyWatchView } from "../host";
import type { BoxFortPublicPuzzle, BoxFortPublicState } from "@pounce/play-api/daily/box-fort/module";

export function BoxFortWatch({ state }: { state: BoxFortPublicState }) {
  const root = useRef<HTMLDivElement>(null);
  const layout = useLayout(root);
  return (
    <div class="bf bf-watch" ref={root} aria-label={`Box Fort, ${state.points} points`}>
      {layout && (
        <>
          <Header state={state} layout={layout} />
          <Rug rug={state.rug} layout={layout} />
          {[0, 1, 2].map((slot) => {
            const piece = state.pieces[slot];
            return (
              <div key={slot} class="bf-slot" style={at(layout.slots[slot]!)}>
                {piece && !state.placed[slot] && <TrayPiece piece={piece} layout={layout} slot={slot} fits />}
              </div>
            );
          })}
          {state.over !== null && <Stamp over={state.over} layout={layout} />}
        </>
      )}
    </div>
  );
}

/** The Dish's watch view: the public state carries the rug and the set in play, so the puzzle isn't needed. */
const BoxFortWatchView: DailyWatchView<BoxFortPublicPuzzle, BoxFortPublicState> = ({ state }) => <BoxFortWatch state={state} />;

export default BoxFortWatchView;
