/**
 * Someone's Cat Nap run as the server sees it, for a TV that pressed Watch: the beds and the
 * quilt, no input. Drawn by the same code as the play view.
 */
import { useMemo } from "preact/hooks";

import { checkBoard } from "./check";
import { Beds, QuiltSvg } from "./quilt";

import type { NapState, Quilt } from "@pounce/play-api/daily/cat-nap/rules";

export function CatNapWatch({ quilt, state }: { quilt: Quilt; state: NapState }) {
  const check = useMemo(() => checkBoard(quilt, state), [quilt, state]);
  return (
    <div class="cn-play cn-watch">
      <Beds n={quilt.n} placed={check.placed} />
      <div class="cn-board">
        <QuiltSvg quilt={quilt} state={state} check={check} svgProps={{ "aria-hidden": "true" }} />
      </div>
    </div>
  );
}
