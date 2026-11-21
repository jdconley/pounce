/**
 * Sniff watched on a TV (spec §8): the run as the server sees it, guesses with their letters,
 * read-only, from one watch frame's public puzzle and state. The TV's host draws whose run it is
 * and the result. A TV loads this module alone: it draws with the trail only, never the play
 * screen, the keyboard, the host or the run session.
 */
import { SniffTrail } from "./trail";

import type { SniffPublic, SniffView } from "@pounce/play-api/daily/sniff/types";

export default function SniffWatch(props: { puzzle: SniffPublic; state: SniffView }) {
  const { guesses, answer } = props.state;
  return (
    <div class="sniff sniff-watch">
      <div class="sniff-board">
        <SniffTrail board={{ guesses, draft: "", pending: null, answer: answer ?? null }} />
      </div>
    </div>
  );
}
