import type { Guess, Mark } from "./types";

const RANK: Record<Mark, number> = { none: 0, near: 1, spot: 2 };

/** The best mark each letter has had in the server's marks: what the keyboard shows. Client-safe. */
export function keyboardMarks(guesses: readonly Guess[]): Partial<Record<string, Mark>> {
  const keys: Partial<Record<string, Mark>> = {};
  for (const { word, marks } of guesses) {
    [...word].forEach((letter, i) => {
      const mark = marks[i] as Mark;
      const had = keys[letter];
      if (had === undefined || RANK[mark] > RANK[had]) keys[letter] = mark;
    });
  }
  return keys;
}
