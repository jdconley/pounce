import { hasKeys, isObj } from "../shape";

import type { GameModule } from "./module";
import type { Seed } from "../rules/rng";

/**
 * Toy Tumble, the real-time falling-toys battle (design 2026-11-26), as a room keeps it: the slow
 * state only, `room.tumble` in `docs/live-protocol.md`. Rounds, wins, who left and who sits out.
 * The boxes themselves live in the room's `TumbleRound` while a round plays, and are never stored.
 *
 * Nobody is ever to act. Every change is the room's: it starts each countdown and round, notes
 * who is out and who won, and marks seats away. A client sends only Play without (which the room
 * handles) and Leave.
 */

/** The game is first to this many round wins (§4.4). */
export const TUMBLE_WINS = 3;

export type CatLevel = "easy" | "quick";
export type TumbleOptions = { cats: CatLevel };

export type TumbleStatus = "countdown" | "playing" | "between" | "over";

export type TumbleState = {
  seats: number;
  cats: CatLevel;
  wins: number[];
  /** Per seat: left for good (Leave, or a forfeit). Its wins stay. */
  left: boolean[];
  /** Per seat: sits out rounds until its device is back (Play without). */
  away: boolean[];
  status: TumbleStatus;
  /** The round, counting from 1; 0 before the first countdown. */
  r: number;
  /** When the round's clock starts: the countdown runs until then. */
  startsAt: number;
  roundSeed: Seed;
  trickSeeds: Seed[];
  /** The seats out this round, in order. */
  outs: number[];
  /** The round's winner once it ends (null: nobody), or the game's once it is over. */
  winner: number | null;
  /** When the next countdown began waiting for a missing device. */
  waitingSince: number | null;
};

/**
 * The snapshot's `room.tumble`: the state, with the seeds from the first countdown on, and `now`,
 * the server's clock when the room made the snapshot.
 */
export type TumbleView = Omit<TumbleState, "roundSeed" | "trickSeeds"> & { roundSeed?: Seed; trickSeeds?: Seed[]; now?: number };

/**
 * What changes the state. Only `playWithout` and `leave` come from clients; the room applies the
 * rest. `playWithout` is the room's own to handle (it knows who is connected): the module refuses it.
 */
export type TumbleAction =
  | { k: "playWithout" }
  | { k: "leave" }
  /** A countdown to `at`. `replay`: the same round again (a restart lost it), else the next. */
  | { k: "start"; at: number; roundSeed: Seed; trickSeeds: Seed[]; replay?: true }
  | { k: "play" }
  | { k: "out"; seat: number }
  | { k: "end"; winner: number | null }
  | { k: "away"; seat: number; away: boolean }
  | { k: "wait"; since: number | null }
  /** The game ends early: too few seats, or no person, left. */
  | { k: "stop" };

export type TumbleError = "game_over" | "not_playing" | "not_allowed";

const NO_SEED: Seed = [0, 0, 0, 0];

/** The seat left with the most wins; nobody on a tie. */
function leader(s: TumbleState): number | null {
  const staying = s.wins.map((w, seat) => ({ w, seat })).filter(({ seat }) => s.left[seat] !== true);
  const best = Math.max(...staying.map(({ w }) => w));
  const top = staying.filter(({ w }) => w === best);
  return top.length === 1 ? (top[0] as { seat: number }).seat : null;
}

function apply(s: TumbleState, seat: number, a: TumbleAction): { ok: true; state: TumbleState; events: never[] } | { ok: false; error: TumbleError } {
  const ok = (state: TumbleState) => ({ ok: true as const, state, events: [] });
  if (s.status === "over") return { ok: false, error: "game_over" };
  switch (a.k) {
    case "playWithout":
      return { ok: false, error: "not_allowed" };
    case "leave": {
      const left = s.left.map((l, i) => l || i === seat);
      const next = { ...s, left };
      if (left.filter((l) => !l).length >= 2) return ok(next);
      return ok({ ...next, status: "over", winner: leader(next), waitingSince: null });
    }
    case "start":
      return ok({
        ...s,
        status: "countdown",
        r: a.replay ? s.r : s.r + 1,
        startsAt: a.at,
        roundSeed: [...a.roundSeed],
        trickSeeds: a.trickSeeds.map((t) => [...t]),
        outs: [],
        winner: null,
        waitingSince: null,
      });
    case "play":
      return s.status === "countdown" ? ok({ ...s, status: "playing" }) : { ok: false, error: "not_playing" };
    case "out":
      if (s.status !== "playing") return { ok: false, error: "not_playing" };
      return ok(s.outs.includes(a.seat) ? s : { ...s, outs: [...s.outs, a.seat] });
    case "end": {
      if (s.status !== "playing") return { ok: false, error: "not_playing" };
      const wins = s.wins.map((w, i) => (i === a.winner ? w + 1 : w));
      const over = a.winner !== null && (wins[a.winner] as number) >= TUMBLE_WINS;
      return ok({ ...s, wins, winner: a.winner, status: over ? "over" : "between", waitingSince: null });
    }
    case "away":
      return ok({ ...s, away: s.away.map((x, i) => (i === a.seat ? a.away : x)) });
    case "wait":
      return ok({ ...s, waitingSince: a.since });
    case "stop":
      return ok({ ...s, status: "over", winner: leader(s), waitingSince: null });
  }
}

function parseAction(raw: unknown): TumbleAction | null {
  if (!isObj(raw) || !hasKeys(raw, ["k"])) return null;
  return raw.k === "playWithout" || raw.k === "leave" ? { k: raw.k } : null;
}

function parseOptions(raw: unknown): TumbleOptions | null {
  if (!isObj(raw) || !hasKeys(raw, ["cats"])) return null;
  return raw.cats === "easy" || raw.cats === "quick" ? { cats: raw.cats } : null;
}

function view(s: TumbleState): TumbleView {
  const view: TumbleView = { ...s, roundSeed: [...s.roundSeed], trickSeeds: s.trickSeeds.map((t) => [...t]) };
  if (s.r === 0) {
    delete view.roundSeed;
    delete view.trickSeeds;
  }
  return view;
}

export const tumble: GameModule<TumbleState, TumbleAction, TumbleView, never, TumbleError, TumbleOptions> = {
  id: "tumble",
  minSeats: 2,
  maxSeats: 6,
  create: (seats, _seed, options) => ({
    seats,
    cats: options?.cats ?? "easy",
    wins: new Array<number>(seats).fill(0),
    left: new Array<boolean>(seats).fill(false),
    away: new Array<boolean>(seats).fill(false),
    status: "between",
    r: 0,
    startsAt: 0,
    roundSeed: [...NO_SEED],
    trickSeeds: [],
    outs: [],
    winner: null,
    waitingSince: null,
  }),
  defaultOptions: { cats: "easy" },
  parseOptions,
  apply,
  view,
  filterEvent: (e) => e,
  currentActor: () => null,
  // Never asked: nobody is ever to act. Something the module refuses, so it could change nothing.
  botAction: () => ({ k: "playWithout" }),
  // A round each human seat plays is its turn for streaks; the room counts those (§5.1).
  endsTurn: () => false,
  parseAction,
  parseAim: () => null,
  aimAllowed: () => false,
  phase: (s) => (s.status === "over" ? "over" : s.status === "between" ? "between" : "playing"),
  betweenAction: null,
  forfeitAction: { k: "leave" },
  forfeited: (s) => s.left,
  turnKey: (s) => `${s.r}:${s.status}`,
  startsTurn: () => false,
  fallbackAction: () => ({ k: "playWithout" }),
  progress: (s) => [...s.wins],
  progressKind: "score",
};
