import { describe, expect, test } from "vitest";

import { linkExpired, linkFailedWords, linkWords, normaliseTvCode, typedTvCode } from "../src/lib/tv-code";
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
    expect(linkWords(new ApiError(403, "not_seated"))).toBe("Take a seat to play.");
    expect(linkWords(new ApiError(409, "seated"))).toBe("This phone is at the table.");
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
