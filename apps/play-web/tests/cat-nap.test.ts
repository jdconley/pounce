// @vitest-environment happy-dom
import { clashes, emptyState, type NapState, type Quilt } from "@pounce/play-api/daily/cat-nap/rules";
import { h, render } from "preact";
import { act } from "preact/test-utils";
import { describe, expect, test } from "vitest";

import { begin, cancel, end, hint, load, move, start, shown, tap } from "../src/daily/cat-nap/model";
import { CatNapPlay } from "../src/daily/cat-nap/play";
import { CatNapWatch } from "../src/daily/cat-nap/watch";

/** The 5 by 5 quilt from the server's vectors. */
const Q: Quilt = { n: 5, patches: [0, 0, 1, 1, 1, 0, 2, 2, 1, 1, 3, 2, 2, 2, 1, 3, 3, 2, 4, 4, 3, 3, 4, 4, 4] };

describe("the play model", () => {
  test("tap cycles empty, x, cat, empty", () => {
    let p = start(Q);
    const marks: number[] = [];
    for (let i = 0; i < 4; i++) {
      const out = tap(p, 7);
      p = out.play;
      marks.push(p.state.cells[7]!);
    }
    expect(marks).toEqual([1, 2, 0, 1]);
    expect(tap(p, 25).move).toBeNull();
  });

  test("a drag paints x over empties only, and sends once at the end", () => {
    let p = tap(tap(start(Q), 2).play, 2).play; // a cat at 2
    p = begin(p, 0)!;
    p = move(p, [1, 2, 3, 3]);
    expect(shown(p).cells.slice(0, 4)).toEqual([1, 1, 2, 1]);
    expect(p.state.cells.slice(0, 4)).toEqual([0, 0, 2, 0]);
    expect(tap(p, 4).move).toBeNull();
    const out = end(p);
    expect(out.move).toEqual({ k: "mark", cells: [0, 1, 3], to: "x" });
    expect(out.play.state.cells.slice(0, 4)).toEqual([1, 1, 2, 1]);
    expect(out.play.drag).toBeNull();
    expect(end(out.play).move).toBeNull();
  });

  test("a drag from x clears; none from a cat; a cancel sends nothing", () => {
    let p = tap(tap(start(Q), 0).play, 1).play;
    p = move(begin(p, 0)!, [1, 2]);
    expect(end(p).move).toEqual({ k: "mark", cells: [0, 1], to: "clear" });
    const cat = tap(tap(start(Q), 0).play, 0).play;
    expect(begin(cat, 0)).toBeNull();
    expect(begin(cat, 99)).toBeNull();
    const c = cancel(move(begin(start(Q), 0)!, [1]));
    expect(end(c).move).toBeNull();
    expect(shown(c)).toEqual(emptyState(Q));
  });

  test("hints lock; load replaces the board", () => {
    let p = tap(tap(start(Q), 0).play, 0).play;
    p = hint(p, 1);
    expect(p.state.hinted).toEqual([1]);
    expect(p.state.cells[0]).toBe(0);
    expect(tap(p, 1).move).toBeNull();
    const server: NapState = { cells: Array(25).fill(1), hinted: [] };
    expect(load(p, server).state).toEqual(server);
    expect(load(p, { cells: [0], hinted: [] }).state).toEqual(p.state);
  });

  test("clashes over 9x9 take well under a millisecond", () => {
    const q9: Quilt = { n: 9, patches: Array.from({ length: 81 }, (_, i) => Math.floor(i / 9)) };
    const s: NapState = { cells: Array.from({ length: 81 }, (_, i) => (i % 4 === 0 ? 2 : 1)), hinted: [] };
    const t0 = performance.now();
    for (let i = 0; i < 1000; i++) clashes(q9, s);
    expect((performance.now() - t0) / 1000).toBeLessThan(1);
  });
});

describe("the views", () => {
  test("watch draws a cat per cat cell, an x per no-cat cell, and takes no input", () => {
    const state: NapState = { cells: emptyState(Q).cells.map((_, i) => (i === 1 || i === 8 ? 2 : i === 0 ? 1 : 0)), hinted: [8] };
    const root = document.createElement("div");
    render(h(CatNapWatch, { quilt: Q, state }), root);
    expect(root.querySelectorAll("[data-cat]")).toHaveLength(2);
    expect(root.querySelectorAll("[data-x]")).toHaveLength(1);
    expect(root.querySelectorAll("[data-hinted]")).toHaveLength(1);
    expect(root.querySelector("[data-cells]")).toBeNull();
    expect(root.textContent).toBe("");
  });

  test("play marks a tapped cell and sends the move", () => {
    const sent: unknown[] = [];
    const root = document.createElement("div");
    document.body.append(root);
    render(h(CatNapPlay, { quilt: Q, onMove: (m) => sent.push(m) }), root);
    const cell = root.querySelector<HTMLElement>('[data-cell="7"]')!;
    act(() => {
      cell.dispatchEvent(new Event("click", { bubbles: true }));
    });
    expect(sent).toEqual([{ k: "mark", cells: [7], to: "x" }]);
    expect(cell.getAttribute("aria-label")).toBe("Row 2, column 3, teal checks, no cat");
  });
});
