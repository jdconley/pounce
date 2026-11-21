import { describe, expect, test } from "vitest";

import { LocalDriver, SAMPLE_GIVENS, SAMPLE_SOLUTION } from "../src/daily/nine-lives/local";
import {
  adopt,
  countOf,
  erase,
  hasNote,
  isSolved,
  move,
  notQuite,
  press,
  reveal,
  start,
  tap,
  toggleNotes,
  type View,
} from "../src/daily/nine-lives/model";

const open = SAMPLE_GIVENS.flatMap((d, i) => (d === 0 ? [i] : []));
const fresh = (): View => start({ givens: SAMPLE_GIVENS });

/** Fills every open cell right except the last. */
function almost(): View {
  let v = fresh();
  for (const i of open.slice(0, -1)) v = press(tap(v, i), SAMPLE_SOLUTION[i]!).view;
  return v;
}

describe("Nine Lives on the web: the board model", () => {
  test("starts on the first open cell, nothing clashing", () => {
    const v = fresh();
    expect(v.selected).toBe(open[0]);
    expect(v.clashes.size).toBe(0);
    expect(isSolved(v)).toBe(false);
  });

  test("a number fills the cell and returns the move; the same number again clears it", () => {
    const v = tap(fresh(), open[0]!);
    const a = press(v, 4);
    expect(a.move).toEqual({ k: "set", i: open[0], d: 4 });
    expect(a.view.cells[open[0]!]).toBe(4);
    expect(a.view.placed).toEqual({ cell: open[0], count: 1 });
    const b = press(a.view, 4);
    expect(b.move).toEqual({ k: "clear", i: open[0] });
    expect(b.view.cells[open[0]!]).toBe(0);
  });

  test("a given takes nothing", () => {
    const given = SAMPLE_GIVENS.findIndex((d) => d !== 0);
    const v = tap(fresh(), given);
    expect(press(v, 1)).toEqual({ view: v });
    expect(erase(v)).toEqual({ view: v });
    expect(press({ ...v, selected: null }, 1).move).toBeUndefined();
  });

  test("a clash shows and bumps; clearing it clears the clash", () => {
    const i = open[0]!;
    const rowGiven = SAMPLE_GIVENS.slice(Math.floor(i / 9) * 9, Math.floor(i / 9) * 9 + 9).find((d) => d !== 0)!;
    const a = press(tap(fresh(), i), rowGiven).view;
    expect(a.clashes.has(i)).toBe(true);
    expect(a.clashBump).toBe(1);
    const b = erase(a);
    expect(b.move).toEqual({ k: "clear", i });
    expect(b.view.clashes.size).toBe(0);
  });

  test("notes toggle per digit, are never sent, and clear when a peer takes the digit", () => {
    const [i, j] = [open[0]!, open[1]!];
    let v = toggleNotes(tap(fresh(), i));
    const a = press(v, 2);
    expect(a.move).toBeUndefined();
    v = press(a.view, 7).view;
    expect(hasNote(v, i, 2) && hasNote(v, i, 7)).toBe(true);
    v = press(v, 7).view;
    expect(hasNote(v, i, 7)).toBe(false);
    // A peer placing 2 removes the note.
    v = press(toggleNotes(tap(v, j)), 2).view;
    expect(hasNote(v, i, 2)).toBe(false);
    // Erase on an empty cell clears its notes.
    v = press(toggleNotes(tap(v, open[40]!)), 3).view;
    expect(erase(v).view.notes[open[40]!]).toBe(0);
    // Notes don't go on a filled cell.
    const onFilled = tap(v, j);
    expect(press(onFilled, 5).view).toBe(onFilled);
  });

  test("arrows move and wrap", () => {
    const v = tap(fresh(), 0);
    expect(move(v, 0, -1).selected).toBe(8);
    expect(move(v, -1, 0).selected).toBe(72);
    expect(move(move(v, 1, 1), 0, 1).selected).toBe(11);
    expect(move({ ...v, selected: null }, 0, 1).selected).toBe(1);
  });

  test("full with a mistake is Not quite, and fixing it solves", () => {
    const last = open.at(-1)!;
    const wrong = (SAMPLE_SOLUTION[last]! % 9) + 1;
    const a = press(tap(almost(), last), wrong).view;
    expect(notQuite(a)).toBe(true);
    expect(a.notQuiteBump).toBe(1);
    const b = press(a, SAMPLE_SOLUTION[last]!).view;
    expect(isSolved(b)).toBe(true);
    expect(b.selected).toBeNull();
    // Solved: nothing more goes in.
    expect(tap(b, 0)).toBe(b);
    expect(move(b, 1, 0)).toBe(b);
    expect(press({ ...b, selected: last }, 1).move).toBeUndefined();
    expect(countOf(b, 1)).toBe(9);
  });

  test("a hint's reveal locks the cell and selects it; the local driver answers from the sample", async () => {
    const driver = new LocalDriver();
    const r = (await driver.hint())!;
    expect(r).toEqual({ i: open[0], d: SAMPLE_SOLUTION[open[0]!] });
    const v = reveal(fresh(), r);
    expect(v.hinted).toEqual([r.i]);
    expect(v.selected).toBe(r.i);
    expect(press(v, 1).move).toBeUndefined();
    driver.send({ k: "set", i: open[1]!, d: SAMPLE_SOLUTION[open[1]!]! });
    driver.send({ k: "clear", i: open[1]! });
    expect(driver.sent).toHaveLength(2);
    for (let k = 0; k < open.length; k++) await driver.hint();
    expect(await driver.hint()).toBeNull();
  });

  test("adopting the server's board, and resuming from it", () => {
    const state = { cells: [...SAMPLE_GIVENS], hinted: [open[0]!] };
    state.cells[open[0]!] = SAMPLE_SOLUTION[open[0]!]!;
    const v = adopt(fresh(), state);
    expect(v.cells).toEqual(state.cells);
    expect(v.hinted).toEqual([open[0]]);
    const resumed = start({ givens: SAMPLE_GIVENS }, state);
    expect(resumed.selected).toBe(open[1]);
    const done = start({ givens: SAMPLE_GIVENS }, { cells: SAMPLE_SOLUTION, hinted: [] });
    expect(done.selected).toBeNull();
  });
});
