import { describe, expect, test } from "vitest";

import { apnsBody, category, collapseId, MAX_CODES, relevance } from "./payload";

import type { NotifyKind } from "./policy";
import type { Outgoing } from "./types";

const yourMove: Outgoing = {
  kind: "your_move",
  title: "JD",
  body: "Mia played. Your move at Couch Cats.",
  code: "GH2VD",
  thread: "GH2VD",
  collapse: "GH2VD",
  from: { name: "Mia", cat: 2 },
  streak: { pair: "pr_3f9c", count: 12, me: false, them: true, naps: 1, myMove: ["GH2VD"], theirMove: [] },
};

describe("categories and relevance (§12.5)", () => {
  test("each kind has its category and score", () => {
    const expected: [NotifyKind, string, number][] = [
      ["your_move", "YOUR_MOVE", 1],
      ["reminder", "REMINDER", 0.6],
      ["last_chance", "REMINDER", 0.6],
      ["fresh_start", "REMINDER", 0.6],
      ["pounce", "POUNCE", 0.9],
      ["going_quiet", "STATUS", 0.2],
      ["pounce_answered", "STATUS", 0.2],
      ["nap", "STATUS", 0.2],
      ["winback", "STATUS", 0.2],
      ["paused", "STATUS", 0.2],
      ["milestone", "STATUS", 0.2],
      ["play_again", "STATUS", 0.2],
      ["nudge", "YOUR_MOVE", 1],
    ];
    for (const [kind, cat, score] of expected) {
      expect(category(kind), kind).toBe(cat);
      expect(relevance(kind), kind).toBe(score);
    }
  });
});

describe("apnsBody (§12.7)", () => {
  test("your move matches the spec's sample", () => {
    expect(apnsBody(yourMove, "active", 2)).toEqual({
      aps: {
        alert: { title: "JD", body: "Mia played. Your move at Couch Cats." },
        sound: "default",
        "thread-id": "GH2VD",
        "mutable-content": 1,
        category: "YOUR_MOVE",
        "interruption-level": "active",
        "relevance-score": 1,
        badge: 2,
      },
      code: "GH2VD",
      kind: "your_move",
      from: { name: "Mia", cat: 2 },
      streak: { pair: "pr_3f9c", count: 12, me: false, them: true, naps: 1, myMove: ["GH2VD"], theirMove: [] },
    });
    expect(new TextEncoder().encode(JSON.stringify(apnsBody(yourMove, "active", 2))).length).toBeLessThan(4096);
  });

  test("a passive push is silent; optional fields are left out; data sits beside aps", () => {
    const nap: Outgoing = { kind: "nap", title: "Couch Cats", body: "x", thread: "pair:pr_1", collapse: "nap:pr_1", data: { pair: "pr_1" } };
    const body = apnsBody(nap, "passive", 0) as { aps: Record<string, unknown> };
    expect(body.aps).not.toHaveProperty("sound");
    expect(body.aps["interruption-level"]).toBe("passive");
    expect(body).toEqual({ aps: body.aps, kind: "nap", pair: "pr_1" });
  });

  test("streak move lists are capped so the payload stays small", () => {
    const many = Array.from({ length: 30 }, (_, i) => `C${i}`);
    const body = apnsBody({ ...yourMove, streak: { ...(yourMove.streak as NonNullable<Outgoing["streak"]>), myMove: many, theirMove: many } }, "active", 1) as {
      streak: { myMove: string[]; theirMove: string[] };
    };
    expect(body.streak.myMove).toHaveLength(MAX_CODES);
    expect(body.streak.theirMove).toHaveLength(MAX_CODES);
  });
});

describe("collapseId", () => {
  test("keeps short ids and shortens long ones to 64 bytes, deterministically", () => {
    expect(collapseId("nap:pr_AAAAAAAAAAAAAAAAAAAAAA")).toBe("nap:pr_AAAAAAAAAAAAAAAAAAAAAA");
    const long = `milestone:${"x".repeat(80)}`;
    const short = collapseId(long);
    expect(new TextEncoder().encode(short).length).toBeLessThanOrEqual(64);
    expect(short).toBe(collapseId(long));
    expect(collapseId(`milestone:${"y".repeat(80)}`)).not.toBe(short);
    expect(new TextEncoder().encode(collapseId("é".repeat(60))).length).toBeLessThanOrEqual(64);
  });
});
