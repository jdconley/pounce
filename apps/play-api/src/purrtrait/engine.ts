import { createRng, type Seed } from "../rules/rng";

import { WORDS, type Group, type Level } from "./words";

import type { Seat } from "../rules/engine";

export type { Group, Level } from "./words";

export type PurrOptions = { timer: 45 | 60 | 90 };
export type PurrPhase = "choosing" | "drawing" | "reveal" | "over";

export type PurrAction =
  | { type: "choose"; level: Level }
  | { type: "gotIt"; seat: Seat }
  | { type: "giveUp" }
  /** Room only: the turn's clock ran out. While choosing it picks the Easy word. */
  | { type: "timeUp" }
  /** Room only: the reveal is over. */
  | { type: "nextTurn" }
  | { type: "forfeit" };

export type PurrEvent =
  | { type: "turn"; drawer: Seat; round: number }
  | { type: "chosen"; drawer: Seat; group: Group; level: Level }
  | { type: "guessed"; drawer: Seat; guesser: Seat; points: number; word: string }
  | { type: "missed"; drawer: Seat; word: string; reason: "time" | "gaveUp" | "left" }
  | { type: "over"; winners: Seat[]; scores: number[] };

export type PurrError = "game_over" | "wrong_phase" | "not_your_turn" | "bad_seat";

export type EndReason = "rounds" | "left" | "stalled";

/** What a turn offers, as word ids: one Easy, one Tricky, and a second Easy for a kitten's device. */
export type Offer = { easy: number; tricky: number; easy2: number };

export type PurrState = {
  seats: number;
  timer: 45 | 60 | 90;
  /** The words come from this seed; `rngCalls` says how far into its stream the game is. */
  seed: Seed;
  rngCalls: number;
  phase: PurrPhase;
  round: 1 | 2;
  /** Every turn so far, from 0. */
  turnIndex: number;
  drawer: Seat | null;
  /** Drawers still to go this round, after the current one. A seat that went out is skipped when its turn comes. */
  queue: Seat[];
  out: boolean[];
  scores: number[];
  /** Word ids (indexes into WORDS) picked so far, so none comes up twice. */
  used: number[];
  offer: Offer | null;
  /** The word being drawn, then revealed; kept until the next turn begins. */
  word: number | null;
  /** The level it scores as: Easy whenever a kitten's device picked, whichever key. */
  level: Level | null;
  last: { word: string; guesser: Seat | null; points: number } | null;
  winners: Seat[];
  endReason?: EndReason;
};

export type ApplyResult =
  | { ok: true; state: PurrState; events: PurrEvent[] }
  | { ok: false; error: PurrError };

export const DEFAULT_TIMER = 60;

export const ROUNDS = 2;

/** The room's clock for a choosing turn, ms. */
export const CHOOSE_MS = 10_000;

const fail = (error: PurrError): ApplyResult => ({ ok: false, error });

const wordAt = (id: number) => WORDS[id] as (typeof WORDS)[number];

/** Three unused words, from the seed's stream. */
function drawOffer(s: PurrState): Offer {
  const rng = createRng(s.seed);
  for (let i = 0; i < s.rngCalls; i++) rng();
  const used = new Set(s.used);
  const pool = (level: Level) => WORDS.flatMap((w, id) => (w.level === level && !used.has(id) ? [id] : []));
  const take = (ids: number[]): number => ids.splice(Math.floor(rng() * ids.length), 1)[0] as number;
  const easyPool = pool("easy");
  const easy = take(easyPool);
  const tricky = take(pool("tricky"));
  const easy2 = take(easyPool);
  s.rngCalls += 3;
  return { easy, tricky, easy2 };
}

const seatsIn = (s: PurrState): Seat[] => s.out.flatMap((o, seat) => (o ? [] : [seat]));

/** Highest score among the seats still in (all seats when none is); ties share. */
function winnersOf(s: PurrState): Seat[] {
  const live = seatsIn(s);
  const pool = live.length > 0 ? live : s.scores.map((_, i) => i);
  const top = Math.max(...pool.map((i) => s.scores[i] as number));
  return pool.filter((i) => s.scores[i] === top);
}

type Out = { state: PurrState; events: PurrEvent[] };

/** Ends the game in `s` (already a copy). */
function over(s: PurrState, reason: EndReason): Out {
  s.phase = "over";
  s.drawer = null;
  s.queue = [];
  s.offer = null;
  s.word = null;
  s.level = null;
  s.endReason = reason;
  s.winners = winnersOf(s);
  return { state: s, events: [{ type: "over", winners: [...s.winners], scores: [...s.scores] }] };
}

/** Ends the game now. The room uses it for a stalled table. */
export function finish(state: PurrState, reason: EndReason): Out {
  if (state.phase === "over") return { state, events: [] };
  return over(structuredClone(state), reason);
}

/** Begins the next turn, or ends the game when no drawer is left or fewer than 2 seats are in. */
function advance(s: PurrState): Out {
  if (seatsIn(s).length < 2) return over(s, "left");
  let next: Seat | undefined;
  for (;;) {
    if (s.queue.length === 0) {
      if (s.round >= ROUNDS) return over(s, "rounds");
      s.round = 2;
      s.queue = seatsIn(s);
    }
    next = s.queue.shift();
    if (next !== undefined && !s.out[next]) break;
  }
  s.turnIndex += 1;
  s.drawer = next;
  s.phase = "choosing";
  s.word = null;
  s.level = null;
  s.offer = drawOffer(s);
  return { state: s, events: [{ type: "turn", drawer: next, round: s.round }] };
}

export function create(seats: number, seed: Seed, options: PurrOptions = { timer: DEFAULT_TIMER }): PurrState {
  const s: PurrState = {
    seats,
    timer: options.timer,
    seed: [...seed],
    rngCalls: 0,
    phase: "choosing",
    round: 1,
    turnIndex: 0,
    drawer: 0,
    queue: Array.from({ length: seats - 1 }, (_, i) => i + 1),
    out: Array.from({ length: seats }, () => false),
    scores: Array.from({ length: seats }, () => 0),
    used: [],
    offer: null,
    word: null,
    level: null,
    last: null,
    winners: [],
  };
  s.offer = drawOffer(s);
  return s;
}

/**
 * `ctx.easyOnly`: the drawer's device is a kitten's, so a pick is always an Easy word and scores 1,
 * whichever key it pressed (the room sets it; design ruling 5).
 */
export function apply(state: PurrState, seat: Seat, a: PurrAction, ctx: { easyOnly: boolean } = { easyOnly: false }): ApplyResult {
  if (state.phase === "over") return fail("game_over");
  if (!Number.isInteger(seat) || seat < 0 || seat >= state.seats) return fail("bad_seat");
  const s = structuredClone(state);
  const drawer = s.drawer as Seat;

  switch (a.type) {
    case "choose": {
      if (s.phase !== "choosing") return fail("wrong_phase");
      if (seat !== drawer) return fail("not_your_turn");
      return pick(s, a.level, ctx.easyOnly);
    }
    case "timeUp": {
      if (s.phase === "choosing") return pick(s, "easy", false);
      if (s.phase !== "drawing") return fail("wrong_phase");
      return miss(s, "time");
    }
    case "giveUp": {
      if (s.phase !== "drawing") return fail("wrong_phase");
      if (seat !== drawer) return fail("not_your_turn");
      return miss(s, "gaveUp");
    }
    case "gotIt": {
      if (s.phase !== "drawing") return fail("wrong_phase");
      if (seat !== drawer) return fail("not_your_turn");
      const g = a.seat;
      if (!Number.isInteger(g) || g < 0 || g >= s.seats || g === drawer || s.out[g]) return fail("bad_seat");
      const points = s.level === "tricky" ? 2 : 1;
      s.scores[g] = (s.scores[g] as number) + points;
      s.scores[drawer] = (s.scores[drawer] as number) + points;
      const word = wordAt(s.word as number).word;
      s.last = { word, guesser: g, points };
      s.phase = "reveal";
      return { ok: true, state: s, events: [{ type: "guessed", drawer, guesser: g, points, word }] };
    }
    case "nextTurn": {
      if (s.phase !== "reveal") return fail("wrong_phase");
      return { ok: true, ...advance(s) };
    }
    case "forfeit": {
      if (s.out[seat]) return fail("bad_seat");
      s.out[seat] = true;
      if (seatsIn(s).length < 2) return { ok: true, ...over(s, "left") };
      if (seat !== drawer) return { ok: true, state: s, events: [] };
      if (s.phase === "drawing") return miss(s, "left");
      if (s.phase === "choosing") return { ok: true, ...advance(s) };
      return { ok: true, state: s, events: [] };
    }
  }
}

function pick(s: PurrState, level: Level, easyOnly: boolean): ApplyResult {
  const offer = s.offer as Offer;
  const id = easyOnly ? (level === "easy" ? offer.easy : offer.easy2) : level === "easy" ? offer.easy : offer.tricky;
  const w = wordAt(id);
  s.word = id;
  s.level = w.level;
  s.used.push(id);
  s.offer = null;
  s.phase = "drawing";
  return { ok: true, state: s, events: [{ type: "chosen", drawer: s.drawer as Seat, group: w.group, level: w.level }] };
}

function miss(s: PurrState, reason: "time" | "gaveUp" | "left"): ApplyResult {
  const word = wordAt(s.word as number).word;
  s.last = { word, guesser: null, points: 0 };
  s.phase = "reveal";
  return { ok: true, state: s, events: [{ type: "missed", drawer: s.drawer as Seat, word, reason }] };
}

/** True when `a`, applied for `seat`, ended a drawing turn. */
export function endsTurn(a: PurrAction, events: readonly PurrEvent[]): boolean {
  return (a.type === "gotIt" || a.type === "giveUp" || a.type === "timeUp") && events.some((e) => e.type === "guessed" || e.type === "missed");
}

/** The word an offer or a turn refers to, for the view. */
export const wordText = (id: number): string => wordAt(id).word;
export const wordGroup = (id: number): Group => wordAt(id).group;
