import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { defaultRoomName } from "../room/names";

import { foldName, isGeneratedName, nameAllowed } from "./filter";

describe("nameAllowed", () => {
  it.each([
    "Alice", "Bob", "Mia", "JD", "Cassandra", "Titus", "Yoshito", "Toshitaka", "Hancock", "Scunthorpe", "Essex",
    "Dickson", "Nazir", "Niger", "Nigel", "Raphael", "Grape Soda", "Shiitake", "Maine Coon", "Pussycat", "Peacock",
    "Analyst", "Cumberbatch", "Arsenal", "Table 455", "Max 2", "The Sleepy Sardines", "Bob's hit list", "Wish It",
    "As If", "Van Dyke", "Hello Kitty", "Class of 2026", "Bass Players", "Sussex Cats", "Mr. T", "A B", "José",
    "猫", "Torpedo", "Assassin", "Butters", "Cockapoo", "Hitchcock", "Glasses", "Passing By", "Go Team!", "Al & Bo",
    "Shoe Box", "Cockatoo", "Shitzu", "X Æ A-12", "Asha", "Kass", "Dan", "Hoel", "Damien",
  ])("allows %s", (name) => {
    expect(nameAllowed(name)).toBe(true);
  });

  it.each([
    "fuck", "FUCK", "Fuuuuck", "f u c k", "f.u.c.k", "f_u_c_k", "fu ck", "fuck you", "you fucker", "motherfucker",
    "phuck", "fvck", "fuk", "sh1t", "5hit", "shit", "sh it", "shitty", "shithead", "dipshit", "bullshit", "b1tch",
    "bitches", "a$$", "ass", "asss", "a s s", "@ss", "asshole", "big ass", "asses", "cunt", "c u n t", "cunts",
    "nigger", "n1gger", "niggger", "nigga", "faggot", "fag", "whore", "slut", "sluts", "dick", "d1ck", "dicks",
    "cock", "c0ck", "pussy", "penis", "vagina", "porn", "pornhub", "sex", "sexy", "s3x", "tits", "boobs", "rape",
    "rapist", "nazi", "nazis", "hitler", "kkk", "retard", "kys", "kill yourself", "wtf", "stfu", "cum", "anal",
    "fück", "f\u200Buck", "ＦＵＣＫ", "pedo", "milf", "wanker", "twat", "piss off", "The Sexy Sardines", "hoe", "crap",
  ])("refuses %s", (name) => {
    expect(nameAllowed(name)).toBe(false);
  });

  it("allows every name the server and the app generate", () => {
    const alphabet = "BCDFGHJKLMNPQRTVWXZ2346789";
    for (const a of alphabet) for (const b of alphabet) expect(nameAllowed(defaultRoomName(`${a}${b}BCD`))).toBe(true);
  });
});

describe("foldName", () => {
  it("joins short pieces, reads look-alikes, and leaves numbers alone", () => {
    expect(foldName("f u c k")).toEqual(["fuck"]);
    expect(foldName("Bob's hit list")).toEqual(["bob", "s", "hit", "list"]);
    expect(foldName("Table 455")).toEqual(["table", "455"]);
    expect(foldName("a$$ h0le")).toEqual(["ass", "hole"]);
    expect(foldName("!!! ---")).toEqual(["iii"]);
    expect(foldName("+ +")).toEqual(["tt"]);
    expect(foldName("")).toEqual([]);
  });
});

describe("isGeneratedName", () => {
  it("knows exactly the app's generated names", () => {
    const swift = readFileSync(
      new URL("../../../play-ios/PounceKit/Sources/PounceKit/Identity/NameGenerator.swift", import.meta.url),
      "utf8",
    );
    const list = /names: \[String\] = \[([^\]]+)\]/.exec(swift)?.[1] ?? "";
    const names = [...list.matchAll(/"([^"]+)"/g)].map((m) => m[1] as string);
    expect(names.length).toBeGreaterThan(40);
    for (const name of names) {
      expect(isGeneratedName(name)).toBe(true);
      expect(nameAllowed(name)).toBe(true);
    }
    expect(isGeneratedName("Alice")).toBe(false);
    expect(isGeneratedName("mochi")).toBe(false);
  });
});
