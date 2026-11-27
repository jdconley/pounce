import { describe, expect, it } from "vitest";

import { apply, create, finish, type PurrAction, type PurrEvent, type PurrState } from "./engine";
import { DEFAULT_OPTIONS } from "./parse";
import { WORDS } from "./words";

import type { Seed } from "../rules/rng";

const SEED: Seed = [11, 22, 33, 44];
const NO: { easyOnly: boolean } = { easyOnly: false };

function ok(s: PurrState, seat: number, a: PurrAction, ctx = NO): { state: PurrState; events: PurrEvent[] } {
  const r = apply(s, seat, a, ctx);
  if (!r.ok) throw new Error(`refused: ${r.error}`);
  return r;
}

const game = (seats = 3): PurrState => create(seats, SEED, DEFAULT_OPTIONS);
const wordOf = (id: number | null) => WORDS[id as number] as (typeof WORDS)[number];

describe("create", () => {
  it("starts seat 0 choosing, round 1", () => {
    const s = game();
    expect(s.phase).toBe("choosing");
    expect(s.drawer).toBe(0);
    expect(s.round).toBe(1);
    expect(s.scores).toEqual([0, 0, 0]);
  });

  it("is deterministic for a seed", () => {
    expect(game(4)).toEqual(game(4));
  });

  it("offers one easy and one tricky unused word, plus a second easy", () => {
    const o = game().offer!;
    expect(wordOf(o.easy).level).toBe("easy");
    expect(wordOf(o.tricky).level).toBe("tricky");
    expect(wordOf(o.easy2).level).toBe("easy");
    expect(o.easy2).not.toBe(o.easy);
  });
});

describe("a turn", () => {
  it("choose then gotIt scores 1 each for easy", () => {
    let s = ok(game(), 0, { type: "choose", level: "easy" }).state;
    expect(s.phase).toBe("drawing");
    const r = ok(s, 0, { type: "gotIt", seat: 2 });
    s = r.state;
    expect(s.phase).toBe("reveal");
    expect(s.scores).toEqual([1, 0, 1]);
    expect(r.events).toEqual([{ type: "guessed", drawer: 0, guesser: 2, points: 1, word: wordOf(s.word).word }]);
    expect(s.last).toEqual({ word: wordOf(s.word).word, guesser: 2, points: 1 });
  });

  it("scores 2 each for tricky", () => {
    let s = ok(game(), 0, { type: "choose", level: "tricky" }).state;
    s = ok(s, 0, { type: "gotIt", seat: 1 }).state;
    expect(s.scores).toEqual([2, 2, 0]);
  });

  it("the chosen event names the group and level, never the word", () => {
    const r = ok(game(), 0, { type: "choose", level: "tricky" });
    expect(r.events).toHaveLength(1);
    expect(r.events[0]).toEqual({ type: "chosen", drawer: 0, group: wordOf(r.state.word).group, level: "tricky" });
    const word = wordOf(r.state.word).word;
    expect(r.events[0]).not.toHaveProperty("word");
    expect(Object.values(r.events[0] as object)).not.toContain(word);
    expect(JSON.stringify(r.events)).not.toContain(word);
  });

  it("timeUp and giveUp score nothing and reveal", () => {
    const drawing = ok(game(), 0, { type: "choose", level: "easy" }).state;
    for (const [a, reason] of [
      [{ type: "timeUp" }, "time"],
      [{ type: "giveUp" }, "gaveUp"],
    ] as const) {
      const r = ok(drawing, 0, a);
      expect(r.state.phase).toBe("reveal");
      expect(r.state.scores).toEqual([0, 0, 0]);
      expect(r.state.last).toEqual({ word: wordOf(drawing.word).word, guesser: null, points: 0 });
      expect(r.events).toEqual([{ type: "missed", drawer: 0, word: wordOf(drawing.word).word, reason }]);
    }
  });

  it("timeUp while choosing picks the easy word", () => {
    const s = game();
    const r = ok(s, 0, { type: "timeUp" });
    expect(r.state.phase).toBe("drawing");
    expect(r.state.word).toBe(s.offer!.easy);
    expect(r.state.level).toBe("easy");
  });

  it("nextTurn after the reveal moves on and keeps the last result", () => {
    let s = ok(game(), 0, { type: "choose", level: "easy" }).state;
    s = ok(s, 0, { type: "gotIt", seat: 1 }).state;
    const r = ok(s, 0, { type: "nextTurn" });
    expect(r.state.phase).toBe("choosing");
    expect(r.state.drawer).toBe(1);
    expect(r.state.turnIndex).toBe(1);
    expect(r.state.last).not.toBeNull();
    expect(r.events).toEqual([{ type: "turn", drawer: 1, round: 1 }]);
  });

  it("refuses wrong seats and phases", () => {
    const s = game();
    expect(apply(s, 1, { type: "choose", level: "easy" }, NO)).toEqual({ ok: false, error: "not_your_turn" });
    expect(apply(s, 0, { type: "gotIt", seat: 1 }, NO)).toEqual({ ok: false, error: "wrong_phase" });
    expect(apply(s, 0, { type: "nextTurn" }, NO)).toEqual({ ok: false, error: "wrong_phase" });
    const d = ok(s, 0, { type: "choose", level: "easy" }).state;
    expect(apply(d, 0, { type: "choose", level: "easy" }, NO)).toEqual({ ok: false, error: "wrong_phase" });
    expect(apply(d, 1, { type: "gotIt", seat: 2 }, NO)).toEqual({ ok: false, error: "not_your_turn" });
    expect(apply(d, 1, { type: "giveUp" }, NO)).toEqual({ ok: false, error: "not_your_turn" });
  });

  it("gotIt for the drawer's own seat or an out seat is bad_seat", () => {
    let d = ok(game(), 0, { type: "choose", level: "easy" }).state;
    expect(apply(d, 0, { type: "gotIt", seat: 0 }, NO)).toEqual({ ok: false, error: "bad_seat" });
    expect(apply(d, 0, { type: "gotIt", seat: 7 }, NO)).toEqual({ ok: false, error: "bad_seat" });
    d = ok(d, 2, { type: "forfeit" }).state;
    expect(apply(d, 0, { type: "gotIt", seat: 2 }, NO)).toEqual({ ok: false, error: "bad_seat" });
  });

  it("easyOnly uses the second easy word for a tricky pick and scores 1", () => {
    const s = game();
    const r = ok(s, 0, { type: "choose", level: "tricky" }, { easyOnly: true });
    expect(r.state.word).toBe(s.offer!.easy2);
    expect(r.state.level).toBe("easy");
    expect(ok(r.state, 0, { type: "gotIt", seat: 1 }).state.scores).toEqual([1, 1, 0]);
    expect(ok(s, 0, { type: "choose", level: "easy" }, { easyOnly: true }).state.word).toBe(s.offer!.easy);
  });

  it("apply does not change its input", () => {
    const s = game();
    const copy = structuredClone(s);
    ok(s, 0, { type: "choose", level: "easy" });
    expect(s).toEqual(copy);
  });
});

function playTurn(s: PurrState, level: "easy" | "tricky", guesser: number): PurrState {
  const d = s.drawer!;
  let n = ok(s, d, { type: "choose", level }).state;
  n = ok(n, d, { type: "gotIt", seat: guesser }).state;
  return n;
}

describe("the game", () => {
  it("runs two rounds in seat order, then over", () => {
    let s = game(3);
    const drawers: number[] = [];
    for (let i = 0; i < 6; i++) {
      drawers.push(s.drawer!);
      expect(s.round).toBe(i < 3 ? 1 : 2);
      s = playTurn(s, "easy", (s.drawer! + 1) % 3);
      const r = ok(s, 0, { type: "nextTurn" });
      s = r.state;
      if (i === 5) expect(r.events.at(-1)?.type).toBe("over");
    }
    expect(drawers).toEqual([0, 1, 2, 0, 1, 2]);
    expect(s.phase).toBe("over");
    expect(s.drawer).toBeNull();
    expect(s.scores).toEqual([4, 4, 4]);
    expect(s.winners).toEqual([0, 1, 2]);
    expect(apply(s, 0, { type: "giveUp" }, NO)).toEqual({ ok: false, error: "game_over" });
  });

  it("the highest score wins, ties share", () => {
    let s = game(3);
    const picks = [2, 2, 2, 0, 0, 0];
    for (const g of picks) {
      s = playTurn(s, "easy", g === s.drawer ? (g + 1) % 3 : g);
      s = ok(s, 0, { type: "nextTurn" }).state;
    }
    expect(s.phase).toBe("over");
    expect(Math.max(...s.scores)).toBe(s.scores[s.winners[0] as number]);
    expect(s.winners.every((w) => s.scores[w] === Math.max(...s.scores))).toBe(true);
  });

  it("a forfeited seat is skipped and the game ends below 2", () => {
    let s = game(3);
    s = ok(s, 1, { type: "forfeit" }).state;
    s = playTurn(s, "easy", 2);
    s = ok(s, 0, { type: "nextTurn" }).state;
    expect(s.drawer).toBe(2);
    expect(s.out).toEqual([false, true, false]);
    expect(s.scores[1]).toBe(0);
    s = playTurn(s, "easy", 0);
    s = ok(s, 0, { type: "nextTurn" }).state;
    expect(s.round).toBe(2);
    expect(s.drawer).toBe(0);
    const r = ok(s, 2, { type: "forfeit" });
    expect(r.state.phase).toBe("over");
    expect(r.events.at(-1)).toMatchObject({ type: "over" });
    expect(r.state.winners).toEqual([0]);
  });

  it("a drawer who leaves mid-turn misses with reason left", () => {
    const s = ok(game(3), 0, { type: "choose", level: "easy" }).state;
    const r = ok(s, 0, { type: "forfeit" });
    expect(r.state.phase).toBe("reveal");
    expect(r.events).toEqual([{ type: "missed", drawer: 0, word: wordOf(s.word).word, reason: "left" }]);
    expect(ok(r.state, 0, { type: "nextTurn" }).state.drawer).toBe(1);
  });

  it("a drawer who leaves while choosing moves straight on", () => {
    const r = ok(game(3), 0, { type: "forfeit" });
    expect(r.state.phase).toBe("choosing");
    expect(r.state.drawer).toBe(1);
    expect(r.events).toEqual([{ type: "turn", drawer: 1, round: 1 }]);
  });

  it("no word twice in a 10-seat game", () => {
    let s = create(10, SEED, DEFAULT_OPTIONS);
    const seen: string[] = [];
    for (let i = 0; i < 20; i++) {
      s = playTurn(s, i % 2 ? "tricky" : "easy", (s.drawer! + 1) % 10);
      seen.push(s.last!.word);
      s = ok(s, 0, { type: "nextTurn" }).state;
    }
    expect(s.phase).toBe("over");
    expect(new Set(seen).size).toBe(20);
  });

  it("stalled ends with the highest as winners", () => {
    let s = playTurn(game(3), "tricky", 2);
    s = ok(s, 0, { type: "nextTurn" }).state;
    const r = finish(s, "stalled");
    expect(r.state.phase).toBe("over");
    expect(r.state.endReason).toBe("stalled");
    expect(r.state.winners).toEqual([0, 2]);
  });

  it("finish does nothing once the game is over", () => {
    const over = finish(game(3), "left").state;
    const again = finish(over, "stalled");
    expect(again.state).toEqual(over);
    expect(again.events).toEqual([]);
    expect(again.state.endReason).toBe("left");
  });

  it("every offer in a 10-seat game excludes used words", () => {
    let s = create(10, SEED, DEFAULT_OPTIONS);
    for (let i = 0; i < 20; i++) {
      const o = s.offer!;
      for (const id of [o.easy, o.tricky, o.easy2]) expect(s.used).not.toContain(id);
      s = playTurn(s, i % 2 ? "tricky" : "easy", (s.drawer! + 1) % 10);
      s = ok(s, 0, { type: "nextTurn" }).state;
    }
  });
});
