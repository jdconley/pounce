/**
 * A Nine Lives run as a TV shows it while someone plays (spec §8): the server's board, read only.
 * No selection and no notes: those stay on the phone.
 */
import { NineLivesGrid, PawDefs } from "./grid";
import { isSolved, start, type BoardState, type Puzzle } from "./model";

export function NineLivesWatch(props: { puzzle: Puzzle; state: BoardState }) {
  const view = { ...start(props.puzzle, props.state), selected: null };
  return (
    <div class="nl-watch">
      <PawDefs />
      <NineLivesGrid view={view} solved={isSolved(view)} />
    </div>
  );
}
