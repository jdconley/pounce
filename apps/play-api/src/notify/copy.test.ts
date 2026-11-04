import { describe, expect, test } from "vitest";

import {
  answeredBody,
  DAILY_LINES,
  days,
  freshStartBody,
  GOING_QUIET,
  LAST_CHANCE_LINES,
  milestoneBody,
  napBody,
  pausedBody,
  pickLine,
  playAgainBody,
  pounceBody,
  winbackBody,
  yourMoveBody,
  type LineCtx,
} from "./copy";

const DAY_MS = 24 * 60 * 60 * 1000;
const ctx: LineCtx = { table: "Couch Cats", partner: "Mia", count: 12 };

describe("the §12.2 copy", () => {
  test("your move names who played", () => {
    expect(yourMoveBody("Mia", "Couch Cats", false)).toBe("Mia played. Your move at Couch Cats.");
    expect(yourMoveBody("Mia", "Couch Cats", true)).toBe("Mia played. Your turn makes today count.");
    expect(yourMoveBody(null, "Couch Cats", false)).toBe("Your move at Couch Cats.");
    expect(yourMoveBody(null, "Couch Cats", true)).toBe("Your turn makes today count.");
  });

  test("pounces and their answers", () => {
    expect(pounceBody("Mia", { table: "Couch Cats" })).toBe("Mia wants to play. Couch Cats?");
    expect(pounceBody("Mia", "new")).toBe("Mia wants to play. New game?");
    expect(pounceBody("Mia", "pick")).toBe("Mia wants to play. You pick.");
    expect(answeredBody("JD", "play")).toBe("JD is coming.");
    expect(answeredBody("JD", "later")).toBe("JD: in a bit.");
    expect(answeredBody("JD", "no")).toBe("JD: not now.");
  });

  test("status pushes", () => {
    expect(napBody(12)).toBe("A cat nap covered yesterday. 12 days and counting.");
    expect(napBody(1)).toBe("A cat nap covered yesterday. 1 day and counting.");
    expect(winbackBody(12)).toBe("Two days in a row brings 12 back.");
    expect(pausedBody("Mia", 3)).toBe("Mia put the cats to bed for 3 days.");
    expect(pausedBody("Mia", 1)).toBe("Mia put the cats to bed for 1 day.");
    expect(milestoneBody(30)).toBe("30 days together. There's a gift on the rug.");
    expect(playAgainBody("Mia")).toBe("Mia dealt a new game.");
    expect(freshStartBody("Mia", false)).toBe("New week, new deal. One turn starts a streak with Mia.");
    expect(freshStartBody("Mia", true)).toBe("New month, new deal. One turn starts a streak with Mia.");
    expect(GOING_QUIET).toBe("The cats will keep your seat warm.");
    expect(days(2)).toBe("2 days");
  });

  test("the rotated lines include the spec's, and there are enough for a week without repeats", () => {
    const daily = DAILY_LINES.map((l) => l.text(ctx));
    expect(daily).toEqual(
      expect.arrayContaining([
        "The cats are on the rug. Your move at Couch Cats.",
        "Day 13 is up for grabs. One turn with Mia keeps it.",
        "Mia's cat is guarding the deck. Your move.",
        "A turn with Mia, then the couch.",
      ]),
    );
    const last = LAST_CHANCE_LINES.map((l) => l.text(ctx));
    expect(last).toEqual(expect.arrayContaining(["One turn tonight keeps 12 days going.", "The cats want one more turn before bed."]));
    expect(DAILY_LINES.length).toBeGreaterThanOrEqual(7);
    expect(LAST_CHANCE_LINES.length).toBeGreaterThanOrEqual(7);
    expect(new Set([...DAILY_LINES, ...LAST_CHANCE_LINES].map((l) => l.id)).size).toBe(DAILY_LINES.length + LAST_CHANCE_LINES.length);
  });

  test("no emoji, no countdowns and no guilt anywhere (§2, §12.2)", () => {
    const all = [
      ...DAILY_LINES.map((l) => l.text(ctx)),
      ...LAST_CHANCE_LINES.map((l) => l.text(ctx)),
      yourMoveBody("Mia", "Couch Cats", true),
      pounceBody("Mia", "pick"),
      napBody(3),
      winbackBody(3),
      pausedBody("Mia", 3),
      milestoneBody(3),
      playAgainBody("Mia"),
      freshStartBody("Mia", true),
      GOING_QUIET,
    ];
    for (const line of all) {
      expect(line).not.toMatch(/\p{Extended_Pictographic}/u);
      expect(line).not.toMatch(/waiting on you|don't break|do not break|you missed|let .* down|hours? left|minutes? left|ends in|lose|lost/i);
    }
  });
});

describe("pickLine", () => {
  const now = Date.UTC(2026, 10, 4, 19);

  test("round-robins from the cursor", () => {
    const first = pickLine(DAILY_LINES, ctx, {}, 0, now);
    expect(first).toEqual({ id: DAILY_LINES[0]?.id, text: DAILY_LINES[0]?.text(ctx), cursor: 1 });
    expect(pickLine(DAILY_LINES, ctx, {}, 1, now)?.id).toBe(DAILY_LINES[1]?.id);
    expect(pickLine(DAILY_LINES, ctx, {}, DAILY_LINES.length, now)?.id).toBe(DAILY_LINES[0]?.id);
  });

  test("skips lines whose needs aren't met", () => {
    const noTable = { ...ctx, table: null, count: 0 };
    const picked = new Set<string>();
    let cursor = 0;
    for (let i = 0; i < DAILY_LINES.length; i++) {
      const p = pickLine(DAILY_LINES, noTable, {}, cursor, now);
      if (!p) throw new Error("no line");
      picked.add(p.text);
      cursor = p.cursor;
    }
    for (const text of picked) {
      expect(text).not.toContain("Couch Cats");
      expect(text).not.toMatch(/Day \d/);
    }
  });

  test("never repeats within 7 days while an older line is eligible, else takes the least recently used", () => {
    const used: Record<string, number> = {};
    const seen: string[] = [];
    let cursor = 0;
    for (let d = 0; d < 7; d++) {
      const p = pickLine(DAILY_LINES, ctx, used, cursor, now + d * DAY_MS);
      if (!p) throw new Error("no line");
      seen.push(p.id);
      used[p.id] = now + d * DAY_MS;
      cursor = p.cursor;
    }
    expect(new Set(seen).size).toBe(7);
    // Only two eligible lines, both used recently: the older one comes back.
    const two = [DAILY_LINES[2], DAILY_LINES[3]] as typeof DAILY_LINES;
    const recent = { [two[0]?.id as string]: now - DAY_MS, [two[1]?.id as string]: now - 2 * DAY_MS };
    expect(pickLine(two, ctx, recent, 0, now)?.id).toBe(two[1]?.id);
  });

  test("null when no line fits", () => {
    const needsTable = DAILY_LINES.filter((l) => l.needs.includes("table"));
    expect(pickLine(needsTable, { ...ctx, table: null }, {}, 0, now)).toBeNull();
  });
});
