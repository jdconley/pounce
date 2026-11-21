/**
 * Sniff in the Daily Dish's host (`../host.tsx`): the host draws the top bar, the clock, Show on
 * TV, give up, the end and share; Sniff draws its trails and keyboard. The TV's watch view is
 * `watch.tsx`, loaded on its own. Each guess goes to the
 * server at once (`urgent`) and waits for its marks; the server's state wins on a resync.
 */
import { useEffect, useState } from "preact/hooks";

import { emptyBoard, type SniffBoard } from "./board";
import { SniffPlay } from "./sniff";

import type { DailyGame, DailyGameScreenProps, ShareMark } from "../host";
import type { Mark, SniffMove, SniffPublic, SniffReveal, SniffView } from "@pounce/play-api/daily/sniff/types";

type Props = DailyGameScreenProps<SniffPublic, SniffView, SniffMove, SniffReveal>;

const fromView = (view: SniffView): SniffBoard => ({ ...emptyBoard(), guesses: view.guesses, answer: view.answer ?? null });

function SniffScreen({ session, playing }: Props) {
  // Each resync remounts the board from the server's state (a draft in progress is dropped).
  const [server, setServer] = useState({ board: fromView(session.start.state), resyncs: 0 });

  useEffect(
    () =>
      session.subscribe((e) => {
        if (e.kind === "resync") setServer((was) => ({ board: fromView(e.state), resyncs: was.resyncs + 1 }));
      }),
    [session],
  );

  return (
    <SniffPlay
      key={server.resyncs}
      start={server.board}
      enabled={playing}
      referee={(word) => session.send({ k: "guess", word }, { urgent: true })}
    />
  );
}

const SHARE: Record<Mark, ShareMark> = { spot: "full", near: "half", none: "none" };

const sniff: DailyGame<SniffPublic, SniffView, SniffMove, SniffReveal> = {
  id: "sniff",
  Screen: SniffScreen,
  // A row of paws per guess: no letters, so it gives nothing away.
  share: (state) => state.guesses.map((g) => g.marks.map((m) => SHARE[m])),
};

export default sniff;
