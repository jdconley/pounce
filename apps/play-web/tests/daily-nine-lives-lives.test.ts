// @vitest-environment happy-dom
/**
 * Nine Lives' lives rules on the web (docs/daily-protocol.md "## Nine Lives"): the board model,
 * the play screen against a fake run session, the end's words, and the TV's watch view.
 */
import { h, render } from "preact";
import { act } from "preact/test-utils";
import { afterEach, beforeEach, describe, expect, test } from "vitest";

import { outcomeWords, resultWords, shareText } from "../src/daily/format";
import nineLives from "../src/daily/nine-lives/dish";
import { SAMPLE_GIVENS, SAMPLE_SOLUTION } from "../src/daily/nine-lives/local";
import {
  answered,
  erase,
  hasLives,
  hintsSpent,
  isLocked,
  isOut,
  isSolved,
  notQuite,
  press,
  reveal,
  revealSolution,
  start,
  tap,
  toggleNotes,
  wrongAt,
  type BoardState,
  type View,
} from "../src/daily/nine-lives/model";
import NineLivesWatch from "../src/daily/nine-lives/watch";
import { endTitle } from "../src/daily/play";
import { resultWords as tvResultWords } from "../src/ui/tv/tv-board-model";

import type { RunEvent, RunSession, SendOptions } from "../src/daily/client";
import type { Reveal } from "../src/daily/nine-lives/dish";
import type { DailyResult } from "@pounce/play-api/daily/module";
import type { NineLivesMove } from "@pounce/play-api/daily/nine-lives/grid";

const open = SAMPLE_GIVENS.flatMap((d, i) => (d === 0 ? [i] : []));
const right = (i: number) => SAMPLE_SOLUTION[i]!;
const wrongOf = (i: number) => (SAMPLE_SOLUTION[i]! % 9) + 1;
const livesState = (extra: Partial<BoardState> = {}): BoardState => ({ cells: [...SAMPLE_GIVENS], hinted: [], rules: "lives", lives: 3, hintsLeft: 3, wrong: [], ...extra });
const fresh = (extra: Partial<BoardState> = {}): View => start({ givens: SAMPLE_GIVENS }, livesState(extra));

describe("the board model under the lives rules", () => {
  test("a run without rules plays the first rules: no lives, no hint count", () => {
    const v = start({ givens: SAMPLE_GIVENS }, { cells: [...SAMPLE_GIVENS], hinted: [] });
    expect(hasLives(v)).toBe(false);
    expect(v.lives).toBeNull();
    expect(v.hintsLeft).toBeNull();
    expect(hintsSpent(v)).toBe(false);
  });

  test("a set shows at once, waits, and locks once the server took it", () => {
    const i = open[0]!;
    const a = press(tap(fresh(), i), right(i));
    expect(a.move).toEqual({ k: "set", i, d: right(i) });
    expect(a.view.cells[i]).toBe(right(i));
    expect(a.view.pending).toEqual([i]);
    // Waiting, it's already locked: no second set, no erase.
    expect(press(a.view, 4).move).toBeUndefined();
    expect(erase(a.view)).toEqual({ view: a.view });
    const b = answered(a.view, a.move!);
    expect(b.pending).toEqual([]);
    expect(b.cells[i]).toBe(right(i));
    expect(isLocked(b, i)).toBe(true);
    expect(press(b, wrongOf(i)).move).toBeUndefined();
  });

  test("a wrong number comes off the board, shows red, and costs a life", () => {
    const i = open[0]!;
    const a = press(tap(fresh(), i), wrongOf(i));
    const b = wrongAt(a.view, { i, d: wrongOf(i), lives: 2 });
    expect(b.cells[i]).toBe(0);
    expect(b.wrong[i]).toBe(wrongOf(i));
    expect(b.lives).toBe(2);
    expect(b.pending).toEqual([]);
    expect(b.missed).toEqual({ cell: i, count: 1 });
    // The batch's answer after it changes nothing.
    expect(answered(b, a.move!)).toBe(b);
    // Clashes aren't the test under lives: nothing is "clash", and a full grid is never Not quite.
    expect(b.clashes.size).toBe(0);
    expect(notQuite(b)).toBe(false);
  });

  test("the same wrong digit in the same cell isn't sent again, and costs nothing", () => {
    const i = open[0]!;
    let v = wrongAt(press(tap(fresh(), i), wrongOf(i)).view, { i, d: wrongOf(i), lives: 2 });
    v = erase(v).view;
    expect(v.wrong[i]).toBe(0);
    const again = press(v, wrongOf(i));
    expect(again.move).toBeUndefined();
    expect(again.view.wrong[i]).toBe(wrongOf(i));
    expect(again.view.lives).toBe(2);
    expect(again.view.clashBump).toBe(v.clashBump + 1);
    // Another digit there is a new set, and replaces the red one.
    const other = press(again.view, right(i));
    expect(other.move).toEqual({ k: "set", i, d: right(i) });
    expect(other.view.wrong[i]).toBe(0);
  });

  test("erase clears a wrong number here and never sends clear", () => {
    const i = open[0]!;
    const v = wrongAt(press(tap(fresh(), i), wrongOf(i)).view, { i, d: wrongOf(i), lives: 2 });
    const e = erase(v);
    expect(e.move).toBeUndefined();
    expect(e.view.wrong[i]).toBe(0);
    // Notes still go on the empty cell, and erase clears them, never sent.
    const noted = press(toggleNotes(e.view), 5).view;
    expect(noted.notes[i]).not.toBe(0);
    const cleared = erase(noted);
    expect(cleared.move).toBeUndefined();
    expect(cleared.view.notes[i]).toBe(0);
  });

  test("hints count down to spent; a hint clears a red number in its cell", () => {
    const i = open[0]!;
    let v = wrongAt(press(tap(fresh(), i), wrongOf(i)).view, { i, d: wrongOf(i), lives: 2 });
    v = reveal(v, { i, d: right(i) });
    expect(v.wrong[i]).toBe(0);
    expect(v.hintsLeft).toBe(2);
    v = reveal(reveal(v, { i: open[1]!, d: right(open[1]!) }), { i: open[2]!, d: right(open[2]!) });
    expect(v.hintsLeft).toBe(0);
    expect(hintsSpent(v)).toBe(true);
  });

  test("out of lives: the solution fills in and nothing more goes in", () => {
    const v = revealSolution(fresh({ lives: 1 }), SAMPLE_SOLUTION);
    expect(isOut(v)).toBe(true);
    expect(isSolved(v)).toBe(false);
    expect(v.lives).toBe(0);
    expect(v.selected).toBeNull();
    expect(tap(v, open[0]!)).toBe(v);
    expect(press({ ...v, selected: open[0]! }, 1).move).toBeUndefined();
  });

  test("solved only once every set is in and taken", () => {
    const cells = [...SAMPLE_SOLUTION];
    const last = open.at(-1)!;
    cells[last] = 0;
    const a = press(tap(fresh({ cells }), last), right(last));
    expect(isSolved(a.view)).toBe(false);
    expect(isSolved(answered(a.view, a.move!))).toBe(true);
  });

  test("resuming shows the lives, hints left, and each still-open cell's latest wrong number", () => {
    const [i, j, k] = [open[0]!, open[1]!, open[2]!];
    const cells = [...SAMPLE_GIVENS];
    cells[k] = right(k);
    const v = fresh({
      cells,
      lives: 0,
      hintsLeft: 1,
      wrong: [
        { i, d: wrongOf(i) },
        { i, d: (wrongOf(i) % 9) + 1 },
        { i: k, d: wrongOf(k) },
      ],
      solution: SAMPLE_SOLUTION,
    });
    expect(v.lives).toBe(0);
    expect(v.hintsLeft).toBe(1);
    expect(v.wrong[i]).toBe((wrongOf(i) % 9) + 1);
    // Fixed since: its wrong number doesn't show.
    expect(v.wrong[k]).toBe(0);
    expect(v.wrong[j]).toBe(0);
    // Both wrong digits stay known in that cell.
    expect(v.tried[i]).toBe((1 << (wrongOf(i) - 1)) | (1 << (((wrongOf(i) % 9) + 1) - 1)));
    expect(isOut(v)).toBe(true);
  });
});

// ---------------------------------------------------------------------------------------------

/** A run session that records what the board sends, and lets a test answer it. */
function fakeSession(state: BoardState = livesState()) {
  const sent: { move: NineLivesMove; options?: SendOptions }[] = [];
  const answers: (() => void)[] = [];
  const listeners = new Set<(e: RunEvent<BoardState, Reveal>) => void>();
  let hints = 0;
  const session: RunSession<{ givens: number[] }, BoardState, NineLivesMove, Reveal> = {
    start: {
      run: "r",
      game: "nine-lives",
      date: "2027-01-04",
      number: 1,
      level: 1,
      startedAt: 0,
      now: 0,
      puzzle: { givens: [...SAMPLE_GIVENS] },
      state,
      seq: 0,
      hints: 0,
      result: null,
      closesAt: 1,
      hintMs: 0,
    },
    game: "nine-lives",
    result: null,
    get hints() {
      return hints;
    },
    send: (move, options) => {
      sent.push({ move, options });
      return new Promise((done) => answers.push(() => done(null)));
    },
    flush: async () => {},
    hint: async () => {
      if (hints >= 3) return null;
      const i = open[10 + hints]!;
      hints++;
      return { i, d: right(i) };
    },
    giveUp: async () => null,
    subscribe: (fn) => {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
    serverNow: () => 0,
    elapsedMs: () => 0,
  };
  const emit = (e: RunEvent<BoardState, Reveal>) => listeners.forEach((fn) => fn(e));
  /** The server answers the oldest waiting batch, revealing `reveals`. */
  const answer = async (reveals: Reveal[] = []) => {
    await act(async () => {
      emit({ kind: "accepted", seq: sent.length, reveals, progress: 0 });
      answers.shift()?.();
    });
  };
  return { session, sent, answer, emit };
}

let root: HTMLElement | undefined;
beforeEach(() => localStorage.clear());
afterEach(() => {
  if (root) {
    render(null, root);
    root.remove();
  }
  root = undefined;
});

function mount(session: RunSession<{ givens: number[] }, BoardState, NineLivesMove, Reveal>, playing = true): void {
  const el = document.createElement("div");
  root = el;
  document.body.append(el);
  act(() => render(h(nineLives.Screen, { session, playing }), el));
}

const cell = (i: number) => root!.querySelector<HTMLButtonElement>(`[data-cell="${i}"]`)!;
const key = (d: number) => root!.querySelector<HTMLButtonElement>(`[data-key="${d}"]`)!;
const hintButton = () => root!.querySelector<HTMLButtonElement>("#nl-hint")!;
const lives = () => root!.querySelector(".nl-lives")!;
const click = (el: HTMLElement) => act(() => el.click());
const tips = () => [...document.querySelectorAll(".tip span")].map((t) => t.textContent);

describe("the play screen under the lives rules", () => {
  test("shows three lives and three hints; old runs show neither", () => {
    const fake = fakeSession();
    mount(fake.session);
    expect(lives().getAttribute("aria-label")).toBe("3 lives left");
    expect(root!.querySelectorAll(".nl-life:not(.nl-lost)")).toHaveLength(3);
    expect(hintButton().getAttribute("aria-label")).toBe("Hint, 3 left");
    render(null, root!);
    mount(fakeSession({ cells: [...SAMPLE_GIVENS], hinted: [] }).session);
    expect(root!.querySelector(".nl-lives")).toBeNull();
    expect(hintButton().getAttribute("aria-label")).toBe("Hint");
    expect(hintButton().textContent?.trim()).toBe("Hint");
  });

  test("every set goes urgent; a right one locks when the answer comes", async () => {
    const fake = fakeSession();
    mount(fake.session);
    const i = open[0]!;
    click(cell(i));
    click(key(right(i)));
    expect(fake.sent).toEqual([{ move: { k: "set", i, d: right(i) }, options: { urgent: true } }]);
    expect(cell(i).getAttribute("aria-label")).toContain(`, ${right(i)}`);
    await fake.answer();
    // Locked: another number changes nothing.
    click(key(wrongOf(i)));
    expect(fake.sent).toHaveLength(1);
  });

  test("a wrong number turns red, a life goes, and its tip shows once", async () => {
    const fake = fakeSession();
    mount(fake.session);
    const i = open[0]!;
    click(cell(i));
    click(key(wrongOf(i)));
    await fake.answer([{ k: "wrong", i, d: wrongOf(i), lives: 2 }]);
    expect(cell(i).getAttribute("aria-label")).toMatch(new RegExp(`, ${wrongOf(i)}, wrong$`));
    expect(lives().getAttribute("aria-label")).toBe("2 lives left");
    expect(root!.querySelectorAll(".nl-lost")).toHaveLength(1);
    expect(root!.querySelectorAll(".nl-life-pop")).toHaveLength(1);
    expect(tips()).toEqual(["Wrong numbers cost a life."]);
    // The same digit again: red again, never sent. Erase clears it, never sent.
    click(key(wrongOf(i)));
    expect(fake.sent).toHaveLength(1);
    click([...root!.querySelectorAll<HTMLButtonElement>("button")].find((b) => b.textContent === "Erase")!);
    expect(cell(i).getAttribute("aria-label")).toMatch(/empty$/);
    expect(fake.sent).toHaveLength(1);
    // The next number entered learns the tip.
    click(key(right(i)));
    expect(tips()).toEqual([]);
  });

  test("three hints, then the button is spent; the first one's tip shows", async () => {
    const fake = fakeSession();
    mount(fake.session);
    for (let n = 0; n < 3; n++) {
      await act(async () => hintButton().click());
      await act(async () => {});
      if (n === 0) expect(tips()).toEqual(["Three hints a day."]);
    }
    expect(hintButton().getAttribute("aria-label")).toBe("Hint, 0 left");
    expect(hintButton().disabled).toBe(true);
    expect(hintButton().classList.contains("nl-spent")).toBe(true);
    expect(cell(open[12]!).getAttribute("aria-label")).toContain("hint");
  });

  test("the third wrong number fills in the solution, under Out of lives", async () => {
    const fake = fakeSession(livesState({ lives: 1, wrong: [{ i: open[5]!, d: wrongOf(open[5]!) }, { i: open[6]!, d: wrongOf(open[6]!) }] }));
    mount(fake.session);
    expect(root!.querySelectorAll(".nl-lost")).toHaveLength(2);
    // Lost before the screen opened: ghosts, no pop.
    expect(root!.querySelectorAll(".nl-life-pop")).toHaveLength(0);
    const i = open[0]!;
    click(cell(i));
    click(key(wrongOf(i)));
    await fake.answer([{ k: "wrong", i, d: wrongOf(i), lives: 0, solution: SAMPLE_SOLUTION }]);
    expect(root!.querySelector(".nl-not-quite")!.textContent).toBe("Out of lives");
    expect(cell(i).getAttribute("aria-label")).toMatch(new RegExp(`, ${right(i)}, answer$`));
    expect(root!.querySelectorAll(".nl-answer")).toHaveLength(open.length);
    expect(key(1).disabled).toBe(true);
  });

  test("resuming a run that ran out shows the solution and no lives", () => {
    mount(fakeSession(livesState({ lives: 0, solution: SAMPLE_SOLUTION })).session, false);
    expect(root!.querySelector(".nl-not-quite")!.textContent).toBe("Out of lives");
    expect(root!.querySelectorAll(".nl-lost")).toHaveLength(3);
  });

  test("the end waits for the solution only when out of lives", () => {
    const r = { outcome: "missed" } as DailyResult;
    expect(nineLives.endDelayMs!(r)).toBeGreaterThan(1000);
    expect(nineLives.endDelayMs!({ ...r, outcome: "solved" })).toBe(0);
    expect(nineLives.endDelayMs!({ ...r, outcome: "gaveUp" })).toBe(0);
  });
});

describe("Out of lives, in words", () => {
  const result = (game: DailyResult["game"], outcome: DailyResult["outcome"]): DailyResult =>
    ({ game, date: "2027-01-04", number: 3, outcome, timeMs: 61_000, hints: 0, tooFast: false, progress: 0.5 }) as DailyResult;

  test("the end, the Dish, the board and the TV say Out of lives for Nine Lives' miss, Missed for Sniff's", () => {
    expect(endTitle(result("nine-lives", "missed"))).toBe("Out of lives");
    expect(endTitle(result("sniff", "missed"))).toBe("Missed");
    expect(endTitle(result("nine-lives", "solved"))).toBe("Solved");
    expect(resultWords(result("nine-lives", "missed"))).toBe("Out of lives");
    expect(resultWords(result("sniff", "missed"))).toBe("Missed");
    // Home's Today tiles are narrow.
    expect(resultWords(result("nine-lives", "missed"), true)).toBe("No lives");
    expect(resultWords(result("sniff", "missed"), true)).toBe("Missed");
    expect(outcomeWords(result("nine-lives", "gaveUp"))).toBe("Gave up");
    expect(tvResultWords(result("nine-lives", "missed"))).toBe("Out of lives");
    expect(tvResultWords(result("sniff", "missed"))).toBe("Missed");
    expect(shareText("Nine Lives", result("nine-lives", "missed"))).toBe("Nine Lives 3: Out of lives");
  });
});

describe("the TV's watch view under the lives rules", () => {
  const watch = (state: BoardState) => {
    const el = document.createElement("div");
    root = el;
    document.body.append(el);
    act(() => render(h(NineLivesWatch, { state, puzzle: { givens: SAMPLE_GIVENS } }), el));
    return el;
  };

  test("shows lives, hints left and each wrong number", () => {
    const i = open[0]!;
    const el = watch(livesState({ lives: 2, hintsLeft: 1, wrong: [{ i, d: wrongOf(i) }] }));
    expect(el.querySelector(".nl-lives")!.getAttribute("aria-label")).toBe("2 lives left");
    expect(el.querySelector(".nl-watch-line")!.textContent).toBe("1 hint left");
    expect(el.querySelector(`[data-cell="${i}"] .nl-clash .nl-digit`)!.textContent).toBe(String(wrongOf(i)));
  });

  test("out of lives: the solution, and the words", () => {
    const el = watch(livesState({ lives: 0, hintsLeft: 3, solution: SAMPLE_SOLUTION }));
    expect(el.querySelector(".nl-watch-line")!.textContent).toBe("Out of lives");
    expect(el.querySelectorAll(".nl-answer")).toHaveLength(open.length);
  });

  test("a run on the first rules shows the quilt alone", () => {
    const el = watch({ cells: [...SAMPLE_GIVENS], hinted: [] });
    expect(el.querySelector(".nl-watch-panel")).toBeNull();
  });
});
