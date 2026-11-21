/**
 * Pieces of the Box Fort screen that the play screen and the TV's watch view both draw.
 */
import { useEffect, useLayoutEffect, useRef, useState } from "preact/hooks";

import { drawBoxes, drawPiece, drawRug, sizeCanvas } from "./art";
import { boxFortLayout, spanOf, trayOrigin, type Box, type BoxFortLayout } from "./layout";

import type { BoxFortPublicState } from "@pounce/play-api/daily/box-fort/module";
import type { Piece } from "@pounce/play-api/daily/box-fort/pieces";
import type { RefObject } from "preact";

import "./box-fort.css";

export const at = (b: Box) => ({ left: `${b.x}px`, top: `${b.y}px`, width: `${b.w}px`, height: `${b.h}px` });

/** The layout for the element's own size, kept up to date as it resizes. */
export function useLayout(root: RefObject<HTMLElement | null>): BoxFortLayout | null {
  const [layout, setLayout] = useState<BoxFortLayout | null>(null);
  useLayoutEffect(() => {
    const el = root.current;
    if (!el) return;
    const measure = (w: number, h: number) =>
      setLayout((old) => (old && old.width === w && old.height === h ? old : boxFortLayout(w, h)));
    measure(el.clientWidth, el.clientHeight);
    const watch = new ResizeObserver(([entry]) => {
      if (entry) measure(entry.contentRect.width, entry.contentRect.height);
    });
    watch.observe(el);
    return () => watch.disconnect();
  }, [root]);
  return layout;
}

/** Points, the combo when there is one, and the set count. */
export function Header({ state, layout }: { state: BoxFortPublicState; layout: BoxFortLayout }) {
  const points = useRef<HTMLSpanElement>(null);
  const last = useRef(state.points);
  useEffect(() => {
    if (state.points === last.current) return;
    last.current = state.points;
    points.current?.animate([{ transform: "scale(1.3)" }, { transform: "scale(1)" }], { duration: 320, easing: "cubic-bezier(0.34, 1.56, 0.64, 1)" });
  }, [state.points]);
  return (
    <div class="bf-header" style={at(layout.header)}>
      <span class="bf-points" ref={points} data-testid="boxfort-points" aria-label={`${state.points} points`}>
        {state.points}
      </span>
      {state.combo >= 2 && (
        <span class="bf-combo" key={state.combo} data-testid="boxfort-combo">
          Combo {state.combo}
        </span>
      )}
      <span class="bf-set">
        Set {Math.min(state.set + 1, state.sets)} of {state.sets}
      </span>
    </div>
  );
}

/** The rug and its boxes, redrawn only when the boxes or the size change. */
export function Rug({ rug, layout }: { rug: readonly number[]; layout: BoxFortLayout }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const { cell } = layout;
  const margin = cell * 0.6;
  useEffect(() => {
    if (!canvas.current) return;
    const ctx = sizeCanvas(canvas.current, layout.rug.w + 2 * margin, layout.rug.h + 2 * margin);
    drawRug(ctx, margin, margin, cell);
    drawBoxes(ctx, rug, margin, margin, cell);
  }, [rug, cell, margin, layout.rug.w, layout.rug.h]);
  const boxes = rug.filter((v) => v !== 0).length;
  return (
    <canvas
      ref={canvas}
      class="bf-rug"
      style={{ left: `${layout.rug.x - margin}px`, top: `${layout.rug.y - margin}px` }}
      role="img"
      aria-label={`Rug, ${boxes} boxes`}
      data-testid="boxfort-rug"
    />
  );
}

/** A piece drawn at `cell` per box. */
export function PieceCanvas({ piece, cell, class: className }: { piece: Piece; cell: number; class?: string }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    if (!canvas.current) return;
    const span = spanOf(piece.cells);
    drawPiece(sizeCanvas(canvas.current, span.cols * cell, span.rows * cell), piece, 0, 0, cell);
  }, [piece, cell]);
  return <canvas ref={canvas} class={className} />;
}

/** A tray piece at tray scale, centered in its slot (positions are relative to the slot). */
export function TrayPiece({ piece, layout, slot, fits }: { piece: Piece; layout: BoxFortLayout; slot: number; fits: boolean }) {
  const o = trayOrigin(layout, slot, spanOf(piece.cells));
  const s = layout.slots[slot] as Box;
  return (
    <div class={`bf-tray-piece${fits ? "" : " bf-stuck"}`} style={{ left: `${o.x - s.x}px`, top: `${o.y - s.y}px` }}>
      <PieceCanvas piece={piece} cell={layout.trayCell} />
    </div>
  );
}

/** The stamp across the rug when the run is over. */
export function Stamp({ over, layout }: { over: "full" | "stuck"; layout: BoxFortLayout }) {
  return (
    <div
      class={`bf-stamp bf-stamp-${over}`}
      style={{ left: `${layout.rug.x + layout.rug.w / 2}px`, top: `${layout.rug.y + layout.rug.h / 2}px`, fontSize: `${layout.cell * 0.85}px` }}
      data-testid="boxfort-over"
    >
      {over === "full" ? "Full fort" : "Out of room"}
    </div>
  );
}
