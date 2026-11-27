/**
 * Where a held card lands on the laid groups. One answer for the glow while it is held and for
 * the drop, so a group lit as a fit always takes the card. It forgives the hand: the card the
 * player sees counts, not only the point under their finger (laid cards are small, the held one
 * is big); a run takes the card on whichever end it fits; and a card that fits one place only goes
 * there from anywhere on the table. Pure: the table's layout and the rules come in as arguments.
 */
import { inside, type Point, type Rect } from "./drag";

import type { Pose } from "./motion";
import type { HitSide } from "@pounce/play-api/rules/groups";

/** A laid group on the table: whose, which, and where its drop rectangle is. */
export type GroupSpot = { seat: number; group: number; rect: Rect; run: boolean };

/** The group a held card would go on, and whether it can (a miss is shown, never sent). */
export type GroupDrop = { seat: number; group: number; side?: HitSide; ok: boolean };

/** How far past a group's edge the finger still counts as over it. */
const FINGER_PAD = 8;

/** The rectangle a card of `cw` by `ch` is drawn in at `pose` (scaled about its middle). */
export function heldRect(pose: Pose, cw: number, ch: number): Rect {
  const s = pose.s ?? 1;
  return { x: pose.x + (cw - cw * s) / 2, y: pose.y + (ch - ch * s) / 2, w: cw * s, h: ch * s };
}

const overlap = (a: Rect, b: Rect): number => Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)) * Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y));

/**
 * The group a card held at `card` (its drawn rectangle), with the finger at `finger`, goes on.
 * `sides` says where the card can be hit now on each group: a set or a coat `[undefined]`, a run
 * the ends it fits, `[]` where it can't. `onTable`: the finger is on the table, not on the hand.
 *
 * Of the groups under the finger or the card, the one it fits (the finger's first, then the one
 * the card covers most); else the one under the finger, as a miss. Over none, the one group the
 * card fits anywhere, if there is just one.
 */
export function groupDrop(o: { finger: Point; card: Rect; spots: GroupSpot[]; sides: (seat: number, group: number) => (HitSide | undefined)[]; onTable: boolean }): GroupDrop | null {
  const near = o.spots
    .map((spot) => ({ spot, under: inside(o.finger, spot.rect, FINGER_PAD), covered: overlap(o.card, spot.rect) }))
    .filter((n) => n.under || n.covered > 0)
    .sort((a, b) => Number(b.under) - Number(a.under) || b.covered - a.covered);
  const fit = near.find((n) => o.sides(n.spot.seat, n.spot.group).length > 0)?.spot;
  if (fit) return aimAt(fit, o.sides(fit.seat, fit.group), o.finger);
  const miss = near.find((n) => n.under)?.spot;
  if (miss) return { seat: miss.seat, group: miss.group, ok: false };
  if (!o.onTable) return null;
  const anywhere = o.spots.filter((spot) => o.sides(spot.seat, spot.group).length > 0);
  if (anywhere.length !== 1) return null;
  return aimAt(anywhere[0]!, o.sides(anywhere[0]!.seat, anywhere[0]!.group), o.finger);
}

/** On a group the card fits: the end it fits, or with both, the end nearer the finger. */
function aimAt(spot: GroupSpot, sides: (HitSide | undefined)[], finger: Point): GroupDrop {
  const at = { seat: spot.seat, group: spot.group, ok: true };
  const ends = sides.filter((s): s is HitSide => s !== undefined);
  if (!spot.run || ends.length === 0) return at;
  const side = ends.length === 1 ? ends[0]! : finger.x < spot.rect.x + spot.rect.w / 2 ? "start" : "end";
  return { ...at, side };
}
