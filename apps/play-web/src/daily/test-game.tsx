/**
 * The server's test game ("count to 3 + level", `DAILY_TEST=on` only), so the host plays end to
 * end before any real game lands. Production never lists it: its start is a 404 there.
 */
import { useEffect, useState } from "preact/hooks";

import type { DailyGame, DailyGameScreenProps } from "./host";
import type { TestMove, TestPuzzle, TestState } from "@pounce/play-api/daily/test-game";

type Reveal = { n: number };
type Props = DailyGameScreenProps<TestPuzzle, TestState, TestMove, Reveal>;

function TestScreen({ session, playing }: Props) {
  const [n, setN] = useState(session.start.state.n);
  const target = session.start.puzzle.target;

  useEffect(
    () =>
      session.subscribe((e) => {
        if (e.kind === "resync") setN(e.state.n);
        else if (e.kind === "hint") setN(e.reveal.n);
      }),
    [session],
  );

  const step = () => {
    const next = n + 1;
    setN(next);
    void session.send({ k: "step", n: next }, { urgent: next === target });
  };

  const hint = () => void session.hint();

  return (
    <div class="dd-test">
      <div class="dd-test-count" data-testid="test-count">
        {n} / {target}
      </div>
      <div class="dd-test-keys">
        <button type="button" class="btn" disabled={!playing || n >= target} onClick={step}>
          Step
        </button>
        <button type="button" class="btn small magenta" disabled={!playing || n >= target} onClick={hint}>
          Hint
        </button>
      </div>
    </div>
  );
}

function TestWatch({ state }: { puzzle: TestPuzzle; state: TestState }) {
  return <div class="dd-test-count">{state.n}</div>;
}

const test: DailyGame<TestPuzzle, TestState, TestMove, Reveal> = {
  id: "test",
  Screen: TestScreen,
  Watch: TestWatch,
  share: (state) => [Array.from({ length: Math.max(1, state.n) }, () => "full" as const)],
};

export default test;
