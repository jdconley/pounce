/**
 * Purrtrait's ink, pure (design §6): the easel's grid, the drawer's points filtered and simplified
 * into ops, ops decoded back into strokes, `compact`, and the pacing that keeps a drawer's device
 * under the server's limits. The drawer's phone, the TV and the raster worker all use it.
 *
 * The wire: `["s", id, colour, width, x, y, dx, dy, ...]` starts stroke `id`; `["p", id, dx, dy, ...]`
 * adds points to it as deltas from its last point; `["u", id]` undoes it; `["c"]` clears the easel.
 */

/** The easel's grid: portrait 3:4, integers, origin at the top left. */
export const EASEL_W = 768;
export const EASEL_H = 1024;

/** The palette, numbered as on the wire: black first, white (8) is the eraser. */
export const COLOURS = ["#1B1B22", "#FF2E2E", "#FF8A00", "#FFD21F", "#2DBE4E", "#2E8BFF", "#8B3DFF", "#8B5A2B", "#FFFFFF"] as const;
export const ERASER = 8;
/** The paper: what the eraser paints. */
export const PAPER = "#FFFFFF";
/** Line widths 0-2, in grid units. */
export const WIDTHS = [4, 10, 24] as const;

/** A point under this many grid units from the last one kept is dropped. */
export const MIN_STEP = 2;
/** Ramer-Douglas-Peucker tolerance, grid units. */
export const RDP_TOLERANCE = 1;
/** A batch goes this often while drawing. */
export const BATCH_MS = 50;
/** The server takes 25 messages a second per device: the writer sends at most this many, for headroom. */
export const MESSAGES_PER_SECOND = 22;
/** The server's limit for one client message, in bytes. */
export const MAX_INK_BYTES = 8192;
/** What the writer packs a message to: under the limit, with room for the envelope's seat and turn. */
export const INK_BUDGET = 7600;
/** The biggest delta the wire takes. */
const MAX_DELTA = 768;

export type InkOp = ["s", number, number, number, number, number, ...number[]] | ["p", number, ...number[]] | ["u", number] | ["c"];

/** A stroke as drawn: absolute grid points, flat (x0, y0, x1, y1, ...). */
export type Stroke = { id: number; colour: number; width: number; points: number[] };

const clampX = (x: number): number => Math.min(EASEL_W - 1, Math.max(0, Math.round(x)));
const clampY = (y: number): number => Math.min(EASEL_H - 1, Math.max(0, Math.round(y)));

/** True when (x, y) is far enough from the last kept point to keep. */
export const keepsPoint = (lx: number, ly: number, x: number, y: number): boolean => (x - lx) * (x - lx) + (y - ly) * (y - ly) >= MIN_STEP * MIN_STEP;

/** Ramer-Douglas-Peucker over flat points: the ends are always kept. Iterative, so a long line can't overflow the stack. */
export function rdp(flat: readonly number[], tolerance: number): number[] {
  const n = flat.length / 2;
  if (n <= 2) return [...flat];
  const keep = new Uint8Array(n);
  keep[0] = keep[n - 1] = 1;
  const stack: [number, number][] = [[0, n - 1]];
  const tol2 = tolerance * tolerance;
  while (stack.length > 0) {
    const [a, b] = stack.pop()!;
    const ax = flat[a * 2]!;
    const ay = flat[a * 2 + 1]!;
    const dx = flat[b * 2]! - ax;
    const dy = flat[b * 2 + 1]! - ay;
    const len2 = dx * dx + dy * dy;
    let worst = -1;
    let at = -1;
    for (let i = a + 1; i < b; i++) {
      const px = flat[i * 2]! - ax;
      const py = flat[i * 2 + 1]! - ay;
      // Squared distance to the segment (to the end point when the segment is a point).
      let d2: number;
      if (len2 === 0) d2 = px * px + py * py;
      else {
        const cross = px * dy - py * dx;
        d2 = (cross * cross) / len2;
      }
      if (d2 > worst) {
        worst = d2;
        at = i;
      }
    }
    if (at >= 0 && worst > tol2) {
      keep[at] = 1;
      stack.push([a, at], [at, b]);
    }
  }
  const out: number[] = [];
  for (let i = 0; i < n; i++) if (keep[i]) out.push(flat[i * 2]!, flat[i * 2 + 1]!);
  return out;
}

/** Deltas from (fromX, fromY) through `flat`, a jump past the wire's limit split into steps it takes. */
function deltas(fromX: number, fromY: number, flat: readonly number[]): number[] {
  const out: number[] = [];
  let lx = fromX;
  let ly = fromY;
  for (let i = 0; i < flat.length; i += 2) {
    const x = flat[i]!;
    const y = flat[i + 1]!;
    const steps = Math.max(1, Math.ceil(Math.max(Math.abs(x - lx), Math.abs(y - ly)) / MAX_DELTA));
    for (let k = 1; k <= steps; k++) {
      const sx = k === steps ? x : Math.round(lx + ((x - lx) * 1) / (steps - k + 1));
      const sy = k === steps ? y : Math.round(ly + ((y - ly) * 1) / (steps - k + 1));
      out.push(sx - lx, sy - ly);
      lx = sx;
      ly = sy;
    }
  }
  return out;
}

/** The size of an `ink` message carrying `ops`, as the server measures it (UTF-8 bytes; all ASCII). */
export const inkBytes = (ops: readonly InkOp[]): number => JSON.stringify({ t: "ink", seat: 9, turn: "99:9999", ops }).length;

/** An op's own size inside a message's `ops` array, comma included. */
const opBytes = (op: InkOp): number => JSON.stringify(op).length + 1;

/** One op split into ops each under `budget` bytes: a long `s` becomes an `s` and `p`s. Others are small. */
function splitOp(op: InkOp, budget: number): InkOp[] {
  if (op[0] !== "s" && op[0] !== "p") return [op];
  const envelope = inkBytes([]);
  if (envelope + opBytes(op) <= budget) return [op];
  const head = op[0] === "s" ? 6 : 2;
  const id = op[1];
  const pairs = op.slice(head) as number[];
  // Each delta pair is at most 10 characters ("-768,-768,"): pack conservatively.
  const per = Math.max(2, Math.floor((budget - envelope - 40) / 10) * 2);
  const out: InkOp[] = [];
  out.push([...(op.slice(0, head) as [string, ...number[]]), ...pairs.slice(0, per)] as InkOp);
  for (let i = per; i < pairs.length; i += per) out.push(["p", id, ...pairs.slice(i, i + per)]);
  return out;
}

/** `ops` in order, packed into messages each at most `budget` bytes (as `inkBytes` counts them). */
export function splitOps(ops: readonly InkOp[], budget: number = INK_BUDGET): InkOp[][] {
  const chunks: InkOp[][] = [];
  let chunk: InkOp[] = [];
  let size = inkBytes([]);
  for (const whole of ops) {
    for (const op of splitOp(whole, budget)) {
      const b = opBytes(op);
      if (chunk.length > 0 && size + b > budget) {
        chunks.push(chunk);
        chunk = [];
        size = inkBytes([]);
      }
      chunk.push(op);
      size += b;
    }
  }
  if (chunk.length > 0) chunks.push(chunk);
  return chunks;
}

/**
 * The drawing ops describe: the visible strokes in order. Ops for a stroke that isn't there (it
 * was undone, or cleared) are ignored, as a decoder that joined late must.
 */
export class Picture {
  strokes: Stroke[] = [];
  private byId = new Map<number, Stroke>();
  /** The highest stroke id seen, visible or not. */
  lastId = -1;

  /** Applies one op; says what changed, for a renderer. */
  apply(op: InkOp): { kind: "start" | "extend"; stroke: Stroke; from: number } | { kind: "undo"; id: number; index: number } | { kind: "clear" } | null {
    switch (op[0]) {
      case "s": {
        const [, id, colour, width, x, y] = op;
        const points = [x, y];
        let lx = x;
        let ly = y;
        for (let i = 6; i + 1 < op.length; i += 2) {
          lx += op[i] as number;
          ly += op[i + 1] as number;
          points.push(lx, ly);
        }
        const stroke: Stroke = { id, colour, width, points };
        const old = this.byId.get(id);
        if (old) this.strokes = this.strokes.filter((s) => s !== old);
        this.strokes.push(stroke);
        this.byId.set(id, stroke);
        this.lastId = Math.max(this.lastId, id);
        return { kind: "start", stroke, from: 0 };
      }
      case "p": {
        const stroke = this.byId.get(op[1]);
        if (!stroke) return null;
        const from = stroke.points.length;
        let lx = stroke.points[from - 2]!;
        let ly = stroke.points[from - 1]!;
        for (let i = 2; i + 1 < op.length; i += 2) {
          lx += op[i] as number;
          ly += op[i + 1] as number;
          stroke.points.push(lx, ly);
        }
        return { kind: "extend", stroke, from };
      }
      case "u": {
        const stroke = this.byId.get(op[1]);
        if (!stroke) return null;
        const index = this.strokes.indexOf(stroke);
        this.strokes.splice(index, 1);
        this.byId.delete(op[1]);
        return { kind: "undo", id: op[1], index };
      }
      case "c":
        this.strokes = [];
        this.byId.clear();
        return { kind: "clear" };
      default:
        return null;
    }
  }

  applyAll(ops: readonly InkOp[]): void {
    for (const op of ops) this.apply(op);
  }

  /** The picture as ops: one `s` per visible stroke. */
  toOps(): InkOp[] {
    return this.strokes.map((s): InkOp => ["s", s.id, s.colour, s.width, s.points[0]!, s.points[1]!, ...deltas(s.points[0]!, s.points[1]!, s.points.slice(2))]);
  }
}

/** The smallest drawing that looks the same: undone strokes and everything before the last clear left out. */
export function compact(ops: readonly InkOp[]): InkOp[] {
  let start = 0;
  for (let i = ops.length - 1; i >= 0; i--) {
    if (ops[i]![0] === "c") {
      start = i + 1;
      break;
    }
  }
  const tail = ops.slice(start);
  const undone = new Set(tail.flatMap((op) => (op[0] === "u" ? [op[1]] : [])));
  return tail.filter((op) => op[0] !== "u" && !undone.has(op[1] as number));
}

/** A sliding window: at most `max` messages in any `windowMs`. */
export class Pacer {
  private times: number[] = [];
  constructor(
    private readonly max: number = MESSAGES_PER_SECOND,
    private readonly windowMs = 1000,
  ) {}

  ready(now: number): boolean {
    while (this.times.length > 0 && this.times[0]! <= now - this.windowMs) this.times.shift();
    return this.times.length < this.max;
  }

  sent(now: number): void {
    this.times.push(now);
  }
}

/**
 * The drawer's side: points in, ops out. Points are filtered as they come (under `MIN_STEP` from
 * the last kept are dropped); each batch is simplified (RDP) from the last point sent. `flush` says
 * what to send now: a batch every `BATCH_MS` while drawing, at once when a stroke ends, an undo or
 * a clear, and never more than the pacer allows (held-back points go with the next message).
 */
export class InkWriter {
  /** What has been encoded this turn, as the TV will draw it. */
  readonly picture = new Picture();
  /** The stroke under the finger, as kept (filtered, not yet simplified): what the drawer sees. */
  live: Stroke | null = null;
  private nextId = 0;
  /** The current stroke's points not yet encoded, after the last encoded one. */
  private held: number[] = [];
  /** The last point encoded for the current stroke. */
  private sentX = 0;
  private sentY = 0;
  /** The current stroke has its `s` op already. */
  private started = false;
  private outbox: InkOp[] = [];
  /** Something ended (a stroke, an undo, a clear): send at once. */
  private urgent = false;
  private lastSent = -Infinity;
  /** Strokes since the last clear, newest last: what Undo takes back. */
  private undoable: number[] = [];
  private readonly pacer: Pacer;

  constructor(options: { pacer?: Pacer } = {}) {
    this.pacer = options.pacer ?? new Pacer();
  }

  get drawing(): boolean {
    return this.live !== null;
  }

  get canUndo(): boolean {
    return this.undoable.length > 0;
  }

  /** Points or ops are waiting to go. */
  get pending(): boolean {
    return this.outbox.length > 0 || this.held.length > 0 || (this.live !== null && !this.started);
  }

  begin(colour: number, width: number, x: number, y: number): void {
    if (this.live) this.end();
    const px = clampX(x);
    const py = clampY(y);
    this.live = { id: this.nextId++, colour, width, points: [px, py] };
    this.started = false;
    this.held = [];
    this.sentX = px;
    this.sentY = py;
  }

  /** A point under the finger. True when it was kept (and the drawer's line grows). */
  move(x: number, y: number): boolean {
    const s = this.live;
    if (!s) return false;
    const px = clampX(x);
    const py = clampY(y);
    const n = s.points.length;
    if (!keepsPoint(s.points[n - 2]!, s.points[n - 1]!, px, py)) return false;
    s.points.push(px, py);
    this.held.push(px, py);
    return true;
  }

  end(): void {
    if (!this.live) return;
    this.encode();
    this.undoable.push(this.live.id);
    this.live = null;
    this.urgent = true;
  }

  /** Takes back the last stroke since the last clear. */
  undo(): boolean {
    if (this.live) this.end();
    const id = this.undoable.pop();
    if (id === undefined) return false;
    this.push(["u", id]);
    this.urgent = true;
    return true;
  }

  clear(): void {
    if (this.live) this.end();
    this.push(["c"]);
    this.undoable = [];
    this.urgent = true;
  }

  /**
   * The messages to send now (each a list of ops under the size limit). `force` sends everything
   * waiting, whatever the time and the pacing (a stroke cut off as the page hides, and tests).
   */
  flush(now: number, force = false): InkOp[][] {
    if (!force) {
      const due = this.urgent || now - this.lastSent >= BATCH_MS;
      if (!due || !this.pending || !this.pacer.ready(now)) return [];
    }
    this.encode();
    if (this.outbox.length === 0) return [];
    const messages = splitOps(this.outbox);
    this.outbox = [];
    this.urgent = false;
    this.lastSent = now;
    for (let i = 0; i < messages.length; i++) this.pacer.sent(now);
    return messages;
  }

  /** The whole easel again, after the server lost it (`inkResend`): a clear, then every visible stroke. */
  resend(): InkOp[][] {
    this.encode();
    return splitOps([["c"], ...this.picture.toOps()]);
  }

  /** Takes the server's drawing as this device's own (a reload mid-turn): its strokes, and ids after its last. */
  adopt(ops: readonly InkOp[]): void {
    this.live = null;
    this.held = [];
    this.outbox = [];
    this.picture.applyAll([["c"], ...ops]);
    this.nextId = Math.max(this.nextId, this.picture.lastId + 1);
    this.undoable = this.picture.strokes.map((s) => s.id);
  }

  /** The held points of the current stroke, simplified, into the outbox. */
  private encode(): void {
    const s = this.live;
    if (!s) return;
    if (!this.started) {
      const [x, y] = [s.points[0]!, s.points[1]!];
      const rest = rdp([x, y, ...this.held], RDP_TOLERANCE).slice(2);
      this.push(["s", s.id, s.colour, s.width, x, y, ...deltas(x, y, rest)]);
      this.started = true;
      this.mark(rest);
    } else if (this.held.length > 0) {
      const rest = rdp([this.sentX, this.sentY, ...this.held], RDP_TOLERANCE).slice(2);
      this.push(["p", s.id, ...deltas(this.sentX, this.sentY, rest)]);
      this.mark(rest);
    }
    this.held = [];
  }

  private mark(rest: number[]): void {
    if (rest.length >= 2) {
      this.sentX = rest[rest.length - 2]!;
      this.sentY = rest[rest.length - 1]!;
    }
  }

  private push(op: InkOp): void {
    this.outbox.push(op);
    this.picture.apply(op);
  }
}
