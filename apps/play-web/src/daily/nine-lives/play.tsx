/**
 * Nine Lives being played: the quilt, the lives, the number keys, and Notes, Erase and Hint. The
 * Daily Dish host draws everything else (the bar, the clock, give up, the end).
 *
 * The status row between the quilt and the keys (beside the quilt on wide screens, above the keys)
 * holds the lives (three cats' heads) and, in the same room, the one line the board ever says:
 * "Out of lives", or "Not quite" for a run on the first rules. Hints left ride on the Hint button.
 */
import { useEffect, useState } from "preact/hooks";

import { buzz } from "../../lib/haptics";
import { play } from "../../lib/sound";
import { learnTip, Tip, tipLearned, useTipsVersion } from "../../ui/common";

import { Lives, NineLivesGrid, PawDefs, PawTile } from "./grid";
import {
  adopt,
  answered,
  erase,
  hasLives,
  HINTS,
  hintsSpent,
  isDone,
  isOut,
  isSolved,
  LIVES,
  move,
  notQuite,
  press,
  reveal,
  revealSolution,
  start,
  tap,
  toggleNotes,
  wrongAt,
  type BoardState,
  type Puzzle,
  type Step,
  type View,
} from "./model";

import type { NineLivesDriver } from "./local";

const ARROWS: Record<string, [number, number]> = { ArrowUp: [-1, 0], ArrowDown: [1, 0], ArrowLeft: [0, -1], ArrowRight: [0, 1] };

/** The first life lost, and the first hint used (lives rules): one tip each, once. */
const LIVES_TIP = "nine-lives.lives";
const LIVES_TIP_TEXT = "Wrong numbers cost a life.";
const HINTS_TIP = "nine-lives.hints";
const HINTS_TIP_TEXT = "Three hints a day.";

/**
 * `playing` false: the run has ended (the host keeps the board up under its end screen), so the
 * board takes no more input.
 */
export function NineLivesPlay(props: { puzzle: Puzzle; state?: BoardState; driver: NineLivesDriver; playing?: boolean }) {
  const [view, setView] = useState<View>(() => start(props.puzzle, props.state));
  const [asking, setAsking] = useState(false);
  useTipsVersion();
  const solved = isSolved(view);
  const out = isOut(view);
  const lives = hasLives(view);
  const live = (props.playing ?? true) && !solved && !out;

  // The server's board wins when it replaces ours.
  useEffect(() => props.driver.resyncs?.((state) => setView((v) => adopt(v, state))), [props.driver]);

  // Lives: the server calls a number wrong (a life goes); the last life brings the solution.
  useEffect(
    () =>
      props.driver.reveals?.((r) => {
        if (r.k !== "wrong") return;
        const { solution } = r;
        setView((v) => (solution ? revealSolution(wrongAt(v, r), solution) : wrongAt(v, r)));
        play("nope", 0.6);
        buzz("nope");
      }),
    [props.driver],
  );

  const apply = (step: Step): void => {
    if (!live) return;
    const m = step.move;
    if (m) {
      if (lives) {
        // Every set goes at once: its answer (right, or a life) is what the board waits for.
        void Promise.resolve(props.driver.send(m, true)).then(() => setView((v) => answered(v, m)));
        if (view.lives! < LIVES) learnTip(LIVES_TIP);
        play("tick", 0.5);
        buzz("tap");
      } else {
        void props.driver.send(m, isSolved(step.view));
        const clash = step.view.clashBump !== view.clashBump;
        play(clash ? "nope" : "tick", 0.5);
        buzz(clash ? "nope" : "tap");
      }
    } else if (step.view.clashBump !== view.clashBump) {
      // A number already known wrong there: shown wrong again, not sent, no life.
      play("nope", 0.5);
      buzz("nope");
    }
    setView(step.view);
  };

  useEffect(() => {
    if (solved) {
      play("sparkle", 0.7);
      buzz("win");
    }
  }, [solved]);

  const onKey = (e: KeyboardEvent): void => {
    if (!live) return;
    const arrow = ARROWS[e.key];
    if (arrow) {
      e.preventDefault();
      setView(move(view, arrow[0], arrow[1]));
    } else if (/^[1-9]$/.test(e.key)) {
      e.preventDefault();
      apply(press(view, Number(e.key)));
    } else if (e.key === "Backspace" || e.key === "Delete" || e.key === "0") {
      e.preventDefault();
      apply(erase(view));
    } else if (e.key === "n" || e.key === "N") {
      setView(toggleNotes(view));
    }
  };

  const askHint = async (): Promise<void> => {
    if (asking || !live || hintsSpent(view)) return;
    if (view.hintsLeft !== null && view.hintsLeft < HINTS) learnTip(HINTS_TIP);
    setAsking(true);
    try {
      const r = await props.driver.hint();
      if (r) setView((v) => reveal(v, r));
    } finally {
      setAsking(false);
    }
  };

  const message = out ? "Out of lives" : notQuite(view) ? "Not quite" : "";
  const spent = hintsSpent(view);
  const livesTip = lives && live && view.lives! < LIVES;
  const hintsTip = lives && live && !spent && view.hintsLeft! < HINTS && !(livesTip && !tipLearned(LIVES_TIP));

  return (
    <div class={`nl-play${lives ? " nl-has-lives" : ""}`}>
      <PawDefs />
      <div class="nl-layout">
        <div class="nl-board-slot">
          <NineLivesGrid view={view} solved={solved} onTap={(cell) => live && setView(tap(view, cell))} onKey={onKey} />
        </div>
        <div class="nl-side">
          <div class={`nl-status${message ? " nl-saying" : ""}`}>
            {lives ? <Lives id="nl-lives" lives={view.lives!} /> : null}
            <div class={`nl-not-quite${message ? " nl-show" : ""}`} key={out ? "out" : view.notQuiteBump} role="status" aria-live="polite">
              {message}
            </div>
          </div>
          <div class={`nl-keys${view.notesOn ? " nl-notes-on" : ""}`}>
            {[1, 2, 3, 4, 5, 6, 7, 8, 9].map((d) => {
              const done = isDone(view, d) && !view.notesOn;
              return (
                <button
                  type="button"
                  key={d}
                  class="nl-key"
                  data-key={d}
                  disabled={done || !live}
                  aria-label={view.notesOn ? `Note ${d}` : String(d)}
                  onClick={() => apply(press(view, d))}
                >
                  <PawTile digit={d} kind="mine" hollow={view.notesOn} />
                </button>
              );
            })}
          </div>
          <div class="nl-tools">
            <button
              type="button"
              class={`btn small ${view.notesOn ? "nl-notes-active" : "teal"}`}
              aria-pressed={view.notesOn}
              disabled={!live}
              onClick={() => setView(toggleNotes(view))}
            >
              {view.notesOn ? "Notes on" : "Notes"}
            </button>
            <button type="button" class="btn small" disabled={!live} onClick={() => apply(erase(view))}>
              Erase
            </button>
            <button
              type="button"
              id="nl-hint"
              class={`btn small magenta nl-hint${spent ? " nl-spent" : ""}`}
              disabled={asking || !live || spent}
              aria-label={view.hintsLeft === null ? "Hint" : `Hint, ${view.hintsLeft} left`}
              onClick={() => void askHint()}
            >
              Hint{" "}
              {view.hintsLeft === null ? null : (
                <span class="nl-hints-left" aria-hidden="true">
                  {view.hintsLeft}
                </span>
              )}
            </button>
          </div>
        </div>
      </div>
      <Tip id={LIVES_TIP} anchor="nl-lives" text={LIVES_TIP_TEXT} show={livesTip} />
      <Tip id={HINTS_TIP} anchor="nl-hint" text={HINTS_TIP_TEXT} show={hintsTip} />
    </div>
  );
}
