import { describe, expect, test } from "vitest";

import { Motion, type Pose } from "../src/table/motion";

/** A stand-in element: records each animation's keyframes. */
function el() {
  const made: Keyframe[][] = [];
  const node = {
    style: {} as Record<string, string>,
    animate: (frames: Keyframe[]) => {
      made.push(frames);
      return { finished: Promise.resolve(), cancel: () => undefined } as unknown as Animation;
    },
    getAnimations: () => [] as Animation[],
  };
  return { node: node as unknown as HTMLElement, made };
}

describe("cards that come onto the table from nowhere", () => {
  test("a view's cards, all new at once (a Cards/Table switch, a new turn's view, a fresh hand), show at their size with no animation", () => {
    const motion = new Motion(() => false);
    const els = new Map<string, HTMLElement>();
    const poses = new Map<string, Pose>();
    const made: Keyframe[][][] = [];
    for (let i = 0; i < 5; i++) {
      const e = el();
      els.set(`c${i}`, e.node);
      poses.set(`c${i}`, { x: i * 40, y: 500, s: 1 });
      made.push(e.made);
    }
    motion.apply(els, poses);
    expect(made.flat()).toEqual([]);
  });

  test("one card alone is just there too, whole: never smaller, never see-through", () => {
    const motion = new Motion(() => false);
    const a = el();
    motion.apply(new Map([["c1", a.node]]), new Map([["c1", { x: 0, y: 0, s: 1 }]]));
    const b = el();
    motion.apply(new Map([["c1", a.node], ["c2", b.node]]), new Map([["c1", { x: 0, y: 0, s: 1 }], ["c2", { x: 40, y: 0, s: 1 }]]));
    expect([...a.made, ...b.made]).toEqual([]);
  });

  test("with reduced motion a card goes to its new place at once, with no fade", () => {
    const motion = new Motion(() => true);
    const a = el();
    motion.apply(new Map([["c1", a.node]]), new Map([["c1", { x: 0, y: 0, s: 1 }]]));
    motion.apply(new Map([["c1", a.node]]), new Map([["c1", { x: 80, y: 0, s: 1 }]]));
    expect(a.made).toEqual([]);
  });

  test("a card from somewhere (the deck) still flies from there", () => {
    const motion = new Motion(() => false);
    const a = el();
    motion.spawnFrom("c1", { x: 100, y: 100, s: 0.7 });
    motion.apply(new Map([["c1", a.node]]), new Map([["c1", { x: 0, y: 400, s: 1 }]]));
    expect(a.made).toHaveLength(1);
    expect(a.made[0]![0]!.transform).toContain("scale(0.700)");
  });
});
