/**
 * The Cat Tower table (TableScene.swift): opponents across the top, the tower down the side, the
 * laid groups and the two piles in the middle, the trays and the hand at the bottom. Drag or
 * tap to play; the keyboard plays the whole game too. Every card is one element moved only by
 * its transform (motion.ts).
 */
import { card, type CardId } from "@pounce/play-api/rules/cards";
import { buildGroup, canHit, type Requirement } from "@pounce/play-api/rules/groups";
import { matchPhase, PHASES } from "@pounce/play-api/rules/phases";
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "preact/hooks";


import { art, catArt, RINGS } from "../lib/art";
import { buzz } from "../lib/haptics";
import { reducedMotion } from "../lib/settings";
import { play } from "../lib/sound";
import { mySeats } from "../store/lobby";
import { Button, Icon, learnTip, Tip, tipLearned, useSize } from "../ui/common";

import { ctLayout, trayPoses, type Insets } from "./ct-layout";
import { inside, press, type Point } from "./drag";
import { CardFace, cardLabel } from "./faces";
import { Motion, MOVE, transformOf, wiggle, type Pose } from "./motion";
import { seatCat, seatName, SeatAvatar } from "./seat";
import { Curtain, Flights, RoundOver, type Flight } from "./shared";

import type { RoomState, RoomStore } from "../store/room";
import type { RoomView } from "@pounce/play-api/protocol";
import type { Action, GameEvent } from "@pounce/play-api/rules/engine";

const REQ_WORDS = (r: Requirement): string => (r.kind === "set" ? `Set of ${r.size}` : r.kind === "run" ? `Run of ${r.size}` : `${r.size} of one coat`);

export const phaseWords = (phase: number): string => (PHASES[phase] ?? []).map(REQ_WORDS).join(" + ");

/** Reads the safe-area insets once per resize, from CSS. */
export function useInsets(): Insets {
  const [insets, setInsets] = useState<Insets>({ top: 0, right: 0, bottom: 0, left: 0 });
  useLayoutEffect(() => {
    const probe = document.createElement("div");
    probe.style.cssText =
      "position:fixed;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)";
    document.body.append(probe);
    const read = () => {
      const cs = getComputedStyle(probe);
      setInsets({ top: parseFloat(cs.paddingTop) || 0, right: parseFloat(cs.paddingRight) || 0, bottom: parseFloat(cs.paddingBottom) || 0, left: parseFloat(cs.paddingLeft) || 0 });
    };
    read();
    window.addEventListener("resize", read);
    return () => {
      window.removeEventListener("resize", read);
      probe.remove();
    };
  }, []);
  return insets;
}

type Hover = { kind: "discard" } | { kind: "tray"; i: number } | { kind: "group"; seat: number; group: number; ok: boolean } | { kind: "seat"; seat: number } | { kind: "hand"; index: number } | null;

export function CatTowerTable(props: { store: RoomStore; state: RoomState }) {
  const { store, state } = props;
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
  const [hover, setHover] = useState<Hover>(null);
  const [held, setHeld] = useState<Map<CardId, Pose>>(new Map());
  const [skipPick, setSkipPick] = useState<CardId | null>(null);
  const [flights, setFlights] = useState<Flight[]>([]);
  const [round, setRound] = useState<Extract<GameEvent, { kind: "roundOver" }> | null>(null);
  const [under, setUnder] = useState<CardId | null>(null);
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

  // The discard's card underneath stays a moment while the new one lands on it.
  const prevTop = useRef<CardId | null>(g.discardTop);
  useEffect(() => {
    if (prevTop.current !== g.discardTop) {
      setUnder(prevTop.current);
      prevTop.current = g.discardTop;
      const t = setTimeout(() => setUnder(null), 420);
      return () => clearTimeout(t);
    }
  }, [g.discardTop]);

  const avatarPose = (s: number, scale = 0.35): Pose => {
    const at = L.opponents.get(s) ?? L.laid.get(s)?.avatar ?? { x: L.centre.x, y: -L.ch };
    return { x: at.x - L.cw / 2, y: at.y - L.ch / 2, r: 0, s: scale };
  };

  // Events: sounds, flights and where new cards come from.
  useEffect(
    () =>
      store.subscribe({
        event: ({ event: e }) => {
          if (e.kind !== "game") return;
          const ev = e.event;
          switch (ev.kind) {
            case "drew": {
              const ours = ev.card !== undefined;
              play("flip", 0.6);
              if (ev.from === "discard" && g.discardTop !== null) motion.spawnFrom(`c${g.discardTop}`, L.discard);
              if (ours && ev.card !== undefined) {
                motion.spawnFrom(`c${ev.card}`, ev.from === "deck" ? L.deck : L.discard);
              } else {
                const to = avatarPose(ev.seat);
                setFlights((f) => [...f, { key: `f${Date.now()}${Math.random()}`, from: ev.from === "deck" ? L.deck : L.discard, to, card: ev.from === "discard" ? (g.discardTop ?? undefined) : undefined }]);
              }
              break;
            }
            case "discarded":
              motion.spawnFrom(`c${ev.card}`, avatarPose(ev.seat));
              play(card(ev.card).kind === "cucumber" ? "scream" : "thud", 0.6);
              buzz("drop");
              break;
            case "laidDown":
              for (const grp of ev.groups) for (const c of grp.cards) motion.spawnFrom(`c${c}`, avatarPose(ev.seat));
              play("sparkle");
              buzz("drop");
              break;
            case "hit":
              motion.spawnFrom(`c${ev.card}`, avatarPose(ev.seat));
              play("pop");
              break;
            case "skipped":
              play("bat");
              break;
            case "turn":
              if (mine.includes(ev.seat)) {
                play("tick", 0.6);
                buzz("turn");
              }
              break;
            case "reshuffled":
              play("whoosh");
              break;
            case "roundOver":
              setRound(ev);
              play(ev.advanced.some((s) => mine.includes(s)) ? "fanfare" : "leap");
              buzz("win");
              break;
            case "roundStarted":
              setRound(null);
              setTrays([]);
              play("whoosh");
              break;
          }
        },
      }),
    [store, L, g.discardTop, mine.join()],
  );

  // A refused move: back where it was, with a shake.
  useEffect(() => {
    if (!state.error) return;
    setHeld(new Map());
    play("nope");
    buzz("nope");
    wiggle(rootRef.current?.querySelector(".hand-zone") as HTMLElement | null);
  }, [state.error?.n]);

  // Poses for every card on show.
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
  for (const [s, row] of L.laid) {
    (g.laid[s] ?? []).forEach((grp, gi) => {
      const at = row.groups[gi];
      grp.cards.forEach((c, j) => {
        const p = at?.poses[j];
        if (p) poses.set(`c${c}`, p);
      });
    });
  }
  if (g.discardTop !== null) poses.set(`c${g.discardTop}`, held.get(g.discardTop) ?? L.discard);

  useLayoutEffect(() => {
    motion.apply(els.current, poses, (key) => {
      // A new deal: cards come off the deck one after another.
      const id = Number(key.slice(1));
      const i = ordered.indexOf(id);
      return i >= 0 && !motion.last(key) ? { ...MOVE, delay: Math.min(i, 12) * 45 } : MOVE;
    });
  });

  const setEl = (key: string) => (el: HTMLElement | null) => {
    if (el) els.current.set(key, el);
    else els.current.delete(key);
  };

  // Moves.
  const act = (action: Action) => {
    if (seat === null) return false;
    return store.act(seat, action);
  };
  const skipCandidates = room.seats.flatMap((s, i) => (i !== seat && (s.kind === "human" || s.kind === "bot") && !g.pendingSkip[i] && !g.forfeited[i] ? [i] : []));

  const draw = (from: "deck" | "discard") => {
    if (!myTurn || g.step !== "draw" || state.pending) return nope();
    if (from === "discard" && (g.discardTop === null || card(g.discardTop).kind === "cucumber")) return nope();
    learnTip("ct.draw");
    buzz("pick");
    act({ type: "draw", from });
  };

  const discard = (c: CardId, skipTarget?: number) => {
    if (!myTurn || g.step !== "play" || state.pending) return nope();
    if (card(c).kind === "cucumber" && skipTarget === undefined && skipCandidates.length > 0) {
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

  const groupsReady = showTrays && trayCards.length === reqs.length && matchPhase(phaseIndex, trayCards.map((cards) => ({ cards }))) !== null;
  const layDown = () => {
    if (!myTurn || g.step !== "play" || !groupsReady || state.pending) return nope();
    learnTip("ct.lay");
    const holdAt = new Map<CardId, Pose>();
    for (const c of trayCards.flat()) {
      const p = motion.last(`c${c}`);
      if (p) holdAt.set(c, p);
    }
    setHeld(holdAt);
    act({ type: "layDown", groups: trayCards.map((cards) => ({ cards })) });
  };

  const hitOk = (c: CardId, s: number, gi: number, side?: "start" | "end") => {
    const grp = g.laid[s]?.[gi];
    return Boolean(grp && laidMine && canHit(grp, c, side).ok);
  };
  const hit = (c: CardId, s: number, gi: number, side?: "start" | "end") => {
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
  const targetAt = (p: Point, c: CardId): Hover => {
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
    if (card(c).kind === "cucumber") {
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

  const sideFor = (p: Point, rect: { x: number; w: number }, s: number, gi: number): "start" | "end" | undefined =>
    g.laid[s]?.[gi]?.kind === "run" ? (p.x < rect.x + rect.w / 2 ? "start" : "end") : undefined;

  const dropAt = (c: CardId, p: Point, pose: Pose) => {
    const t = targetAt(p, c);
    setHover(null);
    motion.place(`c${c}`, pose);
    if (!t) return;
    if (t.kind === "discard") return discard(c);
    if (t.kind === "tray") return toTray(c, t.i);
    if (t.kind === "group") return hit(c, t.seat, t.group, sideFor(p, L.laid.get(t.seat)!.groups[t.group]!.rect, t.seat, t.group));
    if (t.kind === "seat" && card(c).kind === "cucumber") return discard(c, t.seat);
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
      onTap: () => tapCard(c),
      onStart: () => {
        play("tick", 0.4);
        buzz("pick");
        setSelected(null);
      },
      onMove: (p) => setHover(targetAt(p, c)),
      onDrop: (p, pose) => dropAt(c, p, pose),
      onCancel: () => setHover(null),
    });
  };

  // A tap on a target with a card picked.
  const tapTarget = (t: Exclude<Hover, null>) => {
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
        for (const [s, groups] of g.laid.entries()) for (const [gi] of (groups ?? []).entries()) if (hitOk(selected, s, gi)) return hit(selected, s, gi);
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

  const style = { ["--cw" as string]: `${L.cw}px`, ["--ch" as string]: `${L.ch}px`, ["--avatar" as string]: `${L.avatar}px` };
  const canDrawDiscard = myTurn && g.step === "draw" && g.discardTop !== null && card(g.discardTop).kind !== "cucumber";

  return (
    <div class={`ct-table ${L.landscape ? "landscape" : ""} ${myTurn ? "my-turn" : ""}`} ref={rootRef} style={style}>
      <img class="rug-art" src={art("rug")} alt="" style={{ transform: `translate3d(${L.rug.x}px, ${L.rug.y}px, 0)`, width: `${L.rug.w}px`, height: `${L.rug.h}px` }} />

      <Tower seats={room.seats} phase={g.phase} rect={L.tower} turn={g.turn} />

      {opponents.map((s) => {
        const at = L.opponents.get(s);
        if (!at) return null;
        const t = hover?.kind === "seat" && hover.seat === s;
        return (
          <div class="avatar-at" style={{ transform: `translate3d(${at.x - L.avatar / 2}px, ${at.y - L.avatar / 2}px, 0)` }}>
            <SeatAvatar
              seat={s}
              info={room.seats[s]}
              size={L.avatar}
              turn={g.turn === s && g.status === "playing"}
              count={g.handCounts[s]}
              laid={Boolean(g.laid[s])}
              skip={g.pendingSkip[s]}
              out={g.forfeited[s]}
              target={t}
              onClick={selected !== null && card(selected).kind === "cucumber" ? () => tapTarget({ kind: "seat", seat: s }) : undefined}
            />
          </div>
        );
      })}

      {[...L.laid].map(([s, row]) => (
        <>
          <div class="laid-owner" style={{ transform: `translate3d(${row.avatar.x - row.avatar.size / 2}px, ${row.avatar.y - row.avatar.size / 2}px, 0)`, width: `${row.avatar.size}px`, height: `${row.avatar.size}px` }}>
            <SeatAvatar seat={s} info={room.seats[s]} size={row.avatar.size} turn={false} label={`${seatName(room.seats[s])} laid down`} />
          </div>
          {row.groups.map((grp, gi) => {
            const h = hover?.kind === "group" && hover.seat === s && hover.group === gi;
            const ok = selected !== null && hitOk(selected, s, gi);
            const groupCards = g.laid[s]?.[gi]?.cards ?? [];
            return (
              <button
                type="button"
                class={`group-zone ${h ? (hover.ok ? "good" : "bad") : ok ? "good" : ""}`}
                style={{ transform: `translate3d(${grp.rect.x}px, ${grp.rect.y}px, 0)`, width: `${grp.rect.w}px`, height: `${grp.rect.h}px` }}
                aria-label={`${seatName(room.seats[s])}'s group: ${groupCards.map(cardLabel).join(", ")}`}
                tabIndex={selected !== null && laidMine ? 0 : -1}
                onClick={() => tapTarget({ kind: "group", seat: s, group: gi, ok: true })}
              />
            );
          })}
        </>
      ))}

      <button
        type="button"
        id="deck"
        class={`deck ${myTurn && g.step === "draw" ? "live" : ""}`}
        style={{ transform: transformOf(L.deck) }}
        aria-label={`Deck, ${g.deckCount} cards. Draw`}
        disabled={!(myTurn && g.step === "draw")}
        onClick={() => draw("deck")}
      >
        <span class="deck-card d3" />
        <span class="deck-card d2" />
        <span class="deck-card" />
        <span class="pile-count">{g.deckCount}</span>
      </button>
      <button
        type="button"
        id="discard"
        class={`discard ${hover?.kind === "discard" ? "hot" : ""} ${canDrawDiscard ? "live" : ""} ${selected !== null && myTurn && g.step === "play" ? "aim" : ""}`}
        style={{ transform: transformOf(L.discard) }}
        aria-label={g.discardTop === null ? "Discard pile, empty" : `Discard pile: ${cardLabel(g.discardTop)}. ${canDrawDiscard ? "Take it" : selected !== null ? "Discard here" : ""}`}
        onClick={() => (selected !== null ? tapTarget({ kind: "discard" }) : draw("discard"))}
      >
        {under !== null || g.discardCount > 1 ? (
          <span class="under">{under !== null ? <CardFace id={under} /> : <div class="face blank" />}</span>
        ) : null}
      </button>

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

      <div class="hand-zone" style={{ transform: `translate3d(${L.handRect.x}px, ${L.handRect.y}px, 0)`, width: `${L.handRect.w}px`, height: `${L.handRect.h}px` }} />

      <div class="cards" role="group" aria-label="Your hand">
        {[...poses.keys()].map((key) => {
          const id = Number(key.slice(1));
          const p = poses.get(key)!;
          const inHandNow = ordered.includes(id);
          const interactive = inHandNow || inTrays.has(id);
          const compact = (p.s ?? 1) < 0.9;
          return (
            <div
              key={key}
              ref={setEl(key)}
              class={`card ${selected === id ? "picked" : ""} ${interactive ? "mine" : ""}`}
              style={{ transform: transformOf(p), zIndex: p.z ?? 1 }}
              onPointerDown={interactive ? onCardDown(id) : undefined}
            >
              {interactive ? (
                <button type="button" class="card-inner" aria-label={cardLabel(id)} aria-pressed={selected === id} onClick={(e) => e.preventDefault()} onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    tapCard(id);
                  }
                }} onFocus={() => setFocusIndex(Math.max(0, ordered.indexOf(id)))}>
                  <CardFace id={id} compact={compact} />
                </button>
              ) : (
                <div class="card-inner">
                  <CardFace id={id} compact={compact} />
                </div>
              )}
            </div>
          );
        })}
      </div>

      <Flights flights={flights} cw={L.cw} ch={L.ch} onDone={(k) => setFlights((f) => f.filter((x) => x.key !== k))} />

      {showTrays && groupsReady && myTurn && g.step === "play" ? (
        <div class="action-at" style={{ transform: `translate3d(${L.action.x}px, ${L.action.y}px, 0)` }}>
          <Button size="small" variant="ok" onClick={layDown} id="lay" aria-label="Lay down">
            <Icon name="icon-paw-menu" size={28} /> Lay down
          </Button>
        </div>
      ) : null}

      {cue ? (
        <p class={`cue ${myTurn ? "mine" : ""}`} aria-live="polite" style={{ transform: `translate3d(-50%, ${(showTrays ? L.trays[0]!.y : L.handRect.y) - 34}px, 0)` }}>
          {cue}
        </p>
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

      {round ? <RoundOver seats={room.seats} ev={round} mine={mine} /> : null}

      <Tip id="ct.draw" anchor="deck" text="Take a card from the deck or the discard pile." show={myTurn && g.step === "draw" && !state.pending} />
      <Tip id="ct.trays" anchor="tray-0" text={`This round: ${phaseWords(phaseIndex)}. Drag cards into the trays.`} show={myTurn && g.step === "play" && showTrays && tipLearned("ct.draw")} />
      <Tip id="ct.discard" anchor="discard" text="Drag one card to the discard pile." show={myTurn && g.step === "play" && tipLearned("ct.trays") && !groupsReady} />
      <Tip id="ct.lay" anchor="lay" text="Tap the paw to lay down your level." show={groupsReady && myTurn} />
      <Tip id="ct.hit" anchor="discard" text="Drop cards on any laid group they fit." show={myTurn && g.step === "play" && laidMine && tipLearned("ct.discard")} />
    </div>
  );
}

/** The ten-shelf tower with each cat on the shelf they reached (TowerNode.swift). */
function Tower(props: { seats: RoomView["seats"]; phase: number[]; rect: { x: number; y: number; w: number; h: number }; turn: number }) {
  const { rect } = props;
  const shelf = rect.h / 11;
  const cats = props.phase.map((ph, s) => ({ s, ph })).filter(({ s }) => props.seats[s]?.kind === "human" || props.seats[s]?.kind === "bot");
  return (
    <div class="tower" style={{ transform: `translate3d(${rect.x}px, ${rect.y}px, 0)`, width: `${rect.w}px`, height: `${rect.h}px` }} role="img" aria-label={cats.map(({ s, ph }) => `${seatName(props.seats[s])}: level ${Math.min(ph + 1, 10)}`).join(". ")}>
      {Array.from({ length: 10 }, (_, i) => (
        <span class="shelf" style={{ transform: `translate3d(0, ${rect.h - (i + 1) * shelf - shelf * 0.2}px, 0)`, height: `${shelf * 0.7}px` }}>
          <i>{i + 1}</i>
        </span>
      ))}
      {cats.map(({ s, ph }, k) => {
        const level = Math.min(ph, 10);
        const y = rect.h - (level + 0.9) * shelf - shelf * 0.25;
        const offset = (k % 3) * rect.w * 0.18;
        return (
          <span class={`tower-cat ${props.turn === s ? "turn" : ""}`} style={{ transform: `translate3d(${offset}px, ${y}px, 0)`, width: `${rect.w * 0.78}px`, height: `${rect.w * 0.78}px`, ["--ring" as string]: ringOf(s) }}>
            <img src={catImg(props.seats[s])} alt="" />
          </span>
        );
      })}
    </div>
  );
}

const ringOf = (s: number) => RINGS[s % RINGS.length];
const catImg = (s: RoomView["seats"][number] | undefined) => catArt(seatCat(s), "idle");
