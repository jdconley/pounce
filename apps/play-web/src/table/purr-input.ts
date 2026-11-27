/**
 * The drawer's finger on the easel (design §6.3, §7): pointer events on the easel's top layer,
 * every coalesced point (a fast line stays whole on a 60 Hz phone), one stroke at a time (a palm
 * or a second finger is ignored), and a stroke that ends cleanly when the page hides mid-stroke.
 */
import { EASEL_H, EASEL_W, type InkWriter } from "./purr-ink";

/** What the input needs from the page: the layer, and the document whose visibility it watches. */
export type InputTarget = EventTarget & { getBoundingClientRect(): { left: number; top: number; width: number; height: number }; setPointerCapture?(id: number): void };
export type VisibilitySource = EventTarget & { visibilityState: DocumentVisibilityState };

export type InputOptions = {
  writer: InkWriter;
  tool: () => { colour: number; width: number };
  /** No new strokes (the easel is full). */
  blocked: () => boolean;
  /** A stroke began or grew: draw it, and send it. */
  drew: () => void;
  /** A stroke ended (lifted, cancelled, or cut off as the page hid). `hidden`: send it now, there may be no next frame. */
  ended: (hidden: boolean) => void;
};

type Pointer = { pointerId: number; isPrimary: boolean; pointerType: string; button: number; clientX: number; clientY: number; preventDefault(): void; getCoalescedEvents?(): { clientX: number; clientY: number }[] };

export function attachDrawing(el: InputTarget, doc: VisibilitySource, o: InputOptions): () => void {
  const { writer } = o;
  let active: number | null = null;
  let rect = { left: 0, top: 0, width: 1, height: 1 };
  const at = (e: { clientX: number; clientY: number }): [number, number] => [((e.clientX - rect.left) / rect.width) * EASEL_W, ((e.clientY - rect.top) / rect.height) * EASEL_H];
  const down = (ev: Event) => {
    const e = ev as unknown as Pointer;
    if (active !== null || !e.isPrimary || o.blocked()) return;
    if (e.pointerType === "mouse" && e.button !== 0) return;
    e.preventDefault();
    active = e.pointerId;
    el.setPointerCapture?.(e.pointerId);
    // One layout read, at the start of the stroke.
    const r = el.getBoundingClientRect();
    rect = { left: r.left, top: r.top, width: r.width || 1, height: r.height || 1 };
    const [x, y] = at(e);
    const t = o.tool();
    writer.begin(t.colour, t.width, x, y);
    o.drew();
  };
  const move = (ev: Event) => {
    const e = ev as unknown as Pointer;
    if (e.pointerId !== active) return;
    const events = typeof e.getCoalescedEvents === "function" ? e.getCoalescedEvents() : [];
    let grew = false;
    for (const c of events.length > 0 ? events : [e]) {
      const [x, y] = at(c);
      grew = writer.move(x, y) || grew;
    }
    if (grew) o.drew();
  };
  const up = (ev: Event) => {
    const e = ev as unknown as Pointer;
    if (e.pointerId !== active) return;
    active = null;
    writer.end();
    o.ended(false);
  };
  // The phone locked or the tab hidden mid-stroke: the stroke ends cleanly and goes now.
  const hidden = () => {
    if (doc.visibilityState !== "hidden") return;
    if (active !== null) {
      active = null;
      writer.end();
    }
    // Whatever waits goes now: a hidden page draws no more frames to send it on.
    if (writer.pending) o.ended(true);
  };
  const events: [string, (e: Event) => void][] = [
    ["pointerdown", down],
    ["pointermove", move],
    ["pointerup", up],
    ["pointercancel", up],
    ["lostpointercapture", up],
  ];
  for (const [name, fn] of events) el.addEventListener(name, fn);
  doc.addEventListener("visibilitychange", hidden);
  return () => {
    for (const [name, fn] of events) el.removeEventListener(name, fn);
    doc.removeEventListener("visibilitychange", hidden);
  };
}
