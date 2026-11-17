/**
 * Cat Tower on a phone whose table is on a TV: just your cards and what you can do with them. Off
 * turn, the hand and whose turn it is; on your turn, the deck and the discard to draw from, then
 * the trays (or, once laid down, a short list of where the picked card can be hit), the buttons,
 * and the hand, big. Picking a place to hit lights that group on the TV. The table and its sounds
 * are the TV's: this phone makes only its taps and buzzes. Drag, motion and the moves are the full
 * table's own (drag.ts, motion.ts, ct-hand.ts).
 */
import { card, type CardId } from "@pounce/play-api/rules/cards";
import { buildGroup, type Requirement } from "@pounce/play-api/rules/groups";
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "preact/hooks";

import { catArt, RINGS } from "../lib/art";
import { buzz } from "../lib/haptics";
import { reducedMotion } from "../lib/settings";
import { play } from "../lib/sound";
import { Button, CloseMark, Icon, Tip, tipLearned, useSize } from "../ui/common";

import { phaseWords, useInsets } from "./cattower";
import { ctControllerLayout, type CtlLayout, type CtlStep } from "./ct-controller-layout";
import { ctMoves, useCtHand, useCtSeat } from "./ct-hand";
import { trayPoses } from "./ct-layout";
import { hitTargets, targetLabel, type HitTarget } from "./ct-moves";
import { DeckCards } from "./ct-public";
import { inside, press, useLatest, type Point, type Rect } from "./drag";
import { CardFace, cardLabel } from "./faces";
import { Motion, MOVE, transformOf, wiggle, type Pose } from "./motion";
import { seatCat, seatName, SeatAvatar } from "./seat";
import { Curtain, SwitchView, useTextScale } from "./shared";

import type { RoomState, RoomStore } from "../store/room";
import type { View } from "../store/views";

const REQ_WORDS = (r: Requirement): string => (r.kind === "set" ? `Set of ${r.size}` : r.kind === "run" ? `Run of ${r.size}` : `${r.size} of one coat`);

/** Where a held card is: the discard, a tray, or a place in the hand. */
type Over = { kind: "discard" } | { kind: "tray"; i: number } | { kind: "hand"; index: number } | null;

const box = (r: Rect) => ({ transform: `translate3d(${r.x}px, ${r.y}px, 0)`, width: `${r.w}px`, height: `${r.h}px` });
const sameTarget = (a: HitTarget | null, b: HitTarget) => a !== null && a.seat === b.seat && a.group === b.group && a.side === b.side;

export function CtController(props: { store: RoomStore; state: RoomState; onView: (view: View) => void }) {
  const { store, state } = props;
  const room = state.room!;
  const g = room.game!;
  const [rootRef, size] = useSize<HTMLDivElement>();
  const insets = useInsets();
  const text = useTextScale();
  const motion = useMemo(() => new Motion(reducedMotion), []);
  const els = useRef(new Map<string, HTMLElement>());

  const { mine, seat, showHand, curtainSeat, myTurn, reveal } = useCtSeat(room);
  const hand = useCtHand(room, seat, showHand);
  const { ordered, trayCards, inTrays, reqs, phaseIndex, laidMine, showTrays } = hand;
  const step: CtlStep = myTurn && showHand ? g.step : "off";

  const [selected, setSelected] = useState<CardId | null>(null);
  const [over, setOver] = useState<Over>(null);
  const [held, setHeld] = useState<Map<CardId, Pose>>(new Map());
  const [skipPick, setSkipPick] = useState<CardId | null>(null);
  const [target, setTarget] = useState<HitTarget | null>(null);
  const [focusIndex, setFocusIndex] = useState(0);

  // Hit: the places the picked card fits. The list of them opens over the bottom of the piles' room.
  const targets = step === "play" && laidMine && selected !== null ? hitTargets(selected, g.laid) : [];

  // The trays' room is kept until this player lays down, between rounds too: the frame never jumps.
  const trayRoom = seat !== null && !laidMine ? reqs.length : 0;
  const L: CtlLayout = useMemo(
    () => ctControllerLayout({ width: size.width || 360, height: size.height || 640, insets, handCount: ordered.length, trays: trayRoom, step, hits: targets.length, text }),
    [size.width, size.height, insets, ordered.length, trayRoom, step, targets.length, text],
  );

  // The table menu's paw is the table screen's: it grows with this screen's top bar.
  useLayoutEffect(() => {
    const screen = rootRef.current?.parentElement;
    screen?.style.setProperty("--k", String(L.unit));
    return () => screen?.style.removeProperty("--k");
  }, [L.unit]);

  // This player's round, for a moment in the status: whether they climbed, and the points.
  const [result, setResult] = useState<{ up: boolean; points: number } | null>(null);

  useEffect(() => {
    if (!state.pending) setHeld(new Map());
  }, [state.pending]);

  // Your turn buzzes (the TV says it out loud); a new round starts with empty trays; a card you
  // draw comes off the deck.
  useEffect(
    () =>
      store.subscribe({
        event: ({ event: e }) => {
          if (e.kind !== "game") return;
          const ev = e.event;
          if (ev.kind === "turn" && mine.includes(ev.seat)) buzz("turn");
          else if (ev.kind === "roundStarted") {
            hand.setTrays([]);
            setResult(null);
          } else if (ev.kind === "roundOver") {
            // A shared device's seats each have their own: the TV shows them all.
            const own = mine.length === 1 ? mine[0]! : null;
            if (own !== null) setResult({ up: ev.advanced.includes(own), points: ev.points[own] ?? 0 });
          } else if (ev.kind === "drew" && ev.card !== undefined && ev.from === "deck") motion.spawnFrom(`c${ev.card}`, L.piles.deck);
        },
      }),
    [store, mine.join(), L, motion],
  );

  // A refused move: back where it was, with a shake.
  useEffect(() => {
    if (!state.error) return;
    setHeld(new Map());
    play("nope");
    buzz("nope");
    wiggle(rootRef.current?.querySelector(".ctl-hand") as HTMLElement | null);
  }, [state.error?.n]);

  const moves = ctMoves({ store, state, room, seat, myTurn, hand, motion, discardPose: L.piles.discard, setHeld, setSelected, setSkipPick, quiet: true });
  const { nope, draw, discard, toTray, outOfTray, groups, layDown, hit, skipCandidates } = moves;
  const groupsReady = groups !== null;

  // The place chosen to hit, lit on the TV while it is.
  const chosen = targets.find((t) => sameTarget(target, t)) ?? null;
  useEffect(() => setTarget(null), [selected]);
  const aimKey = seat !== null && chosen ? `${seat}:${chosen.seat}:${chosen.group}` : "";
  const aimedFrom = useRef<number | null>(null);
  useEffect(() => {
    if (seat !== null && chosen) {
      store.aim(seat, { target: { seat: chosen.seat, group: chosen.group } });
      aimedFrom.current = seat;
    } else if (aimedFrom.current !== null) {
      store.aim(aimedFrom.current, null);
      aimedFrom.current = null;
    }
  }, [aimKey]);
  useEffect(
    () => () => {
      if (aimedFrom.current !== null) store.aim(aimedFrom.current, null);
    },
    [store],
  );
  const confirmHit = () => {
    if (selected === null || !chosen) return nope();
    hit(selected, chosen.seat, chosen.group, chosen.side);
  };

  // Poses: the hand, the trays, and the discard's top card on its pile.
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
  const pileTop = g.discardTop !== null && !poses.has(`c${g.discardTop}`) ? g.discardTop : null;
  if (pileTop !== null) poses.set(`c${pileTop}`, L.piles.discard);

  const moveStyle = (key: string) => {
    const i = ordered.indexOf(Number(key.slice(1)));
    return i >= 0 && !motion.last(key) ? { ...MOVE, delay: Math.min(i, 12) * 45 } : MOVE;
  };
  useLayoutEffect(() => {
    motion.apply(els.current, poses, moveStyle);
  });
  const setEl = (key: string) => (el: HTMLElement | null) => {
    if (el) els.current.set(key, el);
    else els.current.delete(key);
  };

  // Dragging: to the discard, into a tray, or to a new place in the hand.
  const overAt = (p: Point): Over => {
    if (step === "play" && inside(p, L.piles.discardRect, 14)) return { kind: "discard" };
    for (const [i, t] of L.trays.entries()) if (showTrays && inside(p, t, 6)) return { kind: "tray", i };
    if (inside(p, L.handRect, 10)) {
      let index = L.hand.findIndex((h) => p.x < h.x + L.cw / 2);
      if (index < 0) index = L.hand.length;
      return { kind: "hand", index };
    }
    return null;
  };
  const dropAt = (c: CardId, p: Point, pose: Pose) => {
    const t = overAt(p);
    setOver(null);
    motion.place(`c${c}`, pose);
    if (!t) return;
    if (t.kind === "discard") return discard(c);
    if (t.kind === "tray") return toTray(c, t.i);
    if (inTrays.has(c)) outOfTray(c);
    hand.reorder(c, t.index);
  };
  const tapCard = (c: CardId) => {
    if (inTrays.has(c)) return outOfTray(c);
    play("tick", 0.4);
    buzz("tap");
    setSelected((s) => (s === c ? null : c));
  };
  const live = useLatest({ overAt, dropAt, tapCard });
  const onCardDown = (c: CardId) => (e: PointerEvent) => {
    const el = els.current.get(`c${c}`);
    if (!el || !showHand) return;
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
      onMove: (p) => setOver(live.current.overAt(p)),
      onDrop: (p, pose) => live.current.dropAt(c, p, pose),
      onCancel: () => setOver(null),
    });
  };

  // The keyboard: arrows pick, Enter lifts, D draws, T takes the discard, X discards, L lays down.
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
      else if (k === "l") layDown();
      else if (k === "escape") setSelected(null);
      else return;
      e.preventDefault();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const canDrawDiscard = step === "draw" && g.discardTop !== null && card(g.discardTop).kind !== "cucumber";
  const turnSeat = room.seats[g.turn];
  // The status: a name (cut short only if it must be) and the words after it.
  const status: { who?: string; words: string; tone: "" | "mine" | "up" | "same" } =
    result !== null
      ? { words: `${result.up ? "Level up" : "Same level"} · +${result.points}`, tone: result.up ? "up" : "same" }
      : g.status === "playing"
        ? myTurn
          ? { words: "Your turn", tone: "mine" }
          : { who: seatName(turnSeat), words: "'s turn", tone: "" }
        : g.status === "roundOver"
          ? { words: "Round over", tone: "" }
          : { words: "", tone: "" };
  const statusLong = (status.who ?? "").length + status.words.length > 18;
  const statusCat = seatCat(myTurn && seat !== null ? room.seats[seat] : turnSeat);
  const discardName =
    g.discardTop === null ? "Discard pile, empty" : `Discard pile: ${cardLabel(g.discardTop)}${canDrawDiscard ? ". Take it" : selected !== null && step === "play" ? ". Discard here" : ""}`;
  const switchLearned = tipLearned("tv.switch");

  // The discard's top card is the pile's to show, not yours to move: a tap goes through to the pile.
  const renderCard = (id: CardId, p: Pose) =>
    id === pileTop ? (
      <div key={`c${id}`} ref={setEl(`c${id}`)} class={`card ${step === "off" ? "rest" : ""}`} style={{ transform: transformOf(p), zIndex: p.z ?? 1 }}>
        <div class="card-inner">
          <CardFace id={id} />
        </div>
      </div>
    ) : (
      <div key={`c${id}`} ref={setEl(`c${id}`)} class={`card ${selected === id ? "picked" : ""} mine`} style={{ transform: transformOf(p), zIndex: p.z ?? 1 }} onPointerDown={onCardDown(id)}>
        <button
          type="button"
          class="card-inner"
          aria-label={cardLabel(id)}
          aria-pressed={selected === id}
          onClick={(e) => e.preventDefault()}
          onKeyDown={(e) => {
            if (e.key === "Enter" || e.key === " ") {
              e.preventDefault();
              tapCard(id);
            }
          }}
          onFocus={() => setFocusIndex(Math.max(0, ordered.indexOf(id)))}
        >
          <CardFace id={id} compact={(p.s ?? 1) < 0.9} />
        </button>
      </div>
    );

  return (
    <div class={`ct-table ctl ${L.landscape ? "landscape" : ""} ${myTurn ? "my-turn" : ""}`} ref={rootRef} style={{ ["--cw" as string]: `${L.cw}px`, ["--ch" as string]: `${L.ch}px`, ["--k" as string]: String(L.unit) }}>
      <SwitchView view="cards" onChange={props.onView} style={box(L.switch)} />

      {status.words ? (
        <div class={`ctl-status ${L.status.y === L.switch.y ? "inline" : ""}`} style={box(L.status)}>
          <p class={`ctl-status-pill ${status.tone} ${statusLong ? "long" : ""}`} aria-live="polite" style={{ ["--ring" as string]: RINGS[g.turn % RINGS.length] }}>
            <img src={catArt(statusCat, myTurn ? "awake" : "idle")} alt="" />
            <span class="words">
              {status.who ? <span class="who">{status.who}</span> : null}
              {status.words}
            </span>
          </p>
        </div>
      ) : null}

      {/* Off turn the piles rest where they sit on your turn, for anyone to see: nothing to tap. */}
      {step === "off" ? (
        <>
          <div class="deck rest" style={box(L.piles.deckRect)} role="img" aria-label={`Deck, ${g.deckCount} cards`}>
            <DeckCards count={g.deckCount} />
          </div>
          <div class="discard rest" style={box(L.piles.discardRect)} role="img" aria-label={discardName} />
        </>
      ) : (
        <>
          <button
            type="button"
            id="deck"
            class={`deck ${step === "draw" ? "live" : ""}`}
            style={box(L.piles.deckRect)}
            aria-label={`Deck, ${g.deckCount} cards. Draw`}
            disabled={step !== "draw"}
            onClick={() => draw("deck")}
          >
            <DeckCards count={g.deckCount} />
          </button>
          <button
            type="button"
            id="discard"
            class={`discard ${over?.kind === "discard" ? "hot" : ""} ${canDrawDiscard ? "live" : ""} ${selected !== null && step === "play" ? "aim" : ""}`}
            style={box(L.piles.discardRect)}
            aria-label={discardName}
            onClick={() => (selected !== null && step === "play" ? discard(selected) : draw("discard"))}
          />
        </>
      )}

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
                class={`tray ${over?.kind === "tray" && over.i === i ? "hot" : ""} ${valid ? "good" : full ? "bad" : ""}`}
                style={box(t)}
                aria-label={`Tray ${i + 1}: ${REQ_WORDS(req)}, ${cards.length} of ${req.size}${valid ? ", ready" : ""}`}
                onClick={() => (selected !== null ? toTray(selected, i) : undefined)}
              >
                <span class="tray-label">{cards.length === 0 ? REQ_WORDS(req) : `${cards.length}/${req.size}`}</span>
              </button>
            );
          })
        : null}

      {targets.length > 0 && L.hits && L.hitClose ? (
        <>
          <div class="ctl-hits panel" style={{ ...box(L.hits), ["--close" as string]: `${L.hitClose.w}px` }} role="group" aria-label={`Hit with ${cardLabel(selected!)}`}>
            <ul>
              {targets.map((t) => {
                const both = targets.filter((x) => x.seat === t.seat && x.group === t.group).length > 1;
                const on = sameTarget(chosen, t);
                return (
                  <li key={`${t.seat}:${t.group}:${t.side ?? ""}`}>
                    <button
                      type="button"
                      class={`ctl-hit ${on ? "on" : ""}`}
                      aria-pressed={on}
                      style={{ ["--ring" as string]: RINGS[t.seat % RINGS.length] }}
                      onClick={() => {
                        play("tick", 0.4);
                        buzz("tap");
                        setTarget(on ? null : t);
                      }}
                    >
                      <img src={catArt(seatCat(room.seats[t.seat]), "idle")} alt="" />
                      <span class="label">{targetLabel(room, t.seat, t.group)}</span>
                      {both ? <span class="end">{t.side === "start" ? "Low end" : "High end"}</span> : null}
                    </button>
                  </li>
                );
              })}
            </ul>
          </div>
          <button type="button" class="ctl-hits-close" style={box(L.hitClose)} aria-label="Cancel" onClick={() => setSelected(null)}>
            <CloseMark size={Math.round(12 * L.unit)} />
          </button>
        </>
      ) : null}

      {step !== "off" ? (
        <div class="ctl-actions" style={box(L.actions)}>
          {step === "draw" ? (
            <p class="ctl-cue outlined">Draw a card</p>
          ) : (
            <>
              {showTrays && groupsReady ? (
                <Button size="small" variant="ok" onClick={layDown} id="lay" aria-label="Lay down">
                  <Icon name="icon-paw-menu" size={28} /> Lay down
                </Button>
              ) : null}
              {targets.length > 0 ? (
                <Button size="small" variant="ok" id="hit" disabled={!chosen} onClick={confirmHit}>
                  Hit
                </Button>
              ) : null}
              {!(showTrays && groupsReady) || selected !== null ? (
                <Button size="small" variant="magenta" id="discard-btn" disabled={selected === null} onClick={() => selected !== null && discard(selected)}>
                  Discard
                </Button>
              ) : null}
            </>
          )}
        </div>
      ) : null}

      <div class="ctl-hand" style={box(L.handRect)} />
      <div class="cards" role="group" aria-label="Your hand">
        {[...poses].map(([key, p]) => renderCard(Number(key.slice(1)), p))}
      </div>

      {skipPick !== null ? (
        <div class="skip-pick" role="dialog" aria-label="Skip whose turn?">
          <p class="outlined">Skip whose turn?</p>
          <div class="skip-seats">
            {skipCandidates.map((s) => (
              <SeatAvatar
                seat={s}
                info={room.seats[s]}
                size={72}
                turn={false}
                onClick={() => {
                  const c = skipPick;
                  setSkipPick(null);
                  discard(c, s);
                }}
              />
            ))}
          </div>
          <Button size="small" variant="violet" onClick={() => setSkipPick(null)}>
            Cancel
          </Button>
        </div>
      ) : null}

      {curtainSeat !== null ? <Curtain name={seatName(room.seats[curtainSeat])} cat={room.seats[curtainSeat]?.person?.cat ?? 0} onReveal={() => reveal(curtainSeat)} /> : null}

      <Tip id="tv.switch" anchor="view-switch" text="Your cards are here. The table is on the TV." show={curtainSeat === null && skipPick === null} place="below" />
      <Tip id="ct.draw" anchor="deck" text="Take a card from the deck or the discard pile." show={switchLearned && step === "draw" && !state.pending} />
      <Tip id="ct.trays" anchor="tray-0" text={`This round: ${phaseWords(phaseIndex)}. Drag cards into the trays.`} show={switchLearned && step === "play" && showTrays && tipLearned("ct.draw")} />
      <Tip id="ct.discard" anchor="discard" text="Drag one card to the discard pile." show={switchLearned && step === "play" && tipLearned("ct.trays") && !groupsReady && targets.length === 0} />
      <Tip id="ct.lay" anchor="lay" text="Tap the paw to lay down your level." show={switchLearned && groupsReady && step === "play"} />
    </div>
  );
}
