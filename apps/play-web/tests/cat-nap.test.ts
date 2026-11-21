// @vitest-environment happy-dom
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { clashes, emptyState, type NapMove, type NapState, type Quilt } from "@pounce/play-api/daily/cat-nap/rules";
import { h, render } from "preact";
import { act } from "preact/test-utils";
import { describe, expect, test } from "vitest";

import catNap, { type NapReveal } from "../src/daily/cat-nap/dish";
import { begin, cancel, end, hint, load, move, start, shown, tap } from "../src/daily/cat-nap/model";
import { CatNapPlay } from "../src/daily/cat-nap/play";
import catNapWatch, { CatNapWatch } from "../src/daily/cat-nap/watch";

import type { RunEvent, RunSession } from "../src/daily/client";
import type { ComponentChild } from "preact";

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
    render(h(CatNapWatch, { puzzle: Q, state }), root);
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

describe("the Dish entry", () => {
  type Ev = RunEvent<NapState, NapReveal>;
  function fakeSession(state: NapState = emptyState(Q)) {
    const listeners = new Set<(e: Ev) => void>();
    const sent: NapMove[] = [];
    let hints = 0;
    const session: RunSession<Quilt, NapState, NapMove, NapReveal> = {
      start: { run: "r1", game: "cat-nap", date: "2027-01-04", number: 1, level: 1, startedAt: 0, now: 0, puzzle: Q, state, seq: 0, hints: 0, result: null, closesAt: 1 },
      game: "cat-nap",
      result: null,
      get hints() {
        return hints;
      },
      send: async (m) => {
        sent.push(m);
        return null;
      },
      flush: async () => {},
      hint: async () => {
        hints++;
        const reveal = { cell: 1 };
        for (const l of listeners) l({ kind: "hint", reveal, hints });
        return reveal;
      },
      giveUp: async () => null,
      subscribe: (l) => {
        listeners.add(l);
        return () => listeners.delete(l);
      },
      serverNow: () => 0,
      elapsedMs: () => 0,
    };
    const emit = (e: Ev) => act(() => listeners.forEach((l) => l(e)));
    return { session, sent, emit, listeners };
  }

  function mount(node: ComponentChild) {
    const root = document.createElement("div");
    document.body.append(root);
    act(() => render(node, root));
    return root;
  }

  test("is cat-nap, with no share grid", () => {
    expect(catNap.id).toBe("cat-nap");
    expect(catNap.share?.(emptyState(Q), {} as never)).toBeNull();
  });

  test("a move goes to the session; the quilt starts from the start answer", () => {
    const start = { ...emptyState(Q), cells: emptyState(Q).cells.map((_, i) => (i === 24 ? 2 : 0)) as NapState["cells"] };
    const { session, sent } = fakeSession(start);
    const root = mount(h(catNap.Screen, { session, playing: true }));
    expect(root.querySelectorAll("[data-cat]")).toHaveLength(1);
    act(() => {
      root.querySelector('[data-cell="7"]')!.dispatchEvent(new Event("click", { bubbles: true }));
    });
    expect(sent).toEqual([{ k: "mark", cells: [7], to: "x" }]);
  });

  test("Hint asks the session and draws its locked cat", async () => {
    const { session } = fakeSession();
    const root = mount(h(catNap.Screen, { session, playing: true }));
    const button = root.querySelector<HTMLButtonElement>('[data-testid="catnap-hint"]')!;
    expect(button.textContent).toBe("Hint+30s");
    await act(async () => {
      button.click();
    });
    expect(session.hints).toBe(1);
    expect(root.querySelector('[data-cat="1"] [data-hinted]')).not.toBeNull();
    expect(button.disabled).toBe(false);
  });

  test("a resync redraws from the server's board", () => {
    const { session, emit } = fakeSession();
    const root = mount(h(catNap.Screen, { session, playing: true }));
    emit({ kind: "resync", seq: 3, state: { cells: emptyState(Q).cells.map((_, i) => (i === 0 || i === 13 ? 2 : 0)) as NapState["cells"], hinted: [] } });
    expect(root.querySelectorAll("[data-cat]")).toHaveLength(2);
    emit({ kind: "accepted", seq: 4, reveals: [], progress: 0.4 });
    expect(root.querySelectorAll("[data-cat]")).toHaveLength(2);
  });

  test("an ended run takes no input and asks no hint; unmounting unsubscribes", () => {
    const { session, sent, listeners } = fakeSession();
    const root = mount(h(catNap.Screen, { session, playing: false }));
    act(() => {
      root.querySelector('[data-cell="7"]')!.dispatchEvent(new Event("click", { bubbles: true }));
    });
    expect(sent).toEqual([]);
    expect(root.querySelector<HTMLButtonElement>('[data-testid="catnap-hint"]')!.disabled).toBe(true);
    act(() => render(null, root));
    expect(listeners.size).toBe(0);
  });

  test("the watch module draws from the frame's puzzle and state", () => {
    const state = { cells: emptyState(Q).cells.map((_, i) => (i === 3 ? 2 : 0)) as NapState["cells"], hinted: [] };
    expect("Watch" in catNap).toBe(false);
    const root = mount(h(catNapWatch, { puzzle: Q, state }));
    expect(root.querySelectorAll("[data-cat]")).toHaveLength(1);
    expect(root.querySelector("[data-cell]")).toBeNull();
  });
});

describe("the watch module, loaded alone on a TV", () => {
  test("never pulls in the play screen, the Dish entry, the model or the host", () => {
    const src = resolve(dirname(fileURLToPath(import.meta.url)), "../src/daily/cat-nap");
    const seen = new Set<string>();
    const walk = (file: string) => {
      if (seen.has(file)) return;
      seen.add(file);
      for (const m of readFileSync(file, "utf8").matchAll(/^\s*(?:import|export)\s(?!type\s)[^;]*?from\s+"(\.[^"]+)"/gm)) {
        const base = resolve(dirname(file), m[1]!);
        const next = [".tsx", ".ts"].map((ext) => base + ext).find((p) => existsSync(p));
        if (next) walk(next);
      }
    };
    walk(resolve(src, "watch.tsx"));
    const names = [...seen].map((p) => p.split("/src/daily/")[1]);
    expect(names).toEqual(expect.arrayContaining(["cat-nap/watch.tsx", "cat-nap/quilt.tsx", "cat-nap/check.ts"]));
    for (const heavy of ["cat-nap/play.tsx", "cat-nap/dish.tsx", "cat-nap/model.ts", "host.tsx", "client.ts"]) expect(names).not.toContain(heavy);
  });
});
