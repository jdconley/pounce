import type { Mark } from "./types";

/**
 * Marks a guess against the answer. Server only: clients never see the answer, only these marks.
 * Right spots first; then, left to right, a letter is `near` while the answer still has an
 * unmarked copy of it, else `none`. So a letter is marked only as often as the answer holds it.
 */
export function markGuess(answer: string, guess: string): Mark[] {
  const marks: Mark[] = [];
  const left = new Map<string, number>();
  for (let i = 0; i < guess.length; i++) {
    const a = answer[i] as string;
    if (guess[i] === a) {
      marks[i] = "spot";
    } else {
      marks[i] = "none";
      left.set(a, (left.get(a) ?? 0) + 1);
    }
  }
  for (let i = 0; i < guess.length; i++) {
    if (marks[i] === "spot") continue;
    const g = guess[i] as string;
    const n = left.get(g) ?? 0;
    if (n > 0) {
      marks[i] = "near";
      left.set(g, n - 1);
    }
  }
  return marks;
}
