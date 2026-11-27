import { describe, expect, test } from "vitest";

import { InkWriter, type InkOp } from "../src/table/purr-ink";
import { attachDrawing } from "../src/table/purr-input";

/** An easel layer 384 x 512 CSS px at (10, 20): half the grid's size. */
function setup(blocked = false) {
  const el = Object.assign(new EventTarget(), {
    getBoundingClientRect: () => ({ left: 10, top: 20, width: 384, height: 512 }),
    captured: [] as number[],
    setPointerCapture(id: number) {
      this.captured.push(id);
    },
  });
  const doc = Object.assign(new EventTarget(), { visibilityState: "visible" as DocumentVisibilityState });
  const writer = new InkWriter();
  const log: string[] = [];
  const detach = attachDrawing(el, doc, {
    writer,
    tool: () => ({ colour: 5, width: 2 }),
    blocked: () => blocked,
    drew: () => log.push("drew"),
    ended: (hidden) => log.push(hidden ? "ended:hidden" : "ended"),
  });
  const pointer = (type: string, x: number, y: number, more: Record<string, unknown> = {}) =>
    el.dispatchEvent(Object.assign(new Event(type), { pointerId: 1, isPrimary: true, pointerType: "touch", button: 0, clientX: x, clientY: y, ...more }));
  const ops = (): InkOp[] => writer.flush(0, true).flat();
  return { el, doc, writer, log, detach, pointer, ops };
}

describe("the finger on the easel", () => {
  test("points land on the grid, in the tool's colour and width", () => {
    const { pointer, ops, el } = setup();
    pointer("pointerdown", 10 + 192, 20 + 256);
    pointer("pointerup", 10 + 192, 20 + 256);
    expect(ops()).toEqual([["s", 0, 5, 2, 384, 512]]);
    expect(el.captured).toEqual([1]);
  });

  test("every coalesced point is drawn, not just the last of the frame", () => {
    const { pointer, ops } = setup();
    pointer("pointerdown", 10, 20);
    // One move event carries a fast swipe's samples: a zigzag no simplification can drop.
    const samples = Array.from({ length: 20 }, (_, i) => ({ clientX: 10 + (i + 1) * 5, clientY: 20 + (i % 2 ? 40 : 0) }));
    pointer("pointermove", 110, 20, { getCoalescedEvents: () => samples });
    pointer("pointerup", 110, 20);
    const [s] = ops() as [InkOp];
    // 1 start point and 20 more: every sample's corner is kept.
    expect((s.length - 6) / 2).toBe(20);
  });

  test("a second finger or a palm is ignored while one draws", () => {
    const { pointer, ops } = setup();
    pointer("pointerdown", 10, 20);
    pointer("pointerdown", 300, 300, { pointerId: 2, isPrimary: false });
    pointer("pointermove", 300, 400, { pointerId: 2, isPrimary: false });
    pointer("pointermove", 30, 20);
    pointer("pointerup", 30, 20);
    expect(ops()).toEqual([["s", 0, 5, 2, 0, 0, 40, 0]]);
  });

  test("visibility hidden ends the stroke, and it goes at once", () => {
    const { pointer, doc, writer, log } = setup();
    pointer("pointerdown", 10, 20);
    pointer("pointermove", 60, 20);
    doc.visibilityState = "hidden";
    doc.dispatchEvent(new Event("visibilitychange"));
    expect(writer.drawing).toBe(false);
    expect(log.at(-1)).toBe("ended:hidden");
    // The finger lifting later (on return) changes nothing.
    pointer("pointerup", 90, 20);
    expect(writer.picture.strokes).toHaveLength(1);
    expect(writer.picture.strokes[0]!.points).toEqual([0, 0, 100, 0]);
  });

  test("a full easel takes no new strokes", () => {
    const { pointer, writer } = setup(true);
    pointer("pointerdown", 10, 20);
    expect(writer.drawing).toBe(false);
  });

  test("detached, it hears nothing", () => {
    const { pointer, writer, detach } = setup();
    detach();
    pointer("pointerdown", 10, 20);
    expect(writer.drawing).toBe(false);
  });
});
