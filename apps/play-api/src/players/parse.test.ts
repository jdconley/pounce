import { describe, expect, it } from "vitest";

import { parseLink, parseProfile, parseSignIn, parseStatePatch } from "./parse";

const KEY = "k".repeat(43);
const person = (n: number, extra: Record<string, unknown> = {}) => ({
  id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`,
  name: ` Cat ${n} `,
  cat: n % 8,
  key: KEY,
  ...extra,
});

describe("parseProfile", () => {
  it("accepts a valid profile and trims names", () => {
    expect(
      parseProfile({ timeZone: "America/Los_Angeles", ageBand: "adult", people: [person(1, { ageBand: "teen", at: 5 })] }),
    ).toEqual({
      timeZone: "America/Los_Angeles",
      ageBand: "adult",
      people: [{ id: person(1).id, name: "Cat 1", cat: 1, key: KEY, ageBand: "teen", at: 5 }],
    });
  });

  it("accepts a profile without age bands", () => {
    expect(parseProfile({ timeZone: "UTC", people: [person(1)] })?.ageBand).toBeUndefined();
  });

  it.each([
    ["nine people", { timeZone: "UTC", people: Array.from({ length: 9 }, (_, i) => person(i)) }],
    ["no people", { timeZone: "UTC", people: [] }],
    ["duplicate ids", { timeZone: "UTC", people: [person(1), person(1)] }],
    ["a short key", { timeZone: "UTC", people: [person(1, { key: "k".repeat(42) })] }],
    ["cat 8", { timeZone: "UTC", people: [person(1, { cat: 8 })] }],
    ["an unknown zone", { timeZone: "Mars/Base", people: [person(1)] }],
    ["an unknown key", { timeZone: "UTC", people: [person(1)], extra: 1 }],
    ["an unknown person key", { timeZone: "UTC", people: [person(1, { email: "x" })] }],
    ["a bad band", { timeZone: "UTC", ageBand: "baby", people: [person(1)] }],
    ["a bad person band", { timeZone: "UTC", people: [person(1, { ageBand: 3 })] }],
    ["a negative at", { timeZone: "UTC", people: [person(1, { at: -1 })] }],
    ["a bad id", { timeZone: "UTC", people: [person(1, { id: "x" })] }],
    ["an empty name", { timeZone: "UTC", people: [person(1, { name: "  " })] }],
    ["people not an array", { timeZone: "UTC", people: {} }],
    ["a person not an object", { timeZone: "UTC", people: [1] }],
    ["a missing zone", { people: [person(1)] }],
    ["not an object", null],
  ])("rejects %s", (_, body) => {
    expect(parseProfile(body)).toBeNull();
  });
});

describe("parseStatePatch", () => {
  it("accepts sections of entries", () => {
    const patch = {
      settings: { sound: { v: true, at: 1 }, "quiet.start": { v: { h: 22, m: 0 }, at: 2 } },
      archive: { BCDFG: { v: true, at: 3 } },
      tutorial: {},
    };
    expect(parseStatePatch(patch)).toEqual(patch);
  });

  it.each([
    ["a 300-byte value", { settings: { sound: { v: "x".repeat(300), at: 1 } } }],
    ["a key starting with a digit", { settings: { "1a": { v: 1, at: 1 } } }],
    ["an archive key that isn't a room code", { archive: { hello: { v: true, at: 1 } } }],
    ["65 keys", { settings: Object.fromEntries(Array.from({ length: 65 }, (_, i) => [`k${i}`, { v: 1, at: 1 }])) }],
    ["a fractional at", { settings: { sound: { v: 1, at: 1.5 } } }],
    ["an entry without v", { settings: { sound: { at: 1 } } }],
    ["an entry with extra keys", { settings: { sound: { v: 1, at: 1, x: 1 } } }],
    ["an unknown section", { people: {} }],
    ["a section that isn't an object", { settings: [] }],
    ["an undefined value", { settings: { sound: { v: undefined, at: 1 } } }],
    ["not an object", "x"],
  ])("rejects %s", (_, body) => {
    expect(parseStatePatch(body)).toBeNull();
  });
});

describe("parseSignIn and parseLink", () => {
  it("parse a sign-in body", () => {
    const body = { proof: { identityToken: "t" }, person: { id: person(1).id, key: KEY } };
    expect(parseSignIn(body)).toEqual(body);
  });

  it.each([
    ["no proof", { person: { id: person(1).id, key: KEY } }],
    ["a bad key", { proof: {}, person: { id: person(1).id, key: "x" } }],
    ["a bad person id", { proof: {}, person: { id: "x", key: KEY } }],
    ["a person not an object", { proof: {}, person: "x" }],
    ["extra keys", { proof: {}, person: { id: person(1).id, key: KEY }, x: 1 }],
    ["not an object", 7],
  ])("rejects a sign-in with %s", (_, body) => {
    expect(parseSignIn(body)).toBeNull();
  });

  it("parse a link body, confirmMerge defaulting to false", () => {
    expect(parseLink({ proof: { a: 1 } })).toEqual({ proof: { a: 1 }, confirmMerge: false });
    expect(parseLink({ proof: {}, confirmMerge: true })).toEqual({ proof: {}, confirmMerge: true });
  });

  it.each([
    ["no proof", {}],
    ["a string confirmMerge", { proof: {}, confirmMerge: "yes" }],
    ["extra keys", { proof: {}, x: 1 }],
    ["not an object", []],
  ])("rejects a link with %s", (_, body) => {
    expect(parseLink(body)).toBeNull();
  });
});
