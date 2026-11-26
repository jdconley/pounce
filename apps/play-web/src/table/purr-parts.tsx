/**
 * Pieces every Purrtrait screen shares: the turn's countdown, and the picture the room's ink
 * draws (the TV's, and a drawer's second look after a reload).
 */
import { useEffect, useRef, useState } from "preact/hooks";

import { replayInk } from "../workers/purr-ink";

import { Picture, type InkOp } from "./purr-ink";
import { leftNow, type InkMessage, type PurrView } from "./purr-model";

import type { Easel, EaselSource } from "./purr-easel";
import type { RoomStore } from "../store/room";

/** Ms left on the turn's clock, ticking once a second on the frame clock (no timers on this thread). */
export function useLeft(v: PurrView | undefined): number | null {
  const key = v ? `${v.turn}|${v.phase}|${v.remainingMs}|${v.paused}` : "";
  const anchor = useRef({ key: "", at: 0 });
  if (anchor.current.key !== key) anchor.current = { key, at: performance.now() };
  const read = () => (v ? leftNow(v.remainingMs, v.paused, anchor.current.at, performance.now()) : null);
  const [, setSecond] = useState(0);
  useEffect(() => {
    if (!v || v.remainingMs === null || v.paused) return;
    let frame = 0;
    let shown = -1;
    const tick = () => {
      const left = read() ?? 0;
      const s = Math.ceil(left / 1000);
      if (s !== shown) {
        shown = s;
        setSecond(s);
      }
      if (left > 0) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [key]);
  return read();
}

/**
 * The drawing the room's ink makes, for a screen that only watches it (the TV): live `ink` as it
 * comes, a whole `inkSync` replayed in the worker, and a blank easel when the turn changes. Every
 * change asks the easel for a frame.
 */
export class InkPicture {
  readonly picture = new Picture();
  turn: string | null = null;
  easel: Easel | null = null;
  /** Ink that came while a sync was replayed: applied after it, in order. */
  private behind: InkMessage[] | null = null;
  private syncs = 0;

  /** The easel's view: every stroke but the newest is finished (a stroke ends when the next starts). */
  source = (): EaselSource => {
    const s = this.picture.strokes;
    return { finished: s.length > 1 ? s.slice(0, -1) : [], live: s.at(-1) ?? null };
  };

  /** Everything finished: the turn is over, nothing more comes for it. */
  done = (): EaselSource => ({ finished: this.picture.strokes, live: null });

  /** The turn on show. A new one blanks the easel. */
  setTurn(turn: string): void {
    if (turn === this.turn) return;
    this.turn = turn;
    this.behind = null;
    this.syncs += 1;
    this.picture.applyAll([["c"]]);
    this.easel?.invalidate();
  }

  take(m: InkMessage): void {
    if (m.t === "inkResend") return;
    if (m.t === "inkSync") {
      this.setTurn(m.turn);
      const sync = ++this.syncs;
      this.behind = [];
      void replayInk(m.ops).then(({ strokes, lastId }) => {
        if (sync !== this.syncs) return;
        this.picture.adopt(strokes, lastId);
        const behind = this.behind ?? [];
        this.behind = null;
        for (const b of behind) this.take(b);
        this.easel?.invalidate();
      });
      return;
    }
    if (m.turn !== this.turn) this.setTurn(m.turn);
    if (this.behind) {
      this.behind.push(m);
      return;
    }
    this.picture.applyAll(m.ops as InkOp[]);
    this.easel?.invalidate();
  }
}

/** The room's ink drawn on a watching screen's easel. */
export function useInkPicture(store: RoomStore, turn: string | null): InkPicture {
  const ink = useState(() => new InkPicture())[0];
  useEffect(() => store.subscribe({ ink: (m) => ink.take(m) }), [store]);
  useEffect(() => {
    if (turn !== null) ink.setTurn(turn);
  }, [turn]);
  return ink;
}
