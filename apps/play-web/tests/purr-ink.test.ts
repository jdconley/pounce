import { describe, expect, test } from "vitest";

import {
  EASEL_H,
  EASEL_W,
  InkWriter,
  MAX_INK_BYTES,
  Pacer,
  Picture,
  compact,
  inkBytes,
  keepsPoint,
  rdp,
  splitOps,
  type InkOp,
} from "../src/table/purr-ink";

/** A finger's path as a phone reports it: a point every few px, with jitter. */
function wiggle(n: number, from: [number, number] = [100, 100], step = 3): [number, number][] {
  const out: [number, number][] = [];
  let [x, y] = from;
  for (let i = 0; i < n; i++) {
    x += step;
    y += Math.round(Math.sin(i / 6) * 4);
    out.push([Math.min(EASEL_W - 1, x), Math.min(EASEL_H - 1, Math.max(0, y))]);
  }
  return out;
}

/** Every op a writer sends, drained at once (no pacing). */
function drain(w: InkWriter, now = 0): InkOp[] {
  const out: InkOp[] = [];
  for (const m of w.flush(now, true)) out.push(...m);
  return out;
}

describe("points", () => {
  test("a point under 2 grid units from the last kept is dropped", () => {
    expect(keepsPoint(10, 10, 11, 11)).toBe(false);
    expect(keepsPoint(10, 10, 12, 10)).toBe(true);
    expect(keepsPoint(10, 10, 11, 12)).toBe(true);
  });

  test("RDP keeps the ends and the corners, drops the straight run", () => {
    // An L: straight right, then straight down.
    const flat = [0, 0, 10, 0, 20, 0, 30, 0, 30, 10, 30, 20, 30, 30];
    expect(rdp(flat, 1)).toEqual([0, 0, 30, 0, 30, 30]);
  });

  test("RDP keeps a bump bigger than its tolerance", () => {
    const flat = [0, 0, 10, 0, 20, 3, 30, 0, 40, 0];
    expect(rdp(flat, 1)).toEqual([0, 0, 10, 0, 20, 3, 30, 0, 40, 0]);
    expect(rdp([0, 0, 10, 0, 20, 1, 30, 0, 40, 0], 1)).toEqual([0, 0, 40, 0]);
  });

  test("RDP of one or two points is the points", () => {
    expect(rdp([5, 5], 1)).toEqual([5, 5]);
    expect(rdp([5, 5, 9, 9], 1)).toEqual([5, 5, 9, 9]);
  });
});

describe("the writer", () => {
  test("a stroke goes as s then p, deltas from the last point sent", () => {
    const w = new InkWriter();
    w.begin(2, 1, 100, 200);
    w.move(110, 200);
    w.move(120, 210);
    const first = drain(w);
    expect(first[0]).toEqual(["s", 0, 2, 1, 100, 200, 10, 0, 10, 10]);
    w.move(130, 210);
    w.end();
    const second = drain(w);
    expect(second).toEqual([["p", 0, 10, 0]]);
  });

  test("a tap is a stroke of one point", () => {
    const w = new InkWriter();
    w.begin(0, 2, 50, 60);
    w.end();
    expect(drain(w)).toEqual([["s", 0, 0, 2, 50, 60]]);
  });

  test("ids go up by one, undo names the last stroke, clear is c", () => {
    const w = new InkWriter();
    w.begin(0, 0, 10, 10);
    w.end();
    w.begin(0, 0, 20, 20);
    w.end();
    expect(w.undo()).toBe(true);
    w.clear();
    w.begin(0, 0, 30, 30);
    w.end();
    expect(drain(w)).toEqual([["s", 0, 0, 0, 10, 10], ["s", 1, 0, 0, 20, 20], ["u", 1], ["c"], ["s", 2, 0, 0, 30, 30]]);
  });

  test("undo walks back through the strokes since the last clear, and no further", () => {
    const w = new InkWriter();
    w.begin(0, 0, 10, 10);
    w.end();
    w.clear();
    w.begin(0, 0, 20, 20);
    w.end();
    expect(w.canUndo).toBe(true);
    expect(w.undo()).toBe(true);
    expect(w.canUndo).toBe(false);
    expect(w.undo()).toBe(false);
  });

  test("undo during a stroke ends it and takes it back", () => {
    const w = new InkWriter();
    w.begin(0, 0, 10, 10);
    w.move(40, 10);
    w.undo();
    expect(w.drawing).toBe(false);
    expect(drain(w)).toEqual([["s", 0, 0, 0, 10, 10, 30, 0], ["u", 0]]);
    expect(w.picture.strokes).toEqual([]);
  });

  test("points closer than 2 units are not sent", () => {
    const w = new InkWriter();
    w.begin(0, 0, 10, 10);
    w.move(11, 10);
    w.move(11, 11);
    w.move(13, 10);
    w.end();
    expect(drain(w)).toEqual([["s", 0, 0, 0, 10, 10, 3, 0]]);
  });

  test("points are clamped to the grid", () => {
    const w = new InkWriter();
    w.begin(0, 0, -20, 2000);
    w.move(900, -5);
    w.end();
    // A jump past 768 units goes as two deltas.
    expect(drain(w)).toEqual([["s", 0, 0, 0, 0, 1023, 384, -511, 383, -512]]);
  });

  test("coalesced points keep a fast line whole", () => {
    // A fast swipe: 300 coalesced samples 3 units apart arrive within one 50 ms batch.
    const w = new InkWriter();
    const pts = wiggle(300);
    w.begin(5, 1, 100, 100);
    for (const [x, y] of pts) w.move(x, y);
    w.end();
    const ops = drain(w);
    const pic = new Picture();
    pic.applyAll(ops);
    const stroke = pic.strokes[0]!;
    // The line ends where the finger did, starts where it began, and never jumps more than the
    // simplification could explain: every kept segment hugs the raw path within the tolerance.
    expect(stroke.points.slice(0, 2)).toEqual([100, 100]);
    expect(stroke.points.slice(-2)).toEqual(pts.at(-1));
    const raw = [100, 100, ...pts.flat()];
    for (let i = 0; i < raw.length; i += 2) {
      expect(distanceToPolyline(raw[i]!, raw[i + 1]!, stroke.points)).toBeLessThanOrEqual(1.5);
    }
  });

  test("a batch of a recorded stroke is valid and under 8 KB", () => {
    const w = new InkWriter();
    w.begin(3, 2, 10, 10);
    for (const [x, y] of wiggle(240, [10, 10], 3)) w.move(x, y);
    w.end();
    for (const message of w.flush(0, true)) {
      expect(inkBytes(message)).toBeLessThan(MAX_INK_BYTES);
      expect(validOps(message)).toBe(true);
    }
  });

  test("a huge stroke splits across messages, each under the limit", () => {
    const w = new InkWriter();
    w.begin(1, 0, 0, 0);
    // A zigzag RDP can't simplify: every point is a corner.
    for (let i = 1; i < 4000; i++) w.move((i * 7) % 760, i % 2 === 0 ? 10 + (i % 1000) : 900 - (i % 800));
    w.end();
    const messages = w.flush(0, true);
    expect(messages.length).toBeGreaterThan(1);
    for (const m of messages) expect(inkBytes(m)).toBeLessThan(MAX_INK_BYTES);
    const pic = new Picture();
    for (const m of messages) pic.applyAll(m);
    expect(pic.strokes).toHaveLength(1);
  });

  test("the resend starts with c and redraws the visible easel", () => {
    const w = new InkWriter();
    w.begin(0, 0, 10, 10);
    w.move(50, 50);
    w.end();
    w.begin(1, 1, 100, 100);
    w.end();
    w.undo();
    w.begin(2, 2, 200, 200);
    w.move(220, 230);
    drain(w);
    const resend = w.resend();
    expect(resend[0]![0]).toEqual(["c"]);
    const pic = new Picture();
    for (const m of resend) pic.applyAll(m);
    expect(pic.strokes.map((s) => s.id)).toEqual([0, 2]);
    expect(pic.strokes[1]!.points).toEqual([200, 200, 220, 230]);
  });

  test("adopting the server's drawing takes its strokes and goes on after its last id", () => {
    const w = new InkWriter();
    w.adopt([["s", 0, 0, 0, 10, 10, 5, 5], ["s", 3, 1, 1, 50, 50]]);
    expect(w.picture.strokes.map((s) => s.id)).toEqual([0, 3]);
    w.begin(0, 0, 1, 1);
    w.end();
    expect(drain(w)).toEqual([["s", 4, 0, 0, 1, 1]]);
  });
});

describe("pacing", () => {
  test("at most 22 messages in any second", () => {
    const p = new Pacer(22, 1000);
    let sent = 0;
    for (let t = 0; t < 1000; t += 10) {
      if (p.ready(t)) {
        p.sent(t);
        sent += 1;
      }
    }
    expect(sent).toBe(22);
    expect(p.ready(999)).toBe(false);
    expect(p.ready(1000)).toBe(true);
  });

  test("the writer holds points back while paced, then sends them together", () => {
    const w = new InkWriter({ pacer: new Pacer(1, 1000) });
    w.begin(0, 0, 10, 10);
    expect(w.flush(0)).toHaveLength(1);
    w.move(20, 10);
    expect(w.flush(60)).toEqual([]);
    w.move(30, 10);
    expect(w.flush(1000)).toEqual([[["p", 0, 20, 0]]]);
  });

  test("a batch goes every 50 ms while drawing, and at once when the stroke ends", () => {
    const w = new InkWriter();
    w.begin(0, 0, 10, 10);
    expect(w.flush(0)).toHaveLength(1);
    w.move(20, 10);
    expect(w.flush(30)).toEqual([]);
    expect(w.flush(50)).toHaveLength(1);
    w.move(30, 10);
    w.end();
    expect(w.flush(60)).toHaveLength(1);
  });

  test("nothing is sent while the finger is still", () => {
    const w = new InkWriter();
    w.begin(0, 0, 10, 10);
    w.flush(0);
    expect(w.flush(100)).toEqual([]);
    expect(w.flush(200)).toEqual([]);
  });
});

describe("the picture", () => {
  test("decode(encode(x)) round-trips", () => {
    const w = new InkWriter();
    const strokes: [number, number][][] = [wiggle(40, [10, 10]), wiggle(20, [300, 500], 5)];
    strokes.forEach((pts, i) => {
      w.begin(i, i % 3, pts[0]![0], pts[0]![1]);
      for (const [x, y] of pts.slice(1)) w.move(x, y);
      w.end();
    });
    const pic = new Picture();
    pic.applyAll(drain(w));
    expect(pic.strokes.map((s) => s.points)).toEqual(w.picture.strokes.map((s) => s.points));
    expect(pic.strokes.map((s) => [s.colour, s.width])).toEqual([[0, 0], [1, 1]]);
  });

  test("u removes a stroke, c removes everything", () => {
    const pic = new Picture();
    pic.applyAll([["s", 0, 0, 0, 1, 1], ["s", 1, 0, 0, 2, 2], ["u", 0]]);
    expect(pic.strokes.map((s) => s.id)).toEqual([1]);
    pic.applyAll([["c"]]);
    expect(pic.strokes).toEqual([]);
  });

  test("ops for a stroke that isn't there are ignored", () => {
    const pic = new Picture();
    pic.applyAll([["p", 4, 1, 1], ["u", 9]]);
    expect(pic.strokes).toEqual([]);
  });
});

describe("compact", () => {
  test("s,s,u,c,s carries one stroke", () => {
    const ops: InkOp[] = [["s", 0, 0, 0, 1, 1, 2, 2], ["s", 1, 0, 0, 5, 5], ["u", 1], ["c"], ["s", 2, 1, 1, 9, 9], ["p", 2, 3, 3]];
    expect(compact(ops)).toEqual([["s", 2, 1, 1, 9, 9], ["p", 2, 3, 3]]);
  });

  test("undone strokes go, kept ones stay in order", () => {
    const ops: InkOp[] = [["s", 0, 0, 0, 1, 1], ["s", 1, 0, 0, 5, 5], ["p", 0, 1, 1], ["u", 1]];
    expect(compact(ops)).toEqual([["s", 0, 0, 0, 1, 1], ["p", 0, 1, 1]]);
  });

  test("the compacted drawing looks the same", () => {
    const ops: InkOp[] = [["s", 0, 0, 0, 1, 1, 2, 2], ["s", 1, 3, 2, 5, 5], ["u", 1], ["s", 2, 1, 1, 9, 9], ["c"], ["s", 3, 4, 0, 10, 10, 1, 1], ["s", 4, 4, 0, 11, 11], ["u", 4]];
    const a = new Picture();
    a.applyAll(ops);
    const b = new Picture();
    b.applyAll(compact(ops));
    expect(b.strokes).toEqual(a.strokes);
  });
});

describe("splitting", () => {
  test("splitOps keeps every op whole when it can, and every chunk under the budget", () => {
    const ops: InkOp[] = Array.from({ length: 400 }, (_, i): InkOp => ["s", i, i % 8, i % 3, i % 700, (i * 3) % 1000, 1, 1, 2, 2]);
    const chunks = splitOps(ops, 2000);
    expect(chunks.length).toBeGreaterThan(1);
    expect(chunks.flat()).toEqual(ops);
    for (const c of chunks) expect(inkBytes(c)).toBeLessThanOrEqual(2000);
  });
});

/** The shapes the server takes (design §6.2). */
function validOps(ops: InkOp[]): boolean {
  return ops.every((op) => {
    if (op[0] === "c") return op.length === 1;
    if (op[0] === "u") return op.length === 2 && Number.isInteger(op[1]);
    const nums = op.slice(1) as number[];
    if (!nums.every((n) => Number.isInteger(n))) return false;
    if (op[0] === "s") {
      const [, colour, width, x, y, ...d] = nums;
      return colour! >= 0 && colour! <= 8 && width! >= 0 && width! <= 2 && x! >= 0 && x! < EASEL_W && y! >= 0 && y! < EASEL_H && d.length % 2 === 0 && d.every((v) => v >= -768 && v <= 768);
    }
    const d = nums.slice(1);
    return d.length % 2 === 0 && d.length > 0 && d.every((v) => v >= -768 && v <= 768);
  });
}

function distanceToPolyline(px: number, py: number, flat: readonly number[]): number {
  let best = Infinity;
  for (let i = 0; i + 3 < flat.length; i += 2) {
    const [ax, ay, bx, by] = [flat[i]!, flat[i + 1]!, flat[i + 2]!, flat[i + 3]!];
    const dx = bx - ax;
    const dy = by - ay;
    const len = dx * dx + dy * dy;
    const t = len === 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / len));
    best = Math.min(best, Math.hypot(px - (ax + t * dx), py - (ay + t * dy)));
  }
  return flat.length === 2 ? Math.hypot(px - flat[0]!, py - flat[1]!) : best;
}
