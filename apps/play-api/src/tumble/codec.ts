import { JUNK, TOTAL, TRICKS, W, type Box } from "./box";

/**
 * A box as text, for fixtures and tests: one string per row, top row (y 21) first. Cells are
 * `.`, `1` to `9` for the toy (its index + 1) and `#` for junk; tricks are `.` or `a` to `h` in
 * `TRICKS` order.
 */
export type BoxText = { cells: string[]; tricks: string[] };

const cellChar = (v: number): string => (v === 0 ? "." : v === JUNK ? "#" : String(v));
const trickChar = (v: number): string => (v === 0 ? "." : String.fromCharCode(96 + v));

export function toText(box: Pick<Box, "cells" | "tricks">): BoxText {
  const cells: string[] = [];
  const tricks: string[] = [];
  for (let y = TOTAL - 1; y >= 0; y--) {
    let c = "";
    let t = "";
    for (let x = 0; x < W; x++) {
      c += cellChar(box.cells[y * W + x] as number);
      t += trickChar(box.tricks[y * W + x] as number);
    }
    cells.push(c);
    tricks.push(t);
  }
  return { cells, tricks };
}

/** The reverse of `toText`. Shorter lists are the bottom rows (the last string is y 0); missing rows are empty. */
export function fromText(cellRows: readonly string[], trickRows: readonly string[] = []): Pick<Box, "cells" | "tricks"> {
  const cells = new Array<number>(TOTAL * W).fill(0);
  const tricks = new Array<number>(TOTAL * W).fill(0);
  cellRows.forEach((row, i) => {
    const y = cellRows.length - 1 - i;
    for (let x = 0; x < W; x++) {
      const ch = row[x] ?? ".";
      cells[y * W + x] = ch === "." ? 0 : ch === "#" ? JUNK : Number(ch);
    }
  });
  trickRows.forEach((row, i) => {
    const y = trickRows.length - 1 - i;
    for (let x = 0; x < W; x++) {
      const ch = row[x] ?? ".";
      tricks[y * W + x] = ch === "." ? 0 : ch.charCodeAt(0) - 96;
    }
  });
  if (tricks.some((t) => t > TRICKS.length)) throw new RangeError("unknown trick letter");
  return { cells, tricks };
}
