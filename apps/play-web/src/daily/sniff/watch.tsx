/**
 * Sniff watched on a TV (spec §8): the run as the server sees it, guesses with their letters,
 * read-only, from the run's public state. The TV's host draws whose run it is and the result.
 */
import { SniffTrail } from "./trail";

import type { SniffView } from "@pounce/play-api/daily/sniff/types";


export function SniffWatch(props: { view: SniffView }) {
  const board = { guesses: props.view.guesses, draft: "", pending: null, answer: props.view.answer ?? null };
  return (
    <div class="sniff sniff-watch">
      <div class="sniff-board">
        <SniffTrail board={board} />
      </div>
    </div>
  );
}
