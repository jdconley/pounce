/**
 * Pieces both tables use: cards in flight, the pass-the-device curtain, the round's results, and the
 * Cards/Table switch of a phone whose table is on a TV.
 */
import { useEffect, useLayoutEffect, useRef, useState } from "preact/hooks";


import { art } from "../lib/art";
import { buzz } from "../lib/haptics";
import { reducedMotion } from "../lib/settings";
import { play } from "../lib/sound";
import { Button, Cat, Icon, learnTip, Sheet } from "../ui/common";

import { CardBack, CardFace } from "./faces";
import { MOVE, transformOf, type Pose } from "./motion";
import { seatCat, seatName } from "./seat";

import type { TrayLabel } from "./ct-layout";
import type { Rect } from "./drag";
import type { View } from "../store/views";
import type { RoomView } from "@pounce/play-api/protocol";
import type { CardId } from "@pounce/play-api/rules/cards";
import type { GameEvent } from "@pounce/play-api/rules/engine";

/** A card going somewhere it won't stay (a draw into someone else's hand). */
export type Flight = { key: string; from: Pose; to: Pose; card?: CardId };

function FlightCard(props: { f: Flight; onDone: () => void }) {
  const ref = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el || reducedMotion()) {
      props.onDone();
      return;
    }
    const a = el.animate(
      [
        { transform: transformOf(props.f.from), opacity: 1 },
        { transform: transformOf({ ...props.f.to, s: (props.f.to.s ?? 1) * 1.05 }), opacity: 1, offset: 0.85 },
        { transform: transformOf(props.f.to), opacity: 0 },
      ],
      { duration: MOVE.duration + 120, easing: "cubic-bezier(0.3, 0.7, 0.3, 1)", fill: "forwards" },
    );
    a.onfinish = props.onDone;
    return () => a.cancel();
  }, []);
  return (
    <div class="card flight" ref={ref} style={{ transform: transformOf(props.f.from), zIndex: 900 }} aria-hidden="true">
      <div class="card-inner">{props.f.card !== undefined ? <CardFace id={props.f.card} /> : <CardBack />}</div>
    </div>
  );
}

export function Flights(props: { flights: Flight[]; cw: number; ch: number; onDone: (key: string) => void }) {
  return (
    <>
      {props.flights.map((f) => (
        <FlightCard key={f.key} f={f} onDone={() => props.onDone(f.key)} />
      ))}
    </>
  );
}

const HOLD_MS = 650;

/**
 * A discard with the level made in the trays: lay it down first (the obvious choice, focused, so
 * Enter takes it), or discard anyway. Esc or a tap outside goes back to the turn.
 */
export function LayDownFirst(props: { onLay: () => void; onDiscard: () => void; onClose: () => void }) {
  return (
    <Sheet title="Lay down first?" onClose={props.onClose}>
      <div class="sheet-actions">
        <Button wide variant="ok" id="lay-first" onClick={props.onLay}>
          <Icon name="icon-paw-menu" size={28} /> Lay down
        </Button>
        <Button wide variant="violet" id="discard-anyway" onClick={props.onDiscard}>
          Discard anyway
        </Button>
      </div>
    </Sheet>
  );
}

/**
 * Pass and play's curtain (PassCurtainView.swift): the next person's hand stays hidden until
 * they hold the button, so nobody sees a hand that isn't theirs.
 */
export function Curtain(props: { name: string; cat: number; onReveal: () => void; label?: string }) {
  const [holding, setHolding] = useState(false);
  // The hold is the fill animation itself: its end reveals the hand, so no timer runs beside it.
  const start = () => {
    setHolding(true);
    buzz("tap");
  };
  const stop = () => setHolding(false);
  const filled = () => {
    if (!holding) return;
    play("whoosh", 0.6);
    buzz("pick");
    props.onReveal();
  };
  return (
    <div class="curtain" role="dialog" aria-label={`Pass to ${props.name}`} style={{ backgroundImage: `url(${art("curtain-stage")})` }}>
      <Cat cat={props.cat} pose="awake" size={140} />
      <h2 class="outlined title">Pass to {props.name}</h2>
      <button
        type="button"
        class={`btn ok big hold ${holding ? "holding" : ""}`}
        onPointerDown={start}
        onPointerUp={stop}
        onPointerLeave={stop}
        onPointerCancel={stop}
        onKeyDown={(e) => {
          if ((e.key === "Enter" || e.key === " ") && !e.repeat) start();
        }}
        onKeyUp={stop}
        onContextMenu={(e) => e.preventDefault()}
      >
        <span class="fill" style={{ animationDuration: `${HOLD_MS}ms` }} onAnimationEnd={filled} />
        <span class="label">{props.label ?? "Hold to see your hand"}</span>
      </button>
    </div>
  );
}

/** The round's results (Celebrations.swift): points, and who climbs a shelf. */
export function RoundOver(props: { seats: RoomView["seats"]; ev: Extract<GameEvent, { kind: "roundOver" }>; mine: number[] }) {
  const { ev } = props;
  const rows = props.seats.flatMap((s, i) => (s.kind === "human" || s.kind === "bot" ? [i] : []));
  return (
    <div class="round-over" role="status" aria-live="polite">
      <div class="panel round-card">
        <h2 class="outlined title">{ev.wentOut !== null ? `${seatName(props.seats[ev.wentOut])} went out` : "Round over"}</h2>
        <ul>
          {rows.map((s) => {
            const up = ev.advanced.includes(s);
            return (
              <li class={up ? "up" : ""}>
                <Cat cat={seatCat(props.seats[s])} pose={up ? "leap" : "idle"} size={44} />
                <span class="who">{seatName(props.seats[s])}</span>
                <span class="pts">{ev.points[s] ? `+${ev.points[s]}` : "0"}</span>
                <span class="climb">{up ? `Level ${Math.min((ev.phase[s] ?? 0) + 1, 10)}` : "Stays"}</span>
              </li>
            );
          })}
        </ul>
      </div>
    </div>
  );
}

let textNow: number | null = null;
const textListeners = new Set<(t: number) => void>();
const readText = () => (parseFloat(getComputedStyle(document.documentElement).fontSize) || 16) / 16;

if (typeof window !== "undefined") {
  window.addEventListener("resize", () => {
    // In the next frame, after the browser's own layout (a zoom resizes too).
    requestAnimationFrame(() => {
      textNow = readText();
      for (const l of [...textListeners]) l(textNow);
    });
  });
}

/**
 * A tray's words: what it wants while empty ("Set of 3", as wide as the tray lets it be), then its
 * count ("2/3") in the room the layout keeps for it at the tray's left (`trayLabel`), clear of its cards.
 */
export function TrayCount(props: { tray: Rect; label: TrayLabel; text: string; words: boolean }) {
  const { label } = props;
  const style = props.words ? { fontSize: `${label.font}px`, maxWidth: `${props.tray.w - 20}px` } : { fontSize: `${label.font}px`, width: `${label.w}px` };
  return (
    <span class={`tray-label ${props.words ? "words" : "count"}`} style={style}>
      {props.text}
    </span>
  );
}

/** The reader's text size against the default: the root font over 16 px (2 at 200%). */
export function useTextScale(): number {
  const [text, setText] = useState(() => (textNow ??= typeof document === "undefined" ? 1 : readText()));
  useEffect(() => {
    textListeners.add(setText);
    return () => void textListeners.delete(setText);
  }, []);
  return text;
}

/**
 * Cards or Table, one tap, for a phone whose table is on a TV: just this player's cards (the
 * controller), or the whole table as it is without a TV. It sits at the top of both.
 */
export function SwitchView(props: { view: View; onChange: (view: View) => void; style?: Record<string, string> }) {
  return (
    <div id="view-switch" class="view-switch" role="group" aria-label="View" style={props.style}>
      {(["cards", "table"] as const).map((v) => (
        <button
          type="button"
          class={props.view === v ? "on" : ""}
          aria-pressed={props.view === v}
          onClick={() => {
            play("pop", 0.4);
            buzz("tap");
            learnTip("tv.switch");
            if (v !== props.view) props.onChange(v);
          }}
        >
          {v === "cards" ? "Cards" : "Table"}
        </button>
      ))}
    </div>
  );
}
