/**
 * The Tuna Tiles table (TilesScene.swift): opponents across the top, the sets inside the rope
 * with the toy box, the controls, and the rack. A turn is built on this device (tiles-draft.ts)
 * and sent whole with Play; with nothing changed the button draws instead. The table anyone may
 * see is TilesPublic (tiles-public.tsx), shared with the TV; this is the rack and the turn on top.
 * While a TV shows the table, every change to the draft is sent as an aim, so the room watches the
 * player work it out (off turn, that phone shows tiles-controller.tsx instead).
 */
import { useEffect, useMemo, useRef, useState } from "preact/hooks";


import { art } from "../lib/art";
import { buzz } from "../lib/haptics";
import { reducedMotion } from "../lib/settings";
import { play } from "../lib/sound";
import { mySeats } from "../store/lobby";
import { Button, Icon, IconButton, learnTip, Tip, tipLearned, useSize } from "../ui/common";
import { hint as askHint } from "../workers/hint";

import { useInsets } from "./cattower";
import { inside, press, useLatest, type Point } from "./drag";
import { PieceFace, pieceLabel } from "./faces";
import { Motion, transformOf, wiggle, type Pose } from "./motion";
import { seatName } from "./seat";
import { Curtain } from "./shared";
import { checkDraft, OPENING_POINTS, placedThisTurn, sameDraft, sortRack, tilesAimOf, toNewSet, toRack, toSet, type Draft } from "./tiles-draft";
import { tilesLayout } from "./tiles-layout";
import { aimTable as aimOf, TilesTableBase, tilesStyle, type PieceLook, type TilesHover } from "./tiles-public";
import { rackInOrder, useRackOrder } from "./tiles-rack";

import type { RoomState, RoomStore } from "../store/room";
import type { TileId } from "@pounce/play-api/tiles/pieces";
import type { TilesView } from "@pounce/play-api/tiles/view";

/**
 * `sounds: false` silences the game's own events (a phone whose table is on a TV); taps still sound.
 * `topInset` keeps a strip along the top clear (the Cards/Table switch, while a TV shows the table).
 */
export function TilesTable(props: { store: RoomStore; state: RoomState; sounds?: boolean; topInset?: number }) {
  const { store, state } = props;
  const sounds = props.sounds ?? true;
  const room = state.room!;
  const v = room.tiles as TilesView;
  const [rootRef, size] = useSize<HTMLDivElement>();
  const safe = useInsets();
  const insets = useMemo(() => ({ ...safe, top: safe.top + (props.topInset ?? 0) }), [safe, props.topInset]);
  const motion = useMemo(() => new Motion(reducedMotion), []);
  const els = useRef(new Map<string, HTMLElement>());

  const mine = mySeats(room).filter((s) => !v.forfeited[s]);
  const shared = mine.length > 1;
  const turnKey = String(v.turns);
  const [revealed, setRevealed] = useState<{ seat: number; key: string } | null>(null);
  const acting = !shared ? (mine[0] ?? null) : mine.includes(v.turn) && v.status === "playing" ? v.turn : null;
  const showRack = acting !== null && (!shared || (revealed?.seat === acting && revealed.key === turnKey));
  const curtainSeat = shared && acting !== null && !showRack ? acting : null;
  const seat = acting;
  const myTurn = seat !== null && v.turn === seat && v.status === "playing";
  const serverRack = showRack && seat !== null ? (v.racks[seat] ?? []) : [];
  const opened = seat !== null && v.opened[seat] === true;

  // The draft starts from the table and rack as they stand, and starts again whenever they change.
  const base: Draft = { table: v.table, rack: serverRack };
  const baseKey = JSON.stringify([v.table, serverRack, v.turns, seat]);
  const [draft, setDraft] = useState<Draft>(base);
  const [history, setHistory] = useState<Draft[]>([]);
  // The player's rack order, shared with the controller this phone shows off turn.
  const { order: rackOrder, setOrder: setRackOrder, sortBy, setSortBy } = useRackOrder(`${room.code}:${seat}`);
  const lastBase = useRef(baseKey);
  useEffect(() => {
    if (lastBase.current === baseKey) return;
    lastBase.current = baseKey;
    setDraft({ table: v.table, rack: serverRack });
    setHistory([]);
  }, [baseKey]);

  // The rack keeps the player's order; new pieces go on the end.
  const rackIds = rackInOrder(rackOrder, draft.rack);
  useEffect(() => {
    if (rackIds.join() !== rackOrder.join()) setRackOrder(rackIds);
  });

  const result = checkDraft(v.table, serverRack, opened, { table: draft.table, rack: rackIds });
  const playable = myTurn && result.changed && result.check?.ok === true;

  // While a TV shows the table, the draft goes to it as an aim on every change (the store sends
  // at most one each 120 ms, the latest last). Back to the table as played, it is cleared; a draft
  // the wire won't carry is never sent, and the last one sent stands.
  const aiming = room.screen === true && myTurn && showRack && seat !== null && !state.pending;
  const aimNow = aiming ? tilesAimOf(draft.table, v.table) : null;
  const asPlayed = JSON.stringify(draft.table.filter((set) => set.length > 0)) === JSON.stringify(v.table);
  const aimKey = !aiming || asPlayed ? "" : aimNow ? JSON.stringify(aimNow.table) : "keep";
  const aimSent = useRef<{ seat: number; key: string } | null>(null);
  const clearAim = () => {
    if (aimSent.current) store.aim(aimSent.current.seat, null);
    aimSent.current = null;
  };
  useEffect(() => {
    if (aimKey === "keep") return;
    if (aimNow && seat !== null) {
      if (aimSent.current?.key === aimKey) return;
      store.aim(seat, aimNow);
      aimSent.current = { seat, key: aimKey };
    } else clearAim();
  }, [aimKey]);
  useEffect(() => clearAim, [store]);

  const [selected, setSelected] = useState<TileId | null>(null);
  const [hover, setHover] = useState<TilesHover>(null);
  const opponents = room.seats.flatMap((s, i) => ((s.kind === "human" || s.kind === "bot") && i !== seat ? [i] : []));

  // Watching someone else's turn, the sets are theirs as they arrange them (their aim).
  const aimTable = myTurn ? null : aimOf(room, state.aims);
  const shownTable = aimTable ?? draft.table;

  const L = useMemo(
    () =>
      tilesLayout({
        width: size.width || 360,
        height: size.height || 640,
        insets,
        opponents,
        sets: shownTable.map((s) => s.length),
        rack: rackIds.length,
      }),
    [size.width, size.height, insets, opponents.join(), shownTable.map((s) => s.length).join(), rackIds.length],
  );

  // The rack's own event (the table's are TilesPublic's): your turn.
  useEffect(
    () =>
      store.subscribe({
        event: ({ event: e }) => {
          if (e.kind === "tiles" && e.event.kind === "turn" && mine.includes(e.event.seat)) {
            if (sounds) play("tick", 0.6);
            buzz("turn");
          }
        },
      }),
    [store, mine.join(), sounds],
  );

  useEffect(() => {
    if (!state.error) return;
    play("nope");
    buzz("nope");
    wiggle(rootRef.current?.querySelector(".board") as HTMLElement | null);
  }, [state.error?.n]);

  // Poses for the rack; the table's pieces are TilesPublic's.
  const poses = new Map<string, Pose>();
  rackIds.forEach((id, i) => {
    const p = L.rack[i];
    if (p) poses.set(`p${id}`, p);
  });

  const change = (next: Draft) => {
    if (sameDraft(next, draft)) return;
    setHistory((h) => [...h.slice(-40), draft]);
    setDraft(next);
    setSelected(null);
    learnTip("tt.drag");
    play("pop", 0.5);
    buzz("drop");
  };

  /** A piece on the table this device may move: any once opened, else only this turn's. */
  const movable = (id: TileId) => myTurn && (draft.rack.includes(id) || opened || placedThisTurn(v.table, id));

  const targetAt = (p: Point, id: TileId): TilesHover => {
    for (const [si, set] of L.sets.entries()) {
      if (inside(p, set.rect, L.pw * 0.45)) {
        const xs = (set.poses ?? []).map((q) => q.x + L.pw / 2);
        let index = xs.findIndex((x) => p.x < x);
        if (index < 0) index = xs.length;
        return { kind: "set", set: si, index };
      }
    }
    if (inside(p, L.newSet, 10)) return { kind: "new" };
    if (inside(p, L.rackRect, 6) && (draft.rack.includes(id) || placedThisTurn(v.table, id))) {
      const xs = L.rack.map((q) => q.x + L.pw / 2);
      let index = xs.findIndex((x, i) => p.x < x && Math.abs(p.y - (L.rack[i]!.y + L.ph / 2)) < L.ph);
      if (index < 0) index = rackIds.length;
      return { kind: "rack", index };
    }
    if (inside(p, L.board)) return { kind: "new" };
    return null;
  };

  const dropAt = (id: TileId, p: Point, pose: Pose) => {
    const t = targetAt(p, id);
    setHover(null);
    motion.place(`p${id}`, pose);
    if (!t) return;
    if (t.kind === "rack") {
      const at = Math.min(t.index, rackIds.length);
      if (draft.rack.includes(id)) {
        // Reordering the rack.
        const without = rackIds.filter((x) => x !== id);
        const before = rackIds.indexOf(id);
        without.splice(before < at ? at - 1 : at, 0, id);
        setRackOrder(without);
        play("tick", 0.4);
        return;
      }
      const next = toRack(draft, id, at);
      const order = rackIds.filter((x) => x !== id);
      order.splice(at, 0, id);
      setRackOrder(order);
      return change(next);
    }
    if (!myTurn) return;
    if (t.kind === "set") return change(toSet(draft, id, t.set, t.index));
    return change(toNewSet(draft, id));
  };

  const live = useLatest({ targetAt, dropAt });
  const onDown = (id: TileId) => (e: PointerEvent) => {
    const el = els.current.get(`p${id}`);
    if (!el || (!movable(id) && !draft.rack.includes(id))) return;
    press(e, el, {
      origin: () => {
        const r = rootRef.current!.getBoundingClientRect();
        return { x: r.left, y: r.top };
      },
      pose: () => motion.last(`p${id}`) ?? { x: 0, y: 0 },
      lift: (motion.last(`p${id}`)?.s ?? 1) * 1.1,
      onTap: () => {
        play("tick", 0.4);
        buzz("tap");
        setSelected((s) => (s === id ? null : id));
      },
      onStart: () => {
        play("tick", 0.4);
        buzz("pick");
      },
      onMove: (p) => setHover(live.current.targetAt(p, id)),
      onDrop: (p, pose) => live.current.dropAt(id, p, pose),
      onCancel: () => setHover(null),
    });
  };

  const tapSet = (si: number) => {
    if (selected === null || !movable(selected)) return;
    change(toSet(draft, selected, si, draft.table[si]?.length ?? 0));
  };
  const tapNew = () => {
    if (selected === null || !movable(selected)) return;
    change(toNewSet(draft, selected));
  };

  const submit = () => {
    if (!myTurn || state.pending || seat === null) return;
    if (result.changed) {
      if (!playable) {
        play("nope");
        buzz("nope");
        wiggle(document.getElementById("play-btn"));
        return;
      }
      learnTip("tt.play");
      store.act(seat, { type: "play", table: draft.table });
      // After the play, so the TV never shows the table without it in between.
      clearAim();
      return;
    }
    learnTip("tt.draw");
    store.act(seat, v.poolCount > 0 ? { type: "draw" } : { type: "pass" });
  };

  const undo = () => {
    const prev = history[history.length - 1];
    if (!prev) return;
    setHistory((h) => h.slice(0, -1));
    setDraft(prev);
    play("whoosh", 0.4);
  };
  const reset = () => {
    if (!result.changed) return;
    setHistory((h) => [...h, draft]);
    setDraft({ table: v.table, rack: serverRack });
    play("whoosh", 0.5);
  };
  const sort = (by: "number" | "toy") => {
    setSortBy(by);
    setRackOrder(sortRack(rackIds, by));
    learnTip("tt.sort");
    play("whoosh", 0.4);
  };
  const [thinking, setThinking] = useState(false);
  const hint = async () => {
    if (!myTurn || seat === null || thinking) return;
    learnTip("tt.hint");
    // The House Cat's own move, from this device's view of the table, worked out off the
    // rendering thread (workers/hint.worker.ts).
    setThinking(true);
    const fresh: TilesView = { ...v, table: v.table, racks: { ...v.racks, [seat]: serverRack } };
    const action = await askHint(fresh, seat);
    setThinking(false);
    if (action?.type !== "play") {
      play("nope", 0.5);
      wiggle(document.getElementById("play-btn"));
      return;
    }
    const placed = new Set(action.table.flat());
    change({ table: action.table, rack: serverRack.filter((id) => !placed.has(id)) });
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.metaKey || e.ctrlKey || e.altKey) return;
      const k = e.key.toLowerCase();
      if (k === "enter" && e.target === document.body) submit();
      else if (k === "z") undo();
      else if (k === "n" && selected !== null) tapNew();
      else if (k === "s") sort(sortBy === "number" ? "toy" : "number");
      else if (k === "escape") setSelected(null);
      else return;
      e.preventDefault();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const turnName = seatName(room.seats[v.turn]);
  const openingShown = showRack && !opened && myTurn && result.changed;
  const label = result.changed ? "Play" : v.poolCount > 0 ? "Draw" : "Pass";

  const renderPiece = (id: TileId, p: Pose, ref: (el: HTMLElement | null) => void, look: PieceLook) => {
    const can = draft.rack.includes(id) || movable(id);
    return (
      <div key={`p${id}`} ref={ref} class={`tile ${selected === id ? "picked" : ""} ${can ? "mine" : ""}${look.draft ? " draft" : ""}`} style={{ transform: transformOf(p), zIndex: p.z ?? 1 }} onPointerDown={can ? onDown(id) : undefined}>
        {can ? (
          <button type="button" class="tile-inner" aria-label={pieceLabel(id, look.ghost ?? undefined)} aria-pressed={selected === id} onClick={(e) => e.preventDefault()} onKeyDown={(e) => {
            if (e.key === "Enter" || e.key === " ") {
              e.preventDefault();
              setSelected((s) => (s === id ? null : id));
            }
          }}>
            <PieceFace id={id} ghost={look.ghost} />
          </button>
        ) : (
          <div class="tile-inner" role="img" aria-label={pieceLabel(id, look.ghost ?? undefined)}>
            <PieceFace id={id} ghost={look.ghost} />
          </div>
        )}
      </div>
    );
  };

  return (
    <div class={`tt-table ${myTurn ? "my-turn" : ""}`} ref={rootRef} style={tilesStyle(L)}>
      <TilesTableBase
        store={store}
        room={room}
        layout={L}
        motion={motion}
        aims={state.aims}
        sounds={sounds}
        draft={aimTable ? undefined : draft.table}
        marks={aimTable ? undefined : result.marks}
        mine={mine}
        hand={{ poses, els: els.current, render: renderPiece }}
        hover={hover}
        setsFocusable={selected !== null}
        onSet={tapSet}
        cue={{
          text: v.status !== "playing" ? "" : myTurn ? (result.changed ? (playable ? "Tap Play" : "Not a play yet") : "Your turn") : `${turnName}'s turn`,
          mine: myTurn,
          // Above the opening's points, which ride over Play into the foot of the board.
          y: openingShown ? L.board.y + L.board.h - 80 : undefined,
        }}
        under={
          myTurn ? (
            <button
              type="button"
              id="new-set"
              class={`new-set ${hover?.kind === "new" ? "hot" : ""}`}
              style={{ transform: `translate3d(${L.newSet.x}px, ${L.newSet.y}px, 0)`, width: `${L.newSet.w}px`, height: `${L.newSet.h}px` }}
              aria-label="New set"
              onClick={tapNew}
            >
              <Icon name="icon-plus" size={22} />
            </button>
          ) : null
        }
      >
        {showRack ? (
          <div class="controls" style={{ transform: `translate3d(0, ${L.controls.y}px, 0)`, height: `${L.controls.h}px` }}>
            <div class="side">
              <IconButton icon="icon-replay" label="Undo" onClick={undo} id="undo" />
              <IconButton icon="icon-remove" label="Start over" onClick={reset} />
            </div>
            <div class="middle">
              {openingShown ? (
                <span class={`chip opening ${result.opening !== null && result.opening >= OPENING_POINTS ? "good" : ""}`} id="opening">
                  {result.opening ?? 0}/{OPENING_POINTS}
                </span>
              ) : null}
              <Button id="play-btn" variant={result.changed ? "ok" : "teal"} size="small" disabled={!myTurn || Boolean(state.pending) || (result.changed && !playable)} onClick={submit}>
                <Icon name="icon-paw-menu" size={26} /> {label}
              </Button>
            </div>
            <div class="side">
              {/* One button, two sorts: by number, then by toy, then by number again. */}
              <button type="button" class="icon-btn" aria-label={sortBy === "number" ? "Sort by toy" : "123: sort by number"} title={sortBy === "number" ? "Sort by toy" : "Sort by number"} onClick={() => sort(sortBy === "number" ? "toy" : "number")} id="sort">
                {sortBy === "number" ? <img src={art("tile-fish")} alt="" width={28} height={28} /> : <span class="num-icon">123</span>}
              </button>
              <IconButton icon="fx-sparkle" label="Hint" onClick={() => void hint()} id="hint" />
            </div>
          </div>
        ) : null}

        {curtainSeat !== null ? <Curtain name={seatName(room.seats[curtainSeat])} cat={room.seats[curtainSeat]?.person?.cat ?? 0} onReveal={() => setRevealed({ seat: curtainSeat, key: turnKey })} /> : null}

        <Tip id="tt.drag" anchor="new-set" text="Drag pieces here to make a set." show={myTurn && !result.changed && rackIds.length > 0} />
        <Tip id="tt.open" anchor="opening" text="Your first play must reach this score." show={myTurn && !opened && result.changed && tipLearned("tt.drag")} />
        <Tip id="tt.play" anchor="play-btn" text="Tap Play to send your turn." show={playable && tipLearned("tt.open")} />
        <Tip id="tt.draw" anchor="play-btn" text="Nothing to play? Draw a toy." show={myTurn && !result.changed && tipLearned("tt.drag")} />
        <Tip id="tt.hint" anchor="hint" text="Stuck? Tap for a hint." show={myTurn && tipLearned("tt.draw") && !result.changed} />
      </TilesTableBase>
    </div>
  );
}
