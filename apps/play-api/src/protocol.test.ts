import { describe, expect, it } from "vitest";

import { PROTOCOL_VERSION, parseClientMessage, type ErrorCode } from "./protocol";

const UUID = "123e4567-e89b-42d3-a456-426614174000";
const person = { id: UUID, name: "Mittens", cat: 3 };
const parse = (v: unknown) => parseClientMessage(JSON.stringify(v));
const BAD = { error: "bad_message" };
const act = (action: unknown, seat: unknown = 0) => ({ t: "act", seat, action });

describe("ErrorCode", () => {
  it("names every code the room, the engine and the parser send", () => {
    // A Record over the union fails to compile if a code is added or removed
    // without updating this list, which the iOS client mirrors.
    const codes: Record<ErrorCode, true> = {
      bad_message: true,
      bad_name: true,
      not_allowed: true,
      blocked: true,
      internal: true,
      not_lobby: true,
      in_game: true,
      bad_seat: true,
      seat_taken: true,
      person_seated: true,
      not_seated: true,
      not_your_seat: true,
      seats_open: true,
      not_enough_players: true,
      game_over: true,
      bad_code: true,
      too_many_attempts: true,
      not_playing: true,
      not_your_turn: true,
      bad_step: true,
      bad_card: true,
      bad_groups: true,
      already_laid: true,
      not_laid: true,
      bad_target: true,
      empty_discard: true,
      cucumber_from_discard: true,
      round_not_over: true,
      forfeited: true,
      bot_stalled: true,
      room_closed: true,
      not_over: true,
      too_soon: true,
      not_unlocked: true,
      not_their_turn: true,
    };
    expect(Object.keys(codes)).toHaveLength(35);
  });
});

describe("parseClientMessage", () => {
  it("exports the protocol version", () => {
    expect(PROTOCOL_VERSION).toBe(1);
  });

  it("oversized message -> bad_message", () => {
    const big = JSON.stringify({ t: "start", pad: "x".repeat(8192) });
    expect(parseClientMessage(big)).toEqual(BAD);
  });

  it("measures size in UTF-8 bytes, not characters", () => {
    // 3000 three-byte chars = 9000 bytes but only ~3000 UTF-16 units.
    const wide = JSON.stringify({ t: "claim", seat: 0, person: { ...person, name: "€".repeat(3000) } });
    expect(wide.length).toBeLessThan(8192);
    expect(parseClientMessage(wide)).toEqual(BAD);
    const exactly = '{"t":"start"}' + " ".repeat(8192 - 13);
    expect(new TextEncoder().encode(exactly).length).toBe(8192);
    expect(parseClientMessage(exactly)).toEqual({ t: "start" });
    expect(parseClientMessage(exactly + " ")).toEqual(BAD);
  });

  it("non-JSON -> bad_message", () => {
    expect(parseClientMessage("not json")).toEqual(BAD);
    expect(parseClientMessage("")).toEqual(BAD);
  });

  it("non-object JSON -> bad_message", () => {
    for (const v of [null, 3, "start", true, [], [{ t: "start" }]]) expect(parse(v)).toEqual(BAD);
  });

  it("unknown t -> bad_message", () => {
    expect(parse({ t: "explode" })).toEqual(BAD);
    expect(parse({})).toEqual(BAD);
    expect(parse({ t: 5 })).toEqual(BAD);
    expect(parse({ t: "__proto__" })).toEqual(BAD);
  });

  it("rejects unknown extra keys on messages", () => {
    expect(parse({ t: "start", extra: 1 })).toEqual(BAD);
    expect(parse({ t: "leave", seat: 1, extra: 1 })).toEqual(BAD);
  });

  describe("start / presence / leave / moveSeat", () => {
    it("parses start", () => {
      expect(parse({ t: "start" })).toEqual({ t: "start" });
    });
    it("parses presence states", () => {
      expect(parse({ t: "presence", state: "active" })).toEqual({ t: "presence", state: "active" });
      expect(parse({ t: "presence", state: "background" })).toEqual({ t: "presence", state: "background" });
      expect(parse({ t: "presence", state: "asleep" })).toEqual(BAD);
      expect(parse({ t: "presence" })).toEqual(BAD);
    });
    it("parses leave and moveSeat", () => {
      expect(parse({ t: "leave", seat: 2 })).toEqual({ t: "leave", seat: 2 });
      expect(parse({ t: "moveSeat", seat: 0 })).toEqual({ t: "moveSeat", seat: 0 });
      expect(parse({ t: "leave", seat: -1 })).toEqual(BAD);
      expect(parse({ t: "moveSeat", seat: 1.5 })).toEqual(BAD);
      expect(parse({ t: "moveSeat" })).toEqual(BAD);
    });
  });

  describe("configure", () => {
    it("accepts open, bot, closed", () => {
      for (const kind of ["open", "bot", "closed"]) {
        expect(parse({ t: "configure", seat: 1, kind })).toEqual({ t: "configure", seat: 1, kind });
      }
    });
    it("rejects other kinds and bad seats", () => {
      expect(parse({ t: "configure", seat: 1, kind: "human" })).toEqual(BAD);
      expect(parse({ t: "configure", seat: "1", kind: "bot" })).toEqual(BAD);
      expect(parse({ t: "configure", seat: 1 })).toEqual(BAD);
    });
  });

  describe("claim", () => {
    it("parses a valid claim", () => {
      expect(parse({ t: "claim", seat: 1, person })).toEqual({ t: "claim", seat: 1, person });
    });
    it("claim with 21-char name -> bad_message", () => {
      expect(parse({ t: "claim", seat: 1, person: { ...person, name: "a".repeat(21) } })).toEqual(BAD);
    });
    it("accepts 20-char name and trims", () => {
      const ok = parse({ t: "claim", seat: 0, person: { ...person, name: "  " + "a".repeat(20) + "\n" } });
      expect(ok).toEqual({ t: "claim", seat: 0, person: { ...person, name: "a".repeat(20) } });
      const trimmed = parse({ t: "claim", seat: 0, person: { ...person, name: "  Mo  " } });
      expect(trimmed).toEqual({ t: "claim", seat: 0, person: { ...person, name: "Mo" } });
    });
    it("rejects empty or blank names", () => {
      expect(parse({ t: "claim", seat: 0, person: { ...person, name: "" } })).toEqual(BAD);
      expect(parse({ t: "claim", seat: 0, person: { ...person, name: "   " } })).toEqual(BAD);
      expect(parse({ t: "claim", seat: 0, person: { ...person, name: 7 } })).toEqual(BAD);
    });
    it("validates cat 0-7 integer", () => {
      for (const cat of [0, 7]) expect(parse({ t: "claim", seat: 0, person: { ...person, cat } })).toMatchObject({ t: "claim" });
      for (const cat of [-1, 8, 1.5, "3", null]) expect(parse({ t: "claim", seat: 0, person: { ...person, cat } })).toEqual(BAD);
    });
    it("validates person id as a UUID, case-insensitively", () => {
      const upper = UUID.toUpperCase();
      expect(parse({ t: "claim", seat: 0, person: { ...person, id: upper } })).toEqual({
        t: "claim",
        seat: 0,
        person: { ...person, id: upper },
      });
      for (const id of ["", "not-a-uuid", UUID.replace(/-/g, ""), UUID + "0", "g23e4567-e89b-42d3-a456-426614174000", 5]) {
        expect(parse({ t: "claim", seat: 0, person: { ...person, id } })).toEqual(BAD);
      }
    });
    it("rejects non-object person, missing person and extra person keys", () => {
      expect(parse({ t: "claim", seat: 0 })).toEqual(BAD);
      expect(parse({ t: "claim", seat: 0, person: null })).toEqual(BAD);
      expect(parse({ t: "claim", seat: 0, person: "me" })).toEqual(BAD);
      expect(parse({ t: "claim", seat: 0, person: { ...person, admin: true } })).toEqual(BAD);
      expect(parse({ t: "claim", seat: 0, person: { id: UUID, name: "Mo" } })).toEqual(BAD);
    });
  });

  describe("the name filter", () => {
    const BAD_NAME = { error: "bad_name" };

    it("refuses a claim, a seat rename and a table rename whose name it catches, as bad_name", () => {
      expect(parse({ t: "claim", seat: 0, person: { ...person, name: "sh1thead" } })).toEqual(BAD_NAME);
      expect(parse({ t: "renameSeat", seat: 0, name: "f u c k" })).toEqual(BAD_NAME);
      expect(parse({ t: "rename", name: "The Asshole Club" })).toEqual(BAD_NAME);
    });

    it("leaves ordinary names alone, and a malformed one is still bad_message", () => {
      expect(parse({ t: "renameSeat", seat: 0, name: "Cassandra" })).toEqual({ t: "renameSeat", seat: 0, name: "Cassandra" });
      expect(parse({ t: "rename", name: "Scunthorpe Cats" })).toEqual({ t: "rename", name: "Scunthorpe Cats" });
      expect(parse({ t: "renameSeat", seat: 0, name: "" })).toEqual(BAD);
      expect(parse({ t: "renameSeat", seat: 0, name: "Mi\u202Ea" })).toEqual(BAD);
      expect(parse({ t: "claim", seat: 0, person: { ...person, name: "a\u0007b" } })).toEqual(BAD);
    });
  });

  describe("renameSeat", () => {
    it("parses a renameSeat and trims the name", () => {
      expect(parse({ t: "renameSeat", seat: 1, name: "  Mo  " })).toEqual({ t: "renameSeat", seat: 1, name: "Mo" });
      expect(parse({ t: "renameSeat", seat: 0, name: "a".repeat(20) })).toEqual({ t: "renameSeat", seat: 0, name: "a".repeat(20) });
    });
    it("rejects empty, blank, too-long and non-string names", () => {
      for (const name of ["", "   ", "a".repeat(21), 7, null]) expect(parse({ t: "renameSeat", seat: 0, name })).toEqual(BAD);
    });
    it("rejects bad seats, missing keys and extra keys", () => {
      expect(parse({ t: "renameSeat", seat: -1, name: "Mo" })).toEqual(BAD);
      expect(parse({ t: "renameSeat", seat: "0", name: "Mo" })).toEqual(BAD);
      expect(parse({ t: "renameSeat", name: "Mo" })).toEqual(BAD);
      expect(parse({ t: "renameSeat", seat: 0 })).toEqual(BAD);
      expect(parse({ t: "renameSeat", seat: 0, name: "Mo", cat: 1 })).toEqual(BAD);
    });
  });

  describe("claimMove", () => {
    it("accepts a 6-char code from the alphabet", () => {
      expect(parse({ t: "claimMove", code: "BCDF23" })).toEqual({ t: "claimMove", code: "BCDF23" });
    });
    it("rejects wrong length, chars outside the alphabet, and non-strings", () => {
      for (const code of ["BCDF2", "BCDF234", "BCDFA3", "bcdf23", "BCDF 3", "", 123456, null]) {
        expect(parse({ t: "claimMove", code })).toEqual(BAD);
      }
      expect(parse({ t: "claimMove" })).toEqual(BAD);
    });
  });

  describe("nudge", () => {
    it("takes a seat and nothing else", () => {
      expect(parse({ t: "nudge", seat: 2 })).toEqual({ t: "nudge", seat: 2 });
      expect(parse({ t: "nudge" })).toEqual(BAD);
      expect(parse({ t: "nudge", seat: -1 })).toEqual(BAD);
      expect(parse({ t: "nudge", seat: 1.5 })).toEqual(BAD);
      expect(parse({ t: "nudge", seat: "1" })).toEqual(BAD);
      expect(parse({ t: "nudge", seat: 1, from: 0 })).toEqual(BAD);
    });
  });

  describe("ping and link", () => {
    it("ping is just its type", () => {
      expect(parse({ t: "ping" })).toEqual({ t: "ping" });
      expect(parse({ t: "ping", at: 1 })).toEqual(BAD);
    });
    it("link says weak or good", () => {
      expect(parse({ t: "link", state: "weak" })).toEqual({ t: "link", state: "weak" });
      expect(parse({ t: "link", state: "good" })).toEqual({ t: "link", state: "good" });
      expect(parse({ t: "link", state: "lost" })).toEqual(BAD);
      expect(parse({ t: "link" })).toEqual(BAD);
    });
  });

  describe("act", () => {
    it("valid act parses", () => {
      expect(parse(act({ type: "draw", from: "deck" }, 1))).toEqual({
        t: "act",
        seat: 1,
        action: { type: "draw", from: "deck" },
      });
    });
    it("an optional move id: short and plain", () => {
      const id = "0F8C1D2E-3A4B-4C5D-8E6F-7A8B9C0D1E2F";
      expect(parse({ ...act({ type: "draw", from: "deck" }), id })).toEqual({
        t: "act",
        seat: 0,
        action: { type: "draw", from: "deck" },
        id,
      });
      for (const bad of ["", "x".repeat(65), "has space", "a/b", 7, null]) {
        expect(parse({ ...act({ type: "draw", from: "deck" }), id: bad })).toEqual(BAD);
      }
      expect(parse({ ...act({ type: "fold" }), id })).toEqual(BAD);
    });
    it("act with string seat -> bad_message", () => {
      expect(parse(act({ type: "draw", from: "deck" }, "0"))).toEqual(BAD);
    });
    it("rejects missing or non-object action", () => {
      expect(parse({ t: "act", seat: 0 })).toEqual(BAD);
      for (const a of [null, "draw", 5, [], [{ type: "draw" }]]) expect(parse(act(a))).toEqual(BAD);
    });
    it("rejects unknown action type and extra action keys", () => {
      expect(parse(act({ type: "fold" }))).toEqual(BAD);
      expect(parse(act({}))).toEqual(BAD);
      expect(parse(act({ type: "draw", from: "deck", extra: 1 }))).toEqual(BAD);
      expect(parse(act({ type: "nextRound", extra: 1 }))).toEqual(BAD);
    });

    it("draw: from must be deck or discard", () => {
      expect(parse(act({ type: "draw", from: "discard" }))).toMatchObject({ action: { type: "draw", from: "discard" } });
      expect(parse(act({ type: "draw", from: "hand" }))).toEqual(BAD);
      expect(parse(act({ type: "draw" }))).toEqual(BAD);
    });

    it("nextRound", () => {
      expect(parse(act({ type: "nextRound" }))).toEqual({ t: "act", seat: 0, action: { type: "nextRound" } });
    });

    it("discard: card 0-107, optional integer skipTarget", () => {
      expect(parse(act({ type: "discard", card: 107 }))).toMatchObject({ action: { type: "discard", card: 107 } });
      expect(parse(act({ type: "discard", card: 0, skipTarget: 2 }))).toMatchObject({
        action: { type: "discard", card: 0, skipTarget: 2 },
      });
      for (const card of [-1, 108, 1.5, "3", null, undefined]) expect(parse(act({ type: "discard", card }))).toEqual(BAD);
      for (const skipTarget of [1.5, "1", null]) expect(parse(act({ type: "discard", card: 1, skipTarget }))).toEqual(BAD);
    });

    it("hit: card and target seat/group", () => {
      const ok = { type: "hit", card: 5, target: { seat: 1, group: 0 } };
      expect(parse(act(ok))).toEqual({ t: "act", seat: 0, action: ok });
      expect(parse(act({ ...ok, card: 108 }))).toEqual(BAD);
      expect(parse(act({ type: "hit", card: 5 }))).toEqual(BAD);
      expect(parse(act({ ...ok, target: null }))).toEqual(BAD);
      expect(parse(act({ ...ok, target: { seat: -1, group: 0 } }))).toEqual(BAD);
      expect(parse(act({ ...ok, target: { seat: 1, group: 1.5 } }))).toEqual(BAD);
      expect(parse(act({ ...ok, target: { seat: 1, group: 0, x: 1 } }))).toEqual(BAD);
    });

    it("hit: optional side start/end picks the end of a run", () => {
      const ok = { type: "hit", card: 96, target: { seat: 1, group: 0 } };
      for (const side of ["start", "end"]) {
        expect(parse(act({ ...ok, side }))).toEqual({ t: "act", seat: 0, action: { ...ok, side } });
      }
      for (const side of ["middle", "", 0, null, true]) expect(parse(act({ ...ok, side }))).toEqual(BAD);
    });

    it("layDown: 1-2 groups of 1-12 cards, optional runStart 1-12", () => {
      const g = (cards: unknown, runStart?: unknown) => (runStart === undefined ? { cards } : { cards, runStart });
      const ok = { type: "layDown", groups: [g([0, 1, 2]), g([10, 11, 12, 13], 4)] };
      expect(parse(act(ok))).toEqual({ t: "act", seat: 0, action: ok });
      expect(parse(act({ type: "layDown", groups: [g([5])] }))).toMatchObject({ t: "act" });
      expect(parse(act({ type: "layDown", groups: [g(Array.from({ length: 12 }, (_, i) => i))] }))).toMatchObject({ t: "act" });
      expect(parse(act({ type: "layDown", groups: [g([1], 1)] }))).toMatchObject({ t: "act" });
      expect(parse(act({ type: "layDown", groups: [g([1], 12)] }))).toMatchObject({ t: "act" });

      const bad: unknown[] = [
        { type: "layDown" },
        { type: "layDown", groups: "x" },
        { type: "layDown", groups: [] },
        { type: "layDown", groups: [g([1]), g([2]), g([3])] },
        { type: "layDown", groups: [null] },
        { type: "layDown", groups: [[1, 2, 3]] },
        { type: "layDown", groups: [{}] },
        { type: "layDown", groups: [g("abc")] },
        { type: "layDown", groups: [g([])] },
        { type: "layDown", groups: [g(Array.from({ length: 13 }, (_, i) => i))] },
        { type: "layDown", groups: [g([108])] },
        { type: "layDown", groups: [g([-1])] },
        { type: "layDown", groups: [g([1.5])] },
        { type: "layDown", groups: [g(["1"])] },
        { type: "layDown", groups: [g([1], 0)] },
        { type: "layDown", groups: [g([1], 13)] },
        { type: "layDown", groups: [g([1], 2.5)] },
        { type: "layDown", groups: [g([1], "2")] },
        { type: "layDown", groups: [g([1], null)] },
        { type: "layDown", groups: [{ cards: [1], extra: 1 }] },
        { type: "layDown", groups: [g([1])], extra: 1 },
      ];
      for (const action of bad) expect(parse(act(action))).toEqual(BAD);
    });
  });
});

describe("rename", () => {
  it("parses a trimmed name with its spaces collapsed", () => {
    expect(parse({ t: "rename", name: "  Taco   Night " })).toEqual({ t: "rename", name: "Taco Night" });
  });

  it("rejects a missing, empty, long, non-string or control-character name, and extra keys", () => {
    for (const msg of [
      { t: "rename" },
      { t: "rename", name: "" },
      { t: "rename", name: "   " },
      { t: "rename", name: "x".repeat(31) },
      { t: "rename", name: 7 },
      { t: "rename", name: "two\nlines" },
      { t: "rename", name: "Taco Night", seat: 0 },
    ]) {
      expect(parse(msg), JSON.stringify(msg)).toEqual(BAD);
    }
  });
});

describe("streak additions", () => {
  it("parses rematch", () => {
    expect(parse({ t: "rematch" })).toEqual({ t: "rematch" });
    expect(parse({ t: "rematch", code: "BCDFG" })).toEqual(BAD);
  });

  it("parses setLook with a known rug, back or both", () => {
    expect(parse({ t: "setLook", rug: "rug-night-sky" })).toEqual({ t: "setLook", rug: "rug-night-sky" });
    expect(parse({ t: "setLook", back: "back-crown" })).toEqual({ t: "setLook", back: "back-crown" });
    expect(parse({ t: "setLook", rug: "rug-classic", back: "back-violet-paw" })).toEqual({
      t: "setLook",
      rug: "rug-classic",
      back: "back-violet-paw",
    });
  });

  it("rejects an empty setLook, unknown ids and extra keys", () => {
    for (const bad of [
      { t: "setLook" },
      { t: "setLook", rug: "rug-lava" },
      { t: "setLook", rug: "back-crown" },
      { t: "setLook", back: "rug-classic" },
      { t: "setLook", back: 3 },
      { t: "setLook", rug: "rug-classic", seat: 0 },
    ]) {
      expect(parse(bad)).toEqual(BAD);
    }
  });
});
