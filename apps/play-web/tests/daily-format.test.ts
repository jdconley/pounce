import { describe, expect, test } from "vitest";

import { clock, ordinal, placeWords, puzzleName, puzzleNumber, resultWords, shareText } from "../src/daily/format";

import type { DailyResult } from "@pounce/play-api/daily/module";

const base: DailyResult = { game: "nine-lives", date: "2026-11-23", number: 3, outcome: "solved", timeMs: 245_000, hints: 0, progress: 1, tooFast: false };

describe("the Dish's words", () => {
  test("clock", () => {
    expect(clock(7_400)).toBe("0:07");
    expect(clock(102_000)).toBe("1:42");
    expect(clock(3_599_999)).toBe("59:59");
    expect(clock(3_723_000)).toBe("1:02:03");
    expect(clock(-5)).toBe("0:00");
  });

  test("a result in a few words", () => {
    expect(resultWords(base)).toBe("4:05");
    expect(resultWords({ ...base, game: "sniff", guesses: 4 })).toBe("4 of 6");
    expect(resultWords({ ...base, game: "sniff", outcome: "missed", guesses: 6 })).toBe("Missed");
    expect(resultWords({ ...base, game: "box-fort", outcome: "done", points: 1240 })).toBe("1,240 points");
    expect(resultWords({ ...base, game: "box-fort", outcome: "gaveUp", points: 1 })).toBe("1 point");
    expect(resultWords({ ...base, outcome: "gaveUp" })).toBe("Gave up");
    expect(resultWords({ ...base, outcome: "closed" })).toBe("Unfinished");
  });

  test("share text gives nothing away", () => {
    expect(shareText("Sniff", { ...base, game: "sniff", number: 12, guesses: 4 })).toBe("Sniff 12: 4 of 6");
    expect(shareText("Nine Lives", { ...base, hints: 1 })).toBe("Nine Lives 3: 4:05, 1 hint");
    expect(shareText("Cat Nap", { ...base, game: "cat-nap", hints: 2 })).toBe("Cat Nap 3: 4:05, 2 hints");
    expect(shareText("Box Fort", { ...base, game: "box-fort", outcome: "done", points: 980 })).toBe("Box Fort 3: 980 points");
  });

  test("a puzzle number below 1 (before launch day) is never shown", () => {
    expect(puzzleNumber(12)).toBe("12");
    expect(puzzleNumber(1)).toBe("1");
    expect(puzzleNumber(0)).toBeNull();
    expect(puzzleNumber(-26339)).toBeNull();
    expect(puzzleName("Sniff", 12)).toBe("Sniff 12");
    expect(puzzleName("Sniff", -26339)).toBe("Sniff");
    expect(shareText("Sniff", { ...base, game: "sniff", number: -26339, guesses: 4 })).toBe("Sniff: 4 of 6");
    expect(shareText("Nine Lives", { ...base, number: 0, hints: 1 })).toBe("Nine Lives: 4:05, 1 hint");
  });

  test("places", () => {
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22].map(ordinal)).toEqual(["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd"]);
    expect(placeWords(1, 3)).toBe("1st of 3");
    expect(placeWords(1, 1)).toBe("1st");
  });
});
