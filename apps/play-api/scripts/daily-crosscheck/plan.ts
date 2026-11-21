/**
 * Daily Dish cross-platform check: the plan. From the dev server's TOKEN_SECRET and a date, using the
 * server's own game modules, work out for each game the public puzzle (and its hash), one fixed
 * move list, and the result the server must give for it (everything but the time).
 *
 *   pnpm --filter @pounce/play-api crosscheck:plan <secret> <date> > plan.json
 */
import { createHash } from "node:crypto";

import { greedyMove } from "../../src/daily/box-fort/greedy";
import { levelFor } from "../../src/daily/days";
import { DAILY_GAMES, makeDaily } from "../../src/daily/games";

import type { DailyGameId, DailyModule } from "../../src/daily/module";

/** Sorted-key JSON, so a hash doesn't depend on key order. */
export function canon(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(canon).join(",")}]`;
  if (v && typeof v === "object") {
    return `{${Object.keys(v as object).sort().map((k) => `${JSON.stringify(k)}:${canon((v as Record<string, unknown>)[k])}`).join(",")}}`;
  }
  return JSON.stringify(v);
}
const hash = (v: unknown) => createHash("sha256").update(canon(v)).digest("hex").slice(0, 16);

const [secret, date] = process.argv.slice(2);
if (!secret || !date) throw new Error("usage: plan <secret> <date>");

type Plan = { game: DailyGameId; floorMs: number; paceMs: number; puzzleHash: string; puzzle: unknown; moves: unknown[]; movesHash: string; expect: Record<string, unknown>; extra?: Record<string, unknown> };
const out: Plan[] = [];

for (const game of ["nine-lives", "box-fort", "sniff", "cat-nap"] as DailyGameId[]) {
  const m = DAILY_GAMES[game] as DailyModule;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const p = (await makeDaily(m, secret, game, date)) as any;
  const puzzle = m.publicPuzzle(p);
  const moves: unknown[] = [];
  let extra: Record<string, unknown> | undefined;
  if (game === "nine-lives") {
    for (let i = 0; i < 81; i++) if (p.givens[i] === 0) moves.push({ k: "set", i, d: p.solution[i] });
  } else if (game === "cat-nap") {
    // Each cat by two taps, as a finger does it: empty -> no cat -> cat. Row order.
    for (let r = 0; r < p.n; r++) {
      const cell = r * p.n + p.solution[r];
      moves.push({ k: "mark", cells: [cell], to: "x" }, { k: "mark", cells: [cell], to: "cat" });
    }
  } else if (game === "sniff") {
    const words = ["crane", "sloth"].filter((w) => w !== p.answer);
    for (const word of [...words, p.answer]) moves.push({ k: "guess", word });
    extra = { answerLength: p.answer.length };
  } else {
    // Box Fort: the plain greedy player, set by set, until the run ends.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let s = m.init(p) as any;
    for (;;) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const view = m.publicState(p, s) as any;
      if (view.over !== null) break;
      const move = greedyMove(view.rug, view.pieces, view.placed);
      if (!move) break;
      moves.push(move);
      const a = m.apply(p, s, move, 1e9);
      if (!a.ok) throw new Error(`box-fort plan: ${a.reason}`);
      s = a.state;
      if (a.end) break;
    }
  }
  // Play the list through the module, at a human pace, for the result.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let s = m.init(p) as any;
  let end: string | undefined;
  moves.forEach((move, k) => {
    const a = m.apply(p, s, m.parseMove(move), 10_000 + k * 1000);
    if (!a.ok) throw new Error(`${game} plan: move ${k} ${a.reason}`);
    s = a.state;
    if (a.end) end = a.end;
  });
  if (!end) throw new Error(`${game} plan: the list never ends the run`);
  const expect = m.result(p, s, end as never, 0, 0) as Record<string, unknown>;
  delete expect.timeMs; // the time is the clock's, so it differs from run to run
  const floorMs = m.floorMs[levelFor(date)];
  const paceMs = Math.ceil((floorMs * 1.15 + 3000) / moves.length);
  out.push({ game, floorMs, paceMs, puzzleHash: hash(puzzle), puzzle, moves, movesHash: hash(moves), expect: { outcome: end, ...expect, tooFast: false }, extra });
}
process.stdout.write(JSON.stringify({ date, plans: out }, null, 1));
