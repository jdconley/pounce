import { describe, expect, it } from "vitest";

import { seedOf } from "../../tests/seeds";
import { createRng } from "../rules/rng";

import { NEAR, newMoveCode, newNearKey, newRoomCode, parseNear, ROOM_CODE_ALPHABET, typedNear } from "./codes";

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

describe("near keys (Purrtrait, design §5.2)", () => {
  it("are 8 chars from the alphabet, and a typed code is the room code plus the key's first 3", () => {
    const rng = createRng(seedOf(3));
    for (let i = 0; i < 200; i++) {
      const key = newNearKey(rng);
      expect(key).toMatch(NEAR);
      expect(typedNear("BCDFG", key)).toBe(`BCDFG${key.slice(0, 3)}`);
      expect(typedNear("BCDFG", key)).toMatch(NEAR);
    }
    expect("bcdfghjk").not.toMatch(NEAR);
    expect("BCDFGHJ").not.toMatch(NEAR);
    expect("BCDFGHJKL").not.toMatch(NEAR);
    expect("BCDFGHJA").not.toMatch(NEAR);
    expect(parseNear("bcdfghjk")).toBe("BCDFGHJK");
    expect(parseNear("BCDFGHJA")).toBeNull();
    expect(parseNear(null)).toBeNull();
    expect(parseNear(undefined)).toBeNull();
  });
});
