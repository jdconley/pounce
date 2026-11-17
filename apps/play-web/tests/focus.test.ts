import { describe, expect, test } from "vitest";

import { nearest, type Rect } from "../src/ui/tv/focus";

const box = (left: number, top: number, width = 100, height = 100): Rect => ({ left, top, width, height });

/**
 *   a  b  c
 *   d  e  f
 *   g  h  i      (100 px boxes on a 200 px grid)
 */
const grid = ["a", "b", "c", "d", "e", "f", "g", "h", "i"].map((id, n) => ({ id, rect: box((n % 3) * 200, Math.floor(n / 3) * 200) }));
const from = (id: string) => grid.find((c) => c.id === id)!.rect;
const others = (id: string) => grid.filter((c) => c.id !== id);

describe("d-pad focus: the nearest thing in a direction", () => {
  test("each of the four directions from the middle", () => {
    expect(nearest(from("e"), others("e"), "up")).toBe("b");
    expect(nearest(from("e"), others("e"), "down")).toBe("h");
    expect(nearest(from("e"), others("e"), "left")).toBe("d");
    expect(nearest(from("e"), others("e"), "right")).toBe("f");
  });

  test("nothing in that direction is null", () => {
    expect(nearest(from("a"), others("a"), "up")).toBeNull();
    expect(nearest(from("a"), others("a"), "left")).toBeNull();
    expect(nearest(from("i"), others("i"), "down")).toBeNull();
    expect(nearest(from("i"), others("i"), "right")).toBeNull();
    expect(nearest(box(0, 0), [], "right")).toBeNull();
  });

  test("only what lies past the edge in that direction counts", () => {
    // Beside, not below: a wide button's neighbour at the same height is not "down".
    expect(nearest(box(0, 0, 300, 100), [{ id: "side", rect: box(320, 0) }], "down")).toBeNull();
    // An overlapping box is not past the edge.
    expect(nearest(box(0, 0), [{ id: "over", rect: box(50, 50) }], "right")).toBeNull();
  });

  test("off-axis distance weighs double", () => {
    const candidates = [
      // 300 straight right.
      { id: "far-straight", rect: box(400, 0) },
      // 200 right but 120 down: 200 + 2 * 120 = 440, beaten by 300 straight.
      { id: "near-skew", rect: box(300, 120) },
    ];
    expect(nearest(box(100, 0), candidates, "right")).toBe("far-straight");
    // Less skew wins: 200 + 2 * 40 = 280 beats 300.
    expect(nearest(box(100, 0), [candidates[0], { id: "slight", rect: box(300, 40) }], "right")).toBe("slight");
  });

  test("a tie goes to the first candidate, in document order", () => {
    const above = { id: "above", rect: box(200, -100) };
    const below = { id: "below", rect: box(200, 100) };
    expect(nearest(box(0, 0), [above, below], "right")).toBe("above");
    expect(nearest(box(0, 0), [below, above], "right")).toBe("below");
  });
});
