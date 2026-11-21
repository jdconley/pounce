import { readdirSync, readFileSync } from "node:fs";

import { describe, expect, test } from "vitest";

import { boxFortLayout, lifted, slotAt, snap, trayOrigin, TRAY_SCALE, type Box } from "../src/daily/box-fort/layout";
import { fitsBySlot, placePiece, receiveReveal, resync, startPlay } from "../src/daily/box-fort/model";
import { onRunEvent, placement, playFor } from "../src/daily/box-fort/session";

import type { BoxFortPublicPuzzle, BoxFortPublicState, BoxFortReveal } from "@pounce/play-api/daily/box-fort/module";
import type { Piece } from "@pounce/play-api/daily/box-fort/pieces";

const piece = (picture: string, tint = 1): Piece => ({
  id: picture,
  tint,
  cells: picture.split("/").flatMap((line, r) => [...line].flatMap((ch, c): [number, number][] => (ch === "#" ? [[r, c]] : []))),
});
const EMPTY = Array<number>(64).fill(0);
const inside = (a: Box, b: Box) => a.x >= b.x - 0.5 && a.y >= b.y - 0.5 && a.x + a.w <= b.x + b.w + 0.5 && a.y + a.h <= b.y + b.h + 0.5;
const meets = (a: Box, b: Box) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;

describe("layout", () => {
  test.each([
    [320, 480],
    [375, 583],
    [440, 796],
    [820, 1092],
    [1180, 732],
    [1920, 1000],
  ])("%s by %s fits, the rug square, the tray clear of it", (w, h) => {
    const l = boxFortLayout(w, h);
    const bounds = { x: 0, y: 0, w, h };
    expect(l.rug.w).toBeCloseTo(8 * l.cell);
    expect(l.rug.w).toBe(l.rug.h);
    expect(inside(l.rug, bounds) && inside(l.header, bounds)).toBe(true);
    for (const s of l.slots) {
      expect(inside(s, bounds)).toBe(true);
      expect(meets(s, l.rug) || meets(s, l.header)).toBe(false);
      expect(Math.min(s.w, s.h)).toBeGreaterThanOrEqual(5 * l.trayCell);
    }
    expect(l.sideTray).toBe(w > h * 1.15);
  });

  test("snap rounds to the nearest spot and refuses hanging off the rug (as on iOS)", () => {
    const l = boxFortLayout(400, 700);
    const c = l.cell;
    const { x, y } = l.rug;
    const sq2 = { rows: 2, cols: 2 };
    expect(snap(l, { x: x + 3.4 * c, y: y + 4.6 * c }, sq2)).toEqual({ row: 5, col: 3 });
    expect(snap(l, { x: x - 0.4 * c, y: y - 0.4 * c }, sq2)).toEqual({ row: 0, col: 0 });
    expect(snap(l, { x: x - 0.6 * c, y }, sq2)).toBeNull();
    expect(snap(l, { x: x + 6 * c, y: y + 6 * c }, sq2)).toEqual({ row: 6, col: 6 });
    expect(snap(l, { x: x + 6.6 * c, y: y + 6 * c }, sq2)).toBeNull();
  });

  test("the lifted piece floats above the finger, centered", () => {
    const l = boxFortLayout(375, 583);
    const o = lifted(l, { x: 180, y: 400 }, { rows: 3, cols: 1 });
    expect(o.y + 3 * l.cell).toBeLessThan(400);
    expect(o.x + l.cell / 2).toBeCloseTo(180);
  });

  test("tray pieces sit centered in their slots, and a point finds its slot", () => {
    const l = boxFortLayout(375, 583);
    const o = trayOrigin(l, 1, { rows: 1, cols: 4 });
    expect(o.x + 2 * l.trayCell).toBeCloseTo(l.slots[1]!.x + l.slots[1]!.w / 2);
    expect(l.trayCell).toBeCloseTo(l.cell * TRAY_SCALE);
    expect(slotAt(l, { x: l.slots[2]!.x + 2, y: l.slots[2]!.y + 2 })).toBe(2);
    expect(slotAt(l, { x: l.rug.x + 2, y: l.rug.y + 2 })).toBeNull();
  });
});

describe("the play model", () => {
  const dots = [piece("#", 1), piece("#", 2), piece("#", 3)];

  test("a placement scores at once and waits for the next set after the third", () => {
    const start: BoxFortPublicPuzzle = { rug: EMPTY, sets: 2, pieces: dots };
    let play = startPlay(start);
    expect(play.fits).toEqual([true, true, true]);
    play = placePiece(play, 0, 0, 0)!;
    expect(play.state.points).toBe(1);
    expect(play.gain).toMatchObject({ points: 1, at: { x: 0.5, y: 0.5 } });
    expect(placePiece(play, 0, 1, 1)).toBeNull(); // already placed
    expect(placePiece(play, 1, 0, 0)).toBeNull(); // on a box
    play = placePiece(placePiece(play, 1, 0, 1)!, 2, 0, 2)!;
    expect(play.waiting).toBe(true);
    expect(placePiece(play, 0, 5, 5)).toBeNull();
    const reveal: BoxFortReveal = { set: 1, pieces: [piece("##", 4), piece("#", 5), piece("#", 6)] };
    expect(receiveReveal(play, { ...reveal, set: 2 })).toBe(play); // not the next set
    play = receiveReveal(play, reveal);
    expect(play.waiting).toBe(false);
    expect(play.state.set).toBe(1);
    expect(play.state.pieces).toEqual(reveal.pieces);
    expect(play.dealt).toBe(1);
  });

  test("the last set placed is the full fort, with no wait", () => {
    let play = startPlay({ rug: EMPTY, sets: 1, pieces: dots });
    for (const slot of [0, 1, 2]) play = placePiece(play, slot, 3, slot)!;
    expect(play.waiting).toBe(false);
    expect(play.state.over).toBe("full");
    expect(play.state.points).toBe(203);
  });

  test("a clear bursts the boxes as they were when the piece landed", () => {
    const rug = [...EMPTY];
    for (let col = 0; col < 7; col++) rug[col] = 7;
    const play = placePiece(startPlay({ rug, sets: 3, pieces: dots }), 2, 0, 7)!;
    expect(play.burst?.lines).toBe(1);
    expect(play.burst?.boxes).toHaveLength(8);
    expect(play.burst?.boxes).toContainEqual([7, 3]);
    expect(play.state.rug.every((v) => v === 0)).toBe(true);
  });

  test("fitsBySlot dims only stuck pieces; resync takes the server's state", () => {
    const rug = Array<number>(64).fill(7);
    rug[0] = 0;
    const state: BoxFortPublicState = { rug, set: 0, sets: 2, pieces: [piece("#"), piece("##"), piece("#/#")], placed: [false, true, false], points: 0, combo: 0, lines: 0, over: null };
    expect(fitsBySlot(state)).toEqual([true, true, false]);
    const play = resync(startPlay({ rug: EMPTY, sets: 2, pieces: dots }), state);
    expect(play.state).toBe(state);
    expect(play.waiting).toBe(false);
  });

  test("the golden vectors play the same in the web model", () => {
    const dir = new URL("../../play-api/fixtures/daily/box-fort/", import.meta.url);
    for (const file of readdirSync(dir).filter((f) => f.endsWith(".json"))) {
      const v = JSON.parse(readFileSync(new URL(file, dir), "utf8")) as {
        start: BoxFortPublicPuzzle;
        steps: { move: { slot: number; row: number; col: number }; ok: boolean; reveal: BoxFortReveal | null; state: BoxFortPublicState }[];
      };
      let play = startPlay(v.start);
      for (const step of v.steps) {
        const next = placePiece(play, step.move.slot, step.move.row, step.move.col);
        if (!step.ok) {
          expect(next, file).toBeNull();
          continue;
        }
        play = next!;
        if (step.reveal) play = receiveReveal(play, step.reveal);
        expect(play.state, file).toEqual(step.state);
      }
    }
  });
});

describe("the run wiring", () => {
  const dots = [piece("#", 1), piece("#", 2), piece("#", 3)];
  const puzzle: BoxFortPublicPuzzle = { rug: EMPTY, sets: 2, pieces: dots };

  test("a resumed run draws from the server's state", () => {
    const state: BoxFortPublicState = { ...startPlay(puzzle).state, placed: [true, false, false], points: 1 };
    expect(playFor(puzzle, state).state).toEqual(state);
  });

  test("only the last piece of a set, or of the run, goes at once", () => {
    let play = playFor(puzzle, startPlay(puzzle).state);
    const first = placement(play, 0, 0, 0)!;
    expect(first).toMatchObject({ move: { k: "place", slot: 0, row: 0, col: 0 }, urgent: false });
    play = placement(first.play, 1, 0, 1)!.play;
    const third = placement(play, 2, 0, 2)!;
    expect(third.urgent).toBe(true);
    expect(placement(third.play, 0, 5, 5)).toBeNull(); // waiting for the next set
    const dealt = onRunEvent(third.play, { kind: "accepted", reveals: [{ set: 1, pieces: dots }] });
    expect(dealt.waiting).toBe(false);
    let last = dealt;
    for (const slot of [0, 1]) last = placement(last, slot, 4, slot)!.play;
    const end = placement(last, 2, 4, 2)!;
    expect(end.urgent).toBe(true);
    expect(end.play.state.over).toBe("full");
  });

  test("a resync takes over, other answers change nothing", () => {
    const play = playFor(puzzle, startPlay(puzzle).state);
    const server: BoxFortPublicState = { ...play.state, points: 9 };
    expect(onRunEvent(play, { kind: "resync", state: server }).state).toBe(server);
    expect(onRunEvent(play, { kind: "link" })).toBe(play);
    expect(onRunEvent(play, { kind: "accepted", reveals: [] })).toBe(play);
  });
});
