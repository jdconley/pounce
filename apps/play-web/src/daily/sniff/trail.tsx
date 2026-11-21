/**
 * Sniff's drawing, shared by the play screen and the TV's watch view: six trails of scent tags,
 * each stamped by the server's mark. Marks are shapes as well as colors: a filled paw for the
 * right spot, an outlined paw for elsewhere, a plain tag for neither (spec §1).
 */
import { LETTERS, TRIES, type Mark } from "@pounce/play-api/daily/sniff/types";

import { isSolved, type SniffBoard } from "./board";

import "./sniff.css";

type Face = { letter: string; mark: Mark | "typed" | "slot" | "empty" | "answer" };

/** A paw: one pad, four toes, in a 24 x 24 box. */
export function Paw(props: { filled: boolean }) {
  return (
    <svg class={`paw ${props.filled ? "filled" : "outlined"}`} viewBox="0 0 24 24" aria-hidden="true">
      <ellipse cx="12" cy="16.3" rx="6.7" ry="5.5" />
      <ellipse cx="3.4" cy="9" rx="2.9" ry="3.6" />
      <ellipse cx="8.6" cy="4.4" rx="2.9" ry="3.6" />
      <ellipse cx="15.4" cy="4.4" rx="2.9" ry="3.6" />
      <ellipse cx="20.6" cy="9" rx="2.9" ry="3.6" />
    </svg>
  );
}

const SPOKEN: Partial<Record<Face["mark"], string>> = {
  spot: "right spot",
  near: "elsewhere",
  none: "not in the word",
  answer: "the word",
};

function Tag(props: { face: Face; index: number }) {
  const { letter, mark } = props.face;
  const L = letter.toUpperCase();
  const spoken = SPOKEN[mark];
  return (
    <div
      class="sniff-tag"
      data-mark={mark}
      style={{ "--tilt": `${[-4, 3, -2, 4, -3][props.index]}deg` }}
      role="img"
      aria-label={letter ? (spoken ? `${L}, ${spoken}` : L) : "Empty"}
    >
      <svg class="tag-card" viewBox="0 0 100 120" aria-hidden="true">
        <path d="M26 2 H74 L98 26 V106 Q98 118 86 118 H14 Q2 118 2 106 V26 Z M50 9 a8 8 0 1 0 0.01 0 Z" fill-rule="evenodd" />
      </svg>
      {letter && <span class="tag-letter">{L}</span>}
      {(mark === "spot" || mark === "near") && <Paw filled={mark === "spot"} />}
    </div>
  );
}

function faces(board: SniffBoard, row: number): Face[] {
  const guess = board.guesses[row];
  if (guess) return [...guess.word].map((letter, i) => ({ letter, mark: guess.marks[i] as Mark }));
  const current = row === board.guesses.length && !board.answer && !isSolved(board);
  const typed = current ? (board.pending ?? board.draft) : "";
  return Array.from({ length: LETTERS }, (_, i) =>
    typed[i] ? { letter: typed[i] as string, mark: "typed" } : { letter: "", mark: current ? "slot" : "empty" },
  );
}

/** The six trails, and the answer on its own trail below when the run ended without it. */
export function SniffTrail(props: { board: SniffBoard; shake?: number }) {
  const { board } = props;
  const missedAnswer = board.answer && !isSolved(board) ? board.answer : null;
  return (
    <div class={`sniff-trail ${missedAnswer ? "with-answer" : ""}`}>
      {Array.from({ length: TRIES }, (_, row) => (
        <div
          class="sniff-row"
          key={row === board.guesses.length ? `current-${props.shake ?? 0}` : row}
          data-shake={row === board.guesses.length && (props.shake ?? 0) > 0 ? "" : undefined}
          aria-label={`Try ${row + 1}`}
          role="group"
        >
          {faces(board, row).map((face, i) => (
            <Tag face={face} index={i} key={i} />
          ))}
        </div>
      ))}
      {missedAnswer && (
        <div class="sniff-row answer" role="group" aria-label={`The word was ${missedAnswer.toUpperCase()}`}>
          {[...missedAnswer].map((letter, i) => (
            <Tag face={{ letter, mark: "answer" }} index={i} key={i} />
          ))}
        </div>
      )}
    </div>
  );
}
