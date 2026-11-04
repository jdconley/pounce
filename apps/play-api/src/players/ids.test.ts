import { describe, expect, it } from "vitest";

import { PERSON_ID, PERSON_KEY, PLAYER_ID, base64url, newPlayerId, sha256Hex, subjectHash } from "./ids";

describe("player ids", () => {
  it("are p_ plus 22 base64url characters, and random", () => {
    const a = newPlayerId();
    expect(a).toMatch(PLAYER_ID);
    expect(a).toHaveLength(24);
    expect(newPlayerId()).not.toBe(a);
  });

  it("person ids are UUIDs and person keys are 43 base64url characters", () => {
    expect(PERSON_ID.test("11111111-1111-4111-8111-111111111111")).toBe(true);
    expect(PERSON_ID.test("not-a-uuid")).toBe(false);
    expect(PERSON_KEY.test("k".repeat(43))).toBe(true);
    expect(PERSON_KEY.test("k".repeat(42))).toBe(false);
  });
});

describe("hashing", () => {
  it("sha256Hex is lowercase hex", async () => {
    expect(await sha256Hex("abc")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  });

  it("a subject hash is the SHA-256 of provider:subject", async () => {
    expect(await subjectHash("apple", "x")).toBe(await sha256Hex("apple:x"));
  });

  it("base64url has no padding or + and /", () => {
    expect(base64url(new Uint8Array([251, 255, 191]))).toBe("-_-_");
  });
});
