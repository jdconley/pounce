import { describe, expect, it } from "vitest";

import { checkName, ownerAsks, parseAfter, parseBlock, parseReport } from "./parse";

const PERSON = "123E4567-e89b-42d3-a456-426614174000";

describe("parseReport", () => {
  it("takes a person and one of the picker's reasons", () => {
    expect(parseReport({ person: PERSON, reason: "name" })).toEqual({ person: PERSON.toLowerCase(), reason: "name" });
    expect(parseReport({ person: PERSON, reason: "bothering" })?.reason).toBe("bothering");
    expect(parseReport({ person: PERSON, reason: "other" })?.reason).toBe("other");
  });

  it("refuses anything else: no free text, no extra keys", () => {
    expect(parseReport(null)).toBeNull();
    expect(parseReport({ person: PERSON })).toBeNull();
    expect(parseReport({ person: PERSON, reason: "they are mean" })).toBeNull();
    expect(parseReport({ person: PERSON, reason: 1 })).toBeNull();
    expect(parseReport({ person: "p_someone", reason: "name" })).toBeNull();
    expect(parseReport({ person: 7, reason: "name" })).toBeNull();
    expect(parseReport({ person: PERSON, reason: "name", note: "x" })).toBeNull();
  });
});

describe("parseBlock", () => {
  it("takes just a person", () => {
    expect(parseBlock({ person: PERSON })).toEqual({ person: PERSON.toLowerCase() });
    expect(parseBlock(null)).toBeNull();
    expect(parseBlock({})).toBeNull();
    expect(parseBlock({ person: "x" })).toBeNull();
    expect(parseBlock({ person: 1 })).toBeNull();
    expect(parseBlock({ person: PERSON, more: 1 })).toBeNull();
  });
});

describe("checkName", () => {
  it("says whether the server would take a person's or a table's name", () => {
    expect(checkName({ kind: "person", name: " Mia " }, false)).toEqual({ ok: true });
    expect(checkName({ kind: "table", name: "Taco Night" }, false)).toEqual({ ok: true });
    expect(checkName({ kind: "person", name: "sh1t" }, false)).toEqual({ ok: false, reason: "bad_name" });
    expect(checkName({ kind: "table", name: "f u c k" }, false)).toEqual({ ok: false, reason: "bad_name" });
  });

  it("a kitten types nothing: a generated name for a person, no table names", () => {
    expect(checkName({ kind: "person", name: "Mochi" }, true)).toEqual({ ok: true });
    expect(checkName({ kind: "person", name: "Mia" }, true)).toEqual({ ok: false, reason: "not_allowed" });
    expect(checkName({ kind: "table", name: "Taco Night" }, true)).toEqual({ ok: false, reason: "not_allowed" });
    expect(checkName({ kind: "table", name: "sh1t" }, true)).toEqual({ ok: false, reason: "bad_name" });
  });

  it("is null for a malformed body", () => {
    expect(checkName(null, false)).toBeNull();
    expect(checkName({ kind: "seat", name: "Mia" }, false)).toBeNull();
    expect(checkName({ kind: "person", name: "" }, false)).toBeNull();
    expect(checkName({ kind: "person", name: "x".repeat(21) }, false)).toBeNull();
    expect(checkName({ kind: "table", name: "x".repeat(31) }, false)).toBeNull();
    expect(checkName({ kind: "person" }, false)).toBeNull();
    expect(checkName({ kind: "person", name: "Mia", extra: 1 }, false)).toBeNull();
  });
});

describe("ownerAsks", () => {
  it("needs the configured key as a bearer token", async () => {
    expect(await ownerAsks("Bearer k-123", "k-123")).toBe(true);
    expect(await ownerAsks("Bearer  k-123 ", "k-123")).toBe(true);
    expect(await ownerAsks("Bearer k-124", "k-123")).toBe(false);
    expect(await ownerAsks("k-123", "k-123")).toBe(false);
    expect(await ownerAsks(null, "k-123")).toBe(false);
    expect(await ownerAsks("Bearer ", "")).toBe(false);
    expect(await ownerAsks("Bearer k-123", undefined)).toBe(false);
  });
});

describe("parseAfter", () => {
  it("is a report id, 0 when absent", () => {
    expect(parseAfter(null)).toBe(0);
    expect(parseAfter("41")).toBe(41);
    expect(parseAfter("-1")).toBeNull();
    expect(parseAfter("abc")).toBeNull();
    expect(parseAfter("")).toBeNull();
  });
});
