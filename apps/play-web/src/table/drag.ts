/**
 * Dragging a card or a piece: pointer events with capture, the move handler only stores the
 * point, and one animation frame writes one transform. A press that doesn't travel is a tap.
 * Drop targets are hit-tested against the layout's own rectangles: nothing is measured.
 */
import { useRef } from "preact/hooks";

import { transformOf, type Pose } from "./motion";

export type Point = { x: number; y: number };
export type Rect = { x: number; y: number; w: number; h: number };

export const inside = (p: Point, r: Rect, pad = 0): boolean => p.x >= r.x - pad && p.x <= r.x + r.w + pad && p.y >= r.y - pad && p.y <= r.y + r.h + pad;

/**
 * The latest render's value, read when it is called. A drag outlives the render it started in:
 * its handlers go through this, so a drop is judged on the table as it is now (our draw answered,
 * our turn come), never as it was when the card was picked up.
 */
export function useLatest<T>(value: T): { readonly current: T } {
  const ref = useRef(value);
  ref.current = value;
  return ref;
}

/** Pixels a press may travel and still be a tap. */
const TAP_SLOP = 7;

export type DragHandlers = {
  /** The table's origin on the page, read once at the start of a drag. */
  origin: () => Point;
  /** Where the dragged thing sits before it is lifted. */
  pose: () => Pose;
  onTap: () => void;
  onStart?: () => void;
  /** Called every frame with the point in table coordinates (for hover highlights). */
  onMove?: (p: Point) => void;
  /** Dropped at `p` (table coordinates), where the element now sits at `pose`. */
  onDrop: (p: Point, pose: Pose) => void;
  onCancel?: () => void;
  /** How big it gets while held. */
  lift?: number;
};

/** Starts tracking a press on `el`. Returns nothing; everything ends on pointerup or cancel. */
export function press(e: PointerEvent, el: HTMLElement, h: DragHandlers): void {
  if (e.button !== 0 && e.pointerType === "mouse") return;
  const start = { x: e.clientX, y: e.clientY };
  const origin = h.origin();
  const pose = h.pose();
  // Where in the element the finger is, so it doesn't jump to the corner.
  const grab = { x: e.clientX - origin.x - pose.x, y: e.clientY - origin.y - pose.y };
  let dragging = false;
  let latest = start;
  let frame = 0;
  const id = e.pointerId;
  try {
    el.setPointerCapture(id);
  } catch {
    // A synthetic event in tests.
  }

  const current = (): Pose => ({ x: latest.x - origin.x - grab.x, y: latest.y - origin.y - grab.y, r: 0, s: h.lift ?? 1.12, z: 999 });

  const draw = () => {
    frame = 0;
    el.style.transform = transformOf(current());
    h.onMove?.({ x: latest.x - origin.x, y: latest.y - origin.y });
  };

  const move = (ev: PointerEvent) => {
    if (ev.pointerId !== id) return;
    latest = { x: ev.clientX, y: ev.clientY };
    if (!dragging) {
      if (Math.hypot(latest.x - start.x, latest.y - start.y) < TAP_SLOP) return;
      dragging = true;
      for (const a of el.getAnimations()) a.cancel();
      el.classList.add("dragging");
      h.onStart?.();
    }
    if (!frame) frame = requestAnimationFrame(draw);
  };

  const end = (ev: PointerEvent) => {
    if (ev.pointerId !== id) return;
    cleanup();
    if (!dragging) {
      if (ev.type === "pointerup") h.onTap();
      return;
    }
    if (frame) cancelAnimationFrame(frame);
    el.classList.remove("dragging");
    if (ev.type === "pointercancel") {
      h.onCancel?.();
      return;
    }
    h.onDrop({ x: latest.x - origin.x, y: latest.y - origin.y }, current());
  };

  const cleanup = () => {
    el.removeEventListener("pointermove", move);
    el.removeEventListener("pointerup", end);
    el.removeEventListener("pointercancel", end);
    el.removeEventListener("lostpointercapture", lost);
  };
  const lost = (ev: PointerEvent) => end(new PointerEvent("pointercancel", { pointerId: ev.pointerId }));

  el.addEventListener("pointermove", move);
  el.addEventListener("pointerup", end);
  el.addEventListener("pointercancel", end);
  el.addEventListener("lostpointercapture", lost);
}
