/**
 * The Birdwatch table on a phone, a tablet or a laptop (design §5.2-5.5, §5.7): the public table
 * (bw-public.tsx) with this player's hand and this step's controls on top. Tap a card to lift
 * it and again to play it, or drag it onto the sill; the keys play it too (arrows pick, Enter
 * plays, 1 to 4 pick trump). Cards the server doesn't list in `playable` are dimmed and refused.
 * On a shared device the curtain hides each hand until its holder takes the device. With
 * `cards`, it is the Cards view of a phone whose table is on a TV: just the hand and controls.
 */
import { useEffect, useMemo, useRef, useState } from "preact/hooks";

import { buzz } from "../lib/haptics";
import { reducedMotion } from "../lib/settings";
import { play } from "../lib/sound";
import { learnTip, Tip, tipLearned, useMedia, useSize } from "../ui/common";

import { BirdFace } from "./bw-faces";
import { bwLayout } from "./bw-layout";
import { cardLabel, isSecretPartner, othersInOrder, seatOnShow, sortHand, stepFor, suggestTrump, type BwStep, type CardId, type Suit } from "./bw-model";
import { BidPanel, HandSummaryCard, NestBar, PartnerPicker, ScoreSheet, TrumpPicker, useBidAmount } from "./bw-panels";
import { BwPublic, bwStyle } from "./bw-public";
import { useInsets } from "./cattower";
import { inside, press, useLatest, type Point } from "./drag";
import { Motion, transformOf, wiggle, type Pose } from "./motion";
import { seatName } from "./seat";
import { Curtain } from "./shared";

import type { RoomState, RoomStore } from "../store/room";
import type { BirdView } from "@pounce/play-api/birdwatch/view";
import type { RoomView } from "@pounce/play-api/protocol";

/** What the cue says while someone else acts. */
function waitWords(room: RoomView, v: BirdView): string {
  if (v.turn === null) return "";
  const who = seatName(room.seats[v.turn]);
  if (v.phase === "bidding") return `${who} is bidding`;
  if (v.phase === "nest") return `${who} takes the feeder`;
  if (v.phase === "trump") return `${who} picks trump`;
  if (v.phase === "partner") return `${who} calls a partner`;
  return `${who}'s turn`;
}

export function BirdwatchTable(props: { store: RoomStore; state: RoomState; sounds?: boolean; topInset?: number; cards?: boolean }) {
  const { store, state } = props;
  const sounds = props.sounds ?? true;
  const room = state.room!;
  const v = room.birdwatch as BirdView;
  const [rootRef, size] = useSize<HTMLDivElement>();
  const safe = useInsets();
  const insets = useMemo(() => ({ ...safe, top: safe.top + (props.topInset ?? 0) }), [safe, props.topInset]);
  const motion = useMemo(() => new Motion(reducedMotion), []);
  const els = useRef(new Map<string, HTMLElement>());

  const [revealed, setRevealed] = useState<{ seat: number; hand: number } | null>(null);
  const { mine, seat, showHand, curtainSeat, myTurn } = seatOnShow(room, revealed);
  // The seat the table is seen from: the hand on show, else the last one shown on this device.
  const perspective = seat ?? revealed?.seat ?? mine[0] ?? null;
  const step: BwStep = showHand ? stepFor(v, seat) : v.status === "over" ? "over" : v.phase === "between" ? "between" : "wait";
  const busy = state.pending !== null;
  const serverHand = showHand && seat !== null ? (v.hands[seat] ?? []) : [];
  const hand = sortHand(serverHand, v.trump, v.rules);
  const handKey = `${v.hand}:${seat}:${v.phase}`;

  const [lifted, setLifted] = useState<CardId | null>(null);
  const [chosen, setChosen] = useState<CardId[]>([]);
  const [held, setHeld] = useState<CardId | null>(null);
  const [focusIndex, setFocusIndex] = useState(0);
  const [sheet, setSheet] = useState(false);
  const [amount, setAmount] = useBidAmount(v.bidRange, `${v.hand}:${v.turn}:${v.high?.amount ?? 0}`);

  useEffect(() => {
    setLifted(null);
    setChosen([]);
  }, [handKey]);
  useEffect(() => {
    if (!state.pending) setHeld(null);
  }, [state.pending]);

  const playable = new Set(step === "play" ? (v.playable ?? []) : []);
  const fromNest = new Set(v.fromNest ?? []);

  const L = useMemo(
    () =>
      bwLayout({
        width: size.width || 360,
        height: size.height || 640,
        insets,
        me: perspective,
        others: othersInOrder(v, perspective),
        hand: hand.length,
        cards: props.cards,
      }),
    [size.width, size.height, insets, perspective, v.seats, hand.length, props.cards],
  );

  // Your move: a tick and a buzz.
  useEffect(
    () =>
      store.subscribe({
        event: ({ event: e }) => {
          if (e.kind === "birdwatch" && e.event.kind === "turn" && mine.includes(e.event.seat)) {
            if (sounds) play("tick", 0.6);
            buzz("turn");
          }
        },
      }),
    [store, mine.join(), sounds],
  );

  // A refused move: the card goes back, the hand shakes.
  useEffect(() => {
    if (!state.error) return;
    setHeld(null);
    play("nope");
    buzz("nope");
    wiggle(rootRef.current?.querySelector(".bw-hand-zone") as HTMLElement | null);
  }, [state.error?.n]);

  const nope = (el?: HTMLElement | null) => {
    play("nope", 0.6);
    buzz("nope");
    wiggle(el ?? null);
  };

  const act = (action: Parameters<RoomStore["act"]>[1]) => (seat === null ? false : store.act(seat, action));

  const playCard = (c: CardId) => {
    if (step !== "play" || busy || !playable.has(c)) return nope(els.current.get(`c${c}`));
    learnTip("bw.follow");
    setLifted(null);
    setHeld(c);
    act({ type: "play", card: c });
  };

  const toggleBack = (c: CardId) => {
    setChosen((list) => (list.includes(c) ? list.filter((x) => x !== c) : list.length >= v.nestSize ? list : [...list, c]));
    play("pop", 0.4);
    buzz("tap");
  };

  const tapCard = (c: CardId) => {
    if (step === "nest") return toggleBack(c);
    if (step !== "play") {
      play("tick", 0.3);
      return;
    }
    if (lifted === c) return playCard(c);
    if (!playable.has(c)) return nope(els.current.get(`c${c}`));
    play("tick", 0.4);
    buzz("tap");
    setLifted(c);
  };

  const bid = () => {
    if (step !== "bid" || busy) return nope(document.getElementById("bw-bid"));
    learnTip("bw.bid");
    act({ type: "bid", amount });
  };
  const pass = () => {
    if (step !== "bid" || busy) return nope(document.getElementById("bw-pass"));
    learnTip("bw.bid");
    act({ type: "pass" });
  };
  const nestDone = () => {
    if (step !== "nest" || busy || chosen.length !== v.nestSize) return nope(document.getElementById("bw-nest-done"));
    act({ type: "nest", discard: chosen });
  };
  const pickTrump = (suit: Suit) => {
    if (step !== "trump" || busy) return nope();
    learnTip("bw.trump");
    act({ type: "trump", suit });
  };
  const callPartner = (card: CardId) => {
    if (step !== "partner" || busy) return nope();
    act({ type: "partner", card });
  };

  // Poses: the hand, a lifted card up, the put-back cards up, the card sent on its way to the sill.
  const poses = new Map<string, Pose>();
  hand.forEach((c, i) => {
    const base = L.hand[i];
    if (!base) return;
    const mySlot = seat !== null ? L.slots.get(seat) : undefined;
    if (held === c && mySlot) poses.set(`c${c}`, { ...mySlot, z: 320 });
    else if (lifted === c || chosen.includes(c)) poses.set(`c${c}`, { ...base, y: base.y - L.ch * 0.2 });
    else poses.set(`c${c}`, base);
  });

  // Dragging a card onto the sill plays it.
  const sillHit = (p: Point) => (props.cards ? inside(p, { x: L.panel.x, y: 0, w: L.panel.w, h: L.handRect.y }, 0) : inside(p, L.sill, 16) || inside(p, L.window, 0));
  const live = useLatest({ playCard, tapCard, sillHit, poses });
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
      },
      onDrop: (p, pose) => {
        motion.place(`c${c}`, pose);
        if (live.current.sillHit(p)) live.current.playCard(c);
        // Wherever it ends up (the sill, or home to the hand), the next render animates it there
        // from where it was let go.
        const home = live.current.poses.get(`c${c}`);
        if (home) el.style.transform = transformOf(home);
        rerender((n) => n + 1);
      },
    });
  };
  const [, rerender] = useState(0);

  // Keys (§5.7): arrows pick a card, Enter plays it (or puts it back from the nest), 1 to 4 pick
  // trump, + raises the bid, Enter bids, P passes, Escape lets go.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.metaKey || e.ctrlKey || e.altKey) return;
      if (document.querySelector(".scrim")) return;
      const k = e.key.toLowerCase();
      const focusCard = (i: number) => {
        const c = hand[Math.min(Math.max(i, 0), hand.length - 1)];
        if (c === undefined) return;
        setFocusIndex(hand.indexOf(c));
        (els.current.get(`c${c}`)?.querySelector("button") as HTMLButtonElement | null)?.focus();
      };
      const onCard = e.target instanceof HTMLElement && e.target.closest(".bw-hand-card") !== null;
      if (k === "arrowright") focusCard(focusIndex + 1);
      else if (k === "arrowleft") focusCard(focusIndex - 1);
      else if (step === "trump" && ["1", "2", "3", "4"].includes(k)) pickTrump((["fish", "mouse", "feather", "bell"] as const)[Number(k) - 1]!);
      else if (step === "bid" && (k === "+" || k === "=")) setAmount(Math.min(amount + (v.bidRange?.step ?? 5), v.bidRange?.max ?? amount));
      else if (step === "bid" && k === "-") setAmount(Math.max(amount - (v.bidRange?.step ?? 5), v.bidRange?.min ?? amount));
      else if (step === "bid" && k === "p") pass();
      else if (step === "bid" && k === "enter" && !onCard && e.target === document.body) bid();
      else if (step === "nest" && k === "enter" && !onCard && e.target === document.body) nestDone();
      else if (k === "escape") setLifted(null);
      else return;
      learnTip("bw.keys");
      e.preventDefault();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const fineMouse = useMedia("(hover: hover) and (pointer: fine)");
  const secret = isSecretPartner(v, seat, showHand);
  const cue =
    step === "play"
      ? v.trick.length === 0
        ? "Your lead"
        : "Your turn"
      : step === "wait"
        ? waitWords(room, v)
        : "";

  const renderCard = (id: CardId, p: Pose, ref: (el: HTMLElement | null) => void) => {
    const dim = step === "play" && !playable.has(id);
    const up = lifted === id || chosen.includes(id);
    const words = `${cardLabel(id, v.rules)}${dim ? ", can't play" : ""}${chosen.includes(id) ? ", putting back" : ""}${fromNest.has(id) ? ", from the feeder" : ""}`;
    return (
      <div key={`c${id}`} ref={ref} class={`card mine bw-hand-card ${dim ? "dim" : ""} ${up ? "picked" : ""} ${fromNest.has(id) ? "glow" : ""}`} style={{ transform: transformOf(p), zIndex: p.z ?? 1 }} onPointerDown={onCardDown(id)}>
        <button
          type="button"
          class="card-inner"
          aria-label={words}
          aria-pressed={up}
          aria-disabled={dim}
          onClick={(e) => e.preventDefault()}
          onFocus={() => setFocusIndex(Math.max(0, hand.indexOf(id)))}
          onKeyDown={(e) => {
            if (e.key === "Enter" || e.key === " ") {
              e.preventDefault();
              e.stopPropagation();
              if (step === "play") playCard(id);
              else if (step === "nest") toggleBack(id);
              learnTip("bw.keys");
            }
          }}
        >
          <BirdFace id={id} rules={v.rules} />
        </button>
      </div>
    );
  };

  const panel = L.panel;
  const panelStyle = { transform: `translate3d(${panel.x}px, ${panel.y}px, 0)`, width: `${panel.w}px`, height: `${panel.h}px` };

  return (
    <div class={`bw-table ${L.landscape ? "landscape" : ""} ${props.cards ? "cards-view" : ""} ${myTurn ? "my-turn" : ""}`} ref={rootRef} style={bwStyle(L)}>
      <BwPublic store={store} room={room} layout={L} motion={motion} sounds={sounds} onStrip={() => setSheet(true)} hand={{ poses, els: els.current, render: renderCard }}>
        <div class="bw-hand-zone" id="bw-hand" style={{ transform: `translate3d(${L.handRect.x}px, ${L.handRect.y}px, 0)`, width: `${L.handRect.w}px`, height: `${L.handRect.h}px` }} />

        <div class="bw-panel" style={panelStyle}>
          {step === "bid" && v.bidRange ? (
            <BidPanel range={v.bidRange} amount={amount} setAmount={setAmount} onBid={bid} onPass={pass} busy={busy} />
          ) : step === "nest" ? (
            <NestBar need={v.nestSize} chosen={chosen.length} onDone={nestDone} busy={busy} />
          ) : step === "trump" ? (
            <TrumpPicker suggest={suggestTrump(serverHand, v.rules)} onPick={pickTrump} busy={busy} keys={fineMouse} />
          ) : cue ? (
            <p class={`cue bw-cue ${step === "play" ? "mine" : ""}`} aria-live="polite">
              {cue}
            </p>
          ) : null}
        </div>

        {secret ? (
          <span class="bw-partner-mark" id="bw-partner-mark" style={{ transform: `translate3d(${L.handRect.x + 4}px, ${L.handRect.y - 30}px, 0)` }}>
            Secret partner
          </span>
        ) : null}

        {step === "partner" && v.partnerChoices ? (
          <div class="bw-overlay" style={{ transform: `translate3d(${L.window.x}px, ${insets.top + 8}px, 0)`, width: `${props.cards ? L.panel.w : L.window.w}px`, height: `${Math.max(L.handRect.y - insets.top - 16, 200)}px` }}>
            <PartnerPicker choices={v.partnerChoices} trump={v.trump} rules={v.rules} onPick={callPartner} busy={busy} />
          </div>
        ) : null}

        {v.phase === "between" && v.status === "playing" ? <HandSummaryCard room={room} /> : null}

        {curtainSeat !== null ? <Curtain name={seatName(room.seats[curtainSeat])} cat={room.seats[curtainSeat]?.person?.cat ?? 0} onReveal={() => setRevealed({ seat: curtainSeat, hand: v.hand })} /> : null}

        {sheet ? <ScoreSheet room={room} onClose={() => setSheet(false)} /> : null}

        <Tip id="bw.bid" anchor="bw-bid-sign" text="Bid on the points your side will take." show={step === "bid" && !busy} place="above" />
        <Tip id="bw.trump" anchor="bw-trump" text="Trump beats every other suit." show={step === "play" && v.trump !== null && tipLearned("bw.bid") && !tipLearned("bw.follow")} />
        <Tip id="bw.follow" anchor="bw-hand" text="Follow the suit led. Dim cards can't play." show={step === "play" && playable.size < hand.length && tipLearned("bw.trump")} place="above" />
        <Tip id="bw.partner" anchor="bw-partner-mark" text="You hold the called card. Help the bidder." show={secret} place="above" />
        <Tip id="bw.keys" anchor="bw-hand" text="Keys: arrows pick, Enter plays." show={fineMouse && step === "play" && tipLearned("bw.follow") && !busy} place="above" />
      </BwPublic>
    </div>
  );
}
