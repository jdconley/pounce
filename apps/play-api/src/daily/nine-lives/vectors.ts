/**
 * The golden vectors (spec §12): Nine Lives' rules as data, so the Swift rules can prove they
 * match. `vectors.test.ts` checks the committed files against these, and rewrites them with
 * `UPDATE_VECTORS=1`.
 */
import { createRng } from "../../rules/rng";

import { grade } from "./grade";
import { clashes, isFull, type NineLivesMove, type NineLivesState } from "./grid";
import { makePuzzle, type NineLivesPuzzle } from "./make";
import { nineLives } from "./module";
import { SAMPLE } from "./samples";

import type { DayLevel } from "../days";

type Step = ({ move: NineLivesMove } | { hint: { i: number; d: number } | null }) & {
  ok: boolean;
  reason?: string;
  cells: string;
  hinted: number[];
  clashes: number[];
  full: boolean;
  end: "solved" | null;
  progress: number;
};

type Action = NineLivesMove | "hint";

const text = (cells: number[]): string => cells.join("");

function play(p: NineLivesPuzzle, actions: Action[], from?: NineLivesState): { steps: Step[]; state: NineLivesState } {
  let s = from ?? nineLives.init(p);
  const steps = actions.map((action): Step => {
    const a = action === "hint" ? nineLives.hint(p, s)! : nineLives.apply(p, s, action, 0);
    if (a.ok) s = a.state;
    // A refused hint (the grid is solved) has no cell: `hint` is null.
    const head = action === "hint" ? { hint: (a.ok ? a.reveal : null) as { i: number; d: number } | null } : { move: action };
    return {
      ...head,
      ok: a.ok,
      ...(a.ok ? {} : { reason: a.reason }),
      cells: text(s.cells),
      hinted: [...s.hinted],
      clashes: clashes(s.cells),
      full: isFull(s.cells),
      end: a.ok && a.end === "solved" ? "solved" : null,
      progress: nineLives.progress(p, s),
    };
  });
  return { steps, state: s };
}

export function rulesVectors(): unknown {
  const p = SAMPLE;
  const open = p.givens.flatMap((d, i) => (d === 0 ? [i] : []));
  const given = p.givens.findIndex((d) => d !== 0);
  const right = (i: number): NineLivesMove => ({ k: "set", i, d: p.solution[i]! });
  const wrong = (i: number): NineLivesMove => ({ k: "set", i, d: (p.solution[i]! % 9) + 1 });
  const [a, b] = open as [number, number];
  const last = open.at(-1)!;
  const allButLast = open.slice(0, -1).map(right);
  const hinted = (nineLives.hint(p, nineLives.init(p)) as { reveal: { i: number } }).reveal.i;
  const sameRowGiven = p.givens.find((d, i) => d !== 0 && Math.floor(i / 9) === Math.floor(a / 9))!;

  const cases: [string, Action[]][] = [
    ["solve in order, then over", [...open.map(right), { k: "clear", i: last }, "hint"]],
    ["a clash is legal, and clearing it clears the clash", [{ k: "set", i: a, d: sameRowGiven }, { k: "clear", i: a }]],
    ["givens are refused", [{ k: "set", i: given, d: (p.givens[given]! % 9) + 1 }, { k: "clear", i: given }]],
    ["hinted cells are locked", ["hint", { k: "set", i: hinted, d: 9 }, { k: "clear", i: hinted }, "hint"]],
    ["overwrite, the same digit again, and clearing an empty cell", [wrong(a), right(a), right(a), { k: "clear", i: a }, { k: "clear", i: a }, wrong(b)]],
    ["a full grid with a mistake goes on until it is fixed", [...allButLast, wrong(last), right(last)]],
    ["a hint on a full wrong grid fixes it", [...allButLast, wrong(last), "hint"]],
  ];
  const wire = play(p, [right(a), wrong(b), "hint"]).state;
  return {
    about: "Nine Lives rules (apps/play-api/src/daily/nine-lives/vectors.ts). Cells are 81 digits, 0 empty.",
    wire: {
      puzzle: nineLives.publicPuzzle(p),
      state: nineLives.publicState(p, wire),
      moves: [right(a), { k: "clear", i: a }],
    },
    cases: cases.map(([name, actions]) => ({ name, givens: text(p.givens), steps: play(p, actions).steps })),
  };
}

/** One puzzle per level from fixed seeds: pins the maker, so a change to it is seen. */
export function puzzleVectors(): unknown {
  return ([1, 2, 3, 4, 5, 6, 7] as DayLevel[]).map((level) => {
    const seed = [level, 0x9e3779b9, 0x85ebca6b, 0xc2b2ae35] as [number, number, number, number];
    const p = makePuzzle(createRng(seed), level);
    return { seed, level, givens: text(p.givens), tier: p.tier, hardest: grade(p.givens)!.hardest };
  });
}
