import { describe, expect, test } from "vitest";

import { bwLayout, MIN_SHOW, type BwLayout } from "../src/table/bw-layout";
import { othersInOrder } from "../src/table/bw-model";

import type { Rect } from "../src/table/drag";

const NONE = { top: 0, right: 0, bottom: 0, left: 0 };
const PHONE = { top: 47, right: 0, bottom: 34, left: 0 };
const SCREENS: [string, number, number, typeof NONE][] = [
  ["iPhone SE", 320, 568, NONE],
  ["iPhone 15", 393, 852, PHONE],
  ["phone sideways", 852, 393, { top: 0, right: 47, bottom: 21, left: 47 }],
  ["iPad portrait", 768, 1024, NONE],
  ["iPad sideways", 1024, 768, NONE],
  ["laptop", 1440, 900, NONE],
  ["monitor", 2560, 1440, NONE],
];

const overlaps = (a: Rect, b: Rect, slack = 0) => a.x + slack < b.x + b.w && b.x + slack < a.x + a.w && a.y + slack < b.y + b.h && b.y + slack < a.y + a.h;
/** A card's box at its pose: a scaled card shrinks about its centre. */
const cardBox = (L: BwLayout, p: { x: number; y: number; s?: number }): Rect => {
  const s = p.s ?? 1;
  return { x: p.x + (L.cw * (1 - s)) / 2, y: p.y + (L.ch * (1 - s)) / 2, w: L.cw * s, h: L.ch * s };
};

function layoutFor(W: number, H: number, insets: typeof NONE, seats: number, hand: number, extra: Partial<Parameters<typeof bwLayout>[0]> = {}) {
  return bwLayout({ width: W, height: H, insets, me: 0, others: othersInOrder({ seats }, 0), hand, ...extra });
}

describe("the Birdwatch table fits every screen", () => {
  for (const [name, W, H, insets] of SCREENS) {
    for (const seats of [4, 5, 6]) {
      for (const hand of [9, 10, 15, 17]) {
        test(`${name}, ${seats} players, ${hand} cards`, () => {
          const L = layoutFor(W, H, insets, seats, hand);
          // Every card on screen, clear of the safe areas (a fan's tilt may graze the side by a few px).
          for (const p of L.hand) {
            const b = cardBox(L, p);
            expect(b.x).toBeGreaterThanOrEqual(insets.left - 6);
            expect(b.x + b.w).toBeLessThanOrEqual(W - insets.right + 6);
            expect(b.y + b.h).toBeLessThanOrEqual(H - insets.bottom + 4);
          }
          // Each card's corner shows under the next in its row.
          const rows = new Map<number, number[]>();
          for (const p of L.hand) rows.set(Math.round(p.y / 20), [...(rows.get(Math.round(p.y / 20)) ?? []), p.x]);
          for (const xs of rows.values()) {
            const sorted = [...xs].sort((a, b) => a - b);
            for (let i = 1; i < sorted.length; i++) expect(sorted[i]! - sorted[i - 1]!).toBeGreaterThanOrEqual(MIN_SHOW - 6);
          }
          // Seats never overlap each other, the paw, the strip or the panel.
          const rects = [...L.seatRects.values()];
          for (let i = 0; i < rects.length; i++) {
            for (let j = i + 1; j < rects.length; j++) expect(overlaps(rects[i]!, rects[j]!, 4), `seats ${i} and ${j}`).toBe(false);
            expect(overlaps(rects[i]!, L.panel), `seat ${i} and the panel`).toBe(false);
            expect(overlaps(rects[i]!, L.strip), `seat ${i} and the strip`).toBe(false);
          }
          // The sill has room for a trick, and its cards stay inside it.
          expect(L.sill.w).toBeGreaterThan(L.cw * L.sillScale * 1.4);
          expect(L.sill.h).toBeGreaterThan(L.ch * L.sillScale * 1.4);
          for (const p of L.slots.values()) {
            const b = cardBox(L, p);
            expect(b.x).toBeGreaterThanOrEqual(L.sill.x - 2);
            expect(b.x + b.w).toBeLessThanOrEqual(L.sill.x + L.sill.w + 2);
          }
          // The strip and the panel sit above the hand.
          expect(L.panel.y + L.panel.h).toBeLessThanOrEqual(L.handRect.y + 2);
          expect(L.strip.y + L.strip.h).toBeLessThanOrEqual(L.panel.y + 2);
          expect(L.panel.h).toBeGreaterThanOrEqual(90);
        });
      }
    }
  }

  test("17 cards on a 320 px phone go in two rows, big enough to read", () => {
    const L = layoutFor(320, 568, NONE, 5, 17);
    expect(new Set(L.hand.map((p) => Math.round(p.y / 20))).size).toBeGreaterThanOrEqual(2);
    expect(L.cw).toBeGreaterThanOrEqual(48);
  });

  test("a TV places every seat, with the strip on top and the banner at the foot", () => {
    for (const seats of [4, 5, 6]) {
      const L = bwLayout({ width: 1920, height: 1080, insets: NONE, me: null, others: othersInOrder({ seats }, null), hand: 0, tv: true });
      expect(L.seats.size).toBe(seats);
      expect(L.slots.size).toBe(seats);
      const rects = [...L.seatRects.values()];
      for (let i = 0; i < rects.length; i++) {
        for (let j = i + 1; j < rects.length; j++) expect(overlaps(rects[i]!, rects[j]!)).toBe(false);
        expect(overlaps(rects[i]!, L.sill)).toBe(false);
        expect(overlaps(rects[i]!, L.banner)).toBe(false);
        expect(overlaps(rects[i]!, L.strip)).toBe(false);
      }
      expect(L.cw * L.sillScale).toBeGreaterThanOrEqual(84);
    }
  });

  test("the Cards view gives the hand the screen", () => {
    const L = layoutFor(393, 852, PHONE, 4, 10, { cards: true });
    expect(L.seats.size).toBe(0);
    expect(L.cw).toBeGreaterThan(layoutFor(393, 852, PHONE, 4, 10).cw);
    expect(L.panel.y + L.panel.h).toBeLessThanOrEqual(L.handRect.y + 2);
  });
});
