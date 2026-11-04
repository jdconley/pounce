import { describe, expect, it } from "vitest";

import { ROOM_CODE_ALPHABET } from "./codes";
import { MAX_ROOM_NAME, defaultRoomName, parseRoomName } from "./names";

describe("defaultRoomName", () => {
  it("is the same for the same code, and a cat-themed 'The <Adjective> <Noun>'", () => {
    expect(defaultRoomName("BCDFG")).toBe(defaultRoomName("BCDFG"));
    expect(defaultRoomName("BCDFG")).toMatch(/^The [A-Z][a-z]+ [A-Z][A-Za-z ]+$/);
  });

  it("varies with the code and always fits the name limit", () => {
    const seen = new Set<string>();
    for (const a of ROOM_CODE_ALPHABET) {
      for (const b of ROOM_CODE_ALPHABET) {
        const name = defaultRoomName(`BCD${a}${b}`);
        expect(parseRoomName(name)).toBe(name);
        seen.add(name);
      }
    }
    expect(seen.size).toBeGreaterThan(50);
  });
});

describe("parseRoomName", () => {
  it("trims and collapses runs of whitespace", () => {
    expect(parseRoomName("  Friday   Night Cats ")).toBe("Friday Night Cats");
  });

  it("counts code points, so 30 emoji or accented letters fit", () => {
    expect(parseRoomName("é".repeat(MAX_ROOM_NAME))).toBe("é".repeat(MAX_ROOM_NAME));
    expect(parseRoomName("\u{1F431}".repeat(MAX_ROOM_NAME))).toBe("\u{1F431}".repeat(MAX_ROOM_NAME));
    expect(parseRoomName("é".repeat(MAX_ROOM_NAME + 1))).toBeNull();
  });

  it("rejects non-strings, empty names, and control, separator and bidi characters", () => {
    for (const value of [undefined, null, 7, ["a"], "", "   ", "a\tb", "a\nb", "a\u0000b", "a b", "a‮b", "a⁦b"]) {
      expect(parseRoomName(value), JSON.stringify(value)).toBeNull();
    }
  });
});
