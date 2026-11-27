/**
 * Toy Tumble's bot soak and cost benchmark (spec §9.3, §6.9). Plays House Cat rounds offline
 * through the real referee with a fake clock, and reports round lengths, how often a 5-cell toy
 * is forced into a hole, which tricks decide rounds, how often a scripted kid beats an Easy cat,
 * and the referee's CPU time and messages per second of round.
 * Run: pnpm --filter @pounce/play-api soak:tumble -- --rounds 2000
 */
import { performance } from "node:perf_hooks";

import { CAT_LEVELS, shape, type CatLevel } from "../src/tumble/cats";
import { toyAt } from "../src/tumble/queue";
import { TumbleRound, type RoundOut } from "../src/tumble/round";

import type { Seed } from "../src/rules/rng";
import type { Box } from "../src/tumble/box";

const arg = (name: string, fallback: number): number => {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? Number(process.argv[i + 1]) : fallback;
};
const ROUNDS = arg("rounds", 2000);
const KID_ONLY = process.argv.includes("--kid-only");
const TICK = 100;
const CAP_MS = 15 * 60_000;
const KID: CatLevel = { think: [2500, 4000], sloppy: 0.5, tricks: [] };
const EASY: CatLevel = {
  ...CAT_LEVELS.easy,
  think: [arg("easyMin", CAT_LEVELS.easy.think[0]), arg("easyMax", CAT_LEVELS.easy.think[1])],
  sloppy: arg("easySloppy", CAT_LEVELS.easy.sloppy),
};

let seedCounter = 1;
const seed = (): Seed => {
  const n = seedCounter++;
  return [n * 2654435761 >>> 0 || 1, (n * 40503) >>> 0, (n * 69069 + 1) >>> 0, 0x9e3779b9];
};

type Result = { ms: number; winner: number | null; fiveCell: number; fiveHoles: number; small: number; smallHoles: number; decisive: string[]; cpuMs: number; sends: number; capped: boolean };

const harmful = new Set(["hairball", "swipe", "catnip", "swap"]);

function play(levels: CatLevel[]): Result {
  const T0 = 1_000_000;
  const roundSeed = seed();
  const r = new TumbleRound({ r: 1, seats: levels.map(() => ({ kind: "cat" as const })), roundSeed, trickSeeds: levels.map(() => seed()), startsAt: T0, rng: seed(), catLevels: levels, untilOne: true });
  const holes = levels.map(() => 0);
  const lastNext = levels.map(() => 0);
  let fiveCell = 0;
  let fiveHoles = 0;
  let small = 0;
  let smallHoles = 0;
  let sends = 0;
  let cpu = 0;
  const uses: { at: number; target: number; trick: string }[] = [];
  const held = levels.map(() => [] as string[]);
  let t = T0;
  while (!r.result().over && t - T0 < CAP_MS) {
    t += TICK;
    levels.forEach((_, s) => (held[s] = [...r.box(s).held]));
    const start = performance.now();
    const out: RoundOut[] = r.tick(t);
    cpu += performance.now() - start;
    // Fan-out for the cost benchmark: one person's phone and one TV are connected.
    for (const o of out) sends += o.to === "all" ? 2 : 1;
    for (const o of out) {
      const m = o.message;
      if (m.t !== "tumble" || !("s" in m)) continue;
      for (const e of m.ev) if (e[0] === "u") uses.push({ at: t, target: e[2], trick: held[m.s]?.[e[1]] ?? "?" });
    }
    levels.forEach((_, s) => {
      const b: Box = r.box(s);
      if (b.next !== lastNext[s]) {
        const toy = toyAt(roundSeed, b.next - 1);
        const h = shape(b).holes;
        if (toy === "p5" || toy === "u5") {
          fiveCell++;
          if (h > (holes[s] as number)) fiveHoles++;
        } else {
          small++;
          if (h > (holes[s] as number)) smallHoles++;
        }
        holes[s] = h;
        lastNext[s] = b.next;
      }
    });
  }
  const res = r.result();
  const lastOut = res.outs[res.outs.length - 1];
  const decisive = uses.filter((u) => u.target === lastOut && harmful.has(u.trick) && t - u.at <= 5000).map((u) => u.trick);
  return { ms: t - T0, winner: res.winner, fiveCell, fiveHoles, small, smallHoles, decisive, cpuMs: cpu, sends, capped: t - T0 >= CAP_MS };
}

const pct = (xs: number[], p: number): number => {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.floor((p / 100) * s.length))] ?? 0;
};

const results: Result[] = [];
const sixQuick: Result[] = [];
for (let i = 0; i < (KID_ONLY ? 0 : ROUNDS); i++) {
  const players = 2 + (i % 5);
  const level = i % 2 === 0 ? EASY : CAT_LEVELS.quick;
  const res = play(Array.from({ length: players }, () => level));
  results.push(res);
  if (players === 6 && level !== EASY) sixQuick.push(res);
}
const kidRounds = Math.max(200, Math.floor(ROUNDS / 5));
let kidWins = 0;
for (let i = 0; i < kidRounds; i++) if (play(i % 2 === 0 ? [KID, EASY] : [EASY, KID]).winner === (i % 2 === 0 ? 0 : 1)) kidWins++;

const lengths = results.map((r) => r.ms / 1000);
const trickTally: Record<string, number> = {};
for (const r of results) for (const t of new Set(r.decisive)) trickTally[t] = (trickTally[t] ?? 0) + 1;
const five = results.reduce((a, r) => a + r.fiveCell, 0);
const fiveHoles = results.reduce((a, r) => a + r.fiveHoles, 0);
const cost = sixQuick.length > 0 ? sixQuick : results;
const roundSeconds = cost.reduce((a, r) => a + r.ms / 1000, 0);
console.log(JSON.stringify({
  rounds: ROUNDS,
  lengthSeconds: { p50: pct(lengths, 50), p95: pct(lengths, 95), max: Math.max(...lengths) },
  overFiveMinutes: results.filter((r) => r.ms > 5 * 60_000).length / ROUNDS,
  capped: results.filter((r) => r.capped).length,
  fiveCellHoleShare: five === 0 ? 0 : fiveHoles / five,
  smallToyHoleShare: results.reduce((a, r) => a + r.smallHoles, 0) / Math.max(1, results.reduce((a, r) => a + r.small, 0)),
  decisiveTrickShareOfRounds: Object.fromEntries(Object.entries(trickTally).map(([k, v]) => [k, v / ROUNDS])),
  kidVsEasyCat: { rounds: kidRounds, kidWinShare: kidWins / kidRounds },
  costSixQuickCats: {
    cpuMsPerRoundSecond: cost.reduce((a, r) => a + r.cpuMs, 0) / roundSeconds,
    sendsPerRoundSecond: cost.reduce((a, r) => a + r.sends, 0) / roundSeconds,
  },
}, null, 2));
