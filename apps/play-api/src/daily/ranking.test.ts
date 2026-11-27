import { describe, expect, it } from "vitest";

import { createRng } from "../rules/rng";

import { rankGame, type BoardRow } from "./board";
import { boxFort } from "./box-fort/module";
import { catNap } from "./cat-nap/module";
import { nineLives } from "./nine-lives/module";
import { SAMPLE } from "./nine-lives/samples";
import { sniff } from "./sniff/module";

import type { NapState } from "./cat-nap/rules";
import type { DailyGameId, DailyModule, DailyResult } from "./module";
import type { NineLivesState } from "./nine-lives/grid";
import type { SniffState } from "./sniff/module";

/**
 * JD, 2026-11-26: "if you fail or quit any puzzle you should get ranked on % completed as well.
 * just lower rank than anyone that completed it." (spec §6, "Ranking").
 */
const row = (game: DailyGameId, player: string, r: Partial<DailyResult>): BoardRow => ({
  player,
  name: player,
  cat: 0,
  rank: null,
  playing: null,
  result: { game, date: "2026-11-23", number: 1, outcome: "solved", timeMs: 100_000, hints: 0, tooFast: false, progress: 1, percent: 100, ...r },
});
const order = (m: DailyModule, rows: BoardRow[]) => rankGame(m, rows).map((r) => [r.player, r.rank]);

describe("the board's order: everyone who finished, then everyone else by percent", () => {
  it("Nine Lives: solvers by time, then failed, given up and closed runs together by percent, then time", () => {
    const m = nineLives as unknown as DailyModule;
    const rows = [
      row("nine-lives", "outOfLives", { outcome: "missed", progress: 0.62, percent: 62, timeMs: 50_000 }),
      row("nine-lives", "slowSolve", { timeMs: 900_000 }),
      row("nine-lives", "quit", { outcome: "gaveUp", progress: 0.8, percent: 80, timeMs: 400_000 }),
      row("nine-lives", "leftOpen", { outcome: "closed", progress: 0.62, percent: 62, timeMs: 40_000 }),
      row("nine-lives", "fastSolve", { timeMs: 200_000 }),
    ];
    expect(order(m, rows)).toEqual([["fastSolve", 1], ["slowSolve", 2], ["quit", 3], ["leftOpen", 4], ["outOfLives", 5]]);
  });

  it("Box Fort: every run that ended normally, by points, above every given-up or closed one", () => {
    const m = boxFort as unknown as DailyModule;
    const rows = [
      row("box-fort", "quitBig", { outcome: "gaveUp", points: 5000, progress: 0.9, percent: 90 }),
      row("box-fort", "done", { outcome: "done", points: 300, progress: 0.3, percent: 30 }),
      row("box-fort", "quitSmall", { outcome: "gaveUp", points: 100, progress: 0.2, percent: 20 }),
    ];
    expect(order(m, rows)).toEqual([["done", 1], ["quitBig", 2], ["quitSmall", 3]]);
  });

  it("Sniff: solvers by guesses, then misses by percent", () => {
    const m = sniff as unknown as DailyModule;
    const rows = [
      row("sniff", "missFew", { outcome: "missed", guesses: 6, progress: 0.2, percent: 20 }),
      row("sniff", "six", { guesses: 6 }),
      row("sniff", "missMany", { outcome: "missed", guesses: 6, progress: 0.8, percent: 80 }),
      row("sniff", "three", { guesses: 3 }),
    ];
    expect(order(m, rows)).toEqual([["three", 1], ["six", 2], ["missMany", 3], ["missFew", 4]]);
  });

  it("ties share a rank: the same percent and time", () => {
    const m = catNap as unknown as DailyModule;
    const rows = [row("cat-nap", "a", { outcome: "gaveUp", progress: 0.5, percent: 50 }), row("cat-nap", "b", { outcome: "missed", progress: 0.5, percent: 50 })];
    expect(order(m, rows)).toEqual([["a", 1], ["b", 1]]);
  });

  it("a result stored before percent ranks by its progress", () => {
    const m = catNap as unknown as DailyModule;
    const old = row("cat-nap", "old", { outcome: "gaveUp", progress: 0.75 });
    delete (old.result as { percent?: number }).percent;
    const rows = [row("cat-nap", "new", { outcome: "gaveUp", progress: 0.5, percent: 50 }), old];
    expect(order(m, rows)).toEqual([["old", 1], ["new", 2]]);
  });
});

describe("percent, each game's fair measure", () => {
  it("Nine Lives: right cells the player filled, out of the open cells; hints and wrong numbers don't count", () => {
    const p = SAMPLE;
    const open = p.givens.flatMap((d, i) => (d === 0 ? [i] : []));
    const cells = [...p.givens];
    // Four right, one wrong (first rules), one hinted.
    for (const i of open.slice(0, 4)) cells[i] = p.solution[i]!;
    cells[open[4]!] = (p.solution[open[4]!]! % 9) + 1;
    cells[open[5]!] = p.solution[open[5]!]!;
    const s: NineLivesState = { cells, hinted: [open[5]!] };
    expect(nineLives.result(p, s, "gaveUp", 1, 1).progress).toBeCloseTo(4 / open.length);
    expect(nineLives.result(p, s, "solved", 1, 1).progress).toBe(1);
  });

  it("Cat Nap: cats on their solution cells, out of n; a hinted cat and a wrong cat don't count", () => {
    const p = catNap.make(createRng([4, 3, 2, 1]), 1, { date: "2026-11-23", key: [0, 0, 0, 1] });
    const cells = Array<number>(p.n * p.n).fill(0) as NapState["cells"];
    cells[0 * p.n + p.solution[0]!] = 2;
    cells[1 * p.n + p.solution[1]!] = 2;
    cells[2 * p.n + p.solution[2]!] = 2; // hinted below
    cells[3 * p.n + ((p.solution[3]! + 2) % p.n)] = 2; // wrong
    const s: NapState = { cells, hinted: [2 * p.n + p.solution[2]!] };
    expect(catNap.result(p, s, "gaveUp", 1, 1).progress).toBeCloseTo(2 / p.n);
  });

  it("Sniff: letters found in their right place in any guess, out of five", () => {
    const g = (marks: string[]) => ({ word: "xxxxx", marks }) as SniffState["guesses"][number];
    const s: SniffState = {
      guesses: [g(["spot", "none", "none", "none", "none"]), g(["none", "none", "near", "none", "spot"]), g(["spot", "none", "none", "spot", "none"])],
      lastMs: 0,
    };
    expect(sniff.result({ answer: "crane", level: 1 } as never, s, "missed", 1, 0).progress).toBeCloseTo(3 / 5);
  });
});
