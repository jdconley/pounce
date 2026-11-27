/**
 * The easel's two canvases in the page, sized to their box at the screen's pixel ratio. The
 * drawer's phone and the TV both mount it and feed its `Easel` (purr-easel.ts).
 */
import { useEffect, useLayoutEffect, useRef } from "preact/hooks";

import { rasterInk } from "../workers/purr-ink";

import { Easel, type Surface } from "./purr-easel";

import type { ComponentChildren } from "preact";

export function EaselCanvas(props: { onEasel: (e: Easel | null, input: HTMLCanvasElement | null) => void; class?: string; id?: string; label?: string; children?: ComponentChildren }) {
  const box = useRef<HTMLDivElement>(null);
  const baseRef = useRef<HTMLCanvasElement>(null);
  const liveRef = useRef<HTMLCanvasElement>(null);
  const easelRef = useRef<Easel | null>(null);
  const latest = useRef(props.onEasel);
  latest.current = props.onEasel;

  useLayoutEffect(() => {
    const base = baseRef.current;
    const live = liveRef.current;
    const el = box.current;
    if (!base || !live || !el) return;
    const b = base.getContext("2d");
    const l = live.getContext("2d");
    if (!b || !l) return;
    const easel = new Easel({
      base: b as unknown as Surface,
      live: l as unknown as Surface,
      resize: (w, h) => {
        base.width = live.width = w;
        base.height = live.height = h;
      },
      raster: rasterInk,
    });
    easelRef.current = easel;
    latest.current(easel, live);
    // Sized after the browser's own layout, never forcing one.
    const ro = new ResizeObserver(([entry]) => {
      const r = entry?.contentRect;
      if (r && r.width > 0 && r.height > 0) easel.setSize(r.width, r.height, Math.min(window.devicePixelRatio || 1, 3));
    });
    ro.observe(el);
    return () => {
      ro.disconnect();
      easel.stop();
      easelRef.current = null;
      latest.current(null, null);
    };
  }, []);

  // A screen moved to another display (a new pixel ratio): sized again.
  useEffect(() => {
    const q = matchMedia(`(resolution: ${window.devicePixelRatio || 1}dppx)`);
    const on = () => {
      const el = box.current;
      if (!el || !easelRef.current) return;
      easelRef.current.setSize(el.clientWidth, el.clientHeight, Math.min(window.devicePixelRatio || 1, 3));
    };
    q.addEventListener?.("change", on);
    return () => q.removeEventListener?.("change", on);
  }, []);

  return (
    <div class={`purr-easel ${props.class ?? ""}`} ref={box} id={props.id} role="img" aria-label={props.label ?? "Easel"}>
      <canvas class="purr-layer" ref={baseRef} aria-hidden="true" />
      <canvas class="purr-layer purr-live" ref={liveRef} aria-hidden="true" />
      {props.children}
    </div>
  );
}
