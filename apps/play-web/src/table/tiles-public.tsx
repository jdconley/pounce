/**
 * The Tuna Tiles table as anyone at it may see it: the seats, the rope, the toy box and the sets.
 * While a player arranges their turn, the sets are theirs as they stand (their aim), with the
 * pieces they are adding marked. The phone's full table draws this with its own draft and rack
 * (tiles.tsx); a TV draws this alone. It is drawn into the caller's `.tt-table` (`tilesStyle`).
 */
import { useEffect, useLayoutEffect, useRef } from "preact/hooks";

import { art } from "../lib/art";
import { buzz } from "../lib/haptics";
import { play } from "../lib/sound";

import { PieceFace, pieceLabel } from "./faces";
import { transformOf, type Motion, type Pose } from "./motion";
import { seatName, SeatAvatar } from "./seat";
import { ghostOf } from "./tiles-draft";

import type { TilesLayout } from "./tiles-layout";
import type { RoomStore } from "../store/room";
import type { GameAim, RoomView } from "@pounce/play-api/protocol";
import type { TileId } from "@pounce/play-api/tiles/pieces";
import type { TilesView } from "@pounce/play-api/tiles/view";
import type { ComponentChildren, VNode } from "preact";

/** What a held piece is over: a set, a new set, a place in the rack. */
export type TilesHover = { kind: "set"; set: number; index: number } | { kind: "new" } | { kind: "rack"; index: number } | null;

/** How a piece shows: the number a Yarn stands for in its set, and whether it is new in an aim. */
export type PieceLook = { ghost: number | null; draft: boolean };

/**
 * A rack drawn on the table: its pieces' poses, and how every piece is drawn (on a phone, the
 * table's pieces can be the player's to move too). One set of moving pieces, so a piece goes from
 * the rack to a set in one move.
 */
export type TilesHand = {
  poses: Map<string, Pose>;
  els: Map<string, HTMLElement>;
  render: (id: TileId, pose: Pose, ref: (el: HTMLElement | null) => void, look: PieceLook) => VNode;
};

/** The sizes the table's CSS reads, for the `.tt-table` it is drawn into. */
export const tilesStyle = (L: TilesLayout) => ({ ["--pw" as string]: `${L.pw}px`, ["--ph" as string]: `${L.ph}px`, ["--avatar" as string]: `${L.avatar}px` });

/** The sets on show: this device's own draft, else the acting player's aim, else the table as played. */
export function tilesShown(v: TilesView, aims: Record<number, GameAim>, draft?: TileId[][]): TileId[][] {
  if (draft) return draft;
  const aim = v.status === "playing" ? aims[v.turn] : undefined;
  return aim && "table" in aim ? aim.table : v.table;
}

export function TilesPublic(props: {
  store: RoomStore;
  room: RoomView;
  layout: TilesLayout;
  motion: Motion;
  aims: Record<number, GameAim>;
  /** This device's own arrangement of the table, shown instead of anyone's aim. */
  draft?: TileId[][];
  /** Each set's check while drafting: good, bad or kept. */
  marks?: (string | undefined)[];
  sounds?: boolean;
  /** The seats this device holds (none for a spectator); absent on a TV. */
  mine?: number[];
  /** Each seat's score under its name. */
  scores?: boolean;
  hand?: TilesHand;
  hover?: TilesHover;
  setsFocusable?: boolean;
  onSet?: (set: number) => void;
  /** The line under the sets; by default whose turn it is. */
  cue?: { text: string; mine: boolean };
  /** Drawn under the pieces: the hand layer's new-set target. */
  under?: ComponentChildren;
  /** Drawn over the pieces: the hand layer's controls, curtain and tips. */
  children?: ComponentChildren;
}) {
  const { store, room, layout: L, motion, aims, hover = null } = props;
  const v = room.tiles as TilesView;
  const sounds = props.sounds ?? true;
  const mine = props.mine ?? [];
  const sound: typeof play = (...a) => {
    if (sounds) play(...a);
  };
  const ownEls = useRef(new Map<string, HTMLElement>());
  const els = props.hand?.els ?? ownEls.current;
  const table = tilesShown(v, aims, props.draft);
  const onTable = new Set(v.table.flat());
  const fromAim = props.draft === undefined && table !== v.table;

  const avatarPose = (s: number): Pose => {
    const at = L.opponents.get(s) ?? { x: L.board.x + L.board.w / 2, y: -40 };
    return { x: at.x - L.pw / 2, y: at.y - L.ph / 2, r: 0, s: 0.4 };
  };
  const poolPose: Pose = { x: L.pool.x + L.pool.size / 2 - L.pw / 2, y: L.pool.y + L.pool.size / 2 - L.ph / 2, r: 0, s: 0.5 };

  useEffect(
    () =>
      store.subscribe({
        event: ({ event: e }) => {
          if (e.kind !== "tiles") return;
          const ev = e.event;
          if (ev.kind === "drew") {
            sound("flip", 0.6);
            if (ev.tile !== undefined) motion.spawnFrom(`p${ev.tile}`, poolPose);
          } else if (ev.kind === "played") {
            if (!mine.includes(ev.seat)) for (const id of ev.placed) motion.spawnFrom(`p${id}`, avatarPose(ev.seat));
            sound("sparkle", 0.7);
            buzz("drop");
          } else if (ev.kind === "passed") {
            sound("tick", 0.5);
          } else if (ev.kind === "gameOver") {
            sound("fanfare");
            buzz("win");
          }
        },
      }),
    [store, L, mine.join(), sounds],
  );

  // Poses: the table's pieces, then the rack's.
  const poses = new Map<string, Pose>();
  table.forEach((set, si) =>
    set.forEach((id, i) => {
      const p = L.sets[si]?.poses[i];
      if (p) poses.set(`p${id}`, p);
    }),
  );
  for (const [key, p] of props.hand?.poses ?? []) poses.set(key, p);

  useLayoutEffect(() => {
    motion.apply(els, poses);
  });

  const setEl = (key: string) => (el: HTMLElement | null) => {
    if (el) els.set(key, el);
    else els.delete(key);
  };

  const cue = props.cue ?? { text: v.status === "playing" ? `${seatName(room.seats[v.turn])}'s turn` : "", mine: false };

  return (
    <>
      {[...L.opponents].map(([s, at]) => (
        <div class="avatar-at" style={{ transform: `translate3d(${at.x - L.avatar / 2}px, ${at.y - L.avatar / 2}px, 0)` }}>
          <SeatAvatar seat={s} info={room.seats[s]} size={L.avatar} turn={v.turn === s && v.status === "playing"} count={v.rackCounts[s]} score={props.scores ? v.scores[s] : undefined} out={v.forfeited[s]} />
        </div>
      ))}

      <div class="board" style={{ transform: `translate3d(${L.board.x}px, ${L.board.y}px, 0)`, width: `${L.board.w}px`, height: `${L.board.h}px` }} />
      <div class="pool" style={{ transform: `translate3d(${L.pool.x}px, ${L.pool.y}px, 0)`, width: `${L.pool.size}px` }} role="img" aria-label={`Toy box: ${v.poolCount} pieces`}>
        <img src={art(v.poolCount > 0 ? "toy-box" : "toy-box-closed")} alt="" />
        <span class="pile-count">{v.poolCount}</span>
      </div>

      {L.sets.map((set, si) => {
        const mark = props.marks?.[si];
        const h = hover?.kind === "set" && hover.set === si;
        const cls = `set-zone ${mark ?? ""} ${h ? "hot" : ""}`;
        const style = { transform: `translate3d(${set.rect.x - 4}px, ${set.rect.y - 4}px, 0)`, width: `${set.rect.w + 8}px`, height: `${set.rect.h + 8}px` };
        const name = `Set: ${(table[si] ?? []).map((id, i) => pieceLabel(id, ghostOf(table[si] ?? [], i) ?? undefined)).join(", ")}${mark === "bad" ? ". Not a set yet" : ""}`;
        const marked = mark === "good" ? <img class="mark" src={art("icon-check")} alt="" /> : mark === "bad" ? <span class="mark bad" /> : null;
        return props.onSet ? (
          <button type="button" class={cls} style={style} aria-label={name} tabIndex={props.setsFocusable ? 0 : -1} onClick={() => props.onSet!(si)}>
            {marked}
          </button>
        ) : (
          <div class={cls} style={style} role="img" aria-label={name}>
            {marked}
          </div>
        );
      })}

      {props.under}

      <div class="pieces">
        {[...poses].map(([key, p]) => {
          const id = Number(key.slice(1));
          const si = table.findIndex((set) => set.includes(id));
          const look: PieceLook = { ghost: si >= 0 ? ghostOf(table[si]!, table[si]!.indexOf(id)) : null, draft: fromAim && si >= 0 && !onTable.has(id) };
          if (props.hand) return props.hand.render(id, p, setEl(key), look);
          return (
            <div key={key} ref={setEl(key)} class={`tile ${look.draft ? "draft" : ""}`} style={{ transform: transformOf(p), zIndex: p.z ?? 1 }}>
              <div class="tile-inner" role="img" aria-label={pieceLabel(id, look.ghost ?? undefined)}>
                <PieceFace id={id} ghost={look.ghost} />
              </div>
            </div>
          );
        })}
      </div>

      {props.children}

      <p class={`cue ${cue.mine ? "mine" : ""}`} aria-live="polite" style={{ transform: `translate3d(-50%, ${L.board.y + L.board.h - 40}px, 0)` }}>
        {cue.text}
      </p>
    </>
  );
}
