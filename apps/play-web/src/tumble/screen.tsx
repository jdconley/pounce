/**
 * Toy Tumble on a phone, a tablet or a laptop (spec §5.2 to §5.5): your box with the cat on its
 * rim holding the next toy, the junk meter, every opponent as a live mini (a chip at a TV table),
 * the trick tray, the 3-2-1, round over, and watching once your box is out. Boxes are drawn on
 * canvases on the frame clock; the rest is Preact, redrawn only when what it shows changes.
 */
import { toyAt } from "@pounce/play-api/tumble/queue";
import { useEffect, useMemo, useRef, useState } from "preact/hooks";

import { art, RINGS } from "../lib/art";
import { buzz } from "../lib/haptics";
import { reducedMotion } from "../lib/settings";
import { play } from "../lib/sound";
import { mySeats, waitingSeats, waitingWords } from "../store/lobby";
import { useInsets } from "../table/cattower";
import { seatCat, seatName } from "../table/seat";
import { Button, Cat, learnTip, Tip, tipLearned, useSize } from "../ui/common";

import { BoxPainter, paintToy, TRICK_COLOR } from "./canvas";
import { attachKeys, attachTouch, aimsAtSelf, TrickPicker } from "./input";
import { playLayout, watchLayout, type BoxRect, type PlayLayout, type Rect } from "./layout";
import { stackHeight, type Fx } from "./rules";
import { PLAY_WITHOUT_AFTER_MS, playWithout, TumbleStore, type SeatState, type TumbleRoom } from "./store";

import type { RoomStore, RoomState } from "../store/room";
import type { RoomView } from "@pounce/play-api/protocol";
import type { Trick } from "@pounce/play-api/tumble/box";


/** Each trick's name, as the UI says it (spec §4.6). */
export const TRICK_NAME: Record<Trick, string> = {
  hairball: "Hairball",
  swipe: "Paw Swipe",
  catnip: "Catnip",
  scoop: "Scoop",
  settle: "Settle",
  nap: "Nap",
  swap: "Swap",
  bath: "Bath",
};

/** Wins needed for the game (spec §4.4). */
export const WINS_TO_WIN = 3;

/** The store for this table, started for as long as the component is up. */
export function useTumble(store: RoomStore, screen = false): TumbleStore {
  const tumble = useMemo(() => new TumbleStore({ room: store, screen }), [store, screen]);
  const [, setN] = useState(0);
  useEffect(() => {
    const off = tumble.subscribe(() => setN((n) => n + 1));
    tumble.start();
    return () => {
      off();
      tumble.stop();
    };
  }, [tumble]);
  return tumble;
}

/** Paw tokens: one filled per round won, of the three that win the game. */
export function Paws(props: { wins: number; size?: number }) {
  const n = Math.max(WINS_TO_WIN, props.wins);
  return (
    <span class="tt-paws" role="img" aria-label={`${props.wins} of ${WINS_TO_WIN}`} style={{ ["--paw" as string]: `${props.size ?? 14}px` }}>
      {Array.from({ length: n }, (_, i) => (
        <i class={i < props.wins ? "on" : ""} />
      ))}
    </span>
  );
}

/** The words on a box that isn't simply playing. */
export const stateWords = (s: SeatState): string | null => (s === "lag" ? "Reconnecting" : s === "out" ? "Out" : s === "away" ? "Away" : s === "left" ? "Left" : null);

/** The countdown's number: 3, 2, 1. */
export const countWords = (ms: number): string => String(Math.max(1, Math.ceil(ms / 1000)));

/** The tip to show now, one at a time (spec §5.8), or null. */
export function tipFor(p: { playing: boolean; held: number; waiting: number }): { id: string; text: string; anchor: string } | null {
  if (!p.playing) return null;
  if (p.waiting > 0 && !tipLearned("tumble.block")) return { id: "tumble.block", text: "Clear rows to block it.", anchor: "tt-meter" };
  if (p.held > 0 && !tipLearned("tumble.trick")) return { id: "tumble.trick", text: "Tap a trick, then a box.", anchor: "tt-tray" };
  if (!tipLearned("tumble.move")) return { id: "tumble.move", text: "Drag to move.", anchor: "tt-box" };
  if (!tipLearned("tumble.turn")) return { id: "tumble.turn", text: "Tap to turn.", anchor: "tt-box" };
  if (!tipLearned("tumble.drop")) return { id: "tumble.drop", text: "Flick down to drop.", anchor: "tt-box" };
  return null;
}

const rectStyle = (r: Rect) => ({ transform: `translate3d(${r.x}px, ${r.y}px, 0)`, width: `${r.w}px`, height: `${r.h}px` });

/** Plays what happened: a hit flies from thrower to target and shakes it; clears, set-downs and outs sound. */
function playFx(fx: Fx[], o: { mine: number | null; els: Map<number, HTMLElement>; layer: HTMLElement | null; sounds: boolean }): void {
  const still = reducedMotion();
  for (const f of fx) {
    if (f.k === "set" && f.seat === o.mine) buzz("tap");
    else if (f.k === "clear" && f.seat === o.mine) {
      if (o.sounds) play("sparkle", 0.6 + Math.min(0.4, f.rows * 0.1));
      buzz("drop");
    } else if (f.k === "out") {
      const el = o.els.get(f.seat);
      if (f.seat === o.mine && o.sounds) play("flip");
      el?.classList.add("tipped");
    } else if (f.k === "hit") {
      const from = o.els.get(f.from);
      const to = o.els.get(f.to);
      if (f.to === o.mine) {
        if (o.sounds) play(f.kind === "napped" ? "pop" : "thud", 0.7);
        if (f.kind !== "napped" && f.kind !== "junk") buzz("nope");
      }
      if (!to || still) continue;
      to.animate(
        f.kind === "napped"
          ? [{ opacity: 1 }, { opacity: 0.6 }, { opacity: 1 }]
          : [{ transform: "translateX(0)" }, { transform: "translateX(-5px)" }, { transform: "translateX(5px)" }, { transform: "translateX(0)" }],
        { duration: 320, easing: "ease-out", composite: "add" },
      );
      if (!from || from === to || !o.layer) continue;
      const a = from.getBoundingClientRect();
      const b = to.getBoundingClientRect();
      const base = o.layer.getBoundingClientRect();
      const dot = document.createElement("i");
      dot.className = `tt-throw ${f.kind}`;
      o.layer.append(dot);
      const x0 = a.left + a.width / 2 - base.left;
      const y0 = a.top + a.height / 2 - base.top;
      const x1 = b.left + b.width / 2 - base.left;
      const y1 = b.top + b.height / 2 - base.top;
      dot
        .animate(
          [
            { transform: `translate3d(${x0}px, ${y0}px, 0) scale(0.6)` },
            { transform: `translate3d(${(x0 + x1) / 2}px, ${Math.min(y0, y1) - 60}px, 0) scale(1.2)` },
            { transform: `translate3d(${x1}px, ${y1}px, 0) scale(0.8)` },
          ],
          { duration: 420, easing: "ease-in-out" },
        )
        .finished.then(() => dot.remove(), () => dot.remove());
    }
  }
}

type Props = { store: RoomStore; state: RoomState; sounds?: boolean; topInset?: number };

export function TumbleTable(props: Props) {
  const room = props.state.room!;
  const tumble = useTumble(props.store);
  const t = tumble.room;
  if (!t) return null;
  if (t.status === "between") return <RoundOver room={room} t={t} now={() => tumble.serverNow()} onPlayWithout={() => playWithout(props.store, room)} />;
  if (t.status === "over") return null;
  return <TumblePlay {...props} tumble={tumble} t={t} />;
}

function TumblePlay(props: Props & { tumble: TumbleStore; t: TumbleRoom }) {
  const { tumble, t } = props;
  const room = props.state.room!;
  const sounds = props.sounds ?? true;
  const [rootRef, size] = useSize<HTMLDivElement>();
  const safe = useInsets();
  const insets = useMemo(() => ({ ...safe, top: safe.top + (props.topInset ?? 0) }), [safe, props.topInset]);
  const mine = tumble.mySeat;
  const players = tumble.players;
  const others = players.filter((s) => s !== mine);
  const watching = !tumble.local;
  const chips = room.screen === true && !watching;
  const L: PlayLayout = useMemo(
    () => playLayout({ width: size.width || 375, height: size.height || 667, insets, others: others.length, chips }),
    [size.width, size.height, insets, others.length, chips],
  );
  const grid: BoxRect[] = useMemo(() => watchLayout({ width: size.width || 375, height: size.height || 667, insets, n: players.length }), [size.width, size.height, insets, players.length]);

  const els = useRef(new Map<number, HTMLElement>());
  const canvases = useRef(new Map<number, HTMLCanvasElement>());
  const painters = useRef(new Map<HTMLCanvasElement, BoxPainter>());
  const nextRef = useRef<HTMLCanvasElement>(null);
  const fxLayer = useRef<HTMLDivElement>(null);
  const boxRef = useRef<HTMLDivElement>(null);

  // What the chrome shows, redrawn only when it changes.
  const [ui, setUi] = useState(() => ({ held: [] as Trick[], waiting: 0, count: tumble.countdown() > 0 ? countWords(tumble.countdown()) : "", states: "", next: -1 }));
  const [, setPicked] = useState(0);
  const picker = useMemo(
    () =>
      new TrickPicker({
        use: (slot, seat) => {
          tumble.local?.use(slot, seat);
          learnTip("tumble.trick");
        },
        targetAt: (x, y) => {
          for (const [seat, el] of els.current) {
            const r = el.getBoundingClientRect();
            if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom && tumble.seatState(seat) === "ok") return seat;
          }
          return null;
        },
        changed: () => setPicked((n) => n + 1),
      }),
    [tumble],
  );

  // The frame loop: step this box, draw every box, play what happened.
  useEffect(() => {
    let raf = 0;
    let lastNext = -1;
    const visible = () => tumble.setHidden(document.visibilityState === "hidden");
    document.addEventListener("visibilitychange", visible);
    visible();
    const paint = () => {
      tumble.frame();
      const now = performance.timeOrigin + performance.now();
      for (const [seat, canvas] of canvases.current) {
        let p = painters.current.get(canvas);
        if (!p) painters.current.set(canvas, (p = new BoxPainter(canvas)));
        const v = tumble.view(seat, now);
        const cell = Number(canvas.dataset.cell) || 10;
        const meter = Number(canvas.dataset.meter) || 0;
        p.paint(v, { cell, meter, gap: Number(canvas.dataset.gap) || 0, landing: canvas.dataset.landing === "1" });
      }
      const mv = mine !== null ? tumble.view(mine, now) : null;
      const next = mv ? mv.box.next + 1 : -1;
      if (nextRef.current && tumble.r !== null && next !== lastNext && t.roundSeed) {
        lastNext = next;
        paintToy(nextRef.current, next >= 0 ? toyAt(t.roundSeed, next) : null, nextRef.current.clientWidth || 40);
      }
      const fx = tumble.takeFx();
      if (fx.length > 0) playFx(fx, { mine, els: els.current, layer: fxLayer.current, sounds });
      if (fx.some((f) => f.k === "clear" && f.seat === mine)) learnTip("tumble.block");
      const ms = tumble.countdown(now);
      const states = players.map((s) => tumble.seatState(s)).join();
      const held = mv?.box.held ?? [];
      const waiting = mv?.waiting.length ?? 0;
      const count = ms > 0 ? countWords(ms) : "";
      setUi((u) => (u.held.join() === held.join() && u.waiting === waiting && u.count === count && u.states === states ? u : { held: [...held], waiting, count, states, next }));
      raf = requestAnimationFrame(paint);
    };
    raf = requestAnimationFrame(paint);
    return () => {
      cancelAnimationFrame(raf);
      document.removeEventListener("visibilitychange", visible);
    };
  }, [tumble, tumble.r, mine, players.join()]);

  // Touch on your box and the keys, while it plays.
  useEffect(() => {
    const el = boxRef.current;
    const local = () => tumble.local;
    const active = () => !!local() && !local()!.view().box.out && tumble.countdown() === 0 && picker.lifted === null;
    const h = {
      move: (dx: -1 | 1) => {
        local()?.move(dx);
        learnTip("tumble.move");
      },
      turn: (dir: 1 | -1) => {
        local()?.turn(dir);
        learnTip("tumble.turn");
      },
      soft: (on: boolean) => local()?.soft(on),
      drop: () => {
        local()?.drop();
        learnTip("tumble.drop");
      },
    };
    const offTouch = el ? attachTouch(el, h, { cell: () => L.box.cell, active }) : () => undefined;
    const offKeys = attachKeys(window, { ...h, useOn: (seat) => (local()?.view().box.held.length ? local()?.use(0, seat) : undefined) }, { active: () => !!local() && !local()!.view().box.out });
    return () => {
      offTouch();
      offKeys();
    };
  }, [tumble, tumble.r, L.box.cell, watching]);

  const register = (seat: number, cell: number, opts: { meter?: number; gap?: number; landing?: boolean } = {}) => (c: HTMLCanvasElement | null) => {
    if (!c) {
      for (const [s, el] of canvases.current) if (el.dataset.seat === String(seat) && !el.isConnected) canvases.current.delete(s);
      return;
    }
    c.dataset.seat = String(seat);
    c.dataset.cell = String(cell);
    c.dataset.meter = String(opts.meter ?? 0);
    c.dataset.gap = String(opts.gap ?? 0);
    c.dataset.landing = opts.landing ? "1" : "0";
    canvases.current.set(seat, c);
  };
  const holder = (seat: number) => (el: HTMLElement | null) => {
    if (el) els.current.set(seat, el);
    else els.current.delete(seat);
  };

  const lifted = picker.lifted !== null ? ui.held[picker.lifted] : undefined;
  const glows = (seat: number): boolean => lifted !== undefined && tumble.seatState(seat) === "ok" && (aimsAtSelf(lifted) ? seat === mine : seat !== mine);
  const tip = tipFor({ playing: !watching && ui.count === "", held: ui.held.length, waiting: ui.waiting });
  const wins = (s: number) => t.wins[s] ?? 0;

  const label = (s: number, big: boolean) => (
    <span class={`tt-label ${big ? "big" : ""}`}>
      <Cat cat={seatCat(room.seats[s])} pose={tumble.seatState(s) === "out" ? "terrified" : "awake"} size={big ? 20 : 16} />
      <b class="tt-num">{s + 1}</b>
      {big ? <span class="tt-name">{seatName(room.seats[s])}</span> : null}
      <Paws wins={wins(s)} size={big ? 11 : 7} />
    </span>
  );
  const status = (s: number) => {
    const words = stateWords(tumble.seatState(s));
    return words ? <span class={`tt-state ${tumble.seatState(s)}`}>{words}</span> : null;
  };

  return (
    <div class={`tt-table ${watching ? "watching" : ""}`} ref={rootRef} data-live={!watching && ui.count === "" && tumble.seatState(mine ?? -1) === "ok" ? "" : undefined} style={{ ["--ring" as string]: RINGS[(mine ?? 0) % RINGS.length] }}>
      {watching ? (
        <>
          <p class="tt-watch-head outlined" style={{ top: `${insets.top + 12}px` }}>
            Round {t.r}
          </p>
          {players.map((s, i) => {
            const r = grid[i];
            if (!r) return null;
            return (
              <div class={`tt-mini watch ${tumble.seatState(s)}`} ref={holder(s)} style={{ ...rectStyle(r), ["--ring" as string]: RINGS[s % RINGS.length] }} key={`w${s}`}>
                <canvas class="tt-canvas" ref={register(s, r.cell, { landing: true })} style={{ width: `${r.cell * 12}px`, height: `${r.cell * 18}px` }} />
                {status(s)}
                {label(s, r.w >= 110)}
              </div>
            );
          })}
        </>
      ) : (
        <>
          <div class="tt-rim" style={rectStyle(L.rim)}>
            <span class="tt-rim-cat">
              <Cat cat={seatCat(mine !== null ? room.seats[mine] : undefined)} pose="awake" size={L.rim.h} />
              <canvas class="tt-next" ref={nextRef} aria-label="Next toy" style={{ width: `${Math.round(L.rim.h * 0.75)}px`, height: `${Math.round(L.rim.h * 0.75)}px` }} />
            </span>
            <b class="tt-num big">{(mine ?? 0) + 1}</b>
            <Paws wins={mine !== null ? wins(mine) : 0} size={16} />
          </div>
          <div
            id="tt-box"
            class={`tt-box ${tumble.seatState(mine ?? 0)} ${glows(mine ?? -1) ? "glow" : ""}`}
            ref={(el) => {
              boxRef.current = el;
              holder(mine ?? -1)(el);
            }}
            style={rectStyle({ x: L.box.x, y: L.box.y, w: L.meter.x + L.meter.w - L.box.x, h: L.box.h })}
            onClick={() => {
              if (mine !== null && picker.lifted !== null) picker.tapBox(mine);
            }}
          >
            <canvas
              class="tt-canvas"
              ref={register(mine ?? -1, L.box.cell, { meter: L.meter.w, gap: L.meter.x - L.box.x - L.box.w, landing: true })}
              style={{ width: `${L.meter.x + L.meter.w - L.box.x}px`, height: `${L.box.h}px` }}
            />
            <span id="tt-meter" class="tt-meter-at" style={{ left: `${L.meter.x - L.box.x}px`, width: `${L.meter.w}px` }} />
            {status(mine ?? 0)}
          </div>
          {chips
            ? others.map((s, i) => {
                const r = L.chips[i];
                if (!r) return null;
                const v = tumble.view(s);
                const height = v ? stackHeight(v.box) / 18 : 0;
                return (
                  <button
                    type="button"
                    class={`tt-chip ${r.w < 110 ? "narrow" : ""} ${tumble.seatState(s)} ${glows(s) ? "glow" : ""}`}
                    ref={holder(s)}
                    style={{ ...rectStyle(r), ["--ring" as string]: RINGS[s % RINGS.length] }}
                    onClick={() => picker.tapBox(s)}
                    aria-label={seatName(room.seats[s])}
                  >
                    <Cat cat={seatCat(room.seats[s])} pose="awake" size={Math.min(32, r.h - 8)} />
                    <span class="tt-chip-body">
                      <span class="tt-name">{stateWords(tumble.seatState(s)) ?? seatName(room.seats[s])}</span>
                      <span class="tt-bar">
                        <i style={{ width: `${Math.round(Math.min(1, height) * 100)}%` }} />
                      </span>
                    </span>
                    <span class="tt-chip-wins">{wins(s)}</span>
                  </button>
                );
              })
            : others.map((s, i) => {
                const r = L.minis[i];
                if (!r) return null;
                return (
                  <button
                    type="button"
                    class={`tt-mini ${tumble.seatState(s)} ${glows(s) ? "glow" : ""}`}
                    ref={holder(s)}
                    style={{ ...rectStyle(r), ["--ring" as string]: RINGS[s % RINGS.length] }}
                    onClick={() => picker.tapBox(s)}
                    aria-label={seatName(room.seats[s])}
                    key={`m${s}`}
                  >
                    <canvas class="tt-canvas" ref={register(s, r.cell)} style={{ width: `${r.cell * 12}px`, height: `${r.cell * 18}px` }} />
                    {status(s)}
                    {label(s, r.w >= 110)}
                  </button>
                );
              })}
          <div id="tt-tray" class="tt-tray" role="toolbar" aria-label="Tricks" style={rectStyle(L.tray)}>
            {L.slots.map((r, i) => {
              const trick = ui.held[i];
              return (
                <button
                  type="button"
                  class={`tt-slot ${trick ? "full" : ""} ${picker.lifted === i ? "lifted" : ""}`}
                  disabled={!trick}
                  style={{ left: `${r.x - L.tray.x}px`, top: `${r.y - L.tray.y}px`, width: `${r.w}px`, height: `${r.h}px`, ["--trick" as string]: trick ? TRICK_COLOR[trick] : "transparent" }}
                  onPointerDown={(e) => trick && picker.pointerDown(i, e)}
                  onPointerMove={(e) => picker.pointerMove(e)}
                  onPointerUp={(e) => picker.pointerUp(e)}
                  onKeyDown={(e) => {
                    if (trick && (e.key === "Enter" || e.key === " ")) {
                      e.preventDefault();
                      picker.tapTrick(i);
                    }
                  }}
                  aria-pressed={picker.lifted === i}
                  aria-label={trick ? TRICK_NAME[trick] : "Empty"}
                >
                  {trick ? <span class="tt-slot-name" style={{ fontSize: `${Math.max(9, Math.round(r.w * 0.2))}px` }}>{TRICK_NAME[trick]}</span> : null}
                </button>
              );
            })}
          </div>
        </>
      )}
      <div class="tt-fx" ref={fxLayer} aria-hidden="true" />
      {picker.drag ? <i class="tt-drag" style={{ transform: `translate3d(${picker.drag.x}px, ${picker.drag.y}px, 0)`, ["--trick" as string]: ui.held[picker.drag.slot] ? TRICK_COLOR[ui.held[picker.drag.slot]!] : "#fff" }} /> : null}
      {ui.count ? (
        <div class="tt-count" role="status" aria-live="polite">
          <span class="tt-count-round outlined">Round {t.r}</span>
          <span class="tt-count-n outlined" key={ui.count}>
            {ui.count}
          </span>
        </div>
      ) : null}
      {tip ? <Tip id={tip.id} anchor={tip.anchor} text={tip.text} show place={tip.anchor === "tt-tray" ? "above" : "below"} /> : null}
    </div>
  );
}

/** The clock, read again about once a second while `on` (on the frame clock, not a timer). */
function useSecond(on: boolean, clock: () => number): number {
  const [now, setNow] = useState(clock);
  useEffect(() => {
    if (!on) return;
    let raf = 0;
    const tick = () => {
      const t = clock();
      setNow((n) => (t - n >= 1000 ? t : n));
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [on]);
  return now;
}

/** Confetti over the round's winner: where each bit starts across, its delay and colour. */
const CONFETTI: readonly [number, number, string][] = Array.from({ length: 16 }, (_, i) => [(i * 37) % 100, (i * 113) % 700, RINGS[i % RINGS.length] as string]);

/** Between rounds (spec §5.5): the winner's cat on top with confetti, everyone's paw tokens, and who the next round waits for. */
export function RoundOver(props: { room: RoomView; t: TumbleRoom; tv?: boolean; now?: () => number; onPlayWithout?: () => void }) {
  const { room, t } = props;
  const winner = t.winner;
  const mine = mySeats(room);
  const won = winner !== null && mine.includes(winner);
  useEffect(() => {
    if (props.tv) return;
    if (won) play("fanfare");
    buzz(won ? "win" : "tap");
  }, [t.r]);
  const seats = room.seats.flatMap((s, i) => ((s.kind === "human" || s.kind === "bot") && !t.left[i] ? [i] : []));
  const waiting = waitingSeats(room).filter((s) => !t.left[s] && !t.away[s]);
  // The host may go on without them once the next round has waited 20 seconds (spec §5.1).
  const now = useSecond(t.waitingSince !== null && waiting.length > 0, props.now ?? Date.now);
  const waitedLong = t.waitingSince !== null && now - t.waitingSince >= PLAY_WITHOUT_AFTER_MS;
  return (
    <div class={`tt-over ${props.tv ? "tv" : ""}`} role="dialog" aria-label={`Round ${t.r}`}>
      <img class="tt-over-burst" src={art("sunburst")} alt="" />
      <div class="panel tt-over-card">
        {t.r > 0 ? <p class="tt-over-round">Round {t.r}</p> : null}
        {winner !== null ? (
          <div class="tt-over-winner" style={{ ["--ring" as string]: RINGS[winner % RINGS.length] }}>
            <span class="tt-confetti" aria-hidden="true">
              {CONFETTI.map(([x, delay, color]) => (
                <i style={{ left: `${x}%`, animationDelay: `${delay}ms`, background: color }} />
              ))}
            </span>
            <Cat cat={seatCat(room.seats[winner])} pose="celebrate" size={props.tv ? 220 : 120} />
            <span class="name-tag">{seatName(room.seats[winner])}</span>
          </div>
        ) : null}
        {won ? <h2 class="title outlined">You win the round</h2> : null}
        <ol class="tt-over-paws">
          {seats.map((s) => (
            <li class={s === winner ? "won" : ""}>
              <Cat cat={seatCat(room.seats[s])} pose={s === winner ? "celebrate" : "idle"} size={props.tv ? 56 : 32} />
              <span class="who">{seatName(room.seats[s])}</span>
              {t.away[s] ? <span class="tt-state away">Away</span> : <Paws wins={t.wins[s] ?? 0} size={props.tv ? 26 : 16} />}
            </li>
          ))}
        </ol>
        {waiting.length > 0 ? <p class="tt-over-wait">{waitingWords(room, waiting)}</p> : null}
        {waiting.length > 0 && props.onPlayWithout && room.youAreHost && mine.length > 0 && waitedLong ? (
          <Button variant="violet" id="play-without" onClick={props.onPlayWithout}>
            {waiting.length === 1 ? `Play without ${seatName(room.seats[waiting[0]!])}` : `Play without ${waiting.length}`}
          </Button>
        ) : null}
      </div>
    </div>
  );
}
