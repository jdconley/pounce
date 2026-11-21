/**
 * Sniff's board as one value, the web twin of PounceKit's `SniffBoard`: the server's guesses and
 * marks, the row being typed, and a guess waiting on the server. Marks only ever come from the
 * server; this file never works one out.
 */
import { keyboardMarks } from "@pounce/play-api/daily/sniff/keyboard";
import { LETTERS, TRIES, type Guess, type Mark, type SniffReveal } from "@pounce/play-api/daily/sniff/types";

export type SniffBoard = { guesses: Guess[]; draft: string; pending: string | null; answer: string | null };
export type Submit =
  | { outcome: "send"; word: string; board: SniffBoard }
  | { outcome: "short" | "unknown" | "busy" | "over"; board: SniffBoard };

export const emptyBoard = (): SniffBoard => ({ guesses: [], draft: "", pending: null, answer: null });

export const isSolved = (b: SniffBoard) => b.guesses.some((g) => g.marks.every((m) => m === "spot"));
export const isOver = (b: SniffBoard) => isSolved(b) || b.guesses.length >= TRIES;
const canType = (b: SniffBoard) => !isOver(b) && b.pending === null;

export function typeLetter(b: SniffBoard, letter: string): SniffBoard {
  const l = letter.toLowerCase();
  if (!canType(b) || b.draft.length >= LETTERS || !/^[a-z]$/.test(l)) return b;
  return { ...b, draft: b.draft + l };
}

export function deleteLetter(b: SniffBoard): SniffBoard {
  return canType(b) && b.draft ? { ...b, draft: b.draft.slice(0, -1) } : b;
}

export function submit(b: SniffBoard, allowed: (word: string) => boolean): Submit {
  if (isOver(b)) return { outcome: "over", board: b };
  if (b.pending !== null) return { outcome: "busy", board: b };
  if (b.draft.length < LETTERS) return { outcome: "short", board: b };
  if (!allowed(b.draft)) return { outcome: "unknown", board: b };
  return { outcome: "send", word: b.draft, board: { ...b, pending: b.draft } };
}

/** The server's marks for the pending guess (or any guess, when resuming). */
export function reveal(b: SniffBoard, r: SniffReveal): SniffBoard {
  return { guesses: [...b.guesses, { word: r.word, marks: r.marks }], draft: "", pending: null, answer: r.answer ?? b.answer };
}

/** The server didn't take the pending guess: the row stays typed to send again. */
export const refused = (b: SniffBoard): SniffBoard => ({ ...b, pending: null });

export const keys = (b: SniffBoard): Partial<Record<string, Mark>> => keyboardMarks(b.guesses);
