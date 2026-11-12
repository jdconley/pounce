import { describe, expect, test } from "vitest";

import { SPACING_MS } from "./policy";
import { nudgePush, playAgainPush, pouncePush, retirePush, statusPush, yourMovePush } from "./pushes";
import { MAX_REMEMBERED, noteUpdate, parseSent, updateAlert, updateBody, updateCollapse, updateDue, updateFor, type UpdatePush } from "./update";

const MIA = { name: "Mia", cat: 2 };
const push: UpdatePush = { code: "GH2VD", title: "Couch Cats", from: MIA, game: "tiles", gameTitle: "Tuna Tiles" };

describe("the words", () => {
  test("name the person and the game, and say what to do", () => {
    expect(updateBody("Mia", "Tuna Tiles")).toBe("Mia wants to play Tuna Tiles. Update Pounce to join.");
  });
});

describe("updateFor", () => {
  test("stands in for a push a person sent about the table", () => {
    const asks = [
      yourMovePush({ code: "GH2VD", table: "Couch Cats", to: "JD", from: MIA, completesToday: false, streak: null }),
      nudgePush({ code: "GH2VD", table: "Couch Cats", to: "JD", from: MIA }),
      pouncePush({ id: "pc_1", pair: "pr_1", to: "JD", from: MIA, target: { table: "GH2VD", name: "Couch Cats" }, streak: null }),
    ];
    for (const o of asks) expect(updateFor(o, "tiles", "Tuna Tiles")).toEqual({ ...push, title: "JD" });
    expect(updateFor(playAgainPush({ code: "GH2VD", table: "Couch Cats", who: MIA }), "tiles", "Tuna Tiles")).toEqual(push);
  });

  test("not for a move nobody made, a pounce at no table, a retired seat or a streak's news", () => {
    const not = [
      yourMovePush({ code: "GH2VD", table: "Couch Cats", to: "JD", from: null, completesToday: false, streak: null }),
      pouncePush({ id: "pc_1", pair: "pr_1", to: "JD", from: MIA, target: "new", streak: null }),
      retirePush({ code: "GH2VD", table: "Couch Cats", to: "JD", from: MIA }),
      retirePush({ code: "GH2VD", table: "Couch Cats", to: "JD", from: null }),
      statusPush({ kind: "paused", pair: "pr_1", title: "Mia", count: 3, who: MIA, streak: null }),
    ];
    for (const o of not) expect(updateFor(o, "tiles", "Tuna Tiles")).toBeNull();
  });
});

describe("updateAlert", () => {
  test("is a plain alert version 1.0 shows and opens the app from: no table to open, no badge, no streak", () => {
    expect(updateAlert(push, "active")).toEqual({
      aps: {
        alert: { title: "Couch Cats", body: "Mia wants to play Tuna Tiles. Update Pounce to join." },
        sound: "default",
        "thread-id": "update:GH2VD",
        category: "STATUS",
        "interruption-level": "active",
        "relevance-score": 0.9,
      },
      kind: "update",
      from: MIA,
      update: { code: "GH2VD", game: "tiles" },
    });
  });

  test("makes no sound when passive", () => {
    const body = updateAlert(push, "passive") as { aps: Record<string, unknown> };
    expect(body.aps.sound).toBeUndefined();
    expect(body.aps["interruption-level"]).toBe("passive");
  });

  test("never carries what 1.0 would act on", () => {
    const body = updateAlert(push, "active") as { aps: Record<string, unknown> } & Record<string, unknown>;
    // 1.0 opens a top-level `code`, counts a `badge`, folds a `streak` into its widgets and answers a `pounce`.
    for (const key of ["code", "streak", "pounce", "pair", "kitten"]) expect(key in body).toBe(false);
    for (const key of ["badge", "mutable-content"]) expect(key in body.aps).toBe(false);
    // Its kind is one 1.0 has no name for, and its category one with no buttons.
    expect(["your_move", "reminder", "last_chance", "fresh_start", "going_quiet", "nap", "winback", "paused", "milestone", "play_again", "pounce", "pounce_answered", "nudge", "dismiss", "consent"]).not.toContain(body.kind);
    expect(body.aps.category).toBe("STATUS");
  });

  test("collapses per table", () => {
    expect(updateCollapse("GH2VD")).toBe("update:GH2VD");
  });
});

describe("updateDue", () => {
  const T = 1_800_000_000_000;

  test("the first for a table goes", () => {
    expect(updateDue({}, "GH2VD", T)).toBe(true);
  });

  test("never twice for the same table, however long ago", () => {
    expect(updateDue({ GH2VD: T }, "GH2VD", T + 1)).toBe(false);
    expect(updateDue({ GH2VD: T }, "GH2VD", T + 365 * 24 * 3_600_000)).toBe(false);
  });

  test("another table's waits out the spacing", () => {
    expect(updateDue({ GH2VD: T }, "TB4XN", T + SPACING_MS - 1)).toBe(false);
    expect(updateDue({ GH2VD: T }, "TB4XN", T + SPACING_MS)).toBe(true);
    expect(updateDue({ AAAAA: T - SPACING_MS, GH2VD: T }, "TB4XN", T + 1)).toBe(false);
  });
});

describe("noteUpdate and parseSent", () => {
  test("writes the table down", () => {
    expect(noteUpdate({ A: 1 }, "B", 2)).toEqual({ A: 1, B: 2 });
  });

  test("keeps only the newest", () => {
    let sent = {};
    for (let i = 0; i < MAX_REMEMBERED + 5; i++) sent = noteUpdate(sent, `T${i}`, i);
    expect(Object.keys(sent)).toHaveLength(MAX_REMEMBERED);
    expect(sent).not.toHaveProperty("T0");
    expect(sent).toHaveProperty(`T${MAX_REMEMBERED + 4}`);
  });

  test("reads back what it stored, and nothing from anything else", () => {
    expect(parseSent(JSON.stringify({ A: 1, B: 2 }))).toEqual({ A: 1, B: 2 });
    expect(parseSent(null)).toEqual({});
    expect(parseSent("")).toEqual({});
    expect(parseSent("[1]")).toEqual({});
    expect(parseSent("null")).toEqual({});
    expect(parseSent('{"A":"yesterday","B":3}')).toEqual({ B: 3 });
  });
});
