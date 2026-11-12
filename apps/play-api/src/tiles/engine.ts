import { createRng, shuffle, type Seed } from "../rules/rng";

import { ALL_TILE_IDS, isTileId, rackTotal, type TileId } from "./pieces";
import { readSet, sameSet } from "./sets";

import type { Seat } from "../rules/engine";

/** How a game ended: someone emptied their rack, nobody could move, or everyone else left. */
export type EndReason = "out" | "blocked" | "forfeit";

export type TilesState = {
  seats: number;
  /** The face-down pool; the last element is the next piece drawn. Server-only. */
  pool: TileId[];
  /** Each seat's rack. Server-only except to the seat itself. */
  racks: TileId[][];
  /** The sets on the table, each in display order (see `readSet`). */
  table: TileId[][];
  /** Seats that have made their opening play and may now rearrange the table. */
  opened: boolean[];
  turn: Seat;
  /**
   * Seats that passed since the last piece was played. Only set once the pool
   * is empty; when every seat still in has passed, nobody can move and the
   * game ends.
   */
  passed: boolean[];
  /** Completed turns (plays, draws and passes), for telling one turn from the next. */
  turns: number;
  status: "playing" | "gameOver";
  winners: Seat[];
  /** All zero until the game is over; see `finish`. */
  scores: number[];
  /** Seats that forfeited: out for the rest of the game, last place, never given a turn. */
  forfeited: boolean[];
  /** Pieces from forfeited racks, set aside face down for the rest of the game. Server-only. */
  boxed: TileId[];
  /** Absent until the game is over. */
  endReason?: EndReason;
};

export type TilesAction =
  /** Take one piece from the pool. This is the whole turn. */
  | { type: "draw" }
  /**
   * Put pieces down. `table` is the whole table as it should stand after the
   * turn: every piece already there plus one or more from the rack.
   */
  | { type: "play"; table: TileId[][] }
  /** Do nothing. Only once the pool is empty. */
  | { type: "pass" }
  /** Leave the game for good: any time before it is over, on anyone's turn. */
  | { type: "forfeit" };

export type TilesEvent =
  /** `tile` is private to the drawer: `eventFor` removes it for everyone else. */
  | { kind: "drew"; seat: Seat; tile?: TileId; poolCount: number }
  /** `placed` are the pieces that came from the rack; `opened` marks a seat's opening play. */
  | { kind: "played"; seat: Seat; table: TileId[][]; placed: TileId[]; opened: boolean }
  | { kind: "passed"; seat: Seat }
  | { kind: "turn"; seat: Seat }
  | { kind: "forfeited"; seat: Seat }
  /** `left` is each seat's rack total as the game ended (0 for a seat that forfeited). */
  | { kind: "gameOver"; winners: Seat[]; reason: EndReason; scores: number[]; left: number[] };

export type TilesError =
  | "game_over"
  /** Not one of the four actions. */
  | "bad_action"
  | "not_your_turn"
  /** No such seat. */
  | "bad_seat"
  /** The seat already forfeited. */
  | "forfeited"
  /** Draw with nothing left in the pool. */
  | "pool_empty"
  /** Pass while the pool still has pieces. */
  | "pool_not_empty"
  /** The submitted table is not a list of sets of piece ids. */
  | "bad_piece"
  /** A piece appears on the submitted table more than once. */
  | "duplicate_piece"
  /** A piece that was on the table is not on the submitted table. */
  | "missing_piece"
  /** A new piece on the submitted table is not on the player's rack. */
  | "not_your_piece"
  /** The submitted table adds nothing from the rack. */
  | "nothing_played"
  /** A set on the submitted table is not a run or a group. */
  | "bad_set"
  /** Before opening: a set that was on the table was changed. */
  | "table_touched"
  /** Before opening: the new sets are worth less than 30. */
  | "opening_too_low";

export type ApplyResult =
  | { ok: true; state: TilesState; events: TilesEvent[] }
  | { ok: false; error: TilesError };

export const RACK_SIZE = 14;
export const OPENING_POINTS = 30;
const MIN_SEATS = 2;
const MAX_SEATS = 4;

const fail = (error: TilesError): ApplyResult => ({ ok: false, error });

/** True when `seat` forfeited. */
export function isOut(s: TilesState, seat: Seat): boolean {
  return s.forfeited[seat] === true;
}

/** The seats still in the game, in seat order. */
export function activeSeats(s: TilesState): Seat[] {
  return Array.from({ length: s.seats }, (_, seat) => seat).filter((seat) => !isOut(s, seat));
}

/**
 * Create a game: shuffle the 106 pieces with the seeded rng, deal 14 to each
 * seat, and let the same rng pick who moves first (the seats keep their order
 * across "Play again", so a fixed first seat would always favour one player).
 * The seed is not kept: nothing after the deal is random.
 */
export function newGame(seats: number, seed: Readonly<Seed>): TilesState {
  if (!Number.isInteger(seats) || seats < MIN_SEATS || seats > MAX_SEATS) {
    throw new RangeError(`seats must be ${MIN_SEATS}-${MAX_SEATS}: ${seats}`);
  }
  const rng = createRng(seed);
  const shuffled = shuffle(ALL_TILE_IDS, rng);
  const racks = Array.from({ length: seats }, (_, seat) =>
    shuffled.slice(seat * RACK_SIZE, (seat + 1) * RACK_SIZE),
  );
  return {
    seats,
    pool: shuffled.slice(seats * RACK_SIZE),
    racks,
    table: [],
    opened: new Array<boolean>(seats).fill(false),
    turn: Math.floor(rng() * seats),
    passed: new Array<boolean>(seats).fill(false),
    turns: 0,
    status: "playing",
    winners: [],
    scores: new Array<number>(seats).fill(0),
    forfeited: new Array<boolean>(seats).fill(false),
    boxed: [],
  };
}

/** What a legal play does: the rack pieces it puts down, and what its new sets are worth. */
export type PlayCheck = { ok: true; placed: TileId[]; points: number } | { ok: false; error: TilesError };

/**
 * Checks a submitted table against the table as it stands and the player's
 * rack. Pure, and all a client or a bot needs to know whether a play will be
 * accepted: it reads nothing hidden.
 *
 * In order: the shape, then where every piece came from (nothing invented,
 * nothing taken off the table, nothing from anywhere but this rack, something
 * from this rack), then that every set is a run or a group, then the opening.
 * Until a seat has opened, every set already on the table must still be there
 * piece for piece, and the sets it adds must be worth 30 or more.
 */
export function checkPlay(
  before: readonly (readonly TileId[])[],
  rack: readonly TileId[],
  opened: boolean,
  submitted: unknown,
): PlayCheck {
  const bad = (error: TilesError): PlayCheck => ({ ok: false, error });
  if (!Array.isArray(submitted)) return bad("bad_piece");
  const seen = new Set<TileId>();
  let duplicate = false;
  for (const set of submitted as unknown[]) {
    if (!Array.isArray(set)) return bad("bad_piece");
    for (const id of set as unknown[]) {
      if (!isTileId(id)) return bad("bad_piece");
      if (seen.has(id)) duplicate = true;
      seen.add(id);
    }
  }
  if (duplicate) return bad("duplicate_piece");
  const table = submitted as TileId[][];

  const onTable = new Set(before.flat());
  for (const id of onTable) if (!seen.has(id)) return bad("missing_piece");
  const placed = table.flat().filter((id) => !onTable.has(id));
  if (placed.some((id) => !rack.includes(id))) return bad("not_your_piece");
  if (placed.length === 0) return bad("nothing_played");

  // The sets this play adds are the ones that were not on the table as they are.
  let points = 0;
  let kept = 0;
  for (const set of table) {
    const reading = readSet(set);
    if (reading === null) return bad("bad_set");
    if (before.some((old) => sameSet(old, set))) kept++;
    else points += reading.points;
  }
  if (!opened) {
    if (kept !== before.length) return bad("table_touched");
    if (points < OPENING_POINTS) return bad("opening_too_low");
  }
  return { ok: true, placed, points };
}

/** Apply `action` by `seat`. Pure: `state` is never mutated. */
export function applyAction(state: TilesState, seat: Seat, action: TilesAction): ApplyResult {
  if (state.status !== "playing") return fail("game_over");
  if (action.type === "forfeit") return forfeit(state, seat);
  if (seat !== state.turn) return fail("not_your_turn");

  const s = structuredClone(state);
  const events: TilesEvent[] = [];
  const rack = s.racks[seat] as TileId[];
  switch (action.type) {
    case "draw": {
      const drawn = s.pool.pop();
      if (drawn === undefined) return fail("pool_empty");
      rack.push(drawn);
      events.push({ kind: "drew", seat, tile: drawn, poolCount: s.pool.length });
      break;
    }
    case "pass": {
      if (s.pool.length > 0) return fail("pool_not_empty");
      s.passed[seat] = true;
      events.push({ kind: "passed", seat });
      break;
    }
    case "play": {
      const check = checkPlay(s.table, rack, s.opened[seat] === true, action.table);
      if (!check.ok) return fail(check.error);
      const placed = new Set(check.placed);
      s.racks[seat] = rack.filter((id) => !placed.has(id));
      s.table = action.table.map((set) => [...set]);
      s.passed.fill(false);
      events.push({
        kind: "played",
        seat,
        table: s.table.map((set) => [...set]),
        placed: check.placed,
        opened: s.opened[seat] !== true,
      });
      s.opened[seat] = true;
      break;
    }
    default:
      // Nothing typed reaches here; a message that slipped past the parser must not count as a turn.
      return fail("bad_action");
  }
  s.turns++;
  endTurn(s, events);
  return { ok: true, state: s, events };
}

/**
 * After a turn or a forfeit (mutates `s`): the game ends when the seat that
 * just moved has an empty rack, or when every seat still in has passed since
 * the last piece was played. Otherwise the move goes on round the table,
 * unless `stay` (a forfeit on someone else's turn).
 */
function endTurn(s: TilesState, events: TilesEvent[], stay = false): void {
  const active = activeSeats(s);
  const out = active.filter((seat) => (s.racks[seat] as TileId[]).length === 0);
  if (out.length > 0) return finish(s, out, "out", events);
  if (active.every((seat) => s.passed[seat])) {
    const totals = active.map((seat) => rackTotal(s.racks[seat] as TileId[]));
    const least = Math.min(...totals);
    return finish(s, active.filter((_, i) => totals[i] === least), "blocked", events);
  }
  if (stay) return;
  let next = (s.turn + 1) % s.seats;
  while (isOut(s, next)) next = (next + 1) % s.seats;
  s.turn = next;
  events.push({ kind: "turn", seat: next });
}

/**
 * End the game (mutates `s`). Each seat still in is charged what is left on
 * its rack; a winner also collects what the seats that did not win were left
 * with. A seat that forfeited scores 0 and its pieces count for nobody. A game
 * won because everyone else forfeited has no scores at all.
 */
function finish(s: TilesState, winners: Seat[], reason: EndReason, events: TilesEvent[]): void {
  const left = s.racks.map(rackTotal);
  if (reason !== "forfeit") {
    const pot = activeSeats(s)
      .filter((seat) => !winners.includes(seat))
      .reduce((sum, seat) => sum + (left[seat] as number), 0);
    for (const seat of activeSeats(s)) {
      s.scores[seat] = (winners.includes(seat) ? pot : 0) - (left[seat] as number);
    }
  }
  s.status = "gameOver";
  s.winners = winners;
  s.endReason = reason;
  events.push({ kind: "gameOver", winners: [...winners], reason, scores: [...s.scores], left });
}

/**
 * A seat leaves the game. With one seat left in, that seat wins and the game
 * is over. Otherwise the seat is out: its rack is set aside face down in
 * `boxed` (not back into the pool, see the design spec §4.8), it is never
 * given a turn again and can't win, and on its own turn the move goes on. The
 * pieces it already played stay on the table for everyone to use.
 */
function forfeit(state: TilesState, seat: Seat): ApplyResult {
  if (!Number.isInteger(seat) || seat < 0 || seat >= state.seats) return fail("bad_seat");
  if (isOut(state, seat)) return fail("forfeited");

  const s = structuredClone(state);
  s.forfeited[seat] = true;
  s.boxed.push(...(s.racks[seat] as TileId[]));
  s.racks[seat] = [];
  s.passed[seat] = false;
  const events: TilesEvent[] = [{ kind: "forfeited", seat }];

  const left = activeSeats(s);
  if (left.length === 1) finish(s, left, "forfeit", events);
  else endTurn(s, events, s.turn !== seat);
  return { ok: true, state: s, events };
}
