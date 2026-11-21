/**
 * Box Fort's pieces: our own set of box shapes. Pieces never rotate, so each way a shape can face
 * is a piece of its own. A cell is `[row, col]` from the top-left of the piece's bounding box.
 *
 * Tiers set how often a level deals a shape: 0 easy, 1 medium, 2 awkward (`maker.ts`).
 */
export type Cell = [number, number];
export type Shape = { id: string; tier: 0 | 1 | 2; cells: Cell[] };

/** A piece as dealt: its shape's id, the tint its boxes are drawn in (1 to 6), and its cells. */
export type Piece = { id: string; tint: number; cells: Cell[] };

/** Cells from a little picture: "#" is a box, rows split by "/". */
function cells(picture: string): Cell[] {
  return picture.split("/").flatMap((row, r) => [...row].flatMap((ch, c): Cell[] => (ch === "#" ? [[r, c]] : [])));
}

const s = (id: string, tier: Shape["tier"], picture: string): Shape => ({ id, tier, cells: cells(picture) });

export const SHAPES: readonly Shape[] = [
  // Easy
  s("dot", 0, "#"),
  s("duo-h", 0, "##"),
  s("duo-v", 0, "#/#"),
  s("trio-h", 0, "###"),
  s("trio-v", 0, "#/#/#"),
  s("sq2", 0, "##/##"),
  s("nook-a", 0, "##/#."),
  s("nook-b", 0, "##/.#"),
  s("nook-c", 0, "#./##"),
  s("nook-d", 0, ".#/##"),
  // Medium
  s("quad-h", 1, "####"),
  s("quad-v", 1, "#/#/#/#"),
  s("rect-h", 1, "###/###"),
  s("rect-v", 1, "##/##/##"),
  s("ell-a", 1, "#./#./##"),
  s("ell-b", 1, ".#/.#/##"),
  s("ell-c", 1, "##/#./#."),
  s("ell-d", 1, "##/.#/.#"),
  s("ell-e", 1, "###/#.."),
  s("ell-f", 1, "###/..#"),
  s("ell-g", 1, "#../###"),
  s("ell-h", 1, "..#/###"),
  s("tee-up", 1, ".#./###"),
  s("tee-down", 1, "###/.#."),
  s("tee-left", 1, ".#/##/.#"),
  s("tee-right", 1, "#./##/#."),
  // Awkward
  s("five-h", 2, "#####"),
  s("five-v", 2, "#/#/#/#/#"),
  s("sq3", 2, "###/###/###"),
  s("zig-h", 2, "##./.##"),
  s("zag-h", 2, ".##/##."),
  s("zig-v", 2, "#./##/.#"),
  s("zag-v", 2, ".#/##/#."),
  s("big-a", 2, "###/#../#.."),
  s("big-b", 2, "###/..#/..#"),
  s("big-c", 2, "#../#../###"),
  s("big-d", 2, "..#/..#/###"),
  s("plus", 2, ".#./###/.#."),
  s("paws-a", 2, "#./.#"),
  s("paws-b", 2, ".#/#."),
];

const BY_ID = new Map(SHAPES.map((sh) => [sh.id, sh]));

export function shape(id: string): Shape {
  const found = BY_ID.get(id);
  if (!found) throw new RangeError(`no Box Fort shape ${id}`);
  return found;
}
