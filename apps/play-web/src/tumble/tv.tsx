/**
 * Toy Tumble on the TV page (spec §5.6): every box live in one row, sized to fill the screen,
 * each with its cat, name, wins, the tricks it holds and its junk meter. Falling toys glide
 * between position updates; hits fly from thrower to target; an out box tips. A TV that joins
 * mid-round draws every box from the sync it gets on connecting.
 */
import { useEffect, useMemo, useRef, useState } from "preact/hooks";

import { RINGS } from "../lib/art";
import { seatCat, seatName } from "../table/seat";
import { Cat, useSize } from "../ui/common";

import { BoxPainter, TRICK_COLOR } from "./canvas";
import { tvLayout } from "./layout";
import { stackHeight } from "./rules";
import { Paws, RoundOver, stateWords, TRICK_NAME, useTumble, countWords } from "./screen";

import type { RoomStore, RoomState } from "../store/room";
import type { Trick } from "@pounce/play-api/tumble/box";

const HEADER = 0.11;
const LABEL = 0.15;

export function TvTumble(props: { store: RoomStore; state: RoomState; offline: boolean }) {
  const room = props.state.room!;
  const tumble = useTumble(props.store, true);
  const t = tumble.room;
  const [rootRef, size] = useSize<HTMLDivElement>();
  const width = size.width || 1920;
  const height = size.height || 1080;
  const seats = tumble.players;
  const boxes = useMemo(() => tvLayout({ width, height, n: seats.length, header: Math.round(height * HEADER), label: Math.round(height * LABEL) }), [width, height, seats.length]);
  const canvases = useRef(new Map<number, HTMLCanvasElement>());
  const painters = useRef(new Map<HTMLCanvasElement, BoxPainter>());
  const els = useRef(new Map<number, HTMLElement>());
  const fxLayer = useRef<HTMLDivElement>(null);
  const [ui, setUi] = useState({ sig: "", count: "" });

  useEffect(() => {
    let raf = 0;
    const paint = () => {
      tumble.frame();
      const now = performance.timeOrigin + performance.now();
      for (const [seat, canvas] of canvases.current) {
        let p = painters.current.get(canvas);
        if (!p) painters.current.set(canvas, (p = new BoxPainter(canvas)));
        const cell = Number(canvas.dataset.cell) || 10;
        p.paint(tumble.view(seat, now), { cell, meter: Math.round(cell * 0.8), gap: Math.round(cell * 0.2), landing: false });
      }
      for (const f of tumble.takeFx()) {
        if (f.k === "out") els.current.get(f.seat)?.classList.add("tipped");
        if (f.k !== "hit" || f.from === f.to) continue;
        const a = els.current.get(f.from);
        const b = els.current.get(f.to);
        const layer = fxLayer.current;
        if (!a || !b || !layer) continue;
        const ra = a.getBoundingClientRect();
        const rb = b.getBoundingClientRect();
        const dot = document.createElement("i");
        dot.className = `tt-throw tv ${f.kind}`;
        layer.append(dot);
        const x0 = ra.left + ra.width / 2;
        const x1 = rb.left + rb.width / 2;
        const y0 = ra.top + ra.height * 0.4;
        const y1 = rb.top + rb.height * 0.4;
        dot
          .animate(
            [
              { transform: `translate3d(${x0}px, ${y0}px, 0) scale(1)` },
              { transform: `translate3d(${(x0 + x1) / 2}px, ${Math.min(y0, y1) - height * 0.12}px, 0) scale(2.2)` },
              { transform: `translate3d(${x1}px, ${y1}px, 0) scale(1.4)` },
            ],
            { duration: 520, easing: "ease-in-out" },
          )
          .finished.then(() => dot.remove(), () => dot.remove());
      }
      // The labels change rarely: held tricks, waiting junk, the seat's state, the countdown.
      const sig = seats
        .map((s) => {
          const v = tumble.view(s, now);
          return v ? `${v.box.held.join(".")}|${v.waiting.length}|${v.state}|${Math.round(stackHeight(v.box))}` : "";
        })
        .join(",");
      const ms = tumble.countdown(now);
      const count = ms > 0 ? countWords(ms) : "";
      setUi((u) => (u.sig === sig && u.count === count ? u : { sig, count }));
      raf = requestAnimationFrame(paint);
    };
    raf = requestAnimationFrame(paint);
    return () => cancelAnimationFrame(raf);
  }, [tumble, tumble.r, seats.join()]);

  if (!t) return null;
  if (t.status === "between") return <RoundOver room={room} t={t} tv now={() => tumble.serverNow()} />;
  return (
    <div class="tt-tv" ref={rootRef} data-sig={ui.sig}>
      <header class="tt-tv-head" style={{ height: `${Math.round(height * HEADER)}px` }}>
        <span class="tt-tv-title outlined">Toy Tumble</span>
        <span class="tt-tv-round outlined">{props.offline ? "Reconnecting" : `Round ${t.r}`}</span>
        <span class="tt-tv-code outlined">{room.code}</span>
      </header>
      {seats.map((s, i) => {
        const r = boxes[i];
        if (!r) return null;
        const v = tumble.view(s);
        const state = tumble.seatState(s);
        const words = stateWords(state);
        const held: Trick[] = v?.box.held ?? [];
        return (
          <section
            class={`tt-tv-box ${state}`}
            key={`tv${s}`}
            ref={(el) => {
              if (el) els.current.set(s, el);
              else els.current.delete(s);
            }}
            style={{ transform: `translate3d(${r.x}px, ${r.y}px, 0)`, width: `${r.w + r.cell}px`, ["--ring" as string]: RINGS[s % RINGS.length], ["--cell" as string]: `${r.cell}px` }}
            aria-label={seatName(room.seats[s])}
            data-junk={v ? v.waiting.reduce((n, w) => n + w.rows, 0) : 0}
          >
            <canvas
              class="tt-canvas"
              ref={(c) => {
                if (c) {
                  c.dataset.cell = String(r.cell);
                  canvases.current.set(s, c);
                } else canvases.current.delete(s);
              }}
              style={{ width: `${r.w + r.cell}px`, height: `${r.h}px` }}
            />
            {words ? <span class={`tt-state ${state}`}>{words}</span> : null}
            <div class="tt-tv-label">
              <span class="tt-tv-who">
                <Cat cat={seatCat(room.seats[s])} pose={state === "out" ? "terrified" : "awake"} size={Math.round(height * 0.055)} />
                <span class="tt-name">{seatName(room.seats[s])}</span>
              </span>
              <span class="tt-tv-stats">
                <Paws wins={t.wins[s] ?? 0} size={Math.round(height * 0.02)} />
                <span class="tt-tv-tricks" aria-label={held.map((k) => TRICK_NAME[k]).join(", ")}>
                  {held.map((k) => (
                    <i style={{ ["--trick" as string]: TRICK_COLOR[k] }} />
                  ))}
                </span>
              </span>
            </div>
          </section>
        );
      })}
      <div class="tt-fx" ref={fxLayer} aria-hidden="true" />
      {ui.count ? (
        <div class="tt-count tv" role="status">
          <span class="tt-count-n outlined" key={ui.count}>
            {ui.count}
          </span>
        </div>
      ) : null}
    </div>
  );
}
