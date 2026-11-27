/**
 * The Dish's words, pure: times, results, places and the share text. Nothing here gives a puzzle
 * away (spec §7 "Share"): no letters, no cells, only how it went.
 */
import type { DailyResult } from "@pounce/play-api/daily/module";

/** The link a share carries: it offers the app and the browser. */
export const SHARE_URL = "https://play.conleychaos.com/daily";

const pad = (n: number) => String(n).padStart(2, "0");

/** "0:07", "1:42", "1:02:03". */
export function clock(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return h > 0 ? `${h}:${pad(m)}:${pad(s % 60)}` : `${m}:${pad(s % 60)}`;
}

const points = (n: number) => `${n.toLocaleString("en-US")} ${n === 1 ? "point" : "points"}`;

/** How a run that didn't end solved ended, in a word or two: Nine Lives' miss is out of lives. */
export function outcomeWords(r: Pick<DailyResult, "game" | "outcome">): string {
  switch (r.outcome) {
    case "solved":
      return "Solved";
    case "missed":
      return r.game === "nine-lives" ? "Out of lives" : "Missed";
    case "gaveUp":
      return "Gave up";
    case "closed":
      return "Unfinished";
    default:
      return "Done";
  }
}

/** A result in a few words: "4 of 6", "4:05", "1,240 points", "Missed", "Out of lives". */
export function resultWords(r: DailyResult): string {
  if (typeof r.points === "number") return points(r.points);
  switch (r.outcome) {
    case "solved":
      return typeof r.guesses === "number" ? `${r.guesses} of 6` : clock(r.timeMs);
    case "missed":
    case "gaveUp":
    case "closed":
      return outcomeWords(r);
    default:
      return clock(r.timeMs);
  }
}

/**
 * A puzzle's number as shown, or null when it's below 1: numbers count from launch day (the
 * server's `LAUNCH`, No. 1), so a day before it is 0 or less, and never shown.
 */
export const puzzleNumber = (n: number): string | null => (n >= 1 ? String(n) : null);

/** "Sniff 12", or just "Sniff" while its number isn't shown. */
export function puzzleName(title: string, n: number): string {
  const shown = puzzleNumber(n);
  return shown ? `${title} ${shown}` : title;
}

/** "Sniff 12: 4 of 6", "Nine Lives 3: 4:05, 1 hint". */
export function shareText(title: string, r: DailyResult): string {
  const hints = r.hints > 0 && typeof r.guesses !== "number" && typeof r.points !== "number" ? `, ${r.hints} ${r.hints === 1 ? "hint" : "hints"}` : "";
  return `${puzzleName(title, r.number)}: ${resultWords(r)}${hints}`;
}

export function ordinal(n: number): string {
  const teen = n % 100 >= 11 && n % 100 <= 13;
  const suffix = teen ? "th" : ({ 1: "st", 2: "nd", 3: "rd" } as Record<number, string>)[n % 10] ?? "th";
  return `${n}${suffix}`;
}

/** "1st of 3"; just "1st" with nobody else on the board. */
export const placeWords = (rank: number, of: number): string => (of > 1 ? `${ordinal(rank)} of ${of}` : ordinal(rank));
