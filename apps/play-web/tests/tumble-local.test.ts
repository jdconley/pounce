/**
 * One's own Toy Tumble box on the frame clock (spec §4.2 to §4.5, §6.3): gravity, moves, turns
 * and drops applied at once, events batched to the socket, junk's 2-second wait, and a box that
 * stops on a hidden tab until a sync comes.
 */
import { fits, newBox, W, type Box } from "@pounce/play-api/tumble/box";
import { gravityMs as engineGravity } from "@pounce/play-api/tumble/clock";
import { toyAt } from "@pounce/play-api/tumble/queue";
import { spawn, toyCells } from "@pounce/play-api/tumble/toys";
import { describe, expect, test } from "vitest";

import { Batcher } from "../src/tumble/batcher";
import { LocalBox } from "../src/tumble/local";
import { gravityMs } from "../src/tumble/rules";

import type { Seed } from "@pounce/play-api/rules/rng";
import type { ClientEvent, HitWire } from "@pounce/play-api/tumble/wire";

const ROUND: Seed = [1, 2, 3, 4];
const TRICKS: Seed = [5, 6, 7, 8];
const START = 10_000;

function setup() {
  const sent: ClientEvent[][] = [];
  const box = new LocalBox({ r: 2, seat: 1, roundSeed: ROUND, trickSeed: TRICKS, startsAt: START, send: (ev) => sent.push(ev) });
  return { box, sent };
}

const junk = (id: number, rows = 1, gap = 3): HitWire => ({ t: "tumbleHit", r: 2, id, from: 0, to: 1, k: "junk", x: { rows, gap } });

describe("gravity", () => {
  test("is the engine's shared clock: 1000 ms a row to start, Catnip 4 times as fast, never under 50 ms", () => {
    expect(gravityMs).toBe(engineGravity);
    expect(gravityMs(0)).toBe(1000);
    expect(gravityMs(30_000)).toBeCloseTo(850);
    expect(gravityMs(0, true)).toBe(250);
    expect(gravityMs(600_000)).toBe(50);
  });
});

describe("the batcher", () => {
  test("coalesces moves to the latest, sends at most every 50 ms, and at once on a set-down, a trick or an ack", () => {
    const out: ClientEvent[][] = [];
    const b = new Batcher((ev) => out.push(ev));
    b.push(["m", 0, 0, 5, 18], 0);
    expect(out).toEqual([[["m", 0, 0, 5, 18]]]);
    b.push(["m", 0, 0, 4, 18], 10);
    b.push(["m", 0, 1, 4, 18], 20);
    b.step(40);
    expect(out.length).toBe(1);
    b.step(50);
    expect(out[1]).toEqual([["m", 0, 1, 4, 18]]);
    b.push(["m", 0, 1, 3, 18], 60);
    b.push(["l", 0, 1, 3, 0, 60, []], 61);
    expect(out[2]).toEqual([["m", 0, 1, 3, 18], ["l", 0, 1, 3, 0, 60, []]]);
    b.push(["u", 0, 2], 62);
    expect(out[3]).toEqual([["u", 0, 2]]);
    b.push(["a", 9], 63);
    expect(out[4]).toEqual([["a", 9]]);
    b.step(500);
    expect(out.length).toBe(5);
  });
});

describe("the local box", () => {
  test("waits for the start, then a toy appears and falls a row every 1000 ms", () => {
    const { box } = setup();
    box.step(START - 1);
    expect(box.view().toy).toBeNull();
    box.step(START);
    const toy = toyAt(ROUND, 0);
    const at = spawn(toy);
    expect(box.view().toy).toEqual({ n: 0, id: toy, rot: 0, x: at.x, y: at.y });
    box.step(START + 999);
    expect(box.view().toy?.y).toBe(at.y);
    box.step(START + 1000);
    expect(box.view().toy?.y).toBe(at.y - 1);
    box.step(START + 3000);
    expect(box.view().toy?.y).toBe(at.y - 3);
  });

  test("moves and turns at once, sends the latest position, and a drop sets down at once", () => {
    const { box, sent } = setup();
    box.step(START);
    const at = spawn(toyAt(ROUND, 0));
    box.move(-1);
    expect(box.view().toy?.x).toBe(at.x - 1);
    expect(sent.at(-1)).toEqual([["m", 0, 0, at.x - 1, at.y]]);
    box.move(-1);
    box.turn(1);
    const t = box.view().toy!;
    expect(sent.length).toBe(1);
    box.step(START + 50);
    expect(sent.at(-1)).toEqual([["m", 0, t.rot, t.x, t.y]]);
    const landing = box.view().landing;
    box.drop();
    const last = sent.at(-1)!;
    expect(last.at(-1)).toEqual(["l", 0, t.rot, t.x, landing, 50, []]);
    expect(box.view().box.next).toBe(1);
    expect(box.view().toy?.n).toBe(1);
  });

  test("a toy that can't fall sets down 500 ms later, and a move restarts the wait", () => {
    const { box, sent } = setup();
    box.step(START);
    box.soft(true);
    let now = START;
    while (box.view().toy && box.view().toy!.y > box.view().landing) box.step((now += 40));
    box.soft(false);
    const rested = now;
    box.step(rested + 400);
    box.move(1);
    box.step(rested + 800);
    expect(box.view().box.next).toBe(0);
    box.step(rested + 400 + 500);
    expect(box.view().box.next).toBe(1);
    expect(sent.flat().some((e) => e[0] === "l")).toBe(true);
  });

  test("junk is acked at once, waits 2000 ms from the ack, and lands at the first set-down after that", () => {
    const { box, sent } = setup();
    box.step(START);
    box.hit(junk(7, 2, 4));
    expect(sent.at(-1)).toEqual([["a", 7]]);
    expect(box.view().waiting).toEqual([{ id: 7, rows: 2, leftMs: 2000 }]);
    box.step(START + 1000);
    expect(box.view().waiting[0]?.leftMs).toBe(1000);
    box.drop();
    expect(sent.at(-1)!.at(-1)!.slice(0, 2)).toEqual(["l", 0]);
    expect((sent.at(-1)!.at(-1) as ClientEvent)[6]).toEqual([]);
    box.step(START + 2000);
    box.drop();
    const l = sent.at(-1)!.at(-1) as ClientEvent;
    expect(l[0]).toBe("l");
    expect(l[6]).toEqual([7]);
    expect(box.view().waiting).toEqual([]);
    // Two junk rows came in under the stack, with the gap at column 4.
    const b = box.view().box;
    expect(b.cells[4]).toBe(0);
    expect(b.cells[0]).toBe(10);
    expect(b.cells[W + 4]).toBe(0);
  });

  test("junk waits through a set-down that clears rows, and lands at the next one that clears nothing", () => {
    const { box, sent } = setup();
    box.step(START);
    // Row 0 full but for the columns the first toy fills when dropped straight down.
    const toy = toyAt(ROUND, 0);
    const at = spawn(toy);
    const low = Math.min(...toyCells(toy, 0).map(([, y]) => y));
    const gaps = new Set(toyCells(toy, 0).filter(([, y]) => y === low).map(([x]) => at.x + x));
    const start: Box = newBox(TRICKS);
    for (let x = 0; x < W; x++) if (!gaps.has(x)) start.cells[x] = 10;
    box.sync({ s: 1, box: start, q: 0, waitingLeft: [], catnipLeft: 0, napLeft: 0, status: "ok" }, START);
    box.hit(junk(3));
    box.step(START + 2500);
    expect(fits(box.view().box, toy, 0, at.x, at.y)).toBe(true);
    box.drop();
    const first = sent.at(-1)!.at(-1) as ClientEvent;
    expect(first[6]).toEqual([]);
    expect(box.view().box.rows).toBe(1);
    expect(box.view().waiting.length).toBe(1);
    box.drop();
    expect((sent.at(-1)!.at(-1) as ClientEvent)[6]).toEqual([3]);
  });

  test("a trick hit applies at once and is acked; Catnip makes toys fall 4 times as fast for 10 s", () => {
    const { box, sent } = setup();
    box.step(START);
    const y0 = box.view().toy!.y;
    box.hit({ t: "tumbleHit", r: 2, id: 12, from: 0, to: 1, k: "catnip" });
    expect(sent.at(-1)).toEqual([["a", 12]]);
    box.step(START + 250);
    expect(box.view().toy!.y).toBe(y0 - 1);
    expect(box.view().catnipLeft).toBe(9750);
    box.hit({ t: "tumbleHit", r: 2, id: 13, from: 0, to: 1, k: "hairball", x: { gap: 5 } });
    expect(box.view().box.cells.slice(0, W).filter((c) => c === 10).length).toBe(11);
  });

  test("a trick it holds is used at once: it leaves the tray and `u` goes out", () => {
    const { box, sent } = setup();
    box.step(START);
    const held: Box = { ...newBox(TRICKS), held: ["hairball", "nap"] };
    box.sync({ s: 1, box: held, q: 0, waitingLeft: [], catnipLeft: 0, napLeft: 0, status: "ok" }, START);
    box.use(1, 1);
    expect(sent.at(-1)).toEqual([["u", 1, 1]]);
    expect(box.view().box.held).toEqual(["hairball"]);
    box.use(4, 0);
    expect(sent.at(-1)).toEqual([["u", 1, 1]]);
  });

  test("a hidden tab stops the box until a sync, which starts the toy in hand at the top", () => {
    const { box } = setup();
    box.step(START);
    box.step(START + 3000);
    const y = box.view().toy!.y;
    box.hide();
    expect(box.stale).toBe(true);
    box.step(START + 9000);
    expect(box.view().toy!.y).toBe(y);
    box.sync({ s: 1, box: newBox(TRICKS), q: 4, waitingLeft: [1500], catnipLeft: 0, napLeft: 0, status: "ok" }, START + 9000);
    expect(box.stale).toBe(false);
    expect(box.view().toy!.y).toBe(spawn(toyAt(ROUND, 0)).y);
    box.step(START + 10_000);
    expect(box.view().toy!.y).toBe(spawn(toyAt(ROUND, 0)).y - 1);
  });

  test("a box that goes out stops: no toy, nothing more sent", () => {
    const { box, sent } = setup();
    box.step(START);
    let now = START;
    for (let i = 0; i < 200 && !box.view().box.out; i++) {
      box.drop();
      box.step((now += 10));
    }
    expect(box.view().box.out).toBe(true);
    expect(box.view().toy).toBeNull();
    const n = sent.length;
    box.move(1);
    box.drop();
    box.step(now + 5000);
    expect(sent.length).toBe(n);
  });
});
