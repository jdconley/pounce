/**
 * Box Fort in the Daily Dish (web): the board on the run the host gives it. The host draws the top
 * bar, the clock, Show on TV, give up and the end; Box Fort draws the rug, the pieces and the
 * score. Its share card shows points only, so there is no grid. Its TV view is `watch.tsx`, a
 * module of its own, so a TV never loads this screen.
 */
import { useEffect, useRef, useState } from "preact/hooks";

import { BoxFortPlay } from "./play";
import { onRunEvent, placement, playFor } from "./session";

import type { DailyGame, DailyGameScreenProps } from "../host";
import type { BoxFortPublicPuzzle, BoxFortPublicState, BoxFortReveal, Place } from "@pounce/play-api/daily/box-fort/module";

type Props = DailyGameScreenProps<BoxFortPublicPuzzle, BoxFortPublicState, Place, BoxFortReveal>;

function BoxFortScreen({ session, playing }: Props) {
  const [play, setPlay] = useState(() => playFor(session.start.puzzle, session.start.state));
  const latest = useRef(play);
  latest.current = play;

  useEffect(() => session.subscribe((event) => setPlay((p) => onRunEvent(p, event))), [session]);

  const onPlace = (slot: number, row: number, col: number): boolean => {
    if (!playing) return false;
    const out = placement(latest.current, slot, row, col);
    if (out === null) return false;
    latest.current = out.play;
    setPlay(out.play);
    void session.send(out.move, { urgent: out.urgent });
    return true;
  };

  return <BoxFortPlay play={play} onPlace={onPlace} playing={playing} />;
}

const boxFort: DailyGame<BoxFortPublicPuzzle, BoxFortPublicState, Place, BoxFortReveal> = {
  id: "box-fort",
  Screen: BoxFortScreen,
  share: () => null,
};

export default boxFort;
