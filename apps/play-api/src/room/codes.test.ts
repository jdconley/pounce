import { describe, expect, it } from "vitest";

import { seedOf } from "../../tests/seeds";
import { createRng } from "../rules/rng";

import { newMoveCode, newRoomCode, ROOM_CODE_ALPHABET } from "./codes";

describe("room codes", () => {
  it("alphabet has no vowels or look-alikes", () => {
    expect(ROOM_CODE_ALPHABET).toBe("BCDFGHJKLMNPQRTVWXZ2346789");
    expect(ROOM_CODE_ALPHABET).not.toMatch(/[AEIOUSY015]/);
  });

  it("room code is 5 chars from alphabet", () => {
    const rng = createRng(seedOf(1));
    for (let i = 0; i < 200; i++) {
      const code = newRoomCode(rng);
      expect(code).toHaveLength(5);
      for (const ch of code) expect(ROOM_CODE_ALPHABET).toContain(ch);
    }
  });

  it("move code is 6 chars from alphabet", () => {
    const rng = createRng(seedOf(2));
    for (let i = 0; i < 200; i++) {
      const code = newMoveCode(rng);
      expect(code).toHaveLength(6);
      for (const ch of code) expect(ROOM_CODE_ALPHABET).toContain(ch);
    }
  });

  it("is deterministic for a seeded rng and reaches both ends of the alphabet", () => {
    expect(newRoomCode(createRng(seedOf(7)))).toBe(newRoomCode(createRng(seedOf(7))));
    expect(newRoomCode(() => 0)).toBe("BBBBB");
    expect(newRoomCode(() => 0.999999)).toBe("99999");
  });
});
