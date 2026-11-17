import { describe, expect, test } from "vitest";

import { parseRoute, pathFor, type Route } from "../src/lib/router";

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

  test("pathFor is parseRoute's inverse", () => {
    const routes: Route[] = [
      { kind: "home" },
      { kind: "table", code: "BCDFG" },
      { kind: "join", code: "BCDFG" },
      { kind: "pounce", token: TOKEN },
      { kind: "keypad" },
      { kind: "tv" },
      { kind: "tvLink", token: TOKEN },
    ];
    for (const route of routes) expect(parseRoute(pathFor(route))).toEqual(route);
    expect(pathFor({ kind: "tv" })).toBe("/play/tv");
    expect(pathFor({ kind: "tvLink", token: TOKEN })).toBe(`/play/tv-link/${TOKEN}`);
  });
});
