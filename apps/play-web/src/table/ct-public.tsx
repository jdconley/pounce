/**
 * The Cat Tower table as anyone at it may see it: the rug, the tower, every seat, the laid groups,
 * the two piles, the cue, cards in flight and the round's results, with the group a player is
 * aiming at aglow. The phone's full table draws this and adds its hand (cattower.tsx); a TV draws
 * this alone. It is drawn into the caller's `.ct-table`, which sizes it (`ctStyle`).
 */
import { card, type CardId } from "@pounce/play-api/rules/cards";
import { useEffect, useLayoutEffect, useRef, useState } from "preact/hooks";

import { art, catArt, RINGS } from "../lib/art";
import { buzz } from "../lib/haptics";
import { play } from "../lib/sound";

import { aimedGroup } from "./ct-moves";
import { CardFace, cardLabel } from "./faces";
import { transformOf, type Motion, type MoveStyle, type Pose } from "./motion";
import { usePickled } from "./pickled";
import { seatCat, seatName, SeatAvatar } from "./seat";
import { Flights, RoundOver, type Flight } from "./shared";

import type { CtLayout, LaidOwner as LaidOwnerRoom } from "./ct-layout";
import type { RoomStore } from "../store/room";
import type { GameAim, RoomView } from "@pounce/play-api/protocol";
import type { GameEvent } from "@pounce/play-api/rules/engine";
import type { HitSide } from "@pounce/play-api/rules/groups";
import type { ComponentChildren, VNode } from "preact";

/** What a held card is over: the table's targets, and the hand layer's own (a tray, a place in the hand). */
export type CtHover =
  | { kind: "discard" }
  | { kind: "tray"; i: number }
  | { kind: "group"; seat: number; group: number; side?: HitSide; ok: boolean }
  | { kind: "seat"; seat: number }
  | { kind: "hand"; index: number }
  | null;

/**
 * A hand drawn on the table: its cards' poses (the hand and the trays) and how each is drawn. They
 * share the table's one set of moving cards, so a card goes from the hand to a pile or a group in
 * one move.
 */
export type CtHand = {
  poses: Map<string, Pose>;
  /** Every card element on the table by key, the hand's and the table's: the hand finds its own here. */
  els: Map<string, HTMLElement>;
  render: (id: CardId, pose: Pose, ref: (el: HTMLElement | null) => void) => VNode;
  style?: (key: string) => MoveStyle;
};

/** The sizes the table's CSS reads, for the `.ct-table` it is drawn into. */
export const ctStyle = (L: CtLayout) => ({ ["--cw" as string]: `${L.cw}px`, ["--ch" as string]: `${L.ch}px`, ["--avatar" as string]: `${L.avatar}px` });

/** What the table shows, for anyone: a TV gives only this. */
export type CtPublicProps = {
  store: RoomStore;
  room: RoomView;
  layout: CtLayout;
  motion: Motion;
  aims: Record<number, GameAim>;
  /** Game sounds for what happens at the table. */
  sounds?: boolean;
  /** Haptics for what happens at the table (a phone's; nothing elsewhere). */
  haptics?: boolean;
  /** Each seat's score under its name. */
  scores?: boolean;
  /** The line under the table; by default whose turn it is, where the layout puts the banner. */
  cue?: { text: string; mine: boolean; y: number };
  /** Drawn over the cards. */
  children?: ComponentChildren;
};

/** A hand on top of the table, and what it can do to the table: only a phone's full table has these. */
export type CtHandProps = {
  /** The seats this device holds (none for a spectator). */
  mine: number[];
  hand: CtHand;
  hover?: CtHover;
  /** The picked card fits this group. */
  fits?: (seat: number, group: number) => boolean;
  groupsFocusable?: boolean;
  onGroup?: (seat: number, group: number) => void;
  /** A seat is a target (a Cucumber is picked). */
  onSeat?: (seat: number) => void;
  onDeck?: () => void;
  deckLive?: boolean;
  onDiscard?: () => void;
  /** The discard can be taken. */
  discardLive?: boolean;
  /** A card is picked: the discard glows as a place for it. */
  discardAim?: boolean;
  /** A move is in flight: the discard takes nothing until it settles. */
  discardOff?: boolean;
  /** What a tap on the discard does, after its card in its name ("Take it"). */
  discardHint?: string;
  /** Drawn under the cards: the hand layer's trays and zones. */
  under?: ComponentChildren;
};

/**
 * The table for a TV: what anyone may see, with no hand and nothing to touch. Its props have no
 * room for a hand or a move (they are `never`), so a TV can't be handed one by mistake.
 */
export function CtPublic(props: CtPublicProps & { [K in keyof CtHandProps]?: never }) {
  return <CtTable {...props} />;
}

/** The table with a hand on top (the phone's full table, cattower.tsx), or without one (CtPublic). */
export function CtTable(props: CtPublicProps & Partial<CtHandProps>) {
  const { store, room, layout: L, motion, aims, hover = null } = props;
  const g = room.game!;
  const sounds = props.sounds ?? true;
  const haptics = props.haptics ?? true;
  const mine = props.mine;
  const sound: typeof play = (...a) => {
    if (sounds) play(...a);
  };
  const feel: typeof buzz = (...a) => {
    if (haptics) buzz(...a);
  };
  const ownEls = useRef(new Map<string, HTMLElement>());
  const els = props.hand?.els ?? ownEls.current;

  const [flights, setFlights] = useState<Flight[]>([]);
  const [round, setRound] = useState<Extract<GameEvent, { kind: "roundOver" }> | null>(null);
  const [under, setUnder] = useState<CardId | null>(null);
  const pickled = usePickled(store, g.pendingSkip);

  // The discard's card underneath stays a moment while the new one lands on it: its own CSS
  // animation (`.discard-under.leaving`) times that, and its end lets it go.
  const prevTop = useRef<CardId | null>(g.discardTop);
  useEffect(() => {
    if (prevTop.current === g.discardTop) return;
    const was = prevTop.current;
    prevTop.current = g.discardTop;
    if (was !== null) setUnder(was);
  }, [g.discardTop]);

  const avatarPose = (s: number, scale = 0.35): Pose => {
    const at = L.opponents.get(s) ?? L.laid.get(s)?.avatar ?? { x: L.centre.x, y: -L.ch };
    return { x: at.x - L.cw / 2, y: at.y - L.ch / 2, r: 0, s: scale };
  };

  // Events: sounds, flights and where new cards come from. A card drawn into a hand this device
  // sees comes off its pile; any other draw flies to the drawer's cat.
  useEffect(
    () =>
      store.subscribe({
        event: ({ event: e }) => {
          if (e.kind !== "game") return;
          const ev = e.event;
          switch (ev.kind) {
            case "drew": {
              sound("flip", 0.6);
              if (ev.from === "discard" && g.discardTop !== null) motion.spawnFrom(`c${g.discardTop}`, L.discard);
              if (ev.card !== undefined) {
                motion.spawnFrom(`c${ev.card}`, ev.from === "deck" ? L.deck : L.discard);
              } else {
                const to = avatarPose(ev.seat);
                setFlights((f) => [...f, { key: `f${Date.now()}${Math.random()}`, from: ev.from === "deck" ? L.deck : L.discard, to, card: ev.from === "discard" ? (g.discardTop ?? undefined) : undefined }]);
              }
              break;
            }
            case "discarded":
              motion.spawnFrom(`c${ev.card}`, avatarPose(ev.seat));
              sound(card(ev.card).kind === "cucumber" ? "scream" : "thud", 0.6);
              feel("drop");
              break;
            case "laidDown":
              for (const grp of ev.groups) for (const c of grp.cards) motion.spawnFrom(`c${c}`, avatarPose(ev.seat));
              sound("sparkle");
              feel("drop");
              break;
            case "hit":
              motion.spawnFrom(`c${ev.card}`, avatarPose(ev.seat));
              sound("pop");
              break;
            case "skipped":
              sound("bat");
              break;
            case "reshuffled":
              sound("whoosh");
              break;
            case "roundOver":
              setRound(ev);
              // A device's own player climbing gets the fanfare; a TV cheers anyone who climbs.
              sound((mine ? ev.advanced.some((s) => mine.includes(s)) : ev.advanced.length > 0) ? "fanfare" : "leap");
              feel("win");
              break;
            case "roundStarted":
              setRound(null);
              sound("whoosh");
              break;
          }
        },
      }),
    [store, motion, L, g.discardTop, mine?.join(), sounds, haptics],
  );

  // Poses for the table's cards, after the hand's.
  const own = new Map<string, Pose>();
  for (const [s, row] of L.laid) {
    (g.laid[s] ?? []).forEach((grp, gi) => {
      const at = row.groups[gi];
      grp.cards.forEach((c, j) => {
        const p = at?.poses[j];
        if (p) own.set(`c${c}`, p);
      });
    });
  }
  if (g.discardTop !== null) own.set(`c${g.discardTop}`, L.discard);
  const handPoses = props.hand?.poses ?? new Map<string, Pose>();
  const poses = new Map([...handPoses, ...own]);

  useLayoutEffect(() => {
    motion.apply(els, poses, props.hand?.style);
  });

  const setEl = (key: string) => (el: HTMLElement | null) => {
    if (el) els.set(key, el);
    else els.delete(key);
  };

  const aimed = aimedGroup(room, aims);
  const cue = props.cue ?? { text: g.status === "playing" ? `${seatName(room.seats[g.turn])}'s turn` : "", mine: false, y: L.banner.y };
  const discardName = g.discardTop === null ? "Discard pile, empty" : `Discard pile: ${cardLabel(g.discardTop)}${props.onDiscard ? `. ${props.discardHint ?? ""}` : ""}`;

  return (
    <>
      <img class="rug-art" src={art("rug")} alt="" style={{ transform: `translate3d(${L.rug.x}px, ${L.rug.y}px, 0)`, width: `${L.rug.w}px`, height: `${L.rug.h}px` }} />

      <Tower seats={room.seats} phase={g.phase} rect={L.tower} turn={g.turn} pickled={pickled} />

      {[...L.opponents].map(([s, at]) => (
        <div class="avatar-at" style={{ transform: `translate3d(${at.x - L.avatar / 2}px, ${at.y - L.avatar / 2}px, 0)`, ["--seat-w" as string]: `${L.seats.get(s)?.w ?? L.avatar}px` }}>
          <SeatAvatar
            seat={s}
            info={room.seats[s]}
            size={L.avatar}
            turn={g.turn === s && g.status === "playing"}
            count={g.handCounts[s]}
            score={props.scores ? g.scores[s] : undefined}
            laid={Boolean(g.laid[s])}
            pickled={pickled[s]}
            out={g.forfeited[s]}
            target={hover?.kind === "seat" && hover.seat === s}
            onClick={props.onSeat ? () => props.onSeat!(s) : undefined}
          />
        </div>
      ))}

      {[...L.laid].map(([s, row]) => {
        // A seat's cat is drawn once: beside its groups only when its seat is somewhere else.
        const seatAt = L.opponents.get(s);
        const ownCat = !seatAt || seatAt.x !== row.avatar.x || seatAt.y !== row.avatar.y;
        return (
          <>
            {ownCat ? <LaidOwner seat={s} info={room.seats[s]} owner={row} pickled={pickled[s] ?? false} /> : null}
            {row.groups.map((grp, gi) => {
              const h = hover?.kind === "group" && hover.seat === s && hover.group === gi;
              const ok = props.fits?.(s, gi) ?? false;
              const lit = aimed !== null && aimed.seat === s && aimed.group === gi;
              const cls = `group-zone ${h ? (hover.ok ? "good" : "bad") : ok ? "good" : ""}${lit ? " aimed" : ""}`;
              const style = { transform: `translate3d(${grp.rect.x}px, ${grp.rect.y}px, 0)`, width: `${grp.rect.w}px`, height: `${grp.rect.h}px` };
              const name = `${seatName(room.seats[s])}'s group: ${(g.laid[s]?.[gi]?.cards ?? []).map(cardLabel).join(", ")}`;
              return props.onGroup ? (
                <button type="button" class={cls} style={style} aria-label={name} tabIndex={props.groupsFocusable ? 0 : -1} onClick={() => props.onGroup!(s, gi)} />
              ) : (
                <div class={cls} style={style} role="img" aria-label={name} />
              );
            })}
          </>
        );
      })}

      {props.onDeck ? (
        <button type="button" id="deck" class={`deck ${props.deckLive ? "live" : ""}`} style={{ transform: transformOf(L.deck) }} aria-label={`Deck, ${g.deckCount} cards. Draw`} disabled={!props.deckLive} onClick={props.onDeck}>
          <DeckCards count={g.deckCount} />
        </button>
      ) : (
        <div id="deck" class="deck" style={{ transform: transformOf(L.deck) }} role="img" aria-label={`Deck, ${g.deckCount} cards`}>
          <DeckCards count={g.deckCount} />
        </div>
      )}
      {/* The card underneath the top one: art beside the pile, not inside it, so the pile's name is
          only ever its top card (the old top shows here while the new one lands). */}
      {under !== null || g.discardCount > 1 ? (
        <div class={`discard-under ${under !== null ? "leaving" : ""}`} style={{ transform: transformOf(L.discard) }} aria-hidden="true" onAnimationEnd={() => setUnder(null)}>
          {under !== null ? <CardFace id={under} /> : <div class="face blank" />}
        </div>
      ) : null}
      {props.onDiscard ? (
        <button
          type="button"
          id="discard"
          class={`discard ${hover?.kind === "discard" ? "hot" : ""} ${props.discardLive ? "live" : ""} ${props.discardAim ? "aim" : ""}`}
          style={{ transform: transformOf(L.discard) }}
          aria-label={discardName}
          disabled={props.discardOff}
          onClick={props.onDiscard}
        />
      ) : (
        <div id="discard" class="discard" style={{ transform: transformOf(L.discard) }} role="img" aria-label={discardName} />
      )}

      {props.under}

      <div class="cards" role={props.hand ? "group" : undefined} aria-label={props.hand ? "Your hand" : undefined}>
        {[...poses].map(([key, p]) => {
          const id = Number(key.slice(1));
          if (props.hand && handPoses.has(key)) return props.hand.render(id, p, setEl(key));
          return (
            <div key={key} ref={setEl(key)} class="card" style={{ transform: transformOf(p), zIndex: p.z ?? 1 }}>
              <div class="card-inner">
                <CardFace id={id} compact={(p.s ?? 1) < 0.9} />
              </div>
            </div>
          );
        })}
      </div>

      <Flights flights={flights} cw={L.cw} ch={L.ch} onDone={(k) => setFlights((f) => f.filter((x) => x.key !== k))} />

      {cue.text ? (
        <p class={`cue ${cue.mine ? "mine" : ""}`} aria-live="polite" style={{ transform: `translate3d(-50%, ${cue.y}px, 0)` }}>
          {cue.text}
        </p>
      ) : null}

      {props.children}

      {round ? <RoundOver seats={room.seats} ev={round} mine={mine ?? []} /> : null}
    </>
  );
}

/**
 * A laid row's owner, in the column the layout keeps for it at the row's left: their cat, and their
 * name tag under it, no wider than the column (a long name ends in an ellipsis). Pickled, the cat is
 * terrified in a cucumber-green ring.
 */
function LaidOwner(props: { seat: number; info: RoomView["seats"][number] | undefined; owner: LaidOwnerRoom; pickled: boolean }) {
  const { avatar, tag, font } = props.owner;
  const name = seatName(props.info);
  const top = avatar.size ? avatar.y - avatar.size / 2 : tag.y;
  return (
    <div
      class={`laid-owner ${props.pickled ? "pickled" : ""}`}
      role="img"
      aria-label={`${name} laid down${props.pickled ? ", pickled" : ""}`}
      style={{ transform: `translate3d(${tag.x}px, ${top}px, 0)`, width: `${tag.w}px`, height: `${tag.y + tag.h - top}px`, ["--ring" as string]: ringOf(props.seat) }}
    >
      {avatar.size ? (
        <span class="laid-cat" style={{ width: `${avatar.size}px`, height: `${avatar.size}px` }}>
          <img src={catArt(seatCat(props.info), props.pickled ? "terrified" : "idle")} alt="" draggable={false} decoding="async" />
        </span>
      ) : null}
      <span class="name-tag" style={{ height: `${tag.h}px`, maxWidth: `${tag.w}px`, fontSize: `${font}px`, lineHeight: `${tag.h - 5}px`, marginTop: avatar.size ? "-8px" : "0" }}>
        {name}
      </span>
    </div>
  );
}

/** The deck: three backs and its count. */
export function DeckCards(props: { count: number }) {
  return (
    <>
      <span class="deck-card d3" />
      <span class="deck-card d2" />
      <span class="deck-card" />
      <span class="pile-count">{props.count}</span>
    </>
  );
}

/** The ten-shelf tower with each cat on the shelf they reached (TowerNode.swift); a pickled cat is terrified, with a cucumber. */
function Tower(props: { seats: RoomView["seats"]; phase: number[]; rect: { x: number; y: number; w: number; h: number }; turn: number; pickled: boolean[] }) {
  const { rect } = props;
  const shelf = rect.h / 11;
  const cats = props.phase.map((ph, s) => ({ s, ph })).filter(({ s }) => props.seats[s]?.kind === "human" || props.seats[s]?.kind === "bot");
  return (
    <div class="tower" style={{ transform: `translate3d(${rect.x}px, ${rect.y}px, 0)`, width: `${rect.w}px`, height: `${rect.h}px` }} role="img" aria-label={cats.map(({ s, ph }) => `${seatName(props.seats[s])}: level ${Math.min(ph + 1, 10)}${props.pickled[s] ? ", pickled" : ""}`).join(". ")}>
      {Array.from({ length: 10 }, (_, i) => (
        <span class="shelf" style={{ transform: `translate3d(0, ${rect.h - (i + 1) * shelf - shelf * 0.2}px, 0)`, height: `${shelf * 0.7}px` }}>
          <i>{i + 1}</i>
        </span>
      ))}
      {cats.map(({ s, ph }, k) => {
        const level = Math.min(ph, 10);
        const y = rect.h - (level + 0.9) * shelf - shelf * 0.25;
        // Up to three cats side by side on a shelf, every one inside the tower's width.
        const offset = (k % 3) * rect.w * 0.11;
        return (
          <span class={`tower-cat ${props.turn === s ? "turn" : ""} ${props.pickled[s] ? "pickled" : ""}`} style={{ transform: `translate3d(${offset}px, ${y}px, 0)`, width: `${rect.w * 0.78}px`, height: `${rect.w * 0.78}px`, ["--ring" as string]: ringOf(s) }}>
            <img src={catArt(seatCat(props.seats[s]), props.pickled[s] ? "terrified" : "idle")} alt="" />
            {props.pickled[s] ? <img class="tower-pickle" src={art("badge-skip")} alt="" /> : null}
          </span>
        );
      })}
    </div>
  );
}

const ringOf = (s: number) => RINGS[s % RINGS.length];
