import { describe, expect, expectTypeOf, test } from "vitest";

import type { CtHandProps, CtPublic, CtTable } from "../src/table/ct-public";
import type { TilesHandProps, TilesPublic, TilesTableBase } from "../src/table/tiles-public";

/**
 * The TV draws `CtPublic` and `TilesPublic`: their props leave no room for a hand, a rack or a
 * move, so a hand can't reach a TV by mistake. Checked by the type checker (`pnpm typecheck`).
 */
type Ct = Parameters<typeof CtPublic>[0];
type Tiles = Parameters<typeof TilesPublic>[0];

describe("a TV's table takes no hand", () => {
  test("Cat Tower: no hand, no hover, no moves", () => {
    expectTypeOf<Ct[keyof CtHandProps]>().toEqualTypeOf<undefined>();
    const ok: Partial<Ct> = { sounds: false, haptics: false, scores: true };
    // @ts-expect-error a hand
    const hand: Partial<Ct> = { hand: { poses: new Map(), els: new Map(), render: () => null as never } };
    // @ts-expect-error a move
    const deck: Partial<Ct> = { onDeck: () => {} };
    // @ts-expect-error a target
    const group: Partial<Ct> = { onGroup: () => {}, hover: null };
    expect([ok, hand, deck, group]).toHaveLength(4);
    // The phone's table takes them.
    expectTypeOf<Parameters<typeof CtTable>[0]["onDeck"]>().toEqualTypeOf<(() => void) | undefined>();
  });

  test("Tuna Tiles: no rack, no draft, no moves", () => {
    expectTypeOf<Tiles[keyof TilesHandProps]>().toEqualTypeOf<undefined>();
    // @ts-expect-error a rack
    const hand: Partial<Tiles> = { hand: { poses: new Map(), els: new Map(), render: () => null as never } };
    // @ts-expect-error a draft
    const draft: Partial<Tiles> = { draft: [[1, 2, 3]] };
    // @ts-expect-error a move
    const set: Partial<Tiles> = { onSet: () => {} };
    expect([hand, draft, set]).toHaveLength(3);
    expectTypeOf<Parameters<typeof TilesTableBase>[0]["onSet"]>().toEqualTypeOf<((set: number) => void) | undefined>();
  });
});
