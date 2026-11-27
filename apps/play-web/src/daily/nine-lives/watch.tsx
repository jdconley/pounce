/**
 * A Nine Lives run as a TV shows it while someone plays (spec §8): the server's board, read only,
 * with the givens from the puzzle each watch frame carries. No selection and no notes: those stay
 * on the phone. The TV loads this module alone (`registry.ts`), so it imports no play screen,
 * host, Dish, run session or store.
 *
 * It fills the box it is given (the TV's stage, 1792 by 848 at 1080p) and draws the quilt square,
 * as large as the box's shorter side, centred. A run on the lives rules also shows its lives and
 * hints left, in a column beside the quilt (or a row under it, in a tall box), and each wrong
 * number in its cell, red, as the phone does; out of lives, the solution fills in.
 */
import { Lives, NineLivesGrid, PawDefs } from "./grid";
import { hasLives, isSolved, start, type BoardState, type Puzzle } from "./model";

export function NineLivesWatch(props: { puzzle: Puzzle; state: BoardState }) {
  const view = { ...start(props.puzzle, props.state), selected: null };
  const lives = hasLives(view);
  const hints = view.hintsLeft ?? 0;
  return (
    <div class={`nl-watch${lives ? " nl-watch-lives" : ""}`}>
      <PawDefs />
      <div class="nl-watch-in">
        <div class="nl-watch-quilt">
          <NineLivesGrid view={view} solved={isSolved(view)} />
        </div>
        {lives ? (
          <div class="nl-watch-panel">
            <Lives lives={view.lives!} />
            <p class="nl-watch-line outlined">{view.solution ? "Out of lives" : hints === 1 ? "1 hint left" : `${hints} hints left`}</p>
          </div>
        ) : null}
      </div>
    </div>
  );
}

export default NineLivesWatch;
