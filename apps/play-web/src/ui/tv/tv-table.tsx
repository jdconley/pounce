/**
 * The table on the TV: the public table in the big-screen layout (no hand, nothing to touch), the
 * turn banner in the seat's colour, a big moment when someone lays down, and game over. Read from
 * the couch: everything that matters is at least 28 px on a 1080p screen (tv.css).
 */
import { useEffect, useMemo, useState } from "preact/hooks";

import { art, RINGS } from "../../lib/art";
import { reducedMotion } from "../../lib/settings";
import { play } from "../../lib/sound";
import { ctLayout, tvFrame } from "../../table/ct-layout";
import { CtPublic, ctStyle } from "../../table/ct-public";
import { Motion } from "../../table/motion";
import { seatCat, seatName } from "../../table/seat";
import { tilesLayout } from "../../table/tiles-layout";
import { TilesPublic, tilesShown, tilesStyle } from "../../table/tiles-public";
import { Cat, useSize } from "../common";

import { momentFor, overTitle, standings, turnSeat, type Moment } from "./tv-model";

import type { RoomStore, RoomState } from "../../store/room";
import type { Rect } from "../../table/drag";
import type { RoomView } from "@pounce/play-api/protocol";

const NO_INSETS = { top: 0, right: 0, bottom: 0, left: 0 };
/** The public table's own cue is the phone's; the TV draws its banner instead. */
const NO_CUE = { text: "", mine: false, y: 0 };

type TableProps = { store: RoomStore; state: RoomState; offline: boolean; live: boolean; onMenu: () => void };

/** The table as the TV draws it, for either game. */
export function TvTable(props: TableProps) {
  const room = props.state.room!;
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
  const u = tvFrame(size.width || 1920, size.height || 1080, NO_INSETS).unit;
  const menuAt = { x: L.tower.x + L.tower.w + 24 * u, y: L.banner.y, w: L.banner.h, h: L.banner.h };
  return (
    <div class="ct-table landscape tv-table" ref={rootRef} style={ctStyle(L)}>
      <CtPublic store={store} room={room} layout={L} motion={motion} aims={state.aims} scores haptics={false} cue={NO_CUE}>
        <Banner room={room} rect={L.banner} offline={props.offline} />
        <Moments store={store} room={room} />
      </CtPublic>
      <MenuButton rect={menuAt} live={props.live} onMenu={props.onMenu} />
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
  const menuAt = { x: L.board.x, y: L.banner.y, w: L.banner.h, h: L.banner.h };
  return (
    <div class="tt-table landscape tv-table" ref={rootRef} style={tilesStyle(L)}>
      <TilesPublic store={store} room={room} layout={L} motion={motion} aims={state.aims} scores haptics={false} cue={NO_CUE}>
        <Banner room={room} rect={L.banner} offline={props.offline} />
      </TilesPublic>
      <MenuButton rect={menuAt} live={props.live} onMenu={props.onMenu} />
    </div>
  );
}

/**
 * "<Name>'s turn", big, in the seat's colour, with their cat leaning in. It pops each time the
 * turn moves on. While the TV has lost the table it says so here, over the last table shown.
 */
function Banner(props: { room: RoomView; rect: Rect; offline: boolean }) {
  const { room, rect } = props;
  const seat = turnSeat(room);
  // Centred on its place, at least as wide, and wider for a long name (tv.css caps it).
  const place = { transform: `translate3d(${rect.x + rect.w / 2}px, ${rect.y}px, 0)`, minWidth: `${rect.w}px`, height: `${rect.h}px` };
  if (props.offline) {
    return (
      <div class="tv-banner lost" style={place} role="status">
        <span class="tv-banner-words">
          <span class="dot" /> Reconnecting
        </span>
      </div>
    );
  }
  if (seat === null) return null;
  const turns = room.game ? `${room.game.round}:${room.game.turn}:${room.game.deckCount}` : `${room.tiles?.turns ?? 0}`;
  return (
    <div key={`${seat}:${turns}`} class="tv-banner" style={{ ...place, ["--ring" as string]: RINGS[seat % RINGS.length] }} role="status" aria-live="polite">
      <Cat cat={seatCat(room.seats[seat])} pose="awake" class="tv-banner-cat" size="calc(var(--u) * 132)" />
      <span class="tv-banner-words outlined">
        <span class="tv-banner-name">{seatName(room.seats[seat])}</span>
        <span>'s turn</span>
      </span>
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

/** The menu, for a mouse (a remote's Back opens it too): beside the banner, where nothing else sits. */
function MenuButton(props: { rect?: Rect; live: boolean; onMenu: () => void }) {
  const { rect } = props;
  return (
    <button
      type="button"
      class={`tv-menu-btn ${rect ? "" : "tv-corner"}`}
      data-tv={props.live ? true : undefined}
      tabIndex={props.live ? 0 : -1}
      aria-label="Menu"
      style={rect ? { transform: `translate3d(${rect.x}px, ${rect.y}px, 0)`, width: `${rect.w}px`, height: `${rect.h}px` } : undefined}
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
export function TvOver(props: { room: RoomView; live: boolean; onMenu: () => void }) {
  const { room } = props;
  const rows = standings(room);
  const winners = rows.filter((r) => r.won);
  const title = overTitle(room);
  useEffect(() => {
    // Tuna Tiles' own game over event already cheered at the table.
    if (room.gameId !== "tiles") play(winners.length > 0 ? "fanfare" : "leap");
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
        <h2 class="tv-over-title outlined">{title}</h2>
        <ol class="tv-over-ranks">
          {rows.map((r, i) => (
            <li class={`${r.won ? "won" : ""} ${r.out ? "out" : ""}`} style={{ ["--ring" as string]: RINGS[r.seat % RINGS.length], animationDelay: `${240 + i * 90}ms` }}>
              <span class="tv-over-place">{i + 1}</span>
              <span class="tv-over-ring">
                <Cat cat={seatCat(room.seats[r.seat])} pose={r.won ? "celebrate" : "idle"} />
              </span>
              <span class="tv-over-who">{seatName(room.seats[r.seat])}</span>
              <span class="tv-over-detail">{r.detail}</span>
            </li>
          ))}
        </ol>
      </div>
      <p class="tv-over-again outlined">Play again on any phone</p>
      <MenuButton live={props.live} onMenu={props.onMenu} />
    </div>
  );
}
