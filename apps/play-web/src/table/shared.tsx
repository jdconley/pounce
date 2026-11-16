/** Pieces both tables use: cards in flight, the pass-the-device curtain, the round's results. */
import { useLayoutEffect, useRef, useState } from "preact/hooks";


import { art } from "../lib/art";
import { buzz } from "../lib/haptics";
import { reducedMotion } from "../lib/settings";
import { play } from "../lib/sound";
import { Cat } from "../ui/common";

import { CardBack, CardFace } from "./faces";
import { MOVE, transformOf, type Pose } from "./motion";
import { seatCat, seatName } from "./seat";

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
 * Pass and play's curtain (PassCurtainView.swift): the next person's hand stays hidden until
 * they hold the button, so nobody sees a hand that isn't theirs.
 */
export function Curtain(props: { name: string; cat: number; onReveal: () => void }) {
  const [holding, setHolding] = useState(false);
  const timer = useRef<number | null>(null);
  const start = () => {
    setHolding(true);
    buzz("tap");
    timer.current = window.setTimeout(() => {
      play("whoosh", 0.6);
      buzz("pick");
      props.onReveal();
    }, HOLD_MS);
  };
  const stop = () => {
    setHolding(false);
    if (timer.current !== null) window.clearTimeout(timer.current);
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
        <span class="fill" style={{ animationDuration: `${HOLD_MS}ms` }} />
        <span class="label">Hold to see your hand</span>
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
