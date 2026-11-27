// @vitest-environment happy-dom
import { h, render } from "preact";
import { act } from "preact/test-utils";
import { afterEach, describe, expect, test } from "vitest";

import nineLives, { driverFor } from "../src/daily/nine-lives/dish";
import { SAMPLE_GIVENS, SAMPLE_SOLUTION } from "../src/daily/nine-lives/local";
import NineLivesWatch from "../src/daily/nine-lives/watch";

import type { RunEvent, RunSession, SendOptions } from "../src/daily/client";
import type { DailyGameScreenProps } from "../src/daily/host";
import type { NineLivesMove } from "@pounce/play-api/daily/nine-lives/grid";

type State = { cells: number[]; hinted: number[] };
type Reveal = { i: number; d: number };

const open = SAMPLE_GIVENS.flatMap((d, i) => (d === 0 ? [i] : []));

/** A run session that records what the board sends, and lets a test push server events. */
function fakeSession(cells = [...SAMPLE_GIVENS]) {
  const sent: { move: NineLivesMove; options?: SendOptions }[] = [];
  const listeners = new Set<(e: RunEvent<State, Reveal>) => void>();
  let hints = 0;
  const session: RunSession<{ givens: number[] }, State, NineLivesMove, Reveal> = {
    start: {
      run: "r",
      game: "nine-lives",
      date: "2027-01-04",
      number: 1,
      level: 1,
      startedAt: 0,
      now: 0,
      puzzle: { givens: [...SAMPLE_GIVENS] },
      state: { cells, hinted: [] },
      seq: 0,
      hints: 0,
      result: null,
      closesAt: 1,
    },
    game: "nine-lives",
    result: null,
    get hints() {
      return hints;
    },
    send: async (move, options) => {
      sent.push({ move, options });
      return null;
    },
    flush: async () => {},
    hint: async () => {
      hints++;
      const i = open[0]!;
      return { i, d: SAMPLE_SOLUTION[i]! };
    },
    giveUp: async () => null,
    subscribe: (fn) => {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
    serverNow: () => 0,
    elapsedMs: () => 0,
  };
  return { session, sent, emit: (e: RunEvent<State, Reveal>) => listeners.forEach((fn) => fn(e)), listeners };
}

let root: HTMLElement | undefined;
afterEach(() => {
  if (root) {
    render(null, root);
    root.remove();
  }
  root = undefined;
});

function mount(props: DailyGameScreenProps<{ givens: number[] }, State, NineLivesMove, Reveal>): void {
  if (root) {
    render(null, root);
    root.remove();
  }
  const el = document.createElement("div");
  root = el;
  document.body.append(el);
  act(() => render(h(nineLives.Screen, props), el));
}

const cell = (i: number) => root!.querySelector<HTMLButtonElement>(`[data-cell="${i}"]`)!;
const key = (d: number) => root!.querySelector<HTMLButtonElement>(`[data-key="${d}"]`)!;
const click = (el: HTMLElement) => act(() => el.click());

describe("Nine Lives in the Dish (web)", () => {
  test("the game's entry: its id, no share grid", () => {
    expect(nineLives.id).toBe("nine-lives");
    expect(nineLives.share?.({ cells: [], hinted: [] }, {} as never)).toBeNull();
  });

  test("a move goes to the session, not urgent; the solving move is urgent", () => {
    const fake = fakeSession();
    mount({ session: fake.session, playing: true });
    click(cell(open[0]!));
    click(key(SAMPLE_SOLUTION[open[0]!]!));
    expect(fake.sent).toEqual([{ move: { k: "set", i: open[0], d: SAMPLE_SOLUTION[open[0]!] }, options: { urgent: false } }]);
    expect(cell(open[0]!).getAttribute("aria-label")).toContain(String(SAMPLE_SOLUTION[open[0]!]));

    // One cell from done: the last move is urgent.
    const almost = [...SAMPLE_SOLUTION];
    const last = open.at(-1)!;
    almost[last] = 0;
    const f2 = fakeSession(almost);
    mount({ session: f2.session, playing: true });
    click(cell(last));
    click(key(SAMPLE_SOLUTION[last]!));
    expect(f2.sent.at(-1)).toEqual({ move: { k: "set", i: last, d: SAMPLE_SOLUTION[last] }, options: { urgent: true } });
  });

  test("a resync redraws from the server's board", () => {
    const fake = fakeSession();
    mount({ session: fake.session, playing: true });
    const cells = [...SAMPLE_GIVENS];
    const d = SAMPLE_SOLUTION[open[2]!]!;
    cells[open[2]!] = d;
    act(() => fake.emit({ kind: "resync", state: { cells, hinted: [] }, seq: 3 }));
    expect(cell(open[2]!).getAttribute("aria-label")).toBe(`Row ${Math.floor(open[2]! / 9) + 1}, column ${(open[2]! % 9) + 1}, ${d}`);
    // Other events are not the board's business.
    act(() => fake.emit({ kind: "link", status: "retrying" }));
  });

  test("a hint fills the cell the server names, and locks it", async () => {
    const fake = fakeSession();
    mount({ session: fake.session, playing: true });
    const hint = [...root!.querySelectorAll("button")].find((b) => b.textContent?.trim() === "Hint")!;
    await act(async () => hint.click());
    await act(async () => {});
    expect(cell(open[0]!).getAttribute("aria-label")).toContain("hint");
  });

  test("when the run has ended, nothing takes input", () => {
    const fake = fakeSession();
    mount({ session: fake.session, playing: false });
    click(cell(open[1]!));
    click(key(3));
    expect(fake.sent).toEqual([]);
    expect(key(3).disabled).toBe(true);
  });

  test("unmounting stops listening", () => {
    const fake = fakeSession();
    mount({ session: fake.session, playing: true });
    // Resyncs, and what moves reveal.
    expect(fake.listeners.size).toBe(2);
    act(() => render(null, root!));
    expect(fake.listeners.size).toBe(0);
  });

  test("driverFor passes urgency and hints straight through", async () => {
    const fake = fakeSession();
    const d = driverFor(fake.session);
    d.send({ k: "clear", i: 3 }, true);
    expect(fake.sent).toEqual([{ move: { k: "clear", i: 3 }, options: { urgent: true } }]);
    expect(await d.hint()).toEqual({ i: open[0], d: SAMPLE_SOLUTION[open[0]!] });
  });

  test("the watch view draws the server's board, givens from the puzzle", () => {
    const el = document.createElement("div");
    root = el;
    document.body.append(el);
    const cells = [...SAMPLE_GIVENS];
    act(() => render(h(NineLivesWatch, { state: { cells, hinted: [] }, puzzle: { givens: SAMPLE_GIVENS } }), el));
    expect(el.querySelectorAll(".nl-cell")).toHaveLength(81);
    expect(el.querySelectorAll(".nl-given")).toHaveLength(SAMPLE_GIVENS.filter((d) => d).length);
  });
});
