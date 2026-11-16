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
import { mySeats } from "../store/lobby";
import { Button, Icon, learnTip, Tip, tipLearned, useMedia, useSize } from "../ui/common";

import { ctLayout, trayPoses, type Insets } from "./ct-layout";
import { discardNeedsTarget, hitTargets, layDownGroups, skipTargets } from "./ct-moves";
import { CtTable, ctStyle, type CtHover } from "./ct-public";
import { inside, press, useLatest, type Point } from "./drag";
import { CardFace, cardLabel } from "./faces";
import { Motion, MOVE, transformOf, wiggle, type Pose } from "./motion";
import { seatName, SeatAvatar } from "./seat";
import { Curtain } from "./shared";

import type { RoomState, RoomStore } from "../store/room";
import type { Action } from "@pounce/play-api/rules/engine";

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

/** `sounds: false` silences the game's own events (a phone whose table is on a TV); taps still sound. */
export function CatTowerTable(props: { store: RoomStore; state: RoomState; sounds?: boolean }) {
  const { store, state } = props;
  const sounds = props.sounds ?? true;
  const room = state.room!;
  const g = room.game!;
  const [rootRef, size] = useSize<HTMLDivElement>();
  const insets = useInsets();
  const motion = useMemo(() => new Motion(reducedMotion), []);
  const els = useRef(new Map<string, HTMLElement>());

  // Whose hand is on show: the only seat on this device, or on a shared device the seat whose
  // turn it is, once its holder has taken the device (PassAndPlay.swift).
  const mine = mySeats(room).filter((s) => !g.forfeited[s]);
  const turnKey = `${g.round}:${g.turn}`;
  const [revealed, setRevealed] = useState<{ seat: number; key: string } | null>(null);
  const shared = mine.length > 1;
  const acting = !shared ? (mine[0] ?? null) : mine.includes(g.turn) && g.status === "playing" ? g.turn : null;
  const showHand = acting !== null && (!shared || (revealed?.seat === acting && revealed.key === turnKey));
  const curtainSeat = shared && acting !== null && !showHand ? acting : null;
  const seat = acting;
  const myTurn = seat !== null && g.turn === seat && g.status === "playing";

  // The hand's order and the trays are this device's own.
  const serverHand = showHand && seat !== null ? (g.hands[seat] ?? []) : [];
  const [order, setOrder] = useState<CardId[]>([]);
  const [trays, setTrays] = useState<CardId[][]>([]);
  const trayKey = `${g.round}:${seat}:${g.phase[seat ?? 0]}`;
  const lastTrayKey = useRef(trayKey);
  const phaseIndex = seat === null ? 0 : (g.phase[seat] ?? 0);
  const reqs = PHASES[phaseIndex] ?? [];
  const laidMine = seat !== null && g.laid[seat] !== null && g.laid[seat] !== undefined;
  const showTrays = showHand && !laidMine && g.status === "playing" && reqs.length > 0;

  useEffect(() => {
    if (lastTrayKey.current !== trayKey) {
      lastTrayKey.current = trayKey;
      setTrays([]);
    }
  }, [trayKey]);

  const inHand = new Set(serverHand);
  const trayCards = (trays.length === reqs.length ? trays : reqs.map((_, i) => trays[i] ?? [])).map((t) => t.filter((c) => inHand.has(c)));
  const inTrays = new Set(showTrays ? trayCards.flat() : []);
  const ordered = [...order.filter((c) => inHand.has(c) && !inTrays.has(c)), ...serverHand.filter((c) => !order.includes(c) && !inTrays.has(c))];
  useEffect(() => {
    if (ordered.join() !== order.filter((c) => inHand.has(c) && !inTrays.has(c)).join()) setOrder((o) => [...o.filter((c) => inHand.has(c)), ...serverHand.filter((c) => !o.includes(c))]);
  });

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
          } else if (ev.kind === "roundStarted") setTrays([]);
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
  const act = (action: Action) => {
    if (seat === null) return false;
    return store.act(seat, action);
  };
  const skipCandidates = seat === null ? [] : skipTargets(g, seat, room.seats);

  const draw = (from: "deck" | "discard") => {
    if (!myTurn || g.step !== "draw" || state.pending) return nope();
    if (from === "discard" && (g.discardTop === null || card(g.discardTop).kind === "cucumber")) return nope();
    learnTip("ct.draw");
    buzz("pick");
    act({ type: "draw", from });
  };

  const discard = (c: CardId, skipTarget?: number) => {
    if (!myTurn || g.step !== "play" || state.pending) return nope();
    if (discardNeedsTarget(c) && skipTarget === undefined && skipCandidates.length > 0) {
      if (skipCandidates.length === 1) skipTarget = skipCandidates[0];
      else {
        setSkipPick(c);
        return;
      }
    }
    learnTip("ct.discard");
    setHeld(new Map([[c, L.discard]]));
    setSelected(null);
    play("thud", 0.5);
    act(skipTarget === undefined ? { type: "discard", card: c } : { type: "discard", card: c, skipTarget });
  };

  const toTray = (c: CardId, i: number) => {
    if (!showTrays || i >= reqs.length) return nope();
    learnTip("ct.trays");
    setTrays(() => {
      const next = reqs.map((_, k) => (trayCards[k] ?? []).filter((x) => x !== c));
      if ((next[i]?.length ?? 0) >= (reqs[i]?.size ?? 0)) return trayCards;
      next[i] = [...(next[i] ?? []), c];
      return next;
    });
    setSelected(null);
    play("pop", 0.5);
  };

  const outOfTray = (c: CardId) => {
    setTrays(trayCards.map((t) => t.filter((x) => x !== c)));
    play("pop", 0.4);
  };

  const groups = showTrays && trayCards.length === reqs.length ? layDownGroups(trayCards, phaseIndex) : null;
  const groupsReady = groups !== null;
  const layDown = () => {
    if (!myTurn || g.step !== "play" || groups === null || state.pending) return nope();
    learnTip("ct.lay");
    const holdAt = new Map<CardId, Pose>();
    for (const c of trayCards.flat()) {
      const p = motion.last(`c${c}`);
      if (p) holdAt.set(c, p);
    }
    setHeld(holdAt);
    act({ type: "layDown", groups });
  };

  /** Whether `c` can be hit on seat `s`'s group `gi`: on that end, or on either for a run. */
  const hitOk = (c: CardId, s: number, gi: number, side?: HitSide) =>
    laidMine && hitTargets(c, g.laid).some((t) => t.seat === s && t.group === gi && (side === undefined || t.side === undefined || t.side === side));
  const hit = (c: CardId, s: number, gi: number, side?: HitSide) => {
    if (!myTurn || g.step !== "play" || state.pending || !hitOk(c, s, gi, side)) return nope();
    learnTip("ct.hit");
    setSelected(null);
    act(side ? { type: "hit", card: c, target: { seat: s, group: gi }, side } : { type: "hit", card: c, target: { seat: s, group: gi } });
  };

  function nope() {
    play("nope", 0.6);
    buzz("nope");
    return undefined;
  }

  // Where a card dropped at `p` would go.
  const targetAt = (p: Point, c: CardId): CtHover => {
    if (inside(p, L.discardRect, 14)) return { kind: "discard" };
    for (const [i, t] of L.trays.entries()) if (showTrays && inside(p, t, 6)) return { kind: "tray", i };
    for (const [s, row] of L.laid) {
      for (const [gi, grp] of row.groups.entries()) {
        if (inside(p, grp.rect, 8)) {
          const side = sideFor(p, grp.rect, s, gi);
          return { kind: "group", seat: s, group: gi, ok: hitOk(c, s, gi, side) };
        }
      }
    }
    if (discardNeedsTarget(c)) {
      for (const [s, at] of L.opponents) if (Math.hypot(p.x - at.x, p.y - at.y) < L.avatar * 0.7) return { kind: "seat", seat: s };
    }
    if (inside(p, L.handRect, 10)) {
      const xs = L.hand.map((h) => h.x + L.cw / 2);
      let index = xs.findIndex((x) => p.x < x);
      if (index < 0) index = xs.length;
      return { kind: "hand", index };
    }
    return null;
  };

  const sideFor = (p: Point, rect: { x: number; w: number }, s: number, gi: number): HitSide | undefined =>
    g.laid[s]?.[gi]?.kind === "run" ? (p.x < rect.x + rect.w / 2 ? "start" : "end") : undefined;

  const dropAt = (c: CardId, p: Point, pose: Pose) => {
    const t = targetAt(p, c);
    setHover(null);
    motion.place(`c${c}`, pose);
    if (!t) return;
    if (t.kind === "discard") return discard(c);
    if (t.kind === "tray") return toTray(c, t.i);
    if (t.kind === "group") return hit(c, t.seat, t.group, sideFor(p, L.laid.get(t.seat)!.groups[t.group]!.rect, t.seat, t.group));
    if (t.kind === "seat" && discardNeedsTarget(c)) return discard(c, t.seat);
    if (t.kind === "hand") {
      if (inTrays.has(c)) outOfTray(c);
      const without = ordered.filter((x) => x !== c);
      const before = ordered.indexOf(c);
      const at = t.index > before && before >= 0 ? t.index - 1 : t.index;
      without.splice(Math.min(at, without.length), 0, c);
      setOrder(without);
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
      onMove: (p) => setHover(live.current.targetAt(p, c)),
      onDrop: (p, pose) => live.current.dropAt(c, p, pose),
      onCancel: () => setHover(null),
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
        deckLive={myTurn && g.step === "draw"}
        onDiscard={() => (selected !== null ? tapTarget({ kind: "discard" }) : draw("discard"))}
        discardLive={canDrawDiscard}
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

        {curtainSeat !== null ? <Curtain name={seatName(room.seats[curtainSeat])} cat={room.seats[curtainSeat]?.person?.cat ?? 0} onReveal={() => setRevealed({ seat: curtainSeat, key: turnKey })} /> : null}

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
