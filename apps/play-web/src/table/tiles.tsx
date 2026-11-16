/**
 * The Tuna Tiles table (TilesScene.swift): opponents across the top, the sets inside the rope
 * with the toy box, the controls, and the rack. A turn is built on this device (tiles-draft.ts)
 * and sent whole with Play; with nothing changed the button draws instead.
 */
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "preact/hooks";


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
import { seatName, SeatAvatar } from "./seat";
import { Curtain } from "./shared";
import { checkDraft, ghostOf, OPENING_POINTS, placedThisTurn, sameDraft, sortRack, toNewSet, toRack, toSet, type Draft } from "./tiles-draft";
import { tilesLayout } from "./tiles-layout";

import type { RoomState, RoomStore } from "../store/room";
import type { TileId } from "@pounce/play-api/tiles/pieces";
import type { TilesView } from "@pounce/play-api/tiles/view";

type Hover = { kind: "set"; set: number; index: number } | { kind: "new" } | { kind: "rack"; index: number } | null;

export function TilesTable(props: { store: RoomStore; state: RoomState }) {
  const { store, state } = props;
  const room = state.room!;
  const v = room.tiles as TilesView;
  const [rootRef, size] = useSize<HTMLDivElement>();
  const insets = useInsets();
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
  const [rackOrder, setRackOrder] = useState<TileId[]>([]);
  const lastBase = useRef(baseKey);
  useEffect(() => {
    if (lastBase.current === baseKey) return;
    lastBase.current = baseKey;
    setDraft({ table: v.table, rack: serverRack });
    setHistory([]);
  }, [baseKey]);

  // The rack keeps the player's order; new pieces go on the end.
  const rackIds = [...rackOrder.filter((id) => draft.rack.includes(id)), ...draft.rack.filter((id) => !rackOrder.includes(id))];
  useEffect(() => {
    if (rackIds.join() !== rackOrder.join()) setRackOrder(rackIds);
  });

  const result = checkDraft(v.table, serverRack, opened, { table: draft.table, rack: rackIds });
  const playable = myTurn && result.changed && result.check?.ok === true;

  const [selected, setSelected] = useState<TileId | null>(null);
  const [hover, setHover] = useState<Hover>(null);
  const opponents = room.seats.flatMap((s, i) => ((s.kind === "human" || s.kind === "bot") && i !== seat ? [i] : []));

  const L = useMemo(
    () =>
      tilesLayout({
        width: size.width || 360,
        height: size.height || 640,
        insets,
        opponents,
        sets: draft.table.map((s) => s.length),
        rack: rackIds.length,
      }),
    [size.width, size.height, insets, opponents.join(), draft.table.map((s) => s.length).join(), rackIds.length],
  );

  const avatarPose = (s: number): Pose => {
    const at = L.opponents.get(s) ?? { x: size.width / 2, y: -40 };
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
            play("flip", 0.6);
            if (ev.tile !== undefined) motion.spawnFrom(`p${ev.tile}`, poolPose);
          } else if (ev.kind === "played") {
            if (!mine.includes(ev.seat)) for (const id of ev.placed) motion.spawnFrom(`p${id}`, avatarPose(ev.seat));
            play("sparkle", 0.7);
            buzz("drop");
          } else if (ev.kind === "passed") {
            play("tick", 0.5);
          } else if (ev.kind === "turn" && mine.includes(ev.seat)) {
            play("tick", 0.6);
            buzz("turn");
          } else if (ev.kind === "gameOver") {
            play("fanfare");
            buzz("win");
          }
        },
      }),
    [store, L, mine.join()],
  );

  useEffect(() => {
    if (!state.error) return;
    play("nope");
    buzz("nope");
    wiggle(rootRef.current?.querySelector(".board") as HTMLElement | null);
  }, [state.error?.n]);

  // Poses: table pieces, then the rack.
  const poses = new Map<string, Pose>();
  draft.table.forEach((set, si) => set.forEach((id, i) => {
    const p = L.sets[si]?.poses[i];
    if (p) poses.set(`p${id}`, p);
  }));
  rackIds.forEach((id, i) => {
    const p = L.rack[i];
    if (p) poses.set(`p${id}`, p);
  });

  useLayoutEffect(() => {
    motion.apply(els.current, poses);
  });

  const setEl = (key: string) => (el: HTMLElement | null) => {
    if (el) els.current.set(key, el);
    else els.current.delete(key);
  };

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

  const targetAt = (p: Point, id: TileId): Hover => {
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
  const [sortBy, setSortBy] = useState<"number" | "toy" | null>(null);
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
  const label = result.changed ? "Play" : v.poolCount > 0 ? "Draw" : "Pass";
  const style = { ["--pw" as string]: `${L.pw}px`, ["--ph" as string]: `${L.ph}px`, ["--avatar" as string]: `${L.avatar}px` };

  return (
    <div class={`tt-table ${myTurn ? "my-turn" : ""}`} ref={rootRef} style={style}>
      {opponents.map((s) => {
        const at = L.opponents.get(s);
        if (!at) return null;
        return (
          <div class="avatar-at" style={{ transform: `translate3d(${at.x - L.avatar / 2}px, ${at.y - L.avatar / 2}px, 0)` }}>
            <SeatAvatar seat={s} info={room.seats[s]} size={L.avatar} turn={v.turn === s && v.status === "playing"} count={v.rackCounts[s]} out={v.forfeited[s]} />
          </div>
        );
      })}

      <div class="board" style={{ transform: `translate3d(${L.board.x}px, ${L.board.y}px, 0)`, width: `${L.board.w}px`, height: `${L.board.h}px` }} />
      <div class="pool" style={{ transform: `translate3d(${L.pool.x}px, ${L.pool.y}px, 0)`, width: `${L.pool.size}px` }} role="img" aria-label={`Toy box: ${v.poolCount} pieces`}>
        <img src={art(v.poolCount > 0 ? "toy-box" : "toy-box-closed")} alt="" />
        <span class="pile-count">{v.poolCount}</span>
      </div>

      {L.sets.map((set, si) => {
        const mark = result.marks[si];
        const h = hover?.kind === "set" && hover.set === si;
        return (
          <button
            type="button"
            class={`set-zone ${mark ?? ""} ${h ? "hot" : ""}`}
            style={{ transform: `translate3d(${set.rect.x - 4}px, ${set.rect.y - 4}px, 0)`, width: `${set.rect.w + 8}px`, height: `${set.rect.h + 8}px` }}
            aria-label={`Set: ${(draft.table[si] ?? []).map((id, i) => pieceLabel(id, ghostOf(draft.table[si] ?? [], i) ?? undefined)).join(", ")}${mark === "bad" ? ". Not a set yet" : ""}`}
            tabIndex={selected !== null ? 0 : -1}
            onClick={() => tapSet(si)}
          >
            {mark === "good" ? <img class="mark" src={art("icon-check")} alt="" /> : mark === "bad" ? <span class="mark bad" /> : null}
          </button>
        );
      })}
      {myTurn ? (
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
      ) : null}

      <div class="pieces">
        {[...poses.keys()].map((key) => {
          const id = Number(key.slice(1));
          const p = poses.get(key)!;
          const si = draft.table.findIndex((set) => set.includes(id));
          const ghost = si >= 0 ? ghostOf(draft.table[si]!, draft.table[si]!.indexOf(id)) : null;
          const can = draft.rack.includes(id) || movable(id);
          return (
            <div key={key} ref={setEl(key)} class={`tile ${selected === id ? "picked" : ""} ${can ? "mine" : ""}`} style={{ transform: transformOf(p), zIndex: p.z ?? 1 }} onPointerDown={can ? onDown(id) : undefined}>
              {can ? (
                <button type="button" class="tile-inner" aria-label={pieceLabel(id, ghost ?? undefined)} aria-pressed={selected === id} onClick={(e) => e.preventDefault()} onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    setSelected((s) => (s === id ? null : id));
                  }
                }}>
                  <PieceFace id={id} ghost={ghost} />
                </button>
              ) : (
                <div class="tile-inner" role="img" aria-label={pieceLabel(id, ghost ?? undefined)}>
                  <PieceFace id={id} ghost={ghost} />
                </div>
              )}
            </div>
          );
        })}
      </div>

      {showRack ? (
        <div class="controls" style={{ transform: `translate3d(0, ${L.controls.y}px, 0)`, height: `${L.controls.h}px` }}>
          <div class="side">
            <IconButton icon="icon-replay" label="Undo" onClick={undo} id="undo" />
            <IconButton icon="icon-remove" label="Start over" onClick={reset} />
          </div>
          <div class="middle">
            {!opened && myTurn && result.changed ? (
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

      <p class={`cue ${myTurn ? "mine" : ""}`} aria-live="polite" style={{ transform: `translate3d(-50%, ${L.board.y + L.board.h - 40}px, 0)` }}>
        {v.status !== "playing" ? "" : myTurn ? (result.changed ? (playable ? "Tap Play" : "Not a play yet") : "Your turn") : `${turnName}'s turn`}
      </p>

      {curtainSeat !== null ? <Curtain name={seatName(room.seats[curtainSeat])} cat={room.seats[curtainSeat]?.person?.cat ?? 0} onReveal={() => setRevealed({ seat: curtainSeat, key: turnKey })} /> : null}

      <Tip id="tt.drag" anchor="new-set" text="Drag pieces here to make a set." show={myTurn && !result.changed && rackIds.length > 0} />
      <Tip id="tt.open" anchor="opening" text="Your first play must reach this score." show={myTurn && !opened && result.changed && tipLearned("tt.drag")} />
      <Tip id="tt.play" anchor="play-btn" text="Tap Play to send your turn." show={playable && tipLearned("tt.open")} />
      <Tip id="tt.draw" anchor="play-btn" text="Nothing to play? Draw a toy." show={myTurn && !result.changed && tipLearned("tt.drag")} />
      <Tip id="tt.hint" anchor="hint" text="Stuck? Tap for a hint." show={myTurn && tipLearned("tt.draw") && !result.changed} />
    </div>
  );
}
