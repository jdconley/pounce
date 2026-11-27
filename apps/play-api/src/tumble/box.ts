import { toyAt } from "./queue";
import { rngFloat, rngNext } from "./rng";
import { TOY_INDEX, spawn, toyCells, type Rot, type ToyId } from "./toys";

import type { Seed } from "../rules/rng";

/**
 * One Toy Tumble box and everything that can happen to it (spec §4). Pure and deterministic:
 * every function returns a new box and never changes the one it is given, and the only
 * randomness is the box's own generator, so a box's event stream gives the same box on the
 * server, the web and the app.
 */

export const W = 12;
export const H = 18;
export const TOTAL = 22;
/** A cell's value: 0 empty, 1 to 9 the toy (its index in `TOY_IDS` + 1), 10 junk. */
export const JUNK = 10;
export const MAX_HELD = 6;
/** Junk sent for 0 to 4 rows cleared at once (§4.3). */
export const ATTACK = [0, 0, 1, 2, 4] as const;
/** The first row of the top third: a box with a cell here gets the comeback weights (§4.6). */
export const DANGER_ROW = 12;

export const TRICKS = ["hairball", "swipe", "catnip", "scoop", "settle", "nap", "swap", "bath"] as const;
export type Trick = (typeof TRICKS)[number];
const WEIGHTS = [20, 15, 12, 18, 12, 10, 3, 3] as const;
const DANGER_WEIGHTS = [20, 15, 12, 36, 12, 10, 9, 9] as const;

export type Waiting = { id: number; rows: number; gap: number };
export type Box = {
  /** `TOTAL * W` values, index `y * W + x`, y = 0 at the bottom. */
  cells: number[];
  /** The trick on each cell: 0 none, else its index in `TRICKS` + 1. */
  tricks: number[];
  held: Trick[];
  /** The queue index of the toy now in hand. */
  next: number;
  waiting: Waiting[];
  rng: Seed;
  out: boolean;
  /** Every row this box has cleared this round (the House Cats' tiebreak, §4.4). */
  rows: number;
};
export type Hit =
  | { k: "hairball"; gap: number }
  | { k: "swipe"; shifts: number[] }
  | { k: "catnip" }
  | { k: "nap" }
  | { k: "scoop" }
  | { k: "settle" }
  | { k: "bath" }
  | { k: "swap"; cells: number[]; tricks: number[] };
export type SetDownError = "box_out" | "not_next" | "bad_place" | "not_resting" | "bad_landed";
export type SetDown = { box: Box; cleared: number; sent: number; blocked: { id: number; rows: number }[]; pocketed: Trick[]; out: boolean };

const idx = (x: number, y: number): number => y * W + x;

export function newBox(trickSeed: Readonly<Seed>): Box {
  return {
    cells: new Array<number>(TOTAL * W).fill(0),
    tricks: new Array<number>(TOTAL * W).fill(0),
    held: [],
    next: 0,
    waiting: [],
    rng: [trickSeed[0], trickSeed[1], trickSeed[2], trickSeed[3]],
    out: false,
    rows: 0,
  };
}

const copy = (b: Box): Box => ({ ...b, cells: [...b.cells], tricks: [...b.tricks], held: [...b.held], waiting: b.waiting.map((w) => ({ ...w })), rng: [...b.rng] as Seed });

/** True when the toy at this rotation and position is inside the box and overlaps nothing. */
export function fits(box: Box, toy: ToyId, rot: Rot, x: number, y: number): boolean {
  for (const [cx, cy] of toyCells(toy, rot)) {
    const px = x + cx;
    const py = y + cy;
    if (px < 0 || px >= W || py < 0 || py >= TOTAL) return false;
    if (box.cells[idx(px, py)] !== 0) return false;
  }
  return true;
}

/** The nudges a turn tries, in order (§4.2). */
export const NUDGES: readonly (readonly [number, number])[] = [[0, 0], [-1, 0], [1, 0], [0, 1], [-2, 0], [2, 0]];

/** A quarter turn (`dir` 1 clockwise, -1 counter-clockwise) with the first nudge that fits, or null. */
export function turn(box: Box, toy: ToyId, rot: Rot, x: number, y: number, dir: 1 | -1): { rot: Rot; x: number; y: number } | null {
  const to = (((rot + dir) % 4) + 4) % 4 as Rot;
  for (const [dx, dy] of NUDGES) if (fits(box, toy, to, x + dx, y + dy)) return { rot: to, x: x + dx, y: y + dy };
  return null;
}

/** Where a toy rests if dropped straight down from where it appears, at this rotation and column, or null. */
export function restingY(box: Box, toy: ToyId, rot: Rot, x: number): number | null {
  let y = spawn(toy).y;
  if (!fits(box, toy, rot, x, y)) return null;
  while (fits(box, toy, rot, x, y - 1)) y--;
  return y;
}

/** The highest filled row, or -1 for an empty box. */
export function highest(box: Box): number {
  for (let y = TOTAL - 1; y >= 0; y--) for (let x = 0; x < W; x++) if (box.cells[idx(x, y)] !== 0) return y;
  return -1;
}

const anyAbove = (box: Box): boolean => highest(box) >= H;

const pushTrick = (b: Box, code: number, pocketed: Trick[]): void => {
  if (code === 0) return;
  const t = TRICKS[code - 1] as Trick;
  if (b.held.length < MAX_HELD) {
    b.held.push(t);
    pocketed.push(t);
  }
};

/** Removes the rows `full` (ascending), pocketing their tricks bottom row first, left to right. */
function removeRows(b: Box, full: readonly number[], pocketed: Trick[]): void {
  if (full.length === 0) return;
  for (const y of full) for (let x = 0; x < W; x++) pushTrick(b, b.tricks[idx(x, y)] as number, pocketed);
  const gone = new Set(full);
  const cells: number[] = [];
  const tricks: number[] = [];
  for (let y = 0; y < TOTAL; y++) {
    if (gone.has(y)) continue;
    for (let x = 0; x < W; x++) {
      cells.push(b.cells[idx(x, y)] as number);
      tricks.push(b.tricks[idx(x, y)] as number);
    }
  }
  while (cells.length < TOTAL * W) {
    cells.push(0);
    tricks.push(0);
  }
  b.cells = cells;
  b.tricks = tricks;
}

const fullRows = (b: Box): number[] => {
  const rows: number[] = [];
  for (let y = 0; y < TOTAL; y++) {
    let full = true;
    for (let x = 0; x < W && full; x++) if (b.cells[idx(x, y)] === 0) full = false;
    if (full) rows.push(y);
  }
  return rows;
};

/** Pushes `rows` junk rows in under the stack, all with their gap at `gap`; tricks move with their cells. */
function pushJunk(b: Box, rows: number, gap: number): void {
  const cells = new Array<number>(TOTAL * W).fill(0);
  const tricks = new Array<number>(TOTAL * W).fill(0);
  for (let y = 0; y + rows < TOTAL; y++) {
    for (let x = 0; x < W; x++) {
      cells[idx(x, y + rows)] = b.cells[idx(x, y)] as number;
      tricks[idx(x, y + rows)] = b.tricks[idx(x, y)] as number;
    }
  }
  for (let y = 0; y < Math.min(rows, TOTAL); y++) for (let x = 0; x < W; x++) cells[idx(x, y)] = x === gap ? 0 : JUNK;
  b.cells = cells;
  b.tricks = tricks;
}

/** How often each trick appears for this box, in `TRICKS` order: the comeback weights near the top (§4.6). */
export const trickWeights = (b: Box): readonly number[] => (highest(b) >= DANGER_ROW ? DANGER_WEIGHTS : WEIGHTS);

/** One new trick for each row cleared: its kind by weight, then a filled cell with none (§4.6). */
function spawnTricks(b: Box, count: number): void {
  for (let i = 0; i < count; i++) {
    const weights = trickWeights(b);
    const total = weights.reduce((a, w) => a + w, 0);
    const [u, s1] = rngNext(b.rng);
    b.rng = s1;
    let pick = rngFloat(u) * total;
    let kind = 0;
    while (kind < weights.length - 1 && pick >= (weights[kind] as number)) {
      pick -= weights[kind] as number;
      kind++;
    }
    const open: number[] = [];
    for (let c = 0; c < TOTAL * W; c++) if (b.cells[c] !== 0 && b.tricks[c] === 0) open.push(c);
    if (open.length === 0) continue;
    const [v, s2] = rngNext(b.rng);
    b.rng = s2;
    b.tricks[open[Math.floor(rngFloat(v) * open.length)] as number] = kind + 1;
  }
}

/**
 * Sets toy `n` down at this rotation and position (§4.2 to §4.6): clears full rows, blocks
 * waiting junk with what they would send, adds a trick per row cleared, and, when nothing
 * cleared, lands the junk in `landed` (oldest first, a prefix of `waiting`).
 */
export function setDown(box: Box, roundSeed: Readonly<Seed>, n: number, rot: Rot, x: number, y: number, landed: readonly number[]): SetDown | { error: SetDownError } {
  if (box.out) return { error: "box_out" };
  if (n !== box.next) return { error: "not_next" };
  const toy = toyAt(roundSeed, n);
  if (!fits(box, toy, rot, x, y)) return { error: "bad_place" };
  if (fits(box, toy, rot, x, y - 1)) return { error: "not_resting" };
  if (landed.length > box.waiting.length || landed.some((id, i) => box.waiting[i]?.id !== id)) return { error: "bad_landed" };

  const b = copy(box);
  for (const [cx, cy] of toyCells(toy, rot)) b.cells[idx(x + cx, y + cy)] = TOY_INDEX[toy] + 1;
  const full = fullRows(b);
  if (full.length > 0 && landed.length > 0) return { error: "bad_landed" };
  const pocketed: Trick[] = [];
  removeRows(b, full, pocketed);
  const cleared = full.length;
  let attack: number = ATTACK[Math.min(cleared, 4)] as number;

  const blocked: { id: number; rows: number }[] = [];
  while (attack > 0 && b.waiting.length > 0) {
    const w = b.waiting[0] as Waiting;
    const take = Math.min(attack, w.rows);
    w.rows -= take;
    attack -= take;
    blocked.push({ id: w.id, rows: take });
    if (w.rows === 0) b.waiting.shift();
  }
  spawnTricks(b, cleared);
  for (let i = 0; i < landed.length; i++) {
    const w = b.waiting.shift() as Waiting;
    pushJunk(b, w.rows, w.gap);
  }
  b.rows += cleared;
  b.next = n + 1;
  const nextToy = toyAt(roundSeed, n + 1);
  const at = spawn(nextToy);
  b.out = anyAbove(b) || !fits(b, nextToy, at.rot, at.x, at.y);
  return { box: b, cleared, sent: attack, blocked, pocketed, out: b.out };
}

/**
 * Lands the oldest `count` waiting junk now, as the server does for junk a device owed and didn't
 * land (§6.5). Not a client step: the device is sent the result.
 */
export function landWaiting(box: Box, count: number): Box {
  if (box.out || count <= 0) return box;
  const b = copy(box);
  for (let i = 0; i < count && b.waiting.length > 0; i++) {
    const w = b.waiting.shift() as Waiting;
    pushJunk(b, w.rows, w.gap);
  }
  b.out = anyAbove(b);
  return b;
}

/** Junk that has arrived and starts its wait (§4.5). */
export function receiveJunk(box: Box, w: Waiting): Box {
  if (box.out) return box;
  const b = copy(box);
  b.waiting.push({ ...w });
  return b;
}

/** A trick's effect on this box (§4.6). Rows a trick removes are not clears: no junk, no blocking, no new tricks. */
export function applyHit(box: Box, hit: Hit): { box: Box; pocketed: Trick[] } {
  if (box.out) return { box, pocketed: [] };
  const b = copy(box);
  const pocketed: Trick[] = [];
  switch (hit.k) {
    case "hairball":
      pushJunk(b, 1, hit.gap);
      break;
    case "swipe": {
      const cells = [...b.cells];
      const tricks = [...b.tricks];
      for (let y = 0; y < TOTAL; y++) {
        const s = hit.shifts[y] ?? 0;
        for (let x = 0; x < W; x++) {
          const to = (((x + s) % W) + W) % W;
          cells[idx(to, y)] = b.cells[idx(x, y)] as number;
          tricks[idx(to, y)] = b.tricks[idx(x, y)] as number;
        }
      }
      b.cells = cells;
      b.tricks = tricks;
      break;
    }
    case "scoop":
      removeRows(b, [0, 1], pocketed);
      break;
    case "settle": {
      const cells = new Array<number>(TOTAL * W).fill(0);
      const tricks = new Array<number>(TOTAL * W).fill(0);
      for (let x = 0; x < W; x++) {
        let to = 0;
        for (let y = 0; y < TOTAL; y++) {
          if (b.cells[idx(x, y)] === 0) continue;
          cells[idx(x, to)] = b.cells[idx(x, y)] as number;
          tricks[idx(x, to)] = b.tricks[idx(x, y)] as number;
          to++;
        }
      }
      b.cells = cells;
      b.tricks = tricks;
      removeRows(b, fullRows(b), pocketed);
      break;
    }
    case "bath":
      b.cells.fill(0);
      b.tricks.fill(0);
      b.waiting = [];
      break;
    case "swap":
      b.cells = [...hit.cells];
      b.tricks = [...hit.tricks];
      break;
    case "catnip":
    case "nap":
      break;
  }
  b.out = anyAbove(b);
  return { box: b, pocketed };
}

/** Takes the trick in `slot` out of the box's held tricks, or null when there is none. */
export function useTrick(box: Box, slot: number): { box: Box; trick: Trick } | null {
  if (box.out || slot < 0 || slot >= box.held.length) return null;
  const b = copy(box);
  const [trick] = b.held.splice(slot, 1);
  return { box: b, trick: trick as Trick };
}

/** The part of a box a Swap moves: its cells and the tricks on them. */
export const contents = (box: Box): { cells: number[]; tricks: number[] } => ({ cells: [...box.cells], tricks: [...box.tricks] });
