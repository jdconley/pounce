/**
 * Box Fort's golden vectors (spec §12): each is a puzzle as a client sees it, then every move with
 * what the server answered and the state after it. The TS rules write them
 * (`pnpm --filter @pounce/play-api vectors:box-fort`, into `fixtures/daily/box-fort/`), and the
 * Swift rules (PounceKit `Daily/BoxFort`) must reproduce every step.
 */
import { createRng } from "../../rules/rng";

import { greedyMove, type Place } from "./greedy";
import { boxFort, type BoxFortPublicPuzzle, type BoxFortPublicState, type BoxFortReveal } from "./module";
import { place, SIZE, type Cleared } from "./rules";

import type { DayLevel } from "./contract";
import type { BoxFortPuzzle } from "./maker";
import type { Piece } from "./pieces";

export type VectorStep =
  | {
      move: Place;
      ok: true;
      /** Points the move earned, the full fort included. */
      gained: number;
      cleared: Cleared;
      reveal: BoxFortReveal | null;
      end: "done" | null;
      state: BoxFortPublicState;
    }
  | { move: Place; ok: false; reason: "illegal" | "over"; state: BoxFortPublicState };

export type VectorFile = { name: string; start: BoxFortPublicPuzzle; steps: VectorStep[] };

/** Plays `moves` (or greedily, when `moves` is "greedy") and records every step. */
export function record(name: string, p: BoxFortPuzzle, moves: readonly Place[] | "greedy"): VectorFile {
  let s = boxFort.init(p);
  const steps: VectorStep[] = [];
  const view = () => boxFort.publicState(p, s) as BoxFortPublicState;
  const next = (i: number): Place | null => {
    if (moves !== "greedy") return moves[i] ?? null;
    const v = view();
    return v.over === null ? greedyMove(v.rug, v.pieces, v.placed) : null;
  };
  for (let i = 0, move = next(0); move !== null; move = next(++i)) {
    const before = s;
    const out = boxFort.apply(p, s, move, 1000 * (i + 1));
    if (!out.ok) {
      steps.push({ move, ok: false, reason: out.reason as "illegal" | "over", state: view() });
      continue;
    }
    s = out.state;
    const piece = (p.sets[before.set] as Piece[])[move.slot] as Piece;
    const cleared = (place(before.rug, piece, move.row, move.col) as { cleared: Cleared }).cleared;
    steps.push({
      move,
      ok: true,
      gained: s.points - before.points,
      cleared,
      reveal: (out.reveal as BoxFortReveal | undefined) ?? null,
      end: out.end === "done" ? "done" : null,
      state: view(),
    });
  }
  return { name, start: boxFort.publicPuzzle(p) as BoxFortPublicPuzzle, steps };
}

/** A rug from eight strings of eight: a digit is a box of that tint, "#" a starting box (7). */
export function rugOf(rows: readonly string[]): number[] {
  return rows.flatMap((row) => [...row].map((ch) => (ch === "#" ? 7 : ch === "." ? 0 : Number(ch))));
}

const at = (slot: number, row: number, col: number): Place => ({ k: "place", slot, row, col });

function piece(id: string, tint: number, picture: string): Piece {
  const cells = picture
    .split("/")
    .flatMap((line, r) => [...line].flatMap((ch, c): [number, number][] => (ch === "#" ? [[r, c]] : [])));
  return { id, tint, cells };
}

const dot = (tint: number) => piece("dot", tint, "#");
const duoH = (tint: number) => piece("duo-h", tint, "##");
const trioH = (tint: number) => piece("trio-h", tint, "###");
const trioV = (tint: number) => piece("trio-v", tint, "#/#/#");
const duoV = (tint: number) => piece("duo-v", tint, "#/#");
const sq2 = (tint: number) => piece("sq2", tint, "##/##");
const sq3 = (tint: number) => piece("sq3", tint, "###/###/###");
const plus = (tint: number) => piece("plus", tint, ".#./###/.#.");
const pawsB = (tint: number) => piece("paws-b", tint, ".#/#.");
const ellA = (tint: number) => piece("ell-a", tint, "#./#./##");

const EMPTY = Array<number>(SIZE * SIZE).fill(0);
/** Box Fort makes its day from the seed and level alone; the date and cycle key are unused. */
const DAY = { date: "2027-01-04", key: [1, 2, 3, 4] as [number, number, number, number] };

/** Seeds for the day vectors: one made puzzle per level, played greedily. */
const DAY_SEEDS: Record<DayLevel, [number, number, number, number]> = {
  1: [11, 1, 2, 3],
  2: [22, 4, 5, 6],
  3: [33, 7, 8, 9],
  4: [44, 10, 11, 12],
  5: [55, 13, 14, 15],
  6: [66, 16, 17, 18],
  7: [77, 19, 20, 21],
};

export function buildVectors(): VectorFile[] {
  const files: VectorFile[] = [
    record("placements", { rug: EMPTY, sets: [[dot(1), ellA(2), pawsB(3)], [plus(4), trioV(5), sq2(6)], [dot(1), dot(2), dot(3)]] }, [
      at(1, 0, 0),
      at(0, 7, 7),
      at(2, 4, 4),
      at(0, 2, 3),
      at(2, 5, 0),
      at(1, 1, 6),
    ]),
    record(
      "clears",
      {
        rug: rugOf([
          "######..",
          "######..",
          ".......#",
          ".......#",
          ".......#",
          ".......#",
          ".......#",
          ".......#",
        ]),
        sets: [[duoV(3), sq2(2), dot(4)], [dot(5), dot(6), dot(1)]],
      },
      // A column, then two rows at once, then nothing; the last set is the full fort.
      [at(0, 0, 7), at(1, 0, 6), at(2, 7, 7), at(0, 0, 0), at(1, 0, 1), at(2, 0, 2)],
    ),
    record(
      "cross",
      {
        rug: rugOf([
          ".......#",
          ".......#",
          ".......#",
          "#######.",
          ".......#",
          "#####..#",
          "#####..#",
          "#####..#",
        ]),
        sets: [[dot(1), sq3(2), dot(3)]],
      },
      // A row and a column together, crossing at (3, 7); then three rows at once.
      [at(0, 3, 7), at(1, 5, 5), at(2, 0, 0)],
    ),
    record(
      "combos",
      {
        rug: rugOf([
          "#######.",
          "#######.",
          "#######.",
          "#######.",
          "........",
          "........",
          "........",
          "........",
        ]),
        sets: [[dot(1), dot(2), dot(3)], [dot(4), duoH(5), dot(6)]],
      },
      [at(0, 0, 7), at(1, 1, 7), at(2, 2, 7), at(0, 3, 7), at(1, 6, 0), at(2, 7, 7)],
    ),
    record(
      "nothing-fits-mid-set",
      {
        rug: rugOf(["#.#.#.#.", ".#.#.#.#", "#.#.#.#.", ".#.#.#.#", "#.#.#.#.", ".#.#.#.#", "#.#.#.#.", ".#.#.#.#"]),
        sets: [[dot(1), sq2(2), trioV(3)], [dot(1), dot(1), dot(1)]],
      },
      [at(0, 0, 1), at(1, 2, 2)],
    ),
    record(
      "nothing-fits-on-deal",
      {
        rug: rugOf(["#.#.#.#.", ".#.#.#.#", "#.#.#.#.", ".#.#.#.#", "#.#.#.#.", ".#.#.#.#", "#.#.#.#.", ".#.#.#.#"]),
        sets: [[dot(1), dot(2), dot(3)], [sq2(4), duoH(5), sq3(6)], [dot(1), dot(1), dot(1)]],
      },
      [at(0, 0, 1), at(1, 0, 3), at(2, 0, 5), at(0, 0, 7)],
    ),
    record(
      "full-fort",
      {
        rug: rugOf([
          "........",
          "........",
          "........",
          "........",
          "........",
          "........",
          "#####...",
          "#####...",
        ]),
        sets: [[dot(1), dot(2), dot(3)], [trioH(4), dot(5), trioH(6)]],
      },
      // The last piece clears two rows: line bonus, combo and the full fort all add.
      [at(0, 0, 0), at(1, 0, 1), at(2, 0, 2), at(1, 3, 3), at(0, 6, 5), at(2, 7, 5)],
    ),
    record(
      "illegal",
      { rug: rugOf(["#.......", "........", "........", "........", "........", "........", "........", "........"]), sets: [[sq3(1), dot(2), dot(3)]] },
      [
        at(1, 0, 0), // on a box
        at(0, 6, 0), // off the bottom
        at(0, 0, 6), // off the right
        at(0, 1, 1),
        at(0, 4, 4), // already placed
        at(1, 1, 1), // on the piece just placed
        at(1, 7, 7),
        at(2, 7, 6),
        at(2, 0, 7), // after the end
      ],
    ),
  ];
  for (const level of [1, 2, 3, 4, 5, 6, 7] as DayLevel[]) {
    files.push(record(`day-${level}`, boxFort.make(createRng(DAY_SEEDS[level]), level, DAY), "greedy"));
  }
  return files;
}

/** JSON with two-space indents, except that arrays of numbers (and of number pairs) stay on one line. */
export function formatVector(value: unknown, indent = ""): string {
  const flat = (v: unknown): boolean =>
    Array.isArray(v) && v.every((x) => typeof x !== "object" || (Array.isArray(x) && x.every((y) => typeof y !== "object")));
  if (value === null || typeof value !== "object" || flat(value)) return JSON.stringify(value);
  const inner = `${indent}  `;
  if (Array.isArray(value)) {
    return `[\n${value.map((v) => inner + formatVector(v, inner)).join(",\n")}\n${indent}]`;
  }
  const entries = Object.entries(value).map(([k, v]) => `${inner}${JSON.stringify(k)}: ${formatVector(v, inner)}`);
  return `{\n${entries.join(",\n")}\n${indent}}`;
}
