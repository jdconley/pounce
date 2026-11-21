/**
 * Box Fort's board and controls in the browser (the host draws the top bar, the clock and the
 * end): the score row, the rug, and the tray of three pieces to drag onto it.
 *
 * Holding 120 Hz while dragging: the pointer handler only stores the point; one animation frame
 * writes one transform to the lifted piece's canvas, and the aim canvases redraw only when the
 * snapped spot changes. Preact renders nothing during a drag.
 */
import { place } from "@pounce/play-api/daily/box-fort/rules";
import { useEffect, useRef } from "preact/hooks";

import { buzz } from "../../lib/haptics";
import { play as sound } from "../../lib/sound";
import { useLatest } from "../../table/drag";

import { drawBox, drawPiece, sizeCanvas } from "./art";
import { lifted, snap, spanOf, type Spot } from "./layout";
import { Header, PieceCanvas, Rug, Stamp, TrayPiece, at, useLayout } from "./parts";

import type { Play } from "./model";

export type BoxFortPlayProps = {
  play: Play;
  /** The piece in `slot` let go on (`row`, `col`). True when it was placed. */
  onPlace: (slot: number, row: number, col: number) => boolean;
  /** False once the run has ended: the board stays, and takes no more pieces. */
  playing?: boolean;
};

const BURST_MS = 550;

export function BoxFortPlay({ play, onPlace, playing = true }: BoxFortPlayProps) {
  const root = useRef<HTMLDivElement>(null);
  const layout = useLayout(root);
  const glow = useRef<HTMLCanvasElement>(null);
  const ghost = useRef<HTMLCanvasElement>(null);
  const burst = useRef<HTMLCanvasElement>(null);
  const liftedEl = useRef<HTMLDivElement>(null);
  const gainEl = useRef<HTMLDivElement>(null);
  const slotEls = useRef<(HTMLButtonElement | null)[]>([]);
  const latest = useLatest({ play, layout, onPlace, playing });
  const { state } = play;

  // A clear: the boxes swell, flash white and burst into scraps.
  useEffect(() => {
    const b = play.burst;
    const canvas = burst.current;
    if (!b || !canvas || !layout) return;
    sound("sparkle");
    buzz(b.lines >= 2 || play.state.combo >= 3 ? "win" : "drop");
    const t0 = performance.now();
    let frame = requestAnimationFrame(function draw(now) {
      const t = Math.min(1, (now - t0) / BURST_MS);
      const ctx = sizeCanvas(canvas, layout.width, layout.height);
      const { cell, rug } = layout;
      const scale = t < 0.25 ? 1 + 0.5 * t : Math.max(0, 1.125 * (1 - (t - 0.25) / 0.75));
      for (const [index, tint] of b.boxes) {
        const cx = rug.x + (index % 8) * cell + cell / 2;
        const cy = rug.y + Math.floor(index / 8) * cell + cell / 2;
        const s = cell * scale;
        if (s > 1) drawBox(ctx, cx - s / 2, cy - s / 2, s, tint);
        ctx.fillStyle = `rgba(255, 255, 255, ${Math.max(0, 0.85 - t * 1.6)})`;
        ctx.beginPath();
        ctx.roundRect(cx - s / 2, cy - s / 2, s, s, s * 0.14);
        ctx.fill();
        for (let k = 0; k < 4; k++) {
          const angle = ((index * 37 + k * 90) * Math.PI) / 180;
          const d = cell * (0.3 + 1.4 * t) * (1 + b.lines * 0.15);
          ctx.globalAlpha = 1 - t;
          ctx.fillStyle = ["#ff2e9a", "#00d1c1", "#ff8a00", "#2eb8ff", "#9be22e", "#ffd21f", "#b57bff"][tint - 1] ?? "#fff";
          ctx.fillRect(cx + Math.cos(angle) * d - cell * 0.09, cy + Math.sin(angle) * d + cell * 1.2 * t * t - cell * 0.05, cell * 0.18, cell * 0.1);
          ctx.globalAlpha = 1;
        }
      }
      frame = t < 1 ? requestAnimationFrame(draw) : 0;
    });
    return () => cancelAnimationFrame(frame);
    // Only a new burst starts one.
  }, [play.burst?.id]);

  // "+64" floats up from where the piece landed.
  useEffect(() => {
    const g = play.gain;
    const el = gainEl.current;
    if (!g || !el || !layout) return;
    el.textContent = `+${g.points}`;
    el.classList.toggle("bf-gain-combo", g.combo >= 2);
    el.style.left = `${layout.rug.x + g.at.x * layout.cell}px`;
    el.style.top = `${layout.rug.y + g.at.y * layout.cell}px`;
    el.style.fontSize = `${layout.cell * (g.combo >= 2 ? 0.8 : 0.6)}px`;
    const rise = layout.cell * 1.4;
    el.animate(
      [
        { opacity: 1, transform: "translate(-50%, -50%) scale(0.4)" },
        { opacity: 1, transform: `translate(-50%, calc(-50% - ${rise * 0.2}px)) scale(1.3)`, offset: 0.15 },
        { opacity: 1, transform: `translate(-50%, calc(-50% - ${rise * 0.6}px)) scale(1)`, offset: 0.6 },
        { opacity: 0, transform: `translate(-50%, calc(-50% - ${rise}px)) scale(1)` },
      ],
      { duration: 800, easing: "ease-out", fill: "forwards" },
    );
  }, [play.gain?.id]);

  // A new set bounces into the tray.
  useEffect(() => {
    if (play.dealt === 0) return;
    sound("whoosh", 0.5);
    for (const el of slotEls.current) {
      el?.firstElementChild?.animate([{ transform: "scale(0.3)" }, { transform: "scale(1.15)", offset: 0.6 }, { transform: "scale(1)" }], {
        duration: 380,
        easing: "cubic-bezier(0.34, 1.56, 0.64, 1)",
      });
    }
  }, [play.dealt]);

  useEffect(() => {
    if (state.over === "full") {
      sound("fanfare");
      buzz("win");
    } else if (state.over === "stuck") {
      sound("thud");
      buzz("nope");
    }
  }, [state.over]);

  const pick = (slot: number, e: PointerEvent) => {
    const { play: p, layout: l, playing: live } = latest.current;
    const button = slotEls.current[slot];
    const holder = liftedEl.current;
    if (!live || !l || !button || !holder || e.button > 0) return;
    if (p.waiting || p.state.over !== null || p.state.placed[slot] !== false) return;
    const piece = p.state.pieces[slot]!;
    const span = spanOf(piece.cells);
    const box = (root.current as HTMLDivElement).getBoundingClientRect();
    let finger = { x: e.clientX - box.left, y: e.clientY - box.top };
    let spot: Spot | null = null;
    let frame = 0;
    try {
      button.setPointerCapture(e.pointerId);
    } catch {
      // A synthetic event in tests.
    }
    e.preventDefault();
    button.classList.add("bf-held");
    holder.dataset.slot = String(slot);
    holder.classList.add("bf-lifting");
    buzz("pick");

    const glowCtx = sizeCanvas(glow.current!, l.width, l.height);
    const ghostCtx = sizeCanvas(ghost.current!, l.width, l.height);
    const aim = (next: Spot | null) => {
      if (next?.row === spot?.row && next?.col === spot?.col) return;
      const landed = next ? place(latest.current.play.state.rug, piece, next.row, next.col) : null;
      spot = landed ? next : null;
      glowCtx.clearRect(0, 0, l.width, l.height);
      ghostCtx.clearRect(0, 0, l.width, l.height);
      if (!landed || !spot) return;
      buzz("tap");
      drawPiece(ghostCtx, piece, l.rug.x + spot.col * l.cell, l.rug.y + spot.row * l.cell, l.cell);
      glowCtx.fillStyle = "rgba(255, 255, 255, 0.3)";
      glowCtx.strokeStyle = "#ffd21f";
      glowCtx.lineWidth = 3;
      for (const r of landed.cleared.rows) {
        glowCtx.fillRect(l.rug.x, l.rug.y + r * l.cell, l.rug.w, l.cell);
        glowCtx.strokeRect(l.rug.x, l.rug.y + r * l.cell, l.rug.w, l.cell);
      }
      for (const c of landed.cleared.cols) {
        glowCtx.fillRect(l.rug.x + c * l.cell, l.rug.y, l.cell, l.rug.h);
        glowCtx.strokeRect(l.rug.x + c * l.cell, l.rug.y, l.cell, l.rug.h);
      }
    };
    const draw = () => {
      frame = 0;
      const o = lifted(l, finger, span);
      holder.style.transform = `translate3d(${o.x}px, ${o.y}px, 0)`;
      aim(snap(l, o, span));
    };
    draw();

    const move = (ev: PointerEvent) => {
      if (ev.pointerId !== e.pointerId) return;
      finger = { x: ev.clientX - box.left, y: ev.clientY - box.top };
      if (!frame) frame = requestAnimationFrame(draw);
    };
    const end = (ev: PointerEvent) => {
      if (ev.pointerId !== e.pointerId) return;
      button.removeEventListener("pointermove", move);
      button.removeEventListener("pointerup", end);
      button.removeEventListener("pointercancel", end);
      if (frame) cancelAnimationFrame(frame);
      holder.classList.remove("bf-lifting");
      button.classList.remove("bf-held");
      glowCtx.clearRect(0, 0, l.width, l.height);
      ghostCtx.clearRect(0, 0, l.width, l.height);
      if (ev.type === "pointerup" && spot && latest.current.onPlace(slot, spot.row, spot.col)) {
        buzz("drop");
        sound("pop");
        return;
      }
      if (ev.type === "pointerup") {
        sound("nope", 0.5);
        button.firstElementChild?.animate(
          [{ transform: "rotate(0)" }, { transform: "rotate(10deg)" }, { transform: "rotate(-8deg)" }, { transform: "rotate(4deg)" }, { transform: "rotate(0)" }],
          { duration: 400 },
        );
      }
    };
    button.addEventListener("pointermove", move);
    button.addEventListener("pointerup", end);
    button.addEventListener("pointercancel", end);
  };

  const held = (slot: number) => state.pieces[slot];
  return (
    <div class="bf" ref={root}>
      {layout && (
        <>
          <Header state={state} layout={layout} />
          <Rug rug={state.rug} layout={layout} />
          <canvas ref={glow} class="bf-layer" aria-hidden="true" />
          <canvas ref={ghost} class="bf-layer bf-ghost" aria-hidden="true" />
          <canvas ref={burst} class="bf-layer" aria-hidden="true" />
          {[0, 1, 2].map((slot) => {
            const piece = held(slot);
            const showing = piece && !state.placed[slot] && !play.waiting;
            return (
              <button
                key={slot}
                ref={(el) => {
                  slotEls.current[slot] = el;
                }}
                class="bf-slot"
                style={at(layout.slots[slot]!)}
                aria-label={showing ? `Piece ${slot + 1}, ${piece.cells.length} boxes` : `Piece ${slot + 1}, placed`}
                disabled={!showing || state.over !== null || !playing}
                data-testid={`boxfort-slot-${slot}`}
                onPointerDown={(e) => pick(slot, e as unknown as PointerEvent)}
              >
                {showing && <TrayPiece piece={piece} layout={layout} slot={slot} fits={play.fits[slot] !== false} />}
              </button>
            );
          })}
          <div ref={gainEl} class="bf-gain" aria-hidden="true" />
          {state.over !== null && <Stamp over={state.over} layout={layout} />}
          {/* Each tray piece pre-drawn at rug size; the held one shows while lifted. */}
          <div ref={liftedEl} class="bf-lifted" aria-hidden="true">
            {[0, 1, 2].map((slot) => {
              const piece = held(slot);
              return piece && !state.placed[slot] ? <PieceCanvas key={slot} piece={piece} cell={layout.cell} class={`bf-lifted-${slot}`} /> : null;
            })}
          </div>
        </>
      )}
    </div>
  );
}
