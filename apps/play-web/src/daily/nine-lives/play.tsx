/**
 * Nine Lives being played: the quilt, the number keys, and Notes, Erase and Hint. The Daily Dish
 * host draws everything else (the bar, the clock, give up, the end).
 */
import { useEffect, useRef, useState } from "preact/hooks";

import { buzz } from "../../lib/haptics";
import { play } from "../../lib/sound";

import { NineLivesGrid, PawDefs, PawTile } from "./grid";
import { countOf, erase, isSolved, move, notQuite, press, reveal, start, tap, toggleNotes, type BoardState, type Puzzle, type Step, type View } from "./model";

import type { NineLivesDriver } from "./local";

const ARROWS: Record<string, [number, number]> = { ArrowUp: [-1, 0], ArrowDown: [1, 0], ArrowLeft: [0, -1], ArrowRight: [0, 1] };

export function NineLivesPlay(props: { puzzle: Puzzle; state?: BoardState; driver: NineLivesDriver }) {
  const [view, setView] = useState<View>(() => start(props.puzzle, props.state));
  const [asking, setAsking] = useState(false);
  const boardRef = useRef<HTMLDivElement>(null);
  const solved = isSolved(view);

  const apply = (step: Step): void => {
    if (step.move) {
      props.driver.send(step.move);
      const clash = step.view.clashBump !== view.clashBump;
      play(clash ? "nope" : "tick", 0.5);
      buzz(clash ? "nope" : "tap");
    }
    setView(step.view);
  };

  useEffect(() => {
    if (solved) {
      play("sparkle", 0.7);
      buzz("win");
    }
  }, [solved]);

  // Keep keyboard focus on the selected cell as it moves.
  useEffect(() => {
    const el = boardRef.current?.querySelector<HTMLButtonElement>(`[data-cell="${view.selected}"]`);
    if (el && boardRef.current?.contains(document.activeElement)) el.focus();
  }, [view.selected]);

  const onKey = (e: KeyboardEvent): void => {
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
    if (asking || solved) return;
    setAsking(true);
    try {
      const r = await props.driver.hint();
      if (r) setView((v) => reveal(v, r));
    } finally {
      setAsking(false);
    }
  };

  return (
    <div class="nl-play">
      <PawDefs />
      <div class="nl-layout">
      <div class="nl-board-slot" ref={boardRef}>
        <NineLivesGrid view={view} solved={solved} onTap={(cell) => setView(tap(view, cell))} onKey={onKey} />
      </div>
      <div class="nl-side">
        <div class="nl-not-quite-slot">
          <div class={`nl-not-quite${notQuite(view) ? " nl-show" : ""}`} key={view.notQuiteBump} role="status" aria-live="polite">
            {notQuite(view) ? "Not quite" : ""}
          </div>
        </div>
        <div class={`nl-keys${view.notesOn ? " nl-notes-on" : ""}`}>
          {[1, 2, 3, 4, 5, 6, 7, 8, 9].map((d) => {
            const done = countOf(view, d) >= 9 && !view.notesOn;
            return (
              <button
                type="button"
                key={d}
                class="nl-key"
                data-key={d}
                disabled={done}
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
            onClick={() => setView(toggleNotes(view))}
          >
            {view.notesOn ? "Notes on" : "Notes"}
          </button>
          <button type="button" class="btn small" onClick={() => apply(erase(view))}>
            Erase
          </button>
          <button type="button" class="btn small magenta" disabled={asking || solved} onClick={() => void askHint()}>
            Hint
          </button>
        </div>
      </div>
      </div>
    </div>
  );
}
