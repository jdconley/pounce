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

/** A Monday puzzle the maker made (seedOf(101), level 1), pinned for the vectors and the demos. */
export const SAMPLE = {
  givens: cellsOf("600350270050900130030804906400000003080000020500000009301205080025008040064073002"),
  solution: cellsOf("649351278258967134137824956412589763983716425576432819391245687725698341864173592"),
  tier: 1 as const,
};
