import { describe, expect, it } from "vitest";

import { apply, create, type PurrState } from "./engine";
import { DEFAULT_OPTIONS } from "./parse";
import { view } from "./view";
import { WORDS } from "./words";

const NO = { easyOnly: false };
const start = (): PurrState => create(3, [5, 6, 7, 8], DEFAULT_OPTIONS);
function ok(s: PurrState, seat: number, a: Parameters<typeof apply>[2], ctx = NO): PurrState {
  const r = apply(s, seat, a, ctx);
  if (!r.ok) throw new Error(r.error);
  return r.state;
}
const wordOf = (s: PurrState) => (WORDS[s.word as number] as (typeof WORDS)[number]).word;

describe("view", () => {
  it("before choose every controller sees choices; others do not", () => {
    const s = start();
    const e = WORDS[s.offer!.easy]!.word;
    const t = WORDS[s.offer!.tricky]!.word;
    for (const dev of [true, false]) {
      expect(view(s, [0], { drawerDevice: dev, easyOnly: false }).choices).toEqual({ easy: e, tricky: t });
    }
    expect(view(s, [0]).choices).toEqual({ easy: e, tricky: t });
    expect(view(s, [1]).choices).toBeUndefined();
    expect(view(s, []).choices).toBeUndefined();
    expect(view(s, [1, 2]).choices).toBeUndefined();
  });

  it("only drawerDevice sees word and youDraw once drawing", () => {
    const s = ok(start(), 0, { type: "choose", level: "tricky" });
    const mine = view(s, [0], { drawerDevice: true, easyOnly: false });
    expect(mine.word).toBe(wordOf(s));
    expect(mine.youDraw).toBe(true);
    expect(mine.choices).toBeUndefined();
    const other = view(s, [0], { drawerDevice: false, easyOnly: false });
    expect(other.word).toBeUndefined();
    expect(other.youDraw).toBeUndefined();
    expect(view(s, [1]).word).toBeUndefined();
    expect(view(s, []).word).toBeUndefined();
    expect(JSON.stringify(view(s, [1, 2]))).not.toContain(wordOf(s));
    expect(JSON.stringify(view(s, []))).not.toContain(wordOf(s));
  });

  it("shows the group and level but no word to everyone while drawing", () => {
    const s = ok(start(), 0, { type: "choose", level: "tricky" });
    const v = view(s, []);
    expect(v.group).toBe(WORDS[s.word as number]!.group);
    expect(v.level).toBe("tricky");
    expect(v.phase).toBe("drawing");
    expect(v.turn).toBe("1:0");
  });

  it("the reveal carries the word to everyone in last", () => {
    let s = ok(start(), 0, { type: "choose", level: "easy" });
    s = ok(s, 0, { type: "gotIt", seat: 1 });
    const v = view(s, []);
    expect(v.phase).toBe("reveal");
    expect(v.last).toEqual({ word: wordOf(s), guesser: 1, points: 1 });
    expect(v.word).toBeUndefined();
    expect(v.scores).toEqual([1, 1, 0]);
  });

  it("easyOnly offers two easy words and scores 1", () => {
    const s = start();
    const v = view(s, [0], { drawerDevice: true, easyOnly: true });
    expect(v.choices).toEqual({ easy: WORDS[s.offer!.easy]!.word, tricky: WORDS[s.offer!.easy2]!.word });
    expect(WORDS[s.offer!.easy2]!.level).toBe("easy");
    const picked = ok(s, 0, { type: "choose", level: "tricky" }, { easyOnly: true });
    expect(view(picked, [0], { drawerDevice: true, easyOnly: true }).level).toBe("easy");
    expect(wordOf(picked)).toBe(WORDS[s.offer!.easy2]!.word);
  });

  it("carries the table, order, out and winners; fresh arrays; no clock", () => {
    let s = ok(start(), 2, { type: "forfeit" });
    const v = view(s, []);
    expect(v).toMatchObject({ seats: 3, timer: 60, rounds: 2, round: 1, drawer: 0, order: [0, 1], out: [false, false, true] });
    expect(v.remainingMs).toBeNull();
    expect(v.paused).toBe(false);
    expect(v.winners).toEqual([]);
    v.scores[0] = 99;
    expect(s.scores[0]).toBe(0);
    s = ok(s, 1, { type: "forfeit" });
    const over = view(s, []);
    expect(over.phase).toBe("over");
    expect(over.drawer).toBeNull();
    expect(over.winners).toEqual([0]);
  });
});
