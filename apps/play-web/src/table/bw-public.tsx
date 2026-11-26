/**
 * The Birdwatch table as anyone at it may see it (design §5.2, §5.6): the other cats around the
 * window with their card counts, ribbons, the dealer's chip and their bid signs; the sill with the
 * trick, each card in front of the cat that played it; the trump badge and the high bid; and the
 * score strip. The phone's table (birdwatch.tsx) draws this with its hand on top; a TV draws this
 * alone. Nothing here can show the 5-player partner before the called card is played: it reads
 * only `view.partner` (bw-model `ribbonOf`).
 */
import { useEffect, useLayoutEffect, useRef, useState } from "preact/hooks";

import { catArt } from "../lib/art";
import { buzz } from "../lib/haptics";
import { reducedMotion } from "../lib/settings";
import { play } from "../lib/sound";

import { BirdFace, SuitIcon } from "./bw-faces";
import { cardLabel, ribbonOf, sideName, sides, signOf, SUIT_WORD, type CardId } from "./bw-model";
import { bump, transformOf, type Motion, type Pose } from "./motion";
import { seatCat, seatName, SeatAvatar } from "./seat";

import type { BwLayout } from "./bw-layout";
import type { RoomStore } from "../store/room";
import type { BirdView } from "@pounce/play-api/birdwatch/view";
import type { RoomView } from "@pounce/play-api/protocol";
import type { ComponentChildren, VNode } from "preact";

/** The sizes the table's CSS reads, for the `.bw-table` it is drawn into. */
export const bwStyle = (L: BwLayout) => ({ ["--cw" as string]: `${L.cw}px`, ["--ch" as string]: `${L.ch}px`, ["--avatar" as string]: `${L.avatar}px` });

/** A hand drawn on the table: its cards' poses and how each is drawn, in the same set as the sill's, so a card goes from hand to sill in one move. */
export type BwHand = {
  poses: Map<string, Pose>;
  els: Map<string, HTMLElement>;
  render: (id: CardId, pose: Pose, ref: (el: HTMLElement | null) => void) => VNode;
};

export type BwPublicProps = {
  store: RoomStore;
  room: RoomView;
  layout: BwLayout;
  motion: Motion;
  sounds?: boolean;
  haptics?: boolean;
  /** The score strip opens the score sheet. */
  onStrip?: () => void;
  /** A TV: bigger words, no buttons. */
  tv?: boolean;
  hand?: BwHand;
  children?: ComponentChildren;
};

type Sweep = { key: number; winner: number; cards: { seat: number; card: CardId }[] };

export function BwPublic(props: BwPublicProps) {
  const { store, room, layout: L, motion } = props;
  const v = room.birdwatch as BirdView;
  const sounds = props.sounds ?? true;
  const haptics = props.haptics ?? true;
  const ownEls = useRef(new Map<string, HTMLElement>());
  const els = props.hand?.els ?? ownEls.current;
  const [sweep, setSweep] = useState<Sweep | null>(null);
  const seatEls = useRef(new Map<number, HTMLElement>());

  // Where a card comes from when someone else plays it: their cat.
  const fromSeat = (seat: number): Pose => {
    const at = L.seats.get(seat) ?? { x: L.centre.x, y: L.centre.y };
    return { x: at.x - L.cw / 2, y: at.y - L.ch / 2, r: 0, s: 0.3 };
  };

  useEffect(
    () =>
      store.subscribe({
        event: ({ event: e }) => {
          if (e.kind !== "birdwatch") return;
          const ev = e.event;
          const sound: typeof play = (...a) => {
            if (sounds) play(...a);
          };
          if (ev.kind === "played") {
            if (!props.hand?.poses.has(`c${ev.card}`)) motion.spawnFrom(`c${ev.card}`, fromSeat(ev.seat));
            sound("flip", 0.6);
          } else if (ev.kind === "trick") {
            setSweep({ key: performance.now(), winner: ev.winner, cards: ev.cards });
            sound(ev.points > 0 ? "sparkle" : "whoosh", 0.6);
            if (haptics) buzz("drop");
          } else if (ev.kind === "bid") {
            sound("pop", 0.5);
            bump(seatEls.current.get(ev.seat)?.querySelector(".bw-sign") as HTMLElement | null, 1.25);
          } else if (ev.kind === "passed") {
            sound("tick", 0.4);
          } else if (ev.kind === "bidWon" || ev.kind === "trump") {
            sound("sparkle", 0.5);
            bump(document.getElementById("bw-trump"), 1.2);
          } else if (ev.kind === "partner") {
            // The partner's cat joins the bid winner's side with a flourish.
            sound("leap", 0.6);
            bump(seatEls.current.get(ev.seat), 1.25);
          } else if (ev.kind === "handOver") {
            sound(ev.result.made ? "fanfare" : "nope", 0.5);
          }
        },
      }),
    [store, motion, L, sounds, haptics, props.hand],
  );

  // The trick's cards on the sill, then the hand's.
  const poses = new Map<string, Pose>();
  v.trick.forEach((t, i) => {
    const p = L.slots.get(t.seat);
    if (p) poses.set(`c${t.card}`, { ...p, z: 300 + i });
  });
  for (const [key, p] of props.hand?.poses ?? []) if (!poses.has(key)) poses.set(key, p);

  useLayoutEffect(() => {
    motion.apply(els, poses);
  });

  const setEl = (key: string) => (el: HTMLElement | null) => {
    if (el) els.set(key, el);
    else els.delete(key);
  };

  const live = v.status === "playing" && v.phase !== "between";
  const strip = sides(v);
  const stripWords = strip.map((s) => `${sideName(room, s.seats)}: ${s.score}${s.taken ? `, ${s.taken} this hand` : ""}`).join(". ");
  const trumpWords = v.trump ? `Trump: ${SUIT_WORD[v.trump]}` : "No trump yet";
  const bidWords = v.high ? `${v.phase === "bidding" ? "High bid" : "Bid"} ${v.high.amount}, ${seatName(room.seats[v.high.seat])}` : "";
  const StripTag = props.onStrip ? "button" : "div";
  // Too many sides for names (five players on a phone): each chip shows its cats instead.
  const many = !L.stripColumn && L.strip.w / Math.max(strip.length, 1) < 128;

  return (
    <>
      <div class="bw-window" style={{ transform: `translate3d(${L.window.x}px, ${L.window.y}px, 0)`, width: `${L.window.w}px`, height: `${L.window.h}px` }} aria-hidden="true" />
      <div
        class="bw-sill"
        style={{ transform: `translate3d(${L.sill.x}px, ${L.sill.y}px, 0)`, width: `${L.sill.w}px`, height: `${L.sill.h}px` }}
        role="img"
        aria-label={v.trick.length ? `On the sill: ${v.trick.map((t) => `${seatName(room.seats[t.seat])}, ${cardLabel(t.card, v.rules)}`).join("; ")}` : "The sill is empty"}
      />

      {[...L.seats].map(([s, at]) => {
        const sign = signOf(v, s);
        const ribbon = ribbonOf(v, s);
        const rect = L.seatRects.get(s);
        return (
          <div
            class={`avatar-at bw-seat ${ribbon ? "ribboned" : ""}`}
            ref={(el) => {
              if (el) seatEls.current.set(s, el);
              else seatEls.current.delete(s);
            }}
            style={{
              transform: `translate3d(${at.x - L.avatar / 2}px, ${at.y - L.avatar / 2 - 4}px, 0)`,
              ["--ribbon" as string]: ribbon ?? "transparent",
              ["--seat-w" as string]: `${rect?.w ?? L.avatar}px`,
            }}
          >
            <SeatAvatar seat={s} info={room.seats[s]} size={L.avatar} turn={live && v.turn === s} count={v.handCounts[s]} label={seatLabel(room, v, s, sign?.text)} />
            {v.dealer === s && live ? (
              <span class="bw-dealer" aria-hidden="true">
                D
              </span>
            ) : null}
            {sign ? (
              <span class={`bw-sign ${sign.kind}`} id={`bw-sign-${s}`} aria-hidden="true">
                {sign.text}
              </span>
            ) : null}
          </div>
        );
      })}

      <div
        class="bw-trump"
        id="bw-trump"
        style={{ transform: `translate3d(${L.trump.x}px, ${L.trump.y}px, 0)`, ["--badge" as string]: `${L.trump.w}px` }}
        role="img"
        aria-label={[trumpWords, bidWords].filter(Boolean).join(". ")}
      >
        <span class={`bw-badge ${v.trump ? "on" : ""}`}>{v.trump ? <SuitIcon suit={v.trump} /> : <span class="bw-badge-q">?</span>}</span>
        {v.high ? (
          <span class="bw-high">
            <span class="bw-high-n">{v.high.amount}</span>
            <span class="bw-high-who">{seatName(room.seats[v.high.seat])}</span>
          </span>
        ) : null}
      </div>

      <StripTag
        type={props.onStrip ? "button" : undefined}
        class={`bw-strip ${L.stripColumn ? "column" : ""} ${many ? "many" : ""}`}
        id="bw-strip"
        style={{ transform: `translate3d(${L.strip.x}px, ${L.strip.y}px, 0)`, width: `${L.strip.w}px`, height: L.stripColumn ? undefined : `${L.strip.h}px`, maxHeight: `${L.strip.h}px` }}
        onClick={props.onStrip}
        aria-label={`Scores. ${stripWords}${props.onStrip ? ". Show the score sheet" : ""}`}
        role={(props.onStrip ? undefined : "img") as "button" | undefined}
      >
        {strip.map((s) => (
          <span class={`bw-chip ${s.bidding ? "bidding" : ""}`} style={{ ["--ribbon" as string]: s.ribbon ?? "rgba(255,255,255,0.25)" }}>
            <span class="bw-chip-cats" aria-hidden="true">
              {s.seats.map((seat) => (
                <img src={catArt(seatCat(room.seats[seat]), "idle")} alt="" width={22} height={22} decoding="async" />
              ))}
            </span>
            <span class="bw-chip-who">{sideName(room, s.seats)}</span>
            <span class="bw-chip-score">{s.score}</span>
            {s.taken ? <span class="bw-chip-taken">+{s.taken}</span> : null}
          </span>
        ))}
      </StripTag>

      <div class="cards">
        {[...poses].map(([key, p]) => {
          const id = Number(key.slice(1));
          if (props.hand?.poses.has(key) && !v.trick.some((t) => t.card === id)) return props.hand.render(id, p, setEl(key));
          return (
            <div key={key} ref={setEl(key)} class="card on-sill" style={{ transform: transformOf(p), zIndex: p.z ?? 1 }}>
              <div class="card-inner" role="img" aria-label={cardLabel(id, v.rules)}>
                <BirdFace id={id} rules={v.rules} />
              </div>
            </div>
          );
        })}
        {sweep ? <TrickSweep key={sweep.key} sweep={sweep} L={L} rules={v.rules} to={fromSeat} onDone={() => setSweep(null)} /> : null}
      </div>

      {props.children}
    </>
  );
}

/** What a seat's cat says: its name, cards, team, sign and turn. */
function seatLabel(room: RoomView, v: BirdView, s: number, sign?: string): string {
  const n = v.handCounts[s] ?? 0;
  const parts = [seatName(room.seats[s]), `${n} ${n === 1 ? "card" : "cards"}`];
  if (room.seats[s]?.kind === "bot") parts.push("House Cat");
  if (v.dealer === s) parts.push("dealer");
  if (sign === "Pass") parts.push("passed");
  else if (sign === "Missed") parts.push("missed the bid");
  else if (sign) parts.push(`bid ${sign}`);
  if (v.turn === s && v.status === "playing") parts.push("their turn");
  return parts.join(", ");
}

/** A finished trick: its cards gather and fly to the cat who won it, then fade. */
function TrickSweep(props: { sweep: Sweep; L: BwLayout; rules: BirdView["rules"]; to: (seat: number) => Pose; onDone: () => void }) {
  const ref = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const host = ref.current;
    if (!host || reducedMotion()) {
      props.onDone();
      return;
    }
    const to = props.to(props.sweep.winner);
    const anims = [...host.children].map((el, i) => {
      const from = props.L.slots.get(props.sweep.cards[i]!.seat) ?? to;
      const mid = { x: props.L.centre.x - props.L.cw / 2, y: props.L.centre.y - props.L.ch / 2, r: 0, s: props.L.sillScale };
      return (el as HTMLElement).animate([{ transform: transformOf(from) }, { transform: transformOf(mid), offset: 0.35 }, { transform: transformOf(to) }], {
        duration: 640,
        easing: "cubic-bezier(0.4, 0, 0.3, 1)",
        fill: "forwards",
      });
    });
    // The gathered cards overlap: they fade as one layer, never card by card.
    anims.push(host.animate([{ opacity: 1 }, { opacity: 1, offset: 0.55 }, { opacity: 0 }], { duration: 640, fill: "forwards" }));
    void Promise.all(anims.map((a) => a.finished)).then(props.onDone, props.onDone);
    return () => anims.forEach((a) => a.cancel());
  }, []);
  // One layer, faded as one (AGENTS.md): the cards overlap as they gather.
  return (
    <div ref={ref} class="bw-sweep" aria-hidden="true">
      {props.sweep.cards.map((t) => (
        <div class="card on-sill" style={{ transform: transformOf(props.L.slots.get(t.seat) ?? props.to(props.sweep.winner)) }}>
          <div class="card-inner">
            <BirdFace id={t.card} rules={props.rules} />
          </div>
        </div>
      ))}
    </div>
  );
}
