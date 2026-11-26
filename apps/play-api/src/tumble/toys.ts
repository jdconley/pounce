/**
 * The nine Toy Tumble toys (spec §4.1): their cells, how they turn and where they appear. These
 * values are the contract with the app's Swift engine and the shared fixtures; change them only
 * together.
 */

export const TOY_IDS = ["i3", "v3", "i4", "o4", "t4", "l4", "j4", "p5", "u5"] as const;
export type ToyId = (typeof TOY_IDS)[number];
export type Rot = 0 | 1 | 2 | 3;
export type CellXY = readonly [number, number];

/** The box is 12 wide; toys appear with their lowest cells in this row (the first hidden one). */
const WIDTH = 12;
const SPAWN_ROW = 18;

/** Each toy's cells at rotation 0, x to the right and y up, inside a k by k box. */
const BASE: Record<ToyId, { k: number; cells: CellXY[] }> = {
  i3: { k: 3, cells: [[0, 1], [1, 1], [2, 1]] },
  v3: { k: 2, cells: [[0, 0], [0, 1], [1, 0]] },
  i4: { k: 4, cells: [[0, 2], [1, 2], [2, 2], [3, 2]] },
  o4: { k: 2, cells: [[0, 0], [1, 0], [0, 1], [1, 1]] },
  t4: { k: 3, cells: [[0, 1], [1, 1], [2, 1], [1, 2]] },
  l4: { k: 3, cells: [[0, 1], [1, 1], [2, 1], [2, 2]] },
  j4: { k: 3, cells: [[0, 1], [1, 1], [2, 1], [0, 2]] },
  p5: { k: 3, cells: [[1, 0], [0, 1], [1, 1], [2, 1], [1, 2]] },
  u5: { k: 3, cells: [[0, 0], [1, 0], [2, 0], [0, 1], [2, 1]] },
};

const turnOnce = (cells: readonly CellXY[], k: number): CellXY[] => cells.map(([x, y]) => [y, k - 1 - x] as const);

const TABLE: Record<ToyId, CellXY[][]> = Object.fromEntries(
  TOY_IDS.map((id) => {
    const { k, cells } = BASE[id];
    const rots: CellXY[][] = [cells];
    for (let r = 1; r < 4; r++) rots.push(turnOnce(rots[r - 1] as CellXY[], k));
    return [id, rots];
  }),
) as Record<ToyId, CellXY[][]>;

/** The toy's cells at `rot`, as offsets from its box's bottom-left corner. Clockwise turns keep the cell order. */
export const toyCells = (toy: ToyId, rot: Rot): readonly CellXY[] => TABLE[toy][rot] as CellXY[];

/** The side of the square box a toy turns in. */
export const boxSize = (toy: ToyId): number => BASE[toy].k;

export const TOY_INDEX: Record<ToyId, number> = Object.fromEntries(TOY_IDS.map((id, i) => [id, i])) as Record<ToyId, number>;

/** Where a new toy appears: rotation 0, centred (rounding left), lowest cells in row 18. */
export function spawn(toy: ToyId): { rot: 0; x: number; y: number } {
  const k = boxSize(toy);
  const low = Math.min(...toyCells(toy, 0).map(([, y]) => y));
  return { rot: 0, x: Math.floor((WIDTH - k) / 2), y: SPAWN_ROW - low };
}
