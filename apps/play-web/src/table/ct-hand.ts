/**
 * A Cat Tower hand on this device, wherever it is drawn (the phone's full table, cattower.tsx, or
 * its controller, ct-controller.tsx): whose hand is on show, its order and trays, and the moves it
 * makes. One copy, so both views play by the same rules.
 */
import { card, type CardId } from "@pounce/play-api/rules/cards";
import { type HitSide } from "@pounce/play-api/rules/groups";
import { PHASES } from "@pounce/play-api/rules/phases";
import { useEffect, useRef, useState } from "preact/hooks";

import { buzz } from "../lib/haptics";
import { play } from "../lib/sound";
import { mySeats } from "../store/lobby";
import { learnTip } from "../ui/common";

import { discardNeedsTarget, hitTargets, layDownGroups, skipTargets } from "./ct-moves";

import type { Motion, Pose } from "./motion";
import type { RoomState, RoomStore } from "../store/room";
import type { RoomView } from "@pounce/play-api/protocol";
import type { Action } from "@pounce/play-api/rules/engine";

/**
 * Whose hand is on show: the only seat on this device, or on a shared device the seat whose turn
 * it is, once its holder has taken the device (PassAndPlay.swift).
 */
export function useCtSeat(room: RoomView) {
  const g = room.game!;
  const mine = mySeats(room).filter((s) => !g.forfeited[s]);
  const turnKey = `${g.round}:${g.turn}`;
  const [revealed, setRevealed] = useState<{ seat: number; key: string } | null>(null);
  const shared = mine.length > 1;
  const acting = !shared ? (mine[0] ?? null) : mine.includes(g.turn) && g.status === "playing" ? g.turn : null;
  const showHand = acting !== null && (!shared || (revealed?.seat === acting && revealed.key === turnKey));
  return {
    mine,
    /** The seat whose hand this is, or null (a spectator, or a shared device between turns). */
    seat: acting,
    showHand,
    /** On a shared device, the seat to pass to: the curtain is up. */
    curtainSeat: shared && acting !== null && !showHand ? acting : null,
    myTurn: acting !== null && g.turn === acting && g.status === "playing",
    reveal: (seat: number) => setRevealed({ seat, key: turnKey }),
  };
}

/** The hand's order and the trays: this device's own, kept while the server's hand changes. */
export function useCtHand(room: RoomView, seat: number | null, showHand: boolean) {
  const g = room.game!;
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

  /** Moves `c` to place `index` of the hand (the caller takes it out of its tray first). */
  const reorder = (c: CardId, index: number) => {
    const without = ordered.filter((x) => x !== c);
    const before = ordered.indexOf(c);
    const at = index > before && before >= 0 ? index - 1 : index;
    without.splice(Math.min(at, without.length), 0, c);
    setOrder(without);
  };

  return { ordered, trayCards, setTrays, inTrays, reqs, phaseIndex, laidMine, showTrays, reorder };
}

/**
 * The hand's moves. Each refuses (a buzz and a "nope") what can't be done now, learns its tip, and
 * ends in `store.act`. `quiet` leaves out the discard's thud: a phone whose table is on the TV
 * makes no game sounds of its own, only taps.
 */
export function ctMoves(o: {
  store: RoomStore;
  state: RoomState;
  room: RoomView;
  seat: number | null;
  myTurn: boolean;
  hand: ReturnType<typeof useCtHand>;
  motion: Motion;
  /** Where a discarded card waits for the server: the discard pile's pose. */
  discardPose: Pose | null;
  setHeld: (held: Map<CardId, Pose>) => void;
  setSelected: (c: CardId | null) => void;
  setSkipPick: (c: CardId | null) => void;
  /** A discard that waits on "Lay down first?": the level is staged in the trays (null closes it). */
  setLayFirst: (d: { card: CardId; skipTarget?: number } | null) => void;
  quiet?: boolean;
}) {
  const { store, state, room, seat, myTurn, hand } = o;
  const g = room.game!;
  const { trayCards, reqs, showTrays, phaseIndex, laidMine } = hand;

  function nope() {
    play("nope", 0.6);
    buzz("nope");
    return undefined;
  }
  const act = (action: Action) => (seat === null ? false : store.act(seat, action));
  const skipCandidates = seat === null ? [] : skipTargets(g, seat, room.seats);

  const draw = (from: "deck" | "discard") => {
    if (!myTurn || g.step !== "draw" || state.pending) return nope();
    if (from === "discard" && (g.discardTop === null || card(g.discardTop).kind === "cucumber")) return nope();
    learnTip("ct.draw");
    buzz("pick");
    act({ type: "draw", from });
  };

  const groups = showTrays && trayCards.length === reqs.length ? layDownGroups(trayCards, phaseIndex) : null;

  /**
   * Discards `c` (a Cucumber asks whom it skips). With the level made in the trays it asks first,
   * "Lay down first?", as discarding ends the turn without it; `anyway` is the answer "Discard
   * anyway". Trays that don't make the level yet don't ask: they keep their cards for next turn.
   */
  const discard = (c: CardId, skipTarget?: number, anyway = false) => {
    if (!myTurn || g.step !== "play" || state.pending) return nope();
    if (!anyway && groups !== null) {
      o.setLayFirst(skipTarget === undefined ? { card: c } : { card: c, skipTarget });
      return;
    }
    if (discardNeedsTarget(c) && skipTarget === undefined && skipCandidates.length > 0) {
      if (skipCandidates.length === 1) skipTarget = skipCandidates[0];
      else {
        o.setSkipPick(c);
        return;
      }
    }
    learnTip("ct.discard");
    if (o.discardPose) o.setHeld(new Map([[c, o.discardPose]]));
    o.setSelected(null);
    if (!o.quiet) play("thud", 0.5);
    act(skipTarget === undefined ? { type: "discard", card: c } : { type: "discard", card: c, skipTarget });
  };

  const toTray = (c: CardId, i: number) => {
    if (!showTrays || i >= reqs.length) return nope();
    learnTip("ct.trays");
    hand.setTrays(() => {
      const next = reqs.map((_, k) => (trayCards[k] ?? []).filter((x) => x !== c));
      if ((next[i]?.length ?? 0) >= (reqs[i]?.size ?? 0)) return trayCards;
      next[i] = [...(next[i] ?? []), c];
      return next;
    });
    o.setSelected(null);
    play("pop", 0.5);
  };

  const outOfTray = (c: CardId) => {
    hand.setTrays(trayCards.map((t) => t.filter((x) => x !== c)));
    play("pop", 0.4);
  };

  const layDown = () => {
    if (!myTurn || g.step !== "play" || groups === null || state.pending) return nope();
    learnTip("ct.lay");
    o.setLayFirst(null);
    const holdAt = new Map<CardId, Pose>();
    for (const c of trayCards.flat()) {
      const p = o.motion.last(`c${c}`);
      if (p) holdAt.set(c, p);
    }
    o.setHeld(holdAt);
    act({ type: "layDown", groups });
  };

  /** Whether `c` can be hit on seat `s`'s group `gi`: on that end, or on either for a run. */
  const hitOk = (c: CardId, s: number, gi: number, side?: HitSide) =>
    laidMine && hitTargets(c, g.laid).some((t) => t.seat === s && t.group === gi && (side === undefined || t.side === undefined || t.side === side));
  const hit = (c: CardId, s: number, gi: number, side?: HitSide) => {
    if (!myTurn || g.step !== "play" || state.pending || !hitOk(c, s, gi, side)) return nope();
    learnTip("ct.hit");
    o.setSelected(null);
    act(side ? { type: "hit", card: c, target: { seat: s, group: gi }, side } : { type: "hit", card: c, target: { seat: s, group: gi } });
  };

  return { nope, draw, discard, toTray, outOfTray, groups, layDown, hitOk, hit, skipCandidates };
}
