/**
 * Tuna Tiles on a phone whose table is on a TV, off turn: just your rack, big, in the order you
 * keep it, with whose turn it is and the toy box's count. On your turn the phone shows the full
 * table instead (tiles.tsx), as rearranging what is down needs it; the rack's order is shared
 * between the two (tiles-rack.ts). The table and its sounds are the TV's: this phone makes only
 * its taps and buzzes. The top bar is Cat Tower's controller's (ct-controller.tsx).
 */
import { useEffect, useLayoutEffect, useMemo, useRef } from "preact/hooks";

import { art, catArt, RINGS } from "../lib/art";
import { buzz } from "../lib/haptics";
import { reducedMotion } from "../lib/settings";
import { play } from "../lib/sound";
import { mySeats } from "../store/lobby";
import { learnTip, Tip, useSize } from "../ui/common";

import { useInsets } from "./cattower";
import { inside, press, useLatest, type Point, type Rect } from "./drag";
import { PieceFace, pieceLabel } from "./faces";
import { Motion, MOVE, transformOf, wiggle, type Pose } from "./motion";
import { seatCat, seatName } from "./seat";
import { SwitchView, useTextScale } from "./shared";
import { tilesControllerLayout, type TclLayout } from "./tiles-controller-layout";
import { sortRack } from "./tiles-draft";
import { rackInOrder, useRackOrder } from "./tiles-rack";

import type { RoomState, RoomStore } from "../store/room";
import type { View } from "../store/views";
import type { TileId } from "@pounce/play-api/tiles/pieces";
import type { TilesView } from "@pounce/play-api/tiles/view";

const box = (r: Rect) => ({ transform: `translate3d(${r.x}px, ${r.y}px, 0)`, width: `${r.w}px`, height: `${r.h}px` });

export function TilesController(props: { store: RoomStore; state: RoomState; onView: (view: View) => void }) {
  const { store, state } = props;
  const room = state.room!;
  const v = room.tiles as TilesView;
  const [rootRef, size] = useSize<HTMLDivElement>();
  const insets = useInsets();
  const text = useTextScale();
  const motion = useMemo(() => new Motion(reducedMotion), []);
  const els = useRef(new Map<string, HTMLElement>());

  // A shared device (pass and play) shows no one's rack between turns: the next player takes it.
  const mine = mySeats(room).filter((s) => !v.forfeited[s]);
  const seat = mine.length === 1 ? mine[0]! : null;
  const serverRack = seat !== null ? (v.racks[seat] ?? []) : [];
  const { order, setOrder, sortBy, setSortBy } = useRackOrder(`${room.code}:${seat}`);
  const rackIds = rackInOrder(order, serverRack);
  useEffect(() => {
    if (rackIds.join() !== order.join()) setOrder(rackIds);
  });

  const L: TclLayout = useMemo(
    () => tilesControllerLayout({ width: size.width || 360, height: size.height || 640, insets, rack: rackIds.length, text }),
    [size.width, size.height, insets, rackIds.length, text],
  );

  // The table menu's paw is the table screen's: it grows with this screen's top bar.
  useLayoutEffect(() => {
    const screen = rootRef.current?.parentElement;
    screen?.style.setProperty("--k", String(L.unit));
    return () => screen?.style.removeProperty("--k");
  }, [L.unit]);

  // Your turn buzzes (the TV says it out loud; the full table takes over from here).
  useEffect(
    () =>
      store.subscribe({
        event: ({ event: e }) => {
          if (e.kind === "tiles" && e.event.kind === "turn" && mine.includes(e.event.seat)) buzz("turn");
        },
      }),
    [store, mine.join()],
  );

  useEffect(() => {
    if (!state.error) return;
    play("nope");
    buzz("nope");
    wiggle(rootRef.current?.querySelector(".tcl-rack") as HTMLElement | null);
  }, [state.error?.n]);

  const poses = new Map<string, Pose>();
  rackIds.forEach((id, i) => {
    const p = L.rack[i];
    if (p) poses.set(`p${id}`, p);
  });
  useLayoutEffect(() => {
    motion.apply(els.current, poses, (key) => (motion.last(key) ? MOVE : { ...MOVE, delay: Math.min(rackIds.indexOf(Number(key.slice(1))), 14) * 30 }));
  });
  const setEl = (key: string) => (el: HTMLElement | null) => {
    if (el) els.current.set(key, el);
    else els.current.delete(key);
  };

  // Dragging a piece to a new place in the rack.
  const dropAt = (id: TileId, p: Point, pose: Pose) => {
    motion.place(`p${id}`, pose);
    if (!inside(p, L.rackRect, L.ph * 0.6)) return;
    const at = L.indexAt(p);
    const without = rackIds.filter((x) => x !== id);
    const before = rackIds.indexOf(id);
    without.splice(before < at ? at - 1 : at, 0, id);
    if (without.join() === rackIds.join()) return;
    setOrder(without);
    play("tick", 0.4);
    buzz("drop");
  };
  const live = useLatest({ dropAt });
  const onDown = (id: TileId) => (e: PointerEvent) => {
    const el = els.current.get(`p${id}`);
    if (!el) return;
    press(e, el, {
      origin: () => {
        const r = rootRef.current!.getBoundingClientRect();
        return { x: r.left, y: r.top };
      },
      pose: () => motion.last(`p${id}`) ?? { x: 0, y: 0 },
      lift: 1.1,
      onTap: () => {
        play("tick", 0.3);
        buzz("tap");
      },
      onStart: () => {
        play("tick", 0.4);
        buzz("pick");
      },
      onDrop: (p, pose) => live.current.dropAt(id, p, pose),
    });
  };

  const sort = (by: "number" | "toy") => {
    setSortBy(by);
    setOrder(sortRack(rackIds, by));
    learnTip("tt.sort");
    play("whoosh", 0.4);
  };
  const nextSort = sortBy === "number" ? "toy" : "number";

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.metaKey || e.ctrlKey || e.altKey) return;
      if (e.key.toLowerCase() !== "s" || rackIds.length === 0) return;
      sort(nextSort);
      e.preventDefault();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const myTurn = v.status === "playing" && mine.includes(v.turn);
  const turnSeat = room.seats[v.turn];
  const status: { who?: string; words: string; tone: "" | "mine" } =
    v.status !== "playing" ? { words: "", tone: "" } : myTurn ? { words: "Your turn", tone: "mine" } : { who: seatName(turnSeat), words: "'s turn", tone: "" };
  const statusLong = (status.who ?? "").length + status.words.length > 18;

  return (
    <div class={`tt-table ctl tcl ${L.landscape ? "landscape" : ""}`} ref={rootRef} style={{ ["--pw" as string]: `${L.pw}px`, ["--ph" as string]: `${L.ph}px`, ["--k" as string]: String(L.unit) }}>
      <SwitchView view="cards" onChange={props.onView} style={box(L.switch)} />

      {status.words ? (
        <div class={`ctl-status ${L.status.y === L.switch.y ? "inline" : ""}`} style={box(L.status)}>
          <p class={`ctl-status-pill ${status.tone} ${statusLong ? "long" : ""}`} aria-live="polite" style={{ ["--ring" as string]: RINGS[v.turn % RINGS.length] }}>
            <img src={catArt(seatCat(turnSeat), myTurn ? "awake" : "idle")} alt="" />
            <span class="words">
              {status.who ? <span class="who">{status.who}</span> : null}
              {status.words}
            </span>
          </p>
        </div>
      ) : null}

      <div class="pool" style={{ transform: `translate3d(${L.pool.x}px, ${L.pool.y}px, 0)`, width: `${L.pool.size}px` }} role="img" aria-label={`Toy box: ${v.poolCount} pieces`}>
        <img src={art(v.poolCount > 0 ? "toy-box" : "toy-box-closed")} alt="" />
        <span class="pile-count">{v.poolCount}</span>
      </div>

      {rackIds.length > 0 ? (
        // One button, two sorts: by number, then by toy, then by number again (as on the full table).
        <button type="button" class="icon-btn" id="sort" style={box(L.sort)} aria-label={sortBy === "number" ? "Sort by toy" : "123: sort by number"} title={sortBy === "number" ? "Sort by toy" : "Sort by number"} onClick={() => sort(nextSort)}>
          {sortBy === "number" ? <img src={art("tile-fish")} alt="" /> : <span class="num-icon">123</span>}
        </button>
      ) : null}

      <div class="tcl-rack" style={box(L.rackRect)} />
      <div class="pieces" role="group" aria-label="Your rack">
        {[...poses].map(([key, p]) => {
          const id = Number(key.slice(1));
          return (
            <div key={key} ref={setEl(key)} class="tile mine" style={{ transform: transformOf(p), zIndex: p.z ?? 1 }} onPointerDown={onDown(id)}>
              <div class="tile-inner" role="img" aria-label={pieceLabel(id)}>
                <PieceFace id={id} />
              </div>
            </div>
          );
        })}
      </div>

      <Tip id="tv.switch" anchor="view-switch" text="Your tiles are here. The table is on the TV." show place="below" />
    </div>
  );
}
