/**
 * A Nine Lives run as a TV shows it while someone plays (spec §8): the server's board, read only,
 * with the givens from the puzzle each watch frame carries. No selection and no notes: those stay
 * on the phone. The TV loads this module alone (`registry.ts`), so it imports no play screen,
 * host, Dish, run session or store.
 *
 * It fills the box it is given (the TV's stage, 1792 by 848 at 1080p) and draws the quilt square,
 * as large as the box's shorter side, centred.
 */
import { NineLivesGrid, PawDefs } from "./grid";
import { isSolved, start, type BoardState, type Puzzle } from "./model";

export function NineLivesWatch(props: { puzzle: Puzzle; state: BoardState }) {
  const view = { ...start(props.puzzle, props.state), selected: null };
  return (
    <div class="nl-watch">
      <PawDefs />
      <div class="nl-watch-quilt">
        <NineLivesGrid view={view} solved={isSolved(view)} />
      </div>
    </div>
  );
}

export default NineLivesWatch;
