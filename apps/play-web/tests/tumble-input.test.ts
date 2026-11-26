// @vitest-environment happy-dom
/**
 * Toy Tumble's touch and keys (spec §5.3, §5.4): drags move a column per cell-width, a tap turns,
 * a slow drag down soft-drops while held, a flick drops, tricks go by tap-then-box or a drag onto
 * a box, every key does its job with the repeat timing, and arrows and Space never scroll or press
 * a button while playing.
 */
import { beforeEach, describe, expect, test } from "vitest";

import { attachKeys, attachTouch, REPEAT_AFTER_MS, REPEAT_EVERY_MS, TrickPicker, type KeyHandlers } from "../src/tumble/input";

import { Clock } from "./fake-socket";

type Call = [string, ...unknown[]];

function handlers(calls: Call[]): KeyHandlers {
  return {
    move: (dx) => calls.push(["move", dx]),
    turn: (dir) => calls.push(["turn", dir]),
    soft: (on) => calls.push(["soft", on]),
    drop: () => calls.push(["drop"]),
    useOn: (seat) => calls.push(["useOn", seat]),
  };
}

/** A pointer event with the fields the handlers read. */
function pe(type: string, x: number, y: number, t: number, id = 1): PointerEvent {
  const e = new Event(type, { bubbles: true, cancelable: true });
  for (const [k, v] of Object.entries({ clientX: x, clientY: y, timeStamp: t, pointerId: id, isPrimary: true })) Object.defineProperty(e, k, { value: v });
  return e as PointerEvent;
}

describe("touch", () => {
  let el: HTMLElement;
  let calls: Call[];
  beforeEach(() => {
    el = document.createElement("div");
    document.body.append(el);
    calls = [];
    attachTouch(el, handlers(calls), { cell: () => 24, active: () => true });
  });

  test("a sideways drag of 3 cell-widths moves 3 columns, and no turn", () => {
    el.dispatchEvent(pe("pointerdown", 100, 100, 0));
    el.dispatchEvent(pe("pointermove", 130, 101, 40));
    el.dispatchEvent(pe("pointermove", 175, 102, 80));
    el.dispatchEvent(pe("pointerup", 175, 102, 120));
    expect(calls).toEqual([["move", 1], ["move", 1], ["move", 1]]);
    calls.length = 0;
    el.dispatchEvent(pe("pointerdown", 200, 100, 1000));
    el.dispatchEvent(pe("pointermove", 150, 100, 1040));
    el.dispatchEvent(pe("pointerup", 150, 100, 1080));
    expect(calls).toEqual([["move", -1], ["move", -1]]);
  });

  test("a tap turns clockwise", () => {
    el.dispatchEvent(pe("pointerdown", 100, 100, 0));
    el.dispatchEvent(pe("pointerup", 103, 102, 120));
    expect(calls).toEqual([["turn", 1]]);
  });

  test("a slow drag down soft-drops while held, and lets go without a drop", () => {
    el.dispatchEvent(pe("pointerdown", 100, 100, 0));
    el.dispatchEvent(pe("pointermove", 100, 130, 200));
    expect(calls).toEqual([["soft", true]]);
    el.dispatchEvent(pe("pointermove", 100, 160, 400));
    el.dispatchEvent(pe("pointerup", 100, 170, 600));
    expect(calls).toEqual([["soft", true], ["soft", false]]);
  });

  test("a fast flick down drops", () => {
    el.dispatchEvent(pe("pointerdown", 100, 100, 0));
    el.dispatchEvent(pe("pointermove", 101, 150, 30));
    el.dispatchEvent(pe("pointerup", 102, 190, 60));
    expect(calls.at(-1)).toEqual(["drop"]);
    expect(calls.filter((c) => c[0] === "turn")).toEqual([]);
  });
});

describe("tricks", () => {
  test("tap a trick, then a box, uses it on that box; tapping it again puts it down", () => {
    const used: [number, number][] = [];
    const p = new TrickPicker({ use: (slot, seat) => used.push([slot, seat]), targetAt: () => null });
    expect(p.tapBox(2)).toBe(false);
    p.tapTrick(1);
    expect(p.lifted).toBe(1);
    p.tapTrick(1);
    expect(p.lifted).toBeNull();
    p.tapTrick(3);
    expect(p.tapBox(2)).toBe(true);
    expect(used).toEqual([[3, 2]]);
    expect(p.lifted).toBeNull();
  });

  test("dragging a trick onto a box uses it there; let go over nothing, nothing happens", () => {
    const used: [number, number][] = [];
    const p = new TrickPicker({ use: (slot, seat) => used.push([slot, seat]), targetAt: (x) => (x > 300 ? 4 : null) });
    p.pointerDown(0, pe("pointerdown", 50, 600, 0));
    p.pointerMove(pe("pointermove", 200, 400, 50));
    expect(p.drag?.slot).toBe(0);
    p.pointerUp(pe("pointerup", 320, 200, 100));
    expect(used).toEqual([[0, 4]]);
    p.pointerDown(2, pe("pointerdown", 50, 600, 200));
    p.pointerMove(pe("pointermove", 100, 400, 250));
    p.pointerUp(pe("pointerup", 100, 400, 300));
    expect(used).toEqual([[0, 4]]);
    // A press that doesn't travel is a tap: it lifts the trick.
    p.pointerDown(5, pe("pointerdown", 50, 600, 400));
    p.pointerUp(pe("pointerup", 52, 601, 450));
    expect(p.lifted).toBe(5);
  });
});

describe("keys", () => {
  const key = (type: string, k: string, extra: Partial<KeyboardEventInit> = {}) => {
    const e = new KeyboardEvent(type, { key: k, code: k === " " ? "Space" : k, bubbles: true, cancelable: true, ...extra });
    window.dispatchEvent(e);
    return e;
  };

  test("every key, with the move repeat after 150 ms and then every 33 ms", () => {
    const clock = new Clock();
    const calls: Call[] = [];
    const off = attachKeys(window, handlers(calls), { active: () => true, setTimer: clock.set, clearTimer: clock.clear });
    key("keydown", "ArrowLeft");
    expect(calls).toEqual([["move", -1]]);
    clock.advance(REPEAT_AFTER_MS - 1);
    expect(calls.length).toBe(1);
    clock.advance(1);
    expect(calls.length).toBe(2);
    clock.advance(REPEAT_EVERY_MS * 3);
    expect(calls.length).toBe(5);
    // The browser's own repeats change nothing.
    key("keydown", "ArrowLeft", { repeat: true });
    expect(calls.length).toBe(5);
    key("keyup", "ArrowLeft");
    clock.advance(1000);
    expect(calls.length).toBe(5);
    calls.length = 0;
    key("keydown", "ArrowRight");
    key("keyup", "ArrowRight");
    key("keydown", "ArrowDown");
    key("keyup", "ArrowDown");
    key("keydown", "ArrowUp");
    key("keydown", "x");
    key("keydown", "z");
    key("keydown", " ");
    key("keydown", "3");
    key("keydown", "7");
    expect(calls).toEqual([["move", 1], ["soft", true], ["soft", false], ["turn", 1], ["turn", 1], ["turn", -1], ["drop"], ["useOn", 2]]);
    off();
  });

  test("arrows and Space don't scroll or press a button while playing, and do when not", () => {
    let playing = true;
    const calls: Call[] = [];
    const off = attachKeys(window, handlers(calls), { active: () => playing });
    for (const k of ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", " "]) {
      expect(key("keydown", k).defaultPrevented, k).toBe(true);
      key("keyup", k);
    }
    expect(key("keyup", " ").defaultPrevented).toBe(true);
    playing = false;
    calls.length = 0;
    expect(key("keydown", " ").defaultPrevented).toBe(false);
    expect(key("keydown", "ArrowDown").defaultPrevented).toBe(false);
    expect(calls).toEqual([]);
    off();
  });
});
