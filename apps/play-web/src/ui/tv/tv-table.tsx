/**
 * The table on the TV: the public table in the big-screen layout (no hand, nothing to touch), the
 * turn banner in the seat's colour, a big moment when someone lays down, and game over. Read from
 * the couch: everything that matters is at least 28 px on a 1080p screen (tv.css).
 */
import { useEffect, useMemo, useState } from "preact/hooks";

import { art, RINGS } from "../../lib/art";
import { reducedMotion } from "../../lib/settings";
import { play } from "../../lib/sound";
import { bwLayout } from "../../table/bw-layout";
import { othersInOrder, RULE_COPY } from "../../table/bw-model";
import { BwPublic, bwStyle } from "../../table/bw-public";
import { ctLayout } from "../../table/ct-layout";
import { CtPublic, ctStyle } from "../../table/ct-public";
import { Motion } from "../../table/motion";
import { seatCat, seatName } from "../../table/seat";
import { tilesLayout } from "../../table/tiles-layout";
import { TilesPublic, tilesShown, tilesStyle } from "../../table/tiles-public";
import { isTumble } from "../../tumble/store";
import { TvTumble } from "../../tumble/tv";
import { Cat, useSize } from "../common";

import { momentFor, overTitle, standings, turnSeat, type Moment } from "./tv-model";

import type { RoomStore, RoomState } from "../../store/room";
import type { Rect } from "../../table/drag";
import type { RoomView } from "@pounce/play-api/protocol";

const NO_INSETS = { top: 0, right: 0, bottom: 0, left: 0 };
/** The public table's own cue is the phone's; the TV draws its banner instead. */
const NO_CUE = { text: "", mine: false, y: 0 };

type TableProps = { store: RoomStore; state: RoomState; offline: boolean };

/** The table as the TV draws it, for either game. */
export function TvTable(props: TableProps) {
  const room = props.state.room!;
  if (isTumble(room)) return <TvTumble {...props} />;
  if (room.gameId === "birdwatch") return room.birdwatch ? <TvBirdwatch {...props} /> : null;
  if (room.gameId === "tiles") return room.tiles ? <TvTiles {...props} /> : null;
  return room.game ? <TvCatTower {...props} /> : null;
}

function TvCatTower(props: TableProps) {
  const { store, state } = props;
  const room = state.room!;
  const g = room.game!;
  const [rootRef, size] = useSize<HTMLDivElement>();
  const motion = useMemo(() => new Motion(reducedMotion), []);
  const seats = room.seats.flatMap((s, i) => (s.kind === "human" || s.kind === "bot" ? [i] : []));
  const laid = g.laid.flatMap((groups, s) => (groups ? [{ seat: s, groups: groups.map((grp) => grp.cards.length) }] : []));
  const L = useMemo(
    () => ctLayout({ width: size.width || 1920, height: size.height || 1080, insets: NO_INSETS, opponents: seats, handCount: 0, trays: 0, laid, tv: true }),
    [size.width, size.height, seats.join(), JSON.stringify(laid)],
  );
  return (
    <div class="ct-table landscape tv-table" ref={rootRef} style={ctStyle(L)}>
      <CtPublic store={store} room={room} layout={L} motion={motion} aims={state.aims} scores haptics={false} cue={NO_CUE}>
        <Banner store={store} room={room} rect={L.banner} offline={props.offline} />
        <Moments store={store} room={room} />
      </CtPublic>
    </div>
  );
}

/**
 * Birdwatch on the TV (design §5.6): the sill, the cats with their bid signs, the score strip and
 * the trump badge; no hand, and never the 5-player partner until the called card is played (the
 * public table reads only `partner`).
 */
function TvBirdwatch(props: TableProps) {
  const { store, state } = props;
  const room = state.room!;
  const v = room.birdwatch!;
  const [rootRef, size] = useSize<HTMLDivElement>();
  const motion = useMemo(() => new Motion(reducedMotion), []);
  const L = useMemo(
    () => bwLayout({ width: size.width || 1920, height: size.height || 1080, insets: NO_INSETS, me: null, others: othersInOrder(v, null), hand: 0, tv: true }),
    [size.width, size.height, v.seats],
  );
  return (
    <div class="bw-table tv-table bw-tv" ref={rootRef} style={bwStyle(L)}>
      <BwPublic store={store} room={room} layout={L} motion={motion} haptics={false} tv>
        <p class="bw-tv-rules outlined" style={{ transform: `translate3d(${L.sill.x + L.sill.w - 12}px, ${L.sill.y + 10}px, 0) translateX(-100%)` }}>
          {RULE_COPY[v.rules].name}, to {v.target}
        </p>
        <Banner store={store} room={room} rect={L.banner} offline={props.offline} />
      </BwPublic>
    </div>
  );
}

function TvTiles(props: TableProps) {
  const { store, state } = props;
  const room = state.room!;
  const [rootRef, size] = useSize<HTMLDivElement>();
  const motion = useMemo(() => new Motion(reducedMotion), []);
  const seats = room.seats.flatMap((s, i) => (s.kind === "human" || s.kind === "bot" ? [i] : []));
  // Sized for the sets on show: the acting player's draft while they arrange it.
  const sets = tilesShown(room, state.aims).map((s) => s.length);
  const L = useMemo(
    () => tilesLayout({ width: size.width || 1920, height: size.height || 1080, insets: NO_INSETS, opponents: seats, sets, rack: 0, tv: true }),
    [size.width, size.height, seats.join(), sets.join()],
  );
  return (
    <div class="tt-table landscape tv-table" ref={rootRef} style={tilesStyle(L)}>
      <TilesPublic store={store} room={room} layout={L} motion={motion} aims={state.aims} scores haptics={false} cue={NO_CUE}>
        <Banner store={store} room={room} rect={L.banner} offline={props.offline} />
      </TilesPublic>
    </div>
  );
}

/**
 * "<Name>'s turn", big, in the seat's colour, with their cat leaning in. It pops as each turn
 * starts (a `turn` event), not when the player draws or plays. While the TV has lost the table it
 * says so here, over the last table shown. The outer box holds the place; the inner one pops, so
 * its scale never moves the place.
 */
function Banner(props: { store: RoomStore; room: RoomView; rect: Rect; offline: boolean }) {
  const { room, rect } = props;
  const seat = turnSeat(room);
  const [turns, setTurns] = useState(0);
  useEffect(
    () =>
      props.store.subscribe({
        event: ({ event: e }) => {
          if ((e.kind === "game" || e.kind === "tiles" || e.kind === "birdwatch") && e.event.kind === "turn") setTurns((n) => n + 1);
        },
      }),
    [props.store],
  );
  // Centred on its place, at least as wide, and wider for a long name (tv.css caps it at the
  // layout's `bannerRoom`).
  const at = { transform: `translate3d(${rect.x + rect.w / 2}px, ${rect.y}px, 0)`, height: `${rect.h}px` };
  const size = { minWidth: `${rect.w}px`, height: `${rect.h}px` };
  if (props.offline) {
    return (
      <div class="tv-banner-at" style={at}>
        <div class="tv-banner lost" style={size} role="status">
          <span class="tv-banner-words">
            <span class="dot" /> Reconnecting
          </span>
        </div>
      </div>
    );
  }
  if (seat === null) return null;
  return (
    <div class="tv-banner-at" style={at}>
      <div key={`${seat}:${turns}`} class="tv-banner" style={{ ...size, ["--ring" as string]: RINGS[seat % RINGS.length] }} role="status" aria-live="polite">
        <Cat cat={seatCat(room.seats[seat])} pose="awake" class="tv-banner-cat" size="calc(var(--u) * 132)" />
        <span class="tv-banner-words outlined">
          <span class="tv-banner-name">{seatName(room.seats[seat])}</span>
          <span>'s turn</span>
        </span>
      </div>
    </div>
  );
}

/** A player laying down, big in the middle of the table for a moment (its CSS animation ends it). */
function Moments(props: { store: RoomStore; room: RoomView }) {
  const [moment, setMoment] = useState<(Moment & { key: number }) | null>(null);
  const room = props.room;
  useEffect(
    () =>
      props.store.subscribe({
        event: ({ event }, shown) => {
          const m = momentFor(event, shown ?? room);
          if (m) setMoment({ ...m, key: performance.now() });
        },
      }),
    [props.store],
  );
  if (!moment) return null;
  return (
    <div
      key={moment.key}
      class="tv-moment"
      role="status"
      style={{ ["--ring" as string]: RINGS[moment.seat % RINGS.length] }}
      onAnimationEnd={(e) => {
        if (e.target === e.currentTarget) setMoment(null);
      }}
    >
      <img class="tv-moment-burst" src={art("sunburst")} alt="" />
      <Cat cat={seatCat(room.seats[moment.seat])} pose="celebrate" class="tv-moment-cat" size="calc(var(--u) * 300)" />
      <strong class="tv-moment-title outlined">{moment.title}</strong>
      <span class="tv-moment-sub outlined">{moment.sub}</span>
    </div>
  );
}

/**
 * The menu's paw, one for every screen at a table, in the corner every TV layout keeps free
 * (`tvMenu`). A remote reaches it with the arrows (it is idle: focus never rests on it by itself)
 * or opens the menu with Back.
 */
export function MenuButton(props: { rect: Rect; live: boolean; onMenu: () => void }) {
  const { rect } = props;
  return (
    <button
      type="button"
      class="tv-menu-btn"
      data-tv={props.live ? true : undefined}
      data-tv-idle
      tabIndex={props.live ? 0 : -1}
      aria-label="Menu"
      style={{ left: `${rect.x}px`, top: `${rect.y}px`, width: `${rect.w}px`, height: `${rect.h}px` }}
      onClick={() => {
        play("pop", 0.5);
        props.onMenu();
      }}
    >
      <img src={art("icon-paw-menu")} alt="" />
    </button>
  );
}

/** Game over on the TV: the winners celebrating, everyone's place, and how to play again. */
export function TvOver(props: { room: RoomView; cheered: boolean }) {
  const { room } = props;
  const rows = standings(room);
  const winners = rows.filter((r) => r.won);
  const title = overTitle(room);
  useEffect(() => {
    // One cheer per game end: none here when the table already gave it (`cheerStep`).
    if (!props.cheered) play(winners.length > 0 ? "fanfare" : "leap");
  }, []);
  return (
    <div class="tv-over" role="dialog" aria-label={title}>
      <img class="tv-over-burst" src={art("sunburst")} alt="" aria-hidden="true" />
      <div class="tv-over-card" style={{ ["--rows" as string]: rows.length }}>
        <div class="tv-over-winners">
          {winners.map((w, i) => (
            <span class="tv-over-winner" style={{ ["--ring" as string]: RINGS[w.seat % RINGS.length], animationDelay: `${i * 120}ms` }}>
              <Cat cat={seatCat(room.seats[w.seat])} pose="celebrate" />
            </span>
          ))}
        </div>
        <h2 class={`tv-over-title outlined ${title.length > 18 ? "long" : ""}`}>
          {winners.length === 1 && !room.birdwatch ? (
            <>
              <span class="tv-over-name">{seatName(room.seats[winners[0]!.seat])}</span>
              <span>&nbsp;wins</span>
            </>
          ) : (
            title
          )}
        </h2>
        <ol class="tv-over-ranks">
          {rows.map((r, i) => (
            <li class={`${r.won ? "won" : ""} ${r.out ? "out" : ""}`} style={{ ["--ring" as string]: RINGS[r.seat % RINGS.length], animationDelay: `${240 + i * 90}ms` }}>
              <span class="tv-over-place">{i + 1}</span>
              <span class="tv-over-ring">
                <Cat cat={seatCat(room.seats[r.seat])} pose={r.won ? "celebrate" : "idle"} />
              </span>
              <span class="tv-over-who">{r.name ?? seatName(room.seats[r.seat])}</span>
              <span class="tv-over-detail">{r.detail}</span>
            </li>
          ))}
        </ol>
      </div>
      <p class="tv-over-again tv-label outlined">
        <img src={art("icon-phone")} alt="" />
        Play again on any phone
      </p>
    </div>
  );
}
