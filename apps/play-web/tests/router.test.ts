import { describe, expect, test } from "vitest";

import { parseRoute, pathFor, typedCode, type Route } from "../src/lib/router";

const TOKEN = "AbCdEfGhIjKlMnOpQr_-12";

describe("the web player's routes", () => {
  test("the old routes still parse", () => {
    expect(parseRoute("/play/")).toEqual({ kind: "home" });
    expect(parseRoute("/play/t/bcdfg")).toEqual({ kind: "table", code: "BCDFG" });
    expect(parseRoute("/play/j/BCDFG")).toEqual({ kind: "join", code: "BCDFG" });
    expect(parseRoute(`/play/p/${TOKEN}`)).toEqual({ kind: "pounce", token: TOKEN });
    expect(parseRoute("/play/join")).toEqual({ kind: "keypad" });
  });

  test("/play/tv is the TV page", () => {
    expect(parseRoute("/play/tv")).toEqual({ kind: "tv" });
    expect(parseRoute("/play/tv/")).toEqual({ kind: "tv" });
  });

  test("/play/tv-link/<token> is a phone putting its table on a TV", () => {
    expect(parseRoute(`/play/tv-link/${TOKEN}`)).toEqual({ kind: "tvLink", token: TOKEN });
  });

  test("a TV link with a bad token goes home", () => {
    expect(parseRoute("/play/tv-link/short")).toEqual({ kind: "home" });
    expect(parseRoute("/play/tv-link/")).toEqual({ kind: "home" });
    expect(parseRoute(`/play/tv-link/${TOKEN}x`)).toEqual({ kind: "home" });
    expect(parseRoute("/play/tv-link/AbCdEfGhIjKlMnOpQr.-12")).toEqual({ kind: "home" });
  });

  test("/play/daily is the Dish, and /play/daily/<game> one of its puzzles", () => {
    expect(parseRoute("/play/daily")).toEqual({ kind: "dish" });
    expect(parseRoute("/play/daily/")).toEqual({ kind: "dish" });
    expect(parseRoute("/play/daily/sniff")).toEqual({ kind: "daily", game: "sniff" });
    expect(parseRoute("/play/daily/nine-lives")).toEqual({ kind: "daily", game: "nine-lives" });
    expect(parseRoute("/play/daily/not-a-game")).toEqual({ kind: "dish" });
  });

  test("pathFor is parseRoute's inverse", () => {
    const routes: Route[] = [
      { kind: "home" },
      { kind: "table", code: "BCDFG" },
      { kind: "join", code: "BCDFG" },
      { kind: "pounce", token: TOKEN },
      { kind: "keypad" },
      { kind: "tv" },
      { kind: "tvLink", token: TOKEN },
      { kind: "dish" },
      { kind: "daily", game: "box-fort" },
    ];
    for (const route of routes) expect(parseRoute(pathFor(route))).toEqual(route);
    expect(pathFor({ kind: "tv" })).toBe("/play/tv");
    expect(pathFor({ kind: "tvLink", token: TOKEN })).toBe(`/play/tv-link/${TOKEN}`);
  });
});

describe("Purrtrait's ways in", () => {
  test("the TV's QR opens the easel route with its key", () => {
    expect(parseRoute("/play/e/bcdfg", "?near=kq2x7mnp")).toEqual({ kind: "easel", code: "BCDFG", near: "KQ2X7MNP" });
    expect(parseRoute("/play/e/BCDFG", "")).toEqual({ kind: "easel", code: "BCDFG" });
    expect(parseRoute("/play/e/BCDFG", "?near=<script>")).toEqual({ kind: "easel", code: "BCDFG" });
    expect(pathFor({ kind: "easel", code: "BCDFG", near: "KQ2X7MNP" })).toBe("/play/e/BCDFG");
  });

  test("Join takes a room code, or the TV's eight", () => {
    expect(typedCode("bcdfg")).toEqual({ code: "BCDFG" });
    expect(typedCode("BCDFG KQ2")).toEqual({ code: "BCDFG", near: "BCDFGKQ2" });
    expect(typedCode("BCDFGKQ")).toBeNull();
    expect(typedCode("AAAAA")).toBeNull();
  });
});
