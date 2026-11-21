import { describe, expect, it } from "vitest";

import { ROOM_CODE_ALPHABET } from "../room/codes";
import { createRng } from "../rules/rng";

import { BOARD_TOKEN_TTL_MS, boardLinkDecision, LINK_CODE, LINK_TOKEN, linkDecision, newLinkCode, newLinkToken, parseBoardLinkBody, parseLinkBody, parseScreenBody, SCREEN_LINK_TTL_MS } from "./screens";

describe("link tokens and codes", () => {
  it("live for ten minutes", () => {
    expect(SCREEN_LINK_TTL_MS).toBe(600_000);
  });

  it("a token is 22 base64url characters from 16 bytes", () => {
    const token = newLinkToken(Uint8Array.from({ length: 16 }, (_, i) => i * 17));
    expect(token).toHaveLength(22);
    expect(token).toMatch(LINK_TOKEN);
    expect(newLinkToken(new Uint8Array(16).fill(255))).toBe("_____________________w");
    expect(newLinkToken(new Uint8Array(16).fill(251))).toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect(LINK_TOKEN.test("a".repeat(21))).toBe(false);
    expect(LINK_TOKEN.test("a".repeat(23))).toBe(false);
    expect(LINK_TOKEN.test(`${"a".repeat(21)}=`)).toBe(false);
  });

  it("a 16-byte token only", () => {
    expect(() => newLinkToken(new Uint8Array(15))).toThrow();
  });

  it("a code is 6 characters of the room code alphabet", () => {
    const rng = createRng([1, 2, 3, 4]);
    for (let i = 0; i < 200; i++) {
      const code = newLinkCode(rng);
      expect(code).toHaveLength(6);
      expect([...code].every((c) => ROOM_CODE_ALPHABET.includes(c))).toBe(true);
      expect(code).toMatch(LINK_CODE);
    }
    expect(LINK_CODE.test("BCDFG")).toBe(false);
    expect(LINK_CODE.test("BCDFGA")).toBe(false);
  });
});

describe("parseScreenBody", () => {
  it("takes nothing, or the table the TV shows", () => {
    expect(parseScreenBody({})).toEqual({ showing: null });
    expect(parseScreenBody({ showing: "BCDFG" })).toEqual({ showing: "BCDFG" });
  });

  it("refuses anything else", () => {
    expect(parseScreenBody(null)).toBeNull();
    expect(parseScreenBody({ showing: "bcdfg" })).toBeNull();
    expect(parseScreenBody({ showing: "AAAAA" })).toBeNull();
    expect(parseScreenBody({ showing: null })).toBeNull();
    expect(parseScreenBody({ showing: "BCDFG", extra: 1 })).toBeNull();
    expect(parseScreenBody({ other: 1 })).toBeNull();
  });
});

describe("parseLinkBody", () => {
  const token = "A".repeat(22);

  it("takes a token and a room", () => {
    expect(parseLinkBody({ token, room: "BCDFG" })).toEqual({ token, room: "BCDFG", move: false });
  });

  it("takes a code, a room and move", () => {
    expect(parseLinkBody({ code: "BCDFGH", room: "BCDFG", move: true })).toEqual({ code: "BCDFGH", room: "BCDFG", move: true });
    expect(parseLinkBody({ code: "BCDFGH", room: "BCDFG", move: false })).toEqual({ code: "BCDFGH", room: "BCDFG", move: false });
  });

  it("upper-cases a code first", () => {
    expect(parseLinkBody({ code: "bcdfgh", room: "BCDFG" })).toEqual({ code: "BCDFGH", room: "BCDFG", move: false });
    expect(parseLinkBody({ code: "bCdFg2", room: "BCDFG" })).toEqual({ code: "BCDFG2", room: "BCDFG", move: false });
  });

  it("refuses both a token and a code, or neither", () => {
    expect(parseLinkBody({ token, code: "BCDFGH", room: "BCDFG" })).toBeNull();
    expect(parseLinkBody({ room: "BCDFG" })).toBeNull();
  });

  it("refuses a bad token, code or room", () => {
    expect(parseLinkBody({ token: "short", room: "BCDFG" })).toBeNull();
    expect(parseLinkBody({ token: 7, room: "BCDFG" })).toBeNull();
    expect(parseLinkBody({ code: "BCDFG", room: "BCDFG" })).toBeNull();
    expect(parseLinkBody({ code: "AEIOUY", room: "BCDFG" })).toBeNull();
    expect(parseLinkBody({ code: 123456, room: "BCDFG" })).toBeNull();
    expect(parseLinkBody({ token, room: "bcdfg" })).toBeNull();
    expect(parseLinkBody({ token, room: "BCDF" })).toBeNull();
    expect(parseLinkBody({ token })).toBeNull();
    expect(parseLinkBody({ token, room: 5 })).toBeNull();
  });

  it("refuses a move that isn't a boolean, and extra keys", () => {
    expect(parseLinkBody({ token, room: "BCDFG", move: "yes" })).toBeNull();
    expect(parseLinkBody({ token, room: "BCDFG", extra: 1 })).toBeNull();
  });

  it("refuses no body", () => {
    expect(parseLinkBody(null)).toBeNull();
  });
});

describe("linkDecision", () => {
  const now = 1_000_000;
  const idle = { showing: null, spent: false, expires: now + 1 };

  it("no link is gone", () => {
    expect(linkDecision(null, "BCDFG", false, now)).toBe("gone");
  });

  it("an expired link is gone", () => {
    expect(linkDecision({ ...idle, expires: now }, "BCDFG", false, now)).toBe("gone");
  });

  it("a spent link is gone", () => {
    expect(linkDecision({ ...idle, spent: true }, "BCDFG", false, now)).toBe("gone");
    expect(linkDecision({ ...idle, spent: true, showing: "BCDFG" }, "BCDFG", true, now)).toBe("gone");
  });

  it("a TV showing another table moves only when asked", () => {
    expect(linkDecision({ ...idle, showing: "HJKLM" }, "BCDFG", false, now)).toBe("showing");
    expect(linkDecision({ ...idle, showing: "HJKLM" }, "BCDFG", true, now)).toBe("link");
  });

  it("a TV already showing the table is already there", () => {
    expect(linkDecision({ ...idle, showing: "BCDFG" }, "BCDFG", false, now)).toBe("already");
    expect(linkDecision({ ...idle, showing: "BCDFG" }, "BCDFG", true, now)).toBe("already");
  });

  it("an idle TV links", () => {
    expect(linkDecision(idle, "BCDFG", false, now)).toBe("link");
  });
});

describe("parseBoardLinkBody (the Daily Dish's board on a TV)", () => {
  const token = "A".repeat(22);

  it("takes exactly one of token or code, with board: true", () => {
    expect(parseBoardLinkBody({ token, board: true })).toEqual({ token });
    expect(parseBoardLinkBody({ code: "bcdfgh", board: true })).toEqual({ code: "BCDFGH" });
  });

  it("refuses anything else", () => {
    for (const bad of [
      null,
      { token },
      { token, board: false },
      { token, board: "yes" },
      { board: true },
      { token, code: "BCDFGH", board: true },
      { token, board: true, room: "ABCDE" },
      { token: "short", board: true },
      { code: "nope", board: true },
      { code: 7, board: true },
    ]) {
      expect(parseBoardLinkBody(bad as Record<string, unknown> | null), JSON.stringify(bad)).toBeNull();
    }
  });

  it("is told apart from a table link by its board key", () => {
    expect(parseLinkBody({ token, board: true })).toBeNull();
  });
});

describe("boardLinkDecision", () => {
  it("links a live, unspent link whatever the TV shows; anything else is gone", () => {
    expect(boardLinkDecision({ spent: false, expires: 10 }, 5)).toBe("link");
    expect(boardLinkDecision({ spent: true, expires: 10 }, 5)).toBe("gone");
    expect(boardLinkDecision({ spent: false, expires: 10 }, 10)).toBe("gone");
    expect(boardLinkDecision(null, 5)).toBe("gone");
  });

  it("a board token lasts 30 days", () => {
    expect(BOARD_TOKEN_TTL_MS).toBe(30 * 86_400_000);
  });
});
