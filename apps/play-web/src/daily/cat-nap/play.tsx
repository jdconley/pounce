/**
 * Cat Nap's board in the browser: the beds that count the cats, and the quilt. Tap a cell for "no
 * cat", again for a cat; drag to mark many. Marks show at once and each change goes to `onMove`
 * (the run session, `dish.tsx`); hints and the server's resyncs come back through `subscribe`.
 * The Dish's host draws everything around it; `controls` (the Hint button) sit under the quilt.
 */
import { useEffect, useMemo, useRef, useState } from "preact/hooks";

import { preload } from "../../lib/art";
import { buzz } from "../../lib/haptics";
import { play as sound } from "../../lib/sound";

import { checkBoard } from "./check";
import { begin, cancel, end, hint, load, move, shown, start, tap, type NapPlay } from "./model";
import { Beds, catFor, clothOf, QuiltSvg, U } from "./quilt";

import type { NapMove, NapState, Quilt } from "@pounce/play-api/daily/cat-nap/rules";
import type { ComponentChildren } from "preact";

/** What the server tells the board after it is drawn: a hint's cat, or its own board to redraw from. */
export type NapEvent = { kind: "hint"; cell: number } | { kind: "resync"; state: NapState };

type Pointer = { id: number; start: number; last: { x: number; y: number }; mode: "pending" | "dragging" | "inert"; box: DOMRect };

/** "Row 3, column 4, violet stripes, cat." */
export function cellLabel(q: Quilt, s: NapState, cell: number): string {
  const m = s.cells[cell];
  const mark = m === 2 ? (s.hinted.includes(cell) ? ", cat, locked" : ", cat") : m === 1 ? ", no cat" : "";
  return `Row ${Math.floor(cell / q.n) + 1}, column ${(cell % q.n) + 1}, ${clothOf(q.patches[cell]!).name}${mark}`;
}

export function CatNapPlay({ quilt, state, onMove, subscribe, controls, playing = true }: {
  quilt: Quilt;
  /** The board to start from (a resumed run's is the server's). */
  state?: NapState;
  onMove: (m: NapMove) => void;
  subscribe?: (listener: (e: NapEvent) => void) => () => void;
  controls?: ComponentChildren;
  playing?: boolean;
}) {
  const [board, setBoard] = useState<NapPlay>(() => start(quilt, state));
  const pointer = useRef<Pointer | null>(null);
  const live = useRef(board);
  live.current = board;

  useEffect(
    () =>
      subscribe?.((e) => {
        pointer.current = null;
        live.current = e.kind === "hint" ? hint(live.current, e.cell) : load(live.current, e.state);
        setBoard(live.current);
        if (e.kind === "hint") sound("sparkle");
      }),
    [subscribe],
  );

  // The poses a cat can turn to (a clash wakes it, the finish makes it cheer), decoded ahead.
  useEffect(() => {
    const cats = [...new Set(quilt.patches.map(catFor))];
    preload([...cats.flatMap((c) => [`cat${c}-asleep`, `cat${c}-awake`, `cat${c}-celebrate`]), "icon-padlock"]);
  }, [quilt]);

  const view = shown(board);
  const check = useMemo(() => checkBoard(quilt, board.state), [quilt, board.state]);
  const last = useRef(check);
  useEffect(() => {
    const before = last.current;
    last.current = check;
    if (check.clashes.cells.length > before.clashes.cells.length) {
      buzz("nope");
      sound("nope");
    } else if (check.complete && !before.complete) {
      buzz("win");
      sound("fanfare");
    }
  }, [check]);

  const commit = (out: { play: NapPlay; move: NapMove | null }) => {
    live.current = out.play;
    setBoard(out.play);
    if (!out.move) return;
    if (out.move.to === "cat") {
      buzz("drop");
      sound("pop");
    } else buzz("tap");
    onMove(out.move);
  };

  const cellAt = (p: Pointer | { box: DOMRect }, x: number, y: number): number | null => {
    const unit = p.box.width / quilt.n;
    const cx = Math.floor((x - p.box.left) / unit);
    const cy = Math.floor((y - p.box.top) / unit);
    return cx >= 0 && cy >= 0 && cx < quilt.n && cy < quilt.n ? cy * quilt.n + cx : null;
  };

  /** The cells crossed from a to b, sampled finely so a fast swipe skips none. */
  const crossed = (p: Pointer, b: { x: number; y: number }): number[] => {
    const unit = p.box.width / quilt.n;
    const a = p.last;
    const steps = Math.max(1, Math.ceil(Math.hypot(b.x - a.x, b.y - a.y) / (unit / 4)));
    const out: number[] = [];
    for (let i = 0; i <= steps; i++) {
      const c = cellAt(p, a.x + ((b.x - a.x) * i) / steps, a.y + ((b.y - a.y) * i) / steps);
      if (c !== null && out.at(-1) !== c) out.push(c);
    }
    return out;
  };

  const onPointerDown = (e: PointerEvent) => {
    if (!playing || pointer.current || e.button > 0) return;
    const el = e.currentTarget as SVGSVGElement;
    const box = el.getBoundingClientRect();
    const cell = cellAt({ box }, e.clientX, e.clientY);
    if (cell === null) return;
    el.setPointerCapture?.(e.pointerId);
    pointer.current = { id: e.pointerId, start: cell, last: { x: e.clientX, y: e.clientY }, mode: "pending", box };
  };

  const onPointerMove = (e: PointerEvent) => {
    const p = pointer.current;
    if (!p || p.id !== e.pointerId) return;
    const here = { x: e.clientX, y: e.clientY };
    if (p.mode === "pending") {
      const unit = p.box.width / quilt.n;
      if (Math.hypot(here.x - p.last.x, here.y - p.last.y) <= unit / 3 && cellAt(p, here.x, here.y) === p.start) return;
      const dragging = begin(live.current, p.start);
      p.mode = dragging ? "dragging" : "inert";
      if (dragging) {
        live.current = dragging;
        buzz("tap");
      }
    }
    if (p.mode === "dragging") {
      const next = move(live.current, crossed(p, here));
      if (next !== live.current) {
        live.current = next;
        setBoard(next);
      }
    }
    p.last = here;
  };

  const onPointerUp = (e: PointerEvent) => {
    const p = pointer.current;
    if (!p || p.id !== e.pointerId) return;
    pointer.current = null;
    if (p.mode === "pending") commit(tap(live.current, p.start));
    else if (p.mode === "dragging") commit(end(live.current));
  };

  const onPointerCancel = () => {
    pointer.current = null;
    live.current = cancel(live.current);
    setBoard(live.current);
  };

  /** Keyboard and screen reader activation only: a pointer's tap is handled above. */
  const onCellClick = (e: MouseEvent, cell: number) => {
    if (!playing || e.detail) return;
    commit(tap(live.current, cell));
  };

  const n = quilt.n;
  return (
    <div class={`cn-play${controls ? " cn-has-controls" : ""}`}>
      <Beds n={n} placed={check.placed} />
      <div class="cn-board">
        <QuiltSvg
          quilt={quilt}
          state={view}
          check={check}
          svgProps={{ role: "group", "aria-label": "Quilt", onPointerDown, onPointerMove, onPointerUp, onPointerCancel, "data-testid": "catnap-quilt" }}
        >
          {Array.from({ length: n * n }, (_, cell) => (
            <rect
              key={cell}
              class="cn-cell"
              data-cell={cell}
              role="button"
              tabIndex={cell === 0 ? 0 : -1}
              aria-label={cellLabel(quilt, view, cell)}
              x={(cell % n) * U}
              y={Math.floor(cell / n) * U}
              width={U}
              height={U}
              fill="transparent"
              onClick={(e) => onCellClick(e, cell)}
              onKeyDown={(e) => keys(e, cell, n)}
            />
          ))}
        </QuiltSvg>
      </div>
      {controls && <div class="cn-controls">{controls}</div>}
    </div>
  );
}

/** Arrow keys move between cells; Enter and Space tap. */
function keys(e: KeyboardEvent, cell: number, n: number): void {
  const to = { ArrowLeft: cell % n ? cell - 1 : -1, ArrowRight: cell % n < n - 1 ? cell + 1 : -1, ArrowUp: cell - n, ArrowDown: cell + n }[e.key];
  if (e.key === "Enter" || e.key === " ") {
    e.preventDefault();
    (e.currentTarget as SVGRectElement).dispatchEvent(new MouseEvent("click", { bubbles: true, detail: 0 }));
    return;
  }
  if (to === undefined || to < 0 || to >= n * n) return;
  e.preventDefault();
  const next = (e.currentTarget as SVGRectElement).parentElement?.querySelector<SVGRectElement>(`[data-cell="${to}"]`);
  (e.currentTarget as SVGRectElement).setAttribute("tabindex", "-1");
  next?.setAttribute("tabindex", "0");
  next?.focus();
}
