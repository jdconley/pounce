/**
 * Nine Lives' look on the web, matching the app's (`Pounce/Daily/NineLives/NineLivesArt.swift`):
 * a quilt of 3 by 3 cushions, and every digit on a paw-shaped tile. Shared by play and watch.
 */
import { hasNote, type View } from "./model";

import "./nine-lives.css";

export type TileKind = "given" | "mine" | "hinted" | "clash";

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
        {(
          [
            ["given", "#ffffff", "#ffffff", "#ebe6f5"],
            ["mine", "#82d6ff", "#2eb8ff", "#2aa6e8"],
            ["hinted", "#ffe679", "#ffd21f", "#ecc31f"],
            ["clash", "#ff8a95", "#ff3b4e", "#e9374a"],
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

function kindOf(v: View, i: number): TileKind {
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
  const d = v.cells[i]!;
  if (d === 0) {
    const notes = [1, 2, 3, 4, 5, 6, 7, 8, 9].filter((n) => hasNote(v, i, n));
    return notes.length ? `${where}, notes ${notes.join(" ")}` : `${where}, empty`;
  }
  const tags = [v.givens[i] !== 0 ? "given" : v.hinted.includes(i) ? "hint" : "", v.clashes.has(i) ? "clash" : ""];
  return [where, String(d), ...tags.filter(Boolean)].join(", ");
}

/**
 * The quilt. Square, as wide as its box. With `onTap` the cells are buttons with one tab stop
 * (the selected cell); without it, it is a picture (the TV).
 */
export function NineLivesGrid(props: { view: View; solved?: boolean; onTap?: (cell: number) => void; onKey?: (e: KeyboardEvent) => void }) {
  const { view: v } = props;
  const sel = v.selected;
  const same = sel !== null && v.cells[sel] !== 0 ? v.cells[sel] : 0;
  return (
    <div
      class={`nl-board${props.solved ? " nl-solved" : ""}`}
      role={props.onTap ? "grid" : "img"}
      aria-label="Nine Lives"
      onKeyDown={props.onKey}
    >
      {[0, 1, 2, 3, 4, 5, 6, 7, 8].map((box) => (
        <div class={`nl-box nl-box-${box % 2 ? "b" : "a"}`} key={box} role={props.onTap ? "rowgroup" : undefined}>
          {[0, 1, 2, 3, 4, 5, 6, 7, 8].map((k) => {
            const i = (Math.floor(box / 3) * 3 + Math.floor(k / 3)) * 9 + (box % 3) * 3 + (k % 3);
            const d = v.cells[i]!;
            const classes = ["nl-cell", lit(sel, i) ? "nl-lit" : "", sel === i ? "nl-selected" : "", d && d === same && sel !== i ? "nl-same" : ""];
            const content =
              d !== 0 ? (
                <span
                  class={`nl-tile-wrap${v.placed?.cell === i ? " nl-pop" : ""}${v.clashes.has(i) ? " nl-wiggle" : ""}`}
                  key={v.placed?.cell === i ? `p${v.placed.count}` : v.clashes.has(i) ? `c${v.clashBump}` : "t"}
                  style={{ "--nl-wave": `${(Math.floor(i / 9) + (i % 9)) * 35}ms` }}
                >
                  <PawTile digit={d} kind={kindOf(v, i)} />
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
                data-cell={i}
                role="gridcell"
                aria-label={label(v, i)}
                aria-selected={sel === i}
                tabIndex={sel === i || (sel === null && i === 0) ? 0 : -1}
                onClick={() => props.onTap!(i)}
              >
                {content}
              </button>
            ) : (
              <span key={i} class={classes.join(" ")} data-cell={i}>
                {content}
              </span>
            );
          })}
        </div>
      ))}
    </div>
  );
}
