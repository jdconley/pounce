import { describe, expect, test } from "vitest";

import { cleanVersion, compareVersions, olderThan, parseApp, parseVersion, tooOld, type Version } from "./version";

describe("parseVersion", () => {
  test.each([
    ["1.0", [1, 0]],
    ["1.1", [1, 1]],
    ["1.10", [1, 10]],
    ["2", [2]],
    ["1.2.3", [1, 2, 3]],
    ["1.2.3.4", [1, 2, 3, 4]],
    [" 1.2 ", [1, 2]],
    ["v1.2", [1, 2]],
    ["V1.2", [1, 2]],
    ["1.2-beta", [1, 2]],
    ["1.2 (57)", [1, 2]],
    ["1.2+build", [1, 2]],
    ["01.02", [1, 2]],
    ["0.0", [0, 0]],
  ])("%j is %j", (text, parts) => {
    expect(parseVersion(text)).toEqual(parts);
  });

  test.each([
    "",
    " ",
    "latest",
    "beta-1.2",
    ".1",
    "1.",
    "1..2",
    "1.2.x",
    "1.x",
    "-1.2",
    "1.2.3.4.5",
    "1.1234567",
    "99999999999999999999",
    "١.٢",
    null,
    undefined,
    12,
    {},
  ])("%j is no version", (text) => {
    expect(parseVersion(text)).toBeNull();
  });
});

describe("compareVersions", () => {
  const sign = (a: string, b: string) => compareVersions(parseVersion(a) as Version, parseVersion(b) as Version);

  test.each([
    ["1.0", "1.1", -1],
    ["1.1", "1.0", 1],
    ["1.1", "1.1", 0],
    ["1.1", "1.1.0", 0],
    ["1.1.0", "1.1", 0],
    ["1.9", "1.10", -1],
    ["1.10", "1.9", 1],
    ["1.10", "1.2", 1],
    ["2", "1.99.99", 1],
    ["1.0.1", "1.0", 1],
    ["1", "1.0.0.1", -1],
  ])("%s against %s is %d", (a, b, expected) => {
    expect(sign(a, b)).toBe(expected);
  });
});

describe("olderThan", () => {
  test("says so only when both read as versions", () => {
    expect(olderThan("1.0", "1.1")).toBe(true);
    expect(olderThan("1.1", "1.1")).toBe(false);
    expect(olderThan("1.2", "1.1")).toBe(false);
    expect(olderThan("soon", "1.1")).toBe(false);
    expect(olderThan("1.0", "")).toBe(false);
    expect(olderThan("1.0", null)).toBe(false);
    expect(olderThan(undefined, "1.1")).toBe(false);
  });
});

describe("cleanVersion", () => {
  test("is the numbers alone, or null", () => {
    expect(cleanVersion("v1.2-beta")).toBe("1.2");
    expect(cleanVersion("01.2")).toBe("1.2");
    expect(cleanVersion("nope")).toBeNull();
  });
});

describe("parseApp", () => {
  test("reads what version 1.1 sends", () => {
    expect(parseApp("platform=ios; version=1.1; build=57; protocol=1")).toEqual({ platform: "ios", version: "1.1", build: 57, protocol: 1 });
  });

  test("takes the keys in any order and case, and ignores ones it doesn't know", () => {
    expect(parseApp("Version=1.2.0;channel=testflight;PLATFORM=iOS")).toEqual({ platform: "ios", version: "1.2.0", build: null, protocol: null });
  });

  test("the first of a repeated key wins", () => {
    expect(parseApp("platform=ios; version=1.1; version=9.9")?.version).toBe("1.1");
  });

  test("a build or protocol that isn't a whole number is left out, not guessed", () => {
    expect(parseApp("platform=ios; version=1.1; build=abc; protocol=1.5")).toEqual({ platform: "ios", version: "1.1", build: null, protocol: null });
    expect(parseApp("platform=ios; version=1.1; build=; protocol=-1")).toMatchObject({ build: null, protocol: null });
    expect(parseApp("platform=ios; version=1.1; build=12345678901")).toMatchObject({ build: null });
  });

  test.each([
    null,
    undefined,
    "",
    "ios",
    "ios/1.1",
    "version=1.1",
    "platform=ios",
    "platform=ios; version=soon",
    "platform=; version=1.1",
    "platform=i os; version=1.1",
    "platform=1os; version=1.1",
    "=ios; version=1.1",
    `platform=ios; version=1.1; pad=${"x".repeat(200)}`,
  ])("%j is an app that didn't say", (header) => {
    expect(parseApp(header)).toBeNull();
  });
});

describe("tooOld", () => {
  const app = (version: string, protocol: number | null = 1) => ({ platform: "ios", version, build: 1, protocol });

  test("nobody is while there is no minimum", () => {
    expect(tooOld(null, { minimum: null, minProtocol: 1 })).toBe(false);
    expect(tooOld(app("1.1"), { minimum: null, minProtocol: 1 })).toBe(false);
    expect(tooOld(app("0.1"), { minimum: "", minProtocol: 1 })).toBe(false);
  });

  test("an app below the minimum is, one at or above it isn't", () => {
    const supported = { minimum: "1.2", minProtocol: 1 };
    expect(tooOld(app("1.1"), supported)).toBe(true);
    expect(tooOld(app("1.1.9"), supported)).toBe(true);
    expect(tooOld(app("1.2"), supported)).toBe(false);
    expect(tooOld(app("1.2.0"), supported)).toBe(false);
    expect(tooOld(app("1.10"), supported)).toBe(false);
  });

  test("an app that didn't say is version 1.0", () => {
    expect(tooOld(null, { minimum: "1.0", minProtocol: 1 })).toBe(false);
    expect(tooOld(null, { minimum: "1.0.1", minProtocol: 1 })).toBe(true);
    expect(tooOld(null, { minimum: "1.1", minProtocol: 1 })).toBe(true);
  });

  test("a minimum nobody can read retires nobody", () => {
    expect(tooOld(null, { minimum: "eleven", minProtocol: 1 })).toBe(false);
    expect(tooOld(app("1.1"), { minimum: "1.x", minProtocol: 1 })).toBe(false);
  });

  test("an app that speaks a protocol the server dropped is, whatever its version", () => {
    expect(tooOld(app("3.0", 1), { minimum: null, minProtocol: 2 })).toBe(true);
    expect(tooOld(app("3.0", 2), { minimum: null, minProtocol: 2 })).toBe(false);
    expect(tooOld(null, { minimum: null, minProtocol: 2 })).toBe(true);
    // One that didn't say which protocol is judged by its version alone.
    expect(tooOld(app("3.0", null), { minimum: null, minProtocol: 2 })).toBe(false);
  });
});
