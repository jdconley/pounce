/**
 * Nine Lives' look on the web, matching the app's (`Pounce/Daily/NineLives/NineLivesArt.swift`):
 * a quilt of 3 by 3 cushions, and every digit on a paw-shaped tile. Shared by play and watch.
 */
import { useRef } from "preact/hooks";

import { hasNote, LIVES, type View } from "./model";

import "./nine-lives.css";

/**
 * `clash` is also a wrong number (lives); `answer` is the solution filled in, out of lives;
 * `pending` is a number the server hasn't answered yet (lives): neutral, never right-looking.
 */
export type TileKind = "given" | "mine" | "hinted" | "clash" | "answer" | "pending";

/** The paw's shape and the four faces' gradients, once per page. */
export function PawDefs() {
  return (
    <svg class="nl-defs" width="0" height="0" aria-hidden="true" focusable="false">
      <defs>
        <g id="nl-paw">
          <rect x="0" y="26" width="100" height="74" rx="30" />
          <ellipse cx="15" cy="40.5" rx="13.5" ry="15" />
          <ellipse cx="38" cy="27.5" rx="13.5" ry="15" />
          <ellipse cx="62" cy="27.5" rx="13.5" ry="15" />
          <ellipse cx="85" cy="40.5" rx="13.5" ry="15" />
        </g>
        <path id="nl-cat-head" d="M7 15 5 2.5 16 9.5Q21 8 26 9.5L37 2.5 35 15Q39 21 36.5 28 32 36.5 21 36.5 10 36.5 5.5 28 3 21 7 15Z" />
        {(
          [
            ["given", "#ffffff", "#ffffff", "#ebe6f5"],
            ["mine", "#82d6ff", "#2eb8ff", "#2aa6e8"],
            ["hinted", "#ffe679", "#ffd21f", "#ecc31f"],
            ["clash", "#ff8a95", "#ff3b4e", "#e9374a"],
            ["answer", "#f3ecff", "#ddccff", "#c9b3ff"],
            ["pending", "#7a5cc0", "#5b3f9e", "#4a3089"],
            ["cat", "#ff9ad8", "#ff4fb8", "#e8399f"],
          ] as const
        ).map(([kind, top, mid, bottom]) => (
          <linearGradient id={`nl-face-${kind}`} key={kind} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stop-color={top} />
            <stop offset="0.5" stop-color={mid} />
            <stop offset="1" stop-color={bottom} />
          </linearGradient>
        ))}
      </defs>
    </svg>
  );
}

/** One paw tile: a darker lip below, an ink rim, a glossy face, and the digit. */
export function PawTile(props: { digit: number; kind: TileKind; hollow?: boolean }) {
  return (
    <span class={`nl-tile nl-${props.kind}${props.hollow ? " nl-hollow" : ""}`} aria-hidden="true">
      <svg viewBox="-6 6 112 112" class="nl-paw">
        <use href="#nl-paw" class="nl-lip" y="7" />
        <use href="#nl-paw" class="nl-rim" />
        <use href="#nl-paw" class="nl-face" fill={props.hollow ? undefined : `url(#nl-face-${props.kind})`} />
      </svg>
      <span class="nl-digit">{props.digit}</span>
    </span>
  );
}

/**
 * One life: a cat's head. A lost one stays as a ghost in its place; `pop` (a life lost while
 * watching) also sends a copy of the full head up and away, once.
 */
function CatHead(props: { lost: boolean; pop: boolean }) {
  const head = (
    <svg viewBox="0 0 42 40" class="nl-cat" aria-hidden="true">
      <use href="#nl-cat-head" class="nl-cat-rim" />
      <use href="#nl-cat-head" class="nl-cat-face" fill={props.lost ? undefined : "url(#nl-face-cat)"} />
      {props.lost ? null : (
        <g class="nl-cat-eyes">
          <ellipse cx="15" cy="22" rx="2.6" ry="3.4" />
          <ellipse cx="27" cy="22" rx="2.6" ry="3.4" />
          <path d="M18.5 27.5h5L21 30Z" />
        </g>
      )}
    </svg>
  );
  return (
    <span class={`nl-life${props.lost ? " nl-lost" : ""}`}>
      {head}
      {props.pop ? (
        <span class="nl-life-pop" aria-hidden="true">
          <CatHead lost={false} pop={false} />
        </span>
      ) : null}
    </span>
  );
}

/**
 * Lives left, as three cats' heads (the lives rules). Only a life lost while it's on screen pops:
 * the ones lost before it opened are ghosts from the start.
 */
export function Lives(props: { lives: number; id?: string }) {
  const from = useRef(props.lives).current;
  return (
    <span class="nl-lives" id={props.id} role="img" aria-label={props.lives === 1 ? "1 life left" : `${props.lives} lives left`}>
      {Array.from({ length: LIVES }, (_, k) => (
        <CatHead key={k} lost={k >= props.lives} pop={k >= props.lives && k < from} />
      ))}
    </span>
  );
}

/** What a cell shows: its digit, the solution's (out of lives), or a wrong number (lives). */
function shown(v: View, i: number): number {
  return v.cells[i] || v.solution?.[i] || v.wrong[i] || 0;
}

function kindOf(v: View, i: number): TileKind {
  if (v.cells[i] === 0) return v.solution ? "answer" : "clash";
  if (v.pending.includes(i)) return "pending";
  if (v.clashes.has(i) && v.givens[i] === 0) return "clash";
  if (v.givens[i] !== 0) return "given";
  if (v.hinted.includes(i)) return "hinted";
  return "mine";
}

const lit = (selected: number | null, i: number): boolean => {
  if (selected === null || selected === i) return false;
  const [sr, sc, r, c] = [Math.floor(selected / 9), selected % 9, Math.floor(i / 9), i % 9];
  return sr === r || sc === c || (Math.floor(sr / 3) === Math.floor(r / 3) && Math.floor(sc / 3) === Math.floor(c / 3));
};

function label(v: View, i: number): string {
  const where = `Row ${Math.floor(i / 9) + 1}, column ${(i % 9) + 1}`;
  const d = shown(v, i);
  if (d === 0) {
    const notes = [1, 2, 3, 4, 5, 6, 7, 8, 9].filter((n) => hasNote(v, i, n));
    return notes.length ? `${where}, notes ${notes.join(" ")}` : `${where}, empty`;
  }
  if (v.cells[i] === 0) return `${where}, ${d}, ${v.solution ? "answer" : "wrong"}`;
  if (v.pending.includes(i)) return `${where}, ${d}, checking`;
  const tags = [v.givens[i] !== 0 ? "given" : v.hinted.includes(i) ? "hint" : "", v.clashes.has(i) ? "clash" : ""];
  return [where, String(d), ...tags.filter(Boolean)].join(", ");
}

/** A tapped cell leaves focus on the board. */
const keepFocus = (e: MouseEvent): void => e.preventDefault();

/**
 * The quilt. Square, as wide as its box. With `onTap` it is a group of 81 buttons and one tab stop:
 * the board, whose active cell (`aria-activedescendant`) the arrow keys move. Focus never moves
 * between cells and no cell's `tabIndex` ever changes: either makes the browser lay out the whole
 * page, a frame's budget on its own. Without `onTap` it is a picture (the TV).
 */
export function NineLivesGrid(props: { view: View; solved?: boolean; onTap?: (cell: number) => void; onKey?: (e: KeyboardEvent) => void }) {
  const { view: v } = props;
  const sel = v.selected;
  const same = sel !== null && v.cells[sel] !== 0 ? v.cells[sel] : 0;
  const out = v.solution !== null;
  return (
    <div
      class={`nl-board${props.solved ? " nl-solved" : ""}${out ? " nl-out" : ""}`}
      role={props.onTap ? "group" : "img"}
      aria-label="Nine Lives"
      tabIndex={props.onTap ? 0 : undefined}
      aria-activedescendant={props.onTap && sel !== null ? `nl-cell-${sel}` : undefined}
      onKeyDown={props.onKey}
    >
      {[0, 1, 2, 3, 4, 5, 6, 7, 8].map((box) => (
        <div class={`nl-box nl-box-${box % 2 ? "b" : "a"}`} key={box}>
          {[0, 1, 2, 3, 4, 5, 6, 7, 8].map((k) => {
            const i = (Math.floor(box / 3) * 3 + Math.floor(k / 3)) * 9 + (box % 3) * 3 + (k % 3);
            const d = shown(v, i);
            const kind = d !== 0 ? kindOf(v, i) : null;
            const wiggle = v.clashes.has(i) || (kind === "clash" && v.missed?.cell === i);
            const classes = ["nl-cell", lit(sel, i) ? "nl-lit" : "", sel === i ? "nl-selected" : "", d && d === same && sel !== i ? "nl-same" : ""];
            const content =
              kind !== null ? (
                <span
                  class={`nl-tile-wrap${v.placed?.cell === i && kind !== "clash" ? " nl-pop" : ""}${wiggle ? " nl-wiggle" : ""}${kind === "answer" ? " nl-fill" : ""}`}
                  key={kind === "answer" ? "a" : wiggle ? `c${v.clashBump}` : v.placed?.cell === i ? `${kind === "pending" ? "q" : "p"}${v.placed.count}` : "t"}
                  style={{ "--nl-wave": `${(Math.floor(i / 9) + (i % 9)) * 35}ms` }}
                >
                  <PawTile digit={d} kind={kind} />
                </span>
              ) : v.notes[i] ? (
                <span class="nl-notes" aria-hidden="true">
                  {[1, 2, 3, 4, 5, 6, 7, 8, 9].map((n) => (
                    <span key={n}>{hasNote(v, i, n) ? n : ""}</span>
                  ))}
                </span>
              ) : null;
            return props.onTap ? (
              <button
                type="button"
                key={i}
                class={classes.join(" ")}
                id={`nl-cell-${i}`}
                data-cell={i}
                aria-label={label(v, i)}
                aria-current={sel === i ? "true" : undefined}
                tabIndex={-1}
                onMouseDown={keepFocus}
                onClick={(e) => {
                  const board = (e.currentTarget as HTMLElement).closest<HTMLElement>(".nl-board");
                  if (board && !board.contains(document.activeElement)) board.focus({ preventScroll: true });
                  props.onTap!(i);
                }}
              >
                <span class="nl-in">{content}</span>
              </button>
            ) : (
              <span key={i} class={classes.join(" ")} data-cell={i}>
                <span class="nl-in">{content}</span>
              </span>
            );
          })}
        </div>
      ))}
    </div>
  );
}
