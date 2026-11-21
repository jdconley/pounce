/** The test game as a TV watches it: the count so far. */
import type { DailyWatchView } from "./host";
import type { TestPuzzle, TestState } from "@pounce/play-api/daily/test-game";

const TestWatch: DailyWatchView<TestPuzzle, TestState> = ({ puzzle, state }) => (
  <div class="dd-test-count">
    {state.n} / {puzzle.target}
  </div>
);

export default TestWatch;
