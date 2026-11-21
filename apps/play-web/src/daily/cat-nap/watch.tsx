/**
 * Someone's Cat Nap run as the server sees it, for a TV that pressed Watch: the beds and the
 * quilt, no input. Drawn by the same code as the play view, and loaded on its own (`registry.ts`):
 * it never pulls in the play screen, the host, the Dish or a run session.
 */
import { useMemo } from "preact/hooks";

import { checkBoard } from "./check";
import { Beds, QuiltSvg } from "./quilt";

import type { DailyWatchView } from "./host-contract";
import type { NapState, Quilt } from "@pounce/play-api/daily/cat-nap/rules";

/** A watch frame: the quilt (the run's public puzzle) and the board (its public state). */
export function CatNapWatch({ puzzle, state }: { puzzle: Quilt; state: NapState }) {
  const check = useMemo(() => checkBoard(puzzle, state), [puzzle, state]);
  return (
    <div class="cn-play cn-watch">
      <Beds n={puzzle.n} placed={check.placed} />
      <div class="cn-board">
        <QuiltSvg quilt={puzzle} state={state} check={check} svgProps={{ "aria-hidden": "true" }} />
      </div>
    </div>
  );
}

const watch: DailyWatchView<Quilt, NapState> = CatNapWatch;
export default watch;
