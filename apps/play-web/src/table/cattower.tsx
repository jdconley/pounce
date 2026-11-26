/**
 * The Cat Tower table (TableScene.swift): opponents across the top, the tower down the side, the
 * laid groups and the two piles in the middle, the trays and the hand at the bottom. Drag or
 * tap to play; the keyboard plays the whole game too. Every card is one element moved only by
 * its transform (motion.ts). The table anyone may see is CtPublic (ct-public.tsx), shared with
 * the TV; this is the hand on top of it: the hand, the trays, the moves, the curtain and tips.
 */
import { card, type CardId } from "@pounce/play-api/rules/cards";
import { buildGroup, type HitSide, type Requirement } from "@pounce/play-api/rules/groups";
import { PHASES } from "@pounce/play-api/rules/phases";
import { useEffect, useMemo, useRef, useState } from "preact/hooks";


import { buzz } from "../lib/haptics";
import { reducedMotion } from "../lib/settings";
import { play } from "../lib/sound";
import { Button, Icon, learnTip, Tip, tipLearned, useMedia, useSize } from "../ui/common";

import { groupDrop, heldRect, type GroupSpot } from "./ct-drop";
import { ctMoves, useCtHand, useCtSeat } from "./ct-hand";
import { ctLayout, trayPoses, type Insets } from "./ct-layout";
import { discardNeedsTarget, hitTargets } from "./ct-moves";
import { CtTable, ctStyle, type CtHover } from "./ct-public";
import { inside, press, useLatest, type Point } from "./drag";
import { CardFace, cardLabel } from "./faces";
import { Motion, MOVE, transformOf, wiggle, type Pose } from "./motion";
import { seatName, SeatAvatar } from "./seat";
import { Curtain } from "./shared";

import type { RoomState, RoomStore } from "../store/room";

const REQ_WORDS = (r: Requirement): string => (r.kind === "set" ? `Set of ${r.size}` : r.kind === "run" ? `Run of ${r.size}` : `${r.size} of one coat`);

export const phaseWords = (phase: number): string => (PHASES[phase] ?? []).map(REQ_WORDS).join(" + ");

/** The safe-area insets, read from CSS once (and again on a resize), shared by every table. */
let insetsNow: Insets | null = null;
const insetListeners = new Set<(i: Insets) => void>();

function readInsets(): Insets {
  const probe = document.createElement("div");
  probe.style.cssText =
    "position:fixed;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)";
  document.body.append(probe);
  const cs = getComputedStyle(probe);
  const out = { top: parseFloat(cs.paddingTop) || 0, right: parseFloat(cs.paddingRight) || 0, bottom: parseFloat(cs.paddingBottom) || 0, left: parseFloat(cs.paddingLeft) || 0 };
  probe.remove();
  return out;
}

if (typeof window !== "undefined") {
  window.addEventListener("resize", () => {
    // In the next frame, after the browser's own layout.
    requestAnimationFrame(() => {
      insetsNow = readInsets();
      for (const l of [...insetListeners]) l(insetsNow);
    });
  });
}

export function useInsets(): Insets {
  const [insets, setInsets] = useState<Insets>(() => (insetsNow ??= typeof document === "undefined" ? { top: 0, right: 0, bottom: 0, left: 0 } : readInsets()));
  useEffect(() => {
    insetListeners.add(setInsets);
    return () => void insetListeners.delete(setInsets);
  }, []);
  return insets;
}

/**
 * `sounds: false` silences the game's own events (a phone whose table is on a TV); taps still sound.
 * `topInset` keeps a strip along the top clear (the Cards/Table switch, while a TV shows the table).
 */
export function CatTowerTable(props: { store: RoomStore; state: RoomState; sounds?: boolean; topInset?: number }) {
  const { store, state } = props;
  const sounds = props.sounds ?? true;
  const room = state.room!;
  const g = room.game!;
  const [rootRef, size] = useSize<HTMLDivElement>();
  const safe = useInsets();
  const insets = useMemo(() => ({ ...safe, top: safe.top + (props.topInset ?? 0) }), [safe, props.topInset]);
  const motion = useMemo(() => new Motion(reducedMotion), []);
  const els = useRef(new Map<string, HTMLElement>());

  const { mine, seat, showHand, curtainSeat, myTurn, reveal } = useCtSeat(room);
  const hand = useCtHand(room, seat, showHand);
  const { ordered, trayCards, inTrays, reqs, phaseIndex, laidMine, showTrays } = hand;

  const [selected, setSelected] = useState<CardId | null>(null);
  const [hover, setHover] = useState<CtHover>(null);
  const [held, setHeld] = useState<Map<CardId, Pose>>(new Map());
  const [skipPick, setSkipPick] = useState<CardId | null>(null);
  const [focusIndex, setFocusIndex] = useState(0);

  const opponents = room.seats.flatMap((s, i) => ((s.kind === "human" || s.kind === "bot") && i !== seat ? [i] : []));
  const laidRows = g.laid.flatMap((groups, s) => (groups ? [{ seat: s, groups: groups.map((grp) => grp.cards.length) }] : []));

  const L = useMemo(
    () =>
      ctLayout({
        width: size.width || 360,
        height: size.height || 640,
        insets,
        opponents,
        handCount: ordered.length,
        trays: showTrays ? reqs.length : 0,
        laid: laidRows,
      }),
    [size.width, size.height, insets, opponents.join(), ordered.length, showTrays, reqs.length, JSON.stringify(laidRows)],
  );

  // Clear what this device held in place once the server answers.
  useEffect(() => {
    if (!state.pending) setHeld(new Map());
  }, [state.pending]);

  // The hand's own events (the table's are CtPublic's): your turn, and a new round's empty trays.
  useEffect(
    () =>
      store.subscribe({
        event: ({ event: e }) => {
          if (e.kind !== "game") return;
          const ev = e.event;
          if (ev.kind === "turn" && mine.includes(ev.seat)) {
            if (sounds) play("tick", 0.6);
            buzz("turn");
          } else if (ev.kind === "roundStarted") hand.setTrays([]);
        },
      }),
    [store, mine.join(), sounds],
  );

  // A refused move: back where it was, with a shake.
  useEffect(() => {
    if (!state.error) return;
    setHeld(new Map());
    play("nope");
    buzz("nope");
    wiggle(rootRef.current?.querySelector(".hand-zone") as HTMLElement | null);
  }, [state.error?.n]);

  // Poses for the hand and the trays; the table's own cards are CtPublic's.
  const poses = new Map<string, Pose>();
  ordered.forEach((c, i) => {
    const base = L.hand[i];
    if (base) poses.set(`c${c}`, held.get(c) ?? base);
  });
  if (showTrays) {
    trayCards.forEach((cards, i) => {
      const tray = L.trays[i];
      if (!tray) return;
      trayPoses(tray, cards.length, reqs[i]?.size ?? cards.length, L.cw, L.ch, L.small).forEach((p, j) => poses.set(`c${cards[j]}`, held.get(cards[j] as CardId) ?? { ...p, z: 50 + j }));
    });
  }

  // A new deal: cards come off the deck one after another.
  const moveStyle = (key: string) => {
    const id = Number(key.slice(1));
    const i = ordered.indexOf(id);
    return i >= 0 && !motion.last(key) ? { ...MOVE, delay: Math.min(i, 12) * 45 } : MOVE;
  };

  // Moves.
  const { nope, draw, discard, toTray, outOfTray, groups, layDown, hitOk, hit, skipCandidates } = ctMoves({
    store,
    state,
    room,
    seat,
    myTurn,
    hand,
    motion,
    discardPose: L.discard,
    setHeld,
    setSelected,
    setSkipPick,
  });
  const groupsReady = groups !== null;

  // Hits can be made now: our play step, laid down, and nothing in flight but a hit or the lay
  // down before it (a hit dropped then waits for it). Otherwise the groups don't light at all.
  const queueable = state.pending === null || state.pending.action.type === "hit" || state.pending.action.type === "layDown";
  const hitsNow = myTurn && g.step === "play" && laidMine && queueable;
  const spots: GroupSpot[] = [...L.laid].flatMap(([s, row]) => row.groups.map((grp, gi) => ({ seat: s, group: gi, rect: grp.rect, run: g.laid[s]?.[gi]?.kind === "run" })));

  // Where a card dropped at `p` would go, held where `pose` draws it: what lights while it is held
  // is where it goes (ct-drop.ts).
  const targetAt = (p: Point, c: CardId, pose?: Pose): CtHover => {
    if (inside(p, L.discardRect, 14)) return { kind: "discard" };
    for (const [i, t] of L.trays.entries()) if (showTrays && inside(p, t, 6)) return { kind: "tray", i };
    const inHand = inside(p, L.handRect, 10);
    if (hitsNow) {
      const fits = hitTargets(c, g.laid);
      const drop = groupDrop({
        finger: p,
        // Back over the hand only the finger counts, so the hand can still be put in order.
        card: pose && !inHand ? heldRect(pose, L.cw, L.ch) : { x: p.x, y: p.y, w: 0, h: 0 },
        spots,
        sides: (s, gi) => fits.flatMap((t) => (t.seat === s && t.group === gi ? [t.side] : [])),
        onTable: !inHand && p.y < L.handRect.y,
      });
      if (drop) return { kind: "group", ...drop };
    }
    if (discardNeedsTarget(c)) {
      for (const [s, at] of L.opponents) if (Math.hypot(p.x - at.x, p.y - at.y) < L.avatar * 0.7) return { kind: "seat", seat: s };
    }
    if (inHand) {
      const xs = L.hand.map((h) => h.x + L.cw / 2);
      let index = xs.findIndex((x) => p.x < x);
      if (index < 0) index = xs.length;
      return { kind: "hand", index };
    }
    return null;
  };

  // A hit dropped while the one before it is still in flight goes as soon as that is answered.
  const [queued, setQueued] = useState<{ c: CardId; seat: number; group: number; side?: HitSide } | null>(null);
  useEffect(() => {
    if (state.pending || !queued) return;
    setQueued(null);
    hit(queued.c, queued.seat, queued.group, queued.side);
  }, [state.pending, queued]);

  /** What lit last while the card was held: a drop just past it still lands there. */
  const shown = useRef<CtHover>(null);
  const dropAt = (c: CardId, p: Point, pose: Pose) => {
    const fresh = targetAt(p, c, pose);
    const lit = shown.current;
    shown.current = null;
    const t = (fresh === null || (fresh.kind === "group" && !fresh.ok)) && lit?.kind === "group" && lit.ok ? lit : fresh;
    setHover(null);
    motion.place(`c${c}`, pose);
    if (!t) return;
    if (t.kind === "discard") return discard(c);
    if (t.kind === "tray") return toTray(c, t.i);
    if (t.kind === "group") {
      if (t.ok && state.pending) return setQueued({ c, seat: t.seat, group: t.group, side: t.side });
      return hit(c, t.seat, t.group, t.side);
    }
    if (t.kind === "seat" && discardNeedsTarget(c)) return discard(c, t.seat);
    if (t.kind === "hand") {
      if (inTrays.has(c)) outOfTray(c);
      hand.reorder(c, t.index);
    }
  };

  const tapCard = (c: CardId) => {
    if (inTrays.has(c)) return outOfTray(c);
    play("tick", 0.4);
    buzz("tap");
    setSelected((s) => (s === c ? null : c));
  };

  const live = useLatest({ targetAt, dropAt, tapCard });
  const onCardDown = (c: CardId) => (e: PointerEvent) => {
    if (!showHand) return;
    const el = els.current.get(`c${c}`);
    if (!el) return;
    press(e, el, {
      origin: () => {
        const r = rootRef.current!.getBoundingClientRect();
        return { x: r.left, y: r.top };
      },
      pose: () => motion.last(`c${c}`) ?? { x: 0, y: 0 },
      onTap: () => live.current.tapCard(c),
      onStart: () => {
        play("tick", 0.4);
        buzz("pick");
        setSelected(null);
      },
      onMove: (p, pose) => {
        shown.current = live.current.targetAt(p, c, pose);
        setHover(shown.current);
      },
      onDrop: (p, pose) => live.current.dropAt(c, p, pose),
      onCancel: () => {
        shown.current = null;
        setHover(null);
      },
    });
  };

  // A tap on a target with a card picked.
  const tapTarget = (t: Exclude<CtHover, null>) => {
    if (selected === null) return;
    if (t.kind === "discard") return discard(selected);
    if (t.kind === "tray") return toTray(selected, t.i);
    if (t.kind === "group") return hit(selected, t.seat, t.group);
    if (t.kind === "seat") return discard(selected, t.seat);
  };

  // The keyboard: arrows pick, Enter lifts, D draws, T takes the discard, X discards, 1 and 2 fill trays, L lays down, H hits.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.metaKey || e.ctrlKey || e.altKey) return;
      const k = e.key.toLowerCase();
      const focusCard = (i: number) => {
        const c = ordered[Math.min(Math.max(i, 0), ordered.length - 1)];
        if (c === undefined) return;
        setFocusIndex(ordered.indexOf(c));
        (els.current.get(`c${c}`)?.querySelector("button") as HTMLButtonElement | null)?.focus();
      };
      if (k === "arrowright") focusCard(focusIndex + 1);
      else if (k === "arrowleft") focusCard(focusIndex - 1);
      else if (k === "d") draw("deck");
      else if (k === "t") draw("discard");
      else if (k === "x" && selected !== null) discard(selected);
      else if ((k === "1" || k === "2") && selected !== null) toTray(selected, Number(k) - 1);
      else if (k === "l") layDown();
      else if (k === "h" && selected !== null) {
        const first = laidMine ? hitTargets(selected, g.laid)[0] : undefined;
        if (first) return hit(selected, first.seat, first.group);
        nope();
      } else if (k === "escape") setSelected(null);
      else return;
      learnTip("ct.keys");
      e.preventDefault();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  // What the bottom line says.
  const turnName = seatName(room.seats[g.turn]);
  const cue = !myTurn
    ? g.status === "playing"
      ? `${turnName}'s turn`
      : ""
    : g.step === "draw"
      ? "Draw a card"
      : laidMine
        ? "Play or discard"
        : phaseWords(phaseIndex);

  const fineMouse = useMedia("(hover: hover) and (pointer: fine)");
  const canDrawDiscard = myTurn && g.step === "draw" && g.discardTop !== null && card(g.discardTop).kind !== "cucumber";

  const renderCard = (id: CardId, p: Pose, ref: (el: HTMLElement | null) => void) => (
    <div key={`c${id}`} ref={ref} class={`card ${selected === id ? "picked" : ""} mine`} style={{ transform: transformOf(p), zIndex: p.z ?? 1 }} onPointerDown={onCardDown(id)}>
      <button type="button" class="card-inner" aria-label={cardLabel(id)} aria-pressed={selected === id} onClick={(e) => e.preventDefault()} onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          tapCard(id);
        }
      }} onFocus={() => setFocusIndex(Math.max(0, ordered.indexOf(id)))}>
        <CardFace id={id} compact={(p.s ?? 1) < 0.9} />
      </button>
    </div>
  );

  return (
    <div class={`ct-table ${L.landscape ? "landscape" : ""} ${myTurn ? "my-turn" : ""}`} ref={rootRef} style={ctStyle(L)}>
      <CtTable
        store={store}
        room={room}
        layout={L}
        motion={motion}
        aims={state.aims}
        sounds={sounds}
        mine={mine}
        hand={{ poses, els: els.current, render: renderCard, style: moveStyle }}
        hover={hover}
        fits={(s, gi) => selected !== null && hitOk(selected, s, gi)}
        groupsFocusable={selected !== null && laidMine}
        onGroup={(s, gi) => tapTarget({ kind: "group", seat: s, group: gi, ok: true })}
        onSeat={selected !== null && discardNeedsTarget(selected) ? (s) => tapTarget({ kind: "seat", seat: s }) : undefined}
        onDeck={() => draw("deck")}
        deckLive={myTurn && g.step === "draw" && !state.pending}
        onDiscard={() => (selected !== null ? tapTarget({ kind: "discard" }) : draw("discard"))}
        discardLive={canDrawDiscard}
        discardOff={state.pending !== null}
        discardAim={selected !== null && myTurn && g.step === "play"}
        discardHint={canDrawDiscard ? "Take it" : selected !== null ? "Discard here" : ""}
        cue={{ text: cue, mine: myTurn, y: (showTrays ? L.trays[0]!.y : L.handRect.y) - 34 }}
        under={
          <>
            {showTrays
              ? L.trays.map((t, i) => {
                  const cards = trayCards[i] ?? [];
                  const req = reqs[i]!;
                  const full = cards.length === req.size;
                  const valid = full && buildGroup(req, cards) !== null;
                  return (
                    <button
                      type="button"
                      id={i === 0 ? "tray-0" : undefined}
                      class={`tray ${hover?.kind === "tray" && hover.i === i ? "hot" : ""} ${valid ? "good" : full ? "bad" : ""}`}
                      style={{ transform: `translate3d(${t.x}px, ${t.y}px, 0)`, width: `${t.w}px`, height: `${t.h}px` }}
                      aria-label={`Tray ${i + 1}: ${REQ_WORDS(req)}, ${cards.length} of ${req.size}${valid ? ", ready" : ""}`}
                      onClick={() => tapTarget({ kind: "tray", i })}
                    >
                      <span class="tray-label">{cards.length === 0 ? REQ_WORDS(req) : `${cards.length}/${req.size}`}</span>
                    </button>
                  );
                })
              : null}
            <div class="hand-zone" id="hand" style={{ transform: `translate3d(${L.handRect.x}px, ${L.handRect.y}px, 0)`, width: `${L.handRect.w}px`, height: `${L.handRect.h}px` }} />
          </>
        }
      >
        {showTrays && groupsReady && myTurn && g.step === "play" ? (
          <div class="action-at" style={{ transform: `translate3d(${L.action.x}px, ${L.action.y}px, 0)` }}>
            <Button size="small" variant="ok" onClick={layDown} id="lay" aria-label="Lay down">
              <Icon name="icon-paw-menu" size={28} /> Lay down
            </Button>
          </div>
        ) : null}

        {skipPick !== null ? (
          <div class="skip-pick" role="dialog" aria-label="Skip whose turn?">
            <p class="outlined">Skip whose turn?</p>
            <div class="skip-seats">
              {skipCandidates.map((s) => (
                <SeatAvatar seat={s} info={room.seats[s]} size={72} turn={false} onClick={() => {
                  const c = skipPick;
                  setSkipPick(null);
                  discard(c, s);
                }} />
              ))}
            </div>
            <Button size="small" variant="violet" onClick={() => setSkipPick(null)}>
              Cancel
            </Button>
          </div>
        ) : null}

        {curtainSeat !== null ? <Curtain name={seatName(room.seats[curtainSeat])} cat={room.seats[curtainSeat]?.person?.cat ?? 0} onReveal={() => reveal(curtainSeat)} /> : null}

        <Tip id="ct.draw" anchor="deck" text="Take a card from the deck or the discard pile." show={myTurn && g.step === "draw" && !state.pending} />
        <Tip id="ct.trays" anchor="tray-0" text={`This round: ${phaseWords(phaseIndex)}. Drag cards into the trays.`} show={myTurn && g.step === "play" && showTrays && tipLearned("ct.draw")} />
        <Tip id="ct.discard" anchor="discard" text="Drag one card to the discard pile." show={myTurn && g.step === "play" && tipLearned("ct.trays") && !groupsReady} />
        <Tip id="ct.lay" anchor="lay" text="Tap the paw to lay down your level." show={groupsReady && myTurn} />
        <Tip id="ct.keys" anchor="hand" text="Keys: D draws, X discards, arrows pick a card." show={fineMouse && myTurn && tipLearned("ct.discard") && !state.pending} />
        <Tip id="ct.hit" anchor="discard" text="Drop cards on any laid group they fit." show={myTurn && g.step === "play" && laidMine && tipLearned("ct.discard")} />
      </CtTable>
    </div>
  );
}
