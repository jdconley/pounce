import { N, type Cells } from "./grid";

/** Grids for tests and the golden vectors. Never used to make a daily puzzle. */

/** A valid solved grid: the shifted pattern grid. */
export const SOLVED: Cells = Array.from({ length: N }, (_, i) => {
  const r = Math.floor(i / 9);
  const c = i % 9;
  return ((r * 3 + Math.floor(r / 3) + c) % 9) + 1;
});

/** Reads an 81-character puzzle string, "." or "0" for an empty cell. */
export function cellsOf(text: string): Cells {
  const digits = text.replace(/\s/g, "");
  if (digits.length !== N) throw new RangeError(`need ${N} cells, got ${digits.length}`);
  return [...digits].map((ch) => (ch === "." ? 0 : Number(ch)));
}
