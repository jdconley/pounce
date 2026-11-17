import { describe, expect, test } from "vitest";

import { linkableTables, linkExpired, linkFailedWords, linkWords, normaliseTvCode, typedTvCode } from "../src/lib/tv-code";
import { ApiError } from "../src/net/api";

describe("a TV's code as typed", () => {
  test("spaces go and letters go up", () => {
    expect(normaliseTvCode(" bcd fgh ")).toBe("BCDFGH");
    expect(normaliseTvCode("BCDFGH")).toBe("BCDFGH");
    expect(normaliseTvCode("2346kz")).toBe("2346KZ");
  });

  test("anything but six characters of the alphabet is no code", () => {
    expect(normaliseTvCode("BCDFG")).toBeNull();
    expect(normaliseTvCode("BCDFGHJ")).toBeNull();
    expect(normaliseTvCode("BCDFGA")).toBeNull();
    expect(normaliseTvCode("bcdfge")).toBeNull();
    expect(normaliseTvCode("BCDFG0")).toBeNull();
    expect(normaliseTvCode("BCD-FG")).toBeNull();
    expect(normaliseTvCode("")).toBeNull();
    expect(normaliseTvCode("      ")).toBeNull();
  });

  test("the field upper-cases, drops what isn't a letter or digit, and stops at six", () => {
    expect(typedTvCode("bcd fgh")).toBe("BCDFGH");
    expect(typedTvCode("bc-d")).toBe("BCD");
    expect(typedTvCode("bcdfghjk")).toBe("BCDFGH");
  });
});

describe("what a failed link says", () => {
  test("each answer of POST /v1/screens/link", () => {
    expect(linkWords(new ApiError(404, "not_found"))).toBe("No TV with that code.");
    expect(linkWords(new ApiError(429, "too_many_attempts", 30))).toBe("Too many wrong codes. Try again later.");
    expect(linkWords(new ApiError(403, "not_seated"))).toBe("Sit at this table first.");
    expect(linkWords(new ApiError(409, "seated"))).toBe("That TV is seated here.");
    expect(linkWords(new ApiError(0, "offline"))).toBe("You're offline.");
    expect(linkWords(new ApiError(400, "bad_request"))).toBe("Couldn't reach Pounce. Try again.");
    expect(linkWords(new Error("boom"))).toBe("Couldn't reach Pounce. Try again.");
  });

  test("only a 404 is an expired link", () => {
    expect(linkExpired(new ApiError(404, "not_found"))).toBe(true);
    expect(linkExpired(new ApiError(429, "too_many_attempts"))).toBe(false);
    expect(linkExpired(new Error("x"))).toBe(false);
  });

  test("a table made, then its link failed: the note it opens with", () => {
    expect(linkFailedWords(new ApiError(404, "not_found"))).toBe("The TV link expired.");
    expect(linkFailedWords(new ApiError(429, "too_many_attempts", 30))).toBe("Too many wrong codes. Try again later.");
    expect(linkFailedWords(new ApiError(0, "offline"))).toBe("You're offline.");
  });
});

describe("the tables a phone can put on a TV", () => {
  const mine = { kind: "human", person: { id: "p1", name: "Ava", cat: 1 }, yours: true };
  const theirs = { kind: "human", person: { id: "p2", name: "Ben", cat: 2 } };
  const table = (code: string, status: string, updatedAt: number, seats?: { kind: string; yours?: boolean }[]) => ({ code, status, yourTurn: false, updatedAt, ...(seats ? { seats } : {}) });

  test("only tables still waiting or playing where this phone holds a seat, newest first", () => {
    const list = [
      table("AAAAA", "lobby", 1, [mine, theirs]),
      table("BBBBB", "playing", 3, [theirs, mine]),
      table("CCCCC", "playing", 2, [theirs]),
      table("DDDDD", "over", 4, [mine]),
      table("FFFFF", "lobby", 5),
      table("GGGGG", "lobby", 6, [{ kind: "bot" }, { kind: "open" }]),
    ];
    expect(linkableTables(list).map((t) => t.code)).toEqual(["BBBBB", "AAAAA"]);
  });
});
