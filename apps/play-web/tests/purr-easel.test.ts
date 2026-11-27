import { describe, expect, test } from "vitest";

import { Easel, fitEasel, paint, traceStroke, type Surface } from "../src/table/purr-easel";
import { COLOURS, Picture, WIDTHS, type InkOp, type Stroke } from "../src/table/purr-ink";

/** A 2D context that writes down what it is asked to draw. */
class Recorder implements Surface {
  calls: unknown[][] = [];
  lineWidth = 1;
  lineCap: CanvasLineCap = "butt";
  lineJoin: CanvasLineJoin = "miter";
  strokeStyle: string | CanvasGradient | CanvasPattern = "";
  fillStyle: string | CanvasGradient | CanvasPattern = "";
  beginPath() {
    this.calls.push(["beginPath"]);
  }
  moveTo(x: number, y: number) {
    this.calls.push(["moveTo", x, y]);
  }
  lineTo(x: number, y: number) {
    this.calls.push(["lineTo", x, y]);
  }
  quadraticCurveTo(cx: number, cy: number, x: number, y: number) {
    this.calls.push(["quad", cx, cy, x, y]);
  }
  arc(x: number, y: number, r: number) {
    this.calls.push(["arc", x, y, r]);
  }
  stroke() {
    this.calls.push(["stroke", this.strokeStyle, this.lineWidth]);
  }
  fill() {
    this.calls.push(["fill", this.fillStyle]);
  }
  setTransform(...m: number[]) {
    this.calls.push(["transform", ...m]);
  }
  clearRect(...r: number[]) {
    this.calls.push(["clear", ...r]);
  }
  drawImage(image: unknown) {
    this.calls.push(["image", image]);
  }
  /** The strokes drawn since the last clear: their first points. */
  strokesShown(): number[][] {
    const out: number[][] = [];
    for (const c of this.calls) {
      if (c[0] === "clear") out.length = 0;
      if (c[0] === "moveTo" || c[0] === "arc") out.push([c[1] as number, c[2] as number]);
      if (c[0] === "image") out.push([-1, -1]);
    }
    return out;
  }
}

const stroke = (id: number, points: number[], colour = 0, width = 1): Stroke => ({ id, colour, width, points });

function harness(raster?: (s: readonly Stroke[]) => Promise<unknown>) {
  const base = new Recorder();
  const live = new Recorder();
  const frames: ((t: number) => void)[] = [];
  const easel = new Easel({
    base,
    live,
    resize: () => undefined,
    raster: raster as never,
    request: (fn) => frames.push(fn),
    cancel: () => undefined,
  });
  const runFrame = () => {
    const f = frames.splice(0);
    for (const fn of f) fn(0);
  };
  return { base, live, easel, runFrame, frames };
}

describe("drawing a stroke", () => {
  test("smoothing goes through the midpoints, each point the curve's control", () => {
    const r = new Recorder();
    traceStroke(r, stroke(0, [0, 0, 10, 0, 20, 10, 30, 10]));
    expect(r.calls.filter((c) => c[0] !== "beginPath" && c[0] !== "stroke")).toEqual([
      ["moveTo", 0, 0],
      ["lineTo", 5, 0],
      ["quad", 10, 0, 15, 5],
      ["quad", 20, 10, 25, 10],
      ["lineTo", 30, 10],
    ]);
    expect(r.lineCap).toBe("round");
    expect(r.calls.at(-1)).toEqual(["stroke", COLOURS[0], WIDTHS[1]]);
  });

  test("one point is a dot, two a line", () => {
    const r = new Recorder();
    traceStroke(r, stroke(0, [5, 6], 3, 2));
    expect(r.calls).toContainEqual(["arc", 5, 6, WIDTHS[2] / 2]);
    expect(r.calls).toContainEqual(["fill", COLOURS[3]]);
    const r2 = new Recorder();
    traceStroke(r2, stroke(0, [5, 6, 9, 9]));
    expect(r2.calls).toContainEqual(["lineTo", 9, 9]);
  });

  test("the eraser paints white", () => {
    const r = new Recorder();
    traceStroke(r, stroke(0, [0, 0, 9, 9], 8, 2));
    expect(r.calls.at(-1)).toEqual(["stroke", "#FFFFFF", WIDTHS[2]]);
  });

  test("the easel is 3:4 inside its box", () => {
    expect(fitEasel(300, 1000)).toEqual({ width: 300, height: 400 });
    expect(fitEasel(1000, 400)).toEqual({ width: 300, height: 400 });
  });
});

describe("the two layers", () => {
  test("finished strokes go to the bitmap once; the live stroke redraws alone", () => {
    const { base, live, easel, runFrame } = harness();
    const a = stroke(0, [1, 1, 5, 5]);
    const b = stroke(1, [10, 10]);
    let src = { finished: [a] as Stroke[], live: b as Stroke | null };
    easel.source = () => src;
    easel.setSize(384, 512, 2);
    runFrame();
    expect(base.strokesShown()).toEqual([[1, 1]]);
    expect(live.strokesShown()).toEqual([[10, 10]]);
    // The live stroke grows: only the live layer draws.
    base.calls = [];
    b.points.push(20, 20);
    easel.invalidate();
    runFrame();
    expect(base.calls).toEqual([]);
    expect(live.strokesShown()).toEqual([[10, 10]]);
    // It finishes: onto the bitmap, and the live layer empties.
    src = { finished: [a, b], live: null };
    easel.invalidate();
    runFrame();
    expect(base.strokesShown()).toEqual([[10, 10]]);
    expect(live.strokesShown()).toEqual([]);
  });

  test("the grid scales to the device pixels", () => {
    const { base, easel, runFrame } = harness();
    easel.source = () => ({ finished: [stroke(0, [1, 1])], live: null });
    easel.setSize(384, 512, 1);
    runFrame();
    // 768 grid units across 384 device pixels.
    expect(base.calls).toContainEqual(["transform", 0.5, 0, 0, 0.5, 0, 0]);
    base.calls = [];
    easel.setSize(384, 512, 3);
    runFrame();
    expect(base.calls).toContainEqual(["transform", 1.5, 0, 0, 1.5, 0, 0]);
  });

  test("an undo rebuilds the bitmap off the page, and strokes finished meanwhile land on top", async () => {
    let finish: (img: unknown) => void = () => undefined;
    const asked: (readonly Stroke[])[] = [];
    const { base, easel, runFrame } = harness((s) => {
      asked.push(s);
      return new Promise((r) => (finish = r));
    });
    const pic = new Picture();
    pic.applyAll([["s", 0, 0, 0, 1, 1, 2, 2], ["s", 1, 0, 0, 5, 5], ["s", 2, 0, 0, 9, 9]]);
    easel.source = () => ({ finished: pic.strokes.slice(), live: null });
    easel.setSize(768, 1024, 1);
    // The first size rebuilds too: let it land.
    finish("first");
    await Promise.resolve();
    runFrame();
    pic.applyAll([["u", 1]]);
    easel.invalidate();
    runFrame();
    expect(asked.at(-1)!.map((s) => s.id)).toEqual([0, 2]);
    pic.applyAll([["s", 3, 0, 0, 40, 40]]);
    easel.invalidate();
    runFrame();
    base.calls = [];
    finish("bitmap");
    await Promise.resolve();
    await Promise.resolve();
    expect(base.calls[0]).toEqual(["transform", 1, 0, 0, 1, 0, 0]);
    expect(base.strokesShown()).toEqual([[-1, -1], [40, 40]]);
  });

  test("a clear empties the bitmap at once, with no worker", () => {
    let asked = 0;
    const { base, easel, runFrame } = harness(() => {
      asked += 1;
      return new Promise(() => undefined);
    });
    let strokes = [stroke(0, [1, 1])];
    easel.source = () => ({ finished: strokes, live: null });
    easel.setSize(100, 133, 1);
    runFrame();
    const before = asked;
    strokes = [];
    easel.invalidate();
    runFrame();
    expect(asked).toBe(before);
    expect(base.strokesShown()).toEqual([]);
  });

  test("inkSync replays to the same picture as the live stream did", () => {
    // The TV saw every op live; a TV that reloads gets the compacted drawing. Same strokes, same pixels.
    const ops: InkOp[] = [["s", 0, 1, 1, 10, 10, 5, 5, 5, 0], ["s", 1, 2, 0, 50, 50, 3, 3], ["u", 1], ["c"], ["s", 2, 3, 2, 100, 100, 10, 10], ["p", 2, 4, 4], ["s", 3, 8, 2, 105, 105, 2, 2], ["s", 4, 0, 0, 7, 7], ["u", 4]];
    const live = new Picture();
    for (const op of ops) live.apply(op);
    const synced = new Picture();
    synced.applyAll([["s", 2, 3, 2, 100, 100, 10, 10], ["p", 2, 4, 4], ["s", 3, 8, 2, 105, 105, 2, 2]]);
    const a = new Recorder();
    const b = new Recorder();
    paint(a, live.strokes, 768, 1024, 1);
    paint(b, synced.strokes, 768, 1024, 1);
    expect(b.calls).toEqual(a.calls);
  });
});
