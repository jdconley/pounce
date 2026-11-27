/**
 * Toy Tumble's touch and keys (spec §5.3, §5.4), applied the moment the event arrives:
 * - touch: drag sideways anywhere on your box (a column per cell-width), tap to turn, drag down
 *   to soft-drop while held, flick down to drop;
 * - keys: arrows move (repeating after 150 ms, then every 33 ms), Down soft-drops, Up or X turns
 *   clockwise and Z the other way, Space drops, 1 to 6 use the first trick held on that player;
 * - tricks: tap one to lift it, then tap a box; or drag it onto a box.
 * While playing, arrows and Space never scroll the page or press a focused button.
 */
import type { Trick } from "@pounce/play-api/tumble/box";

export type PlayHandlers = {
  move(dx: -1 | 1): void;
  turn(dir: 1 | -1): void;
  soft(on: boolean): void;
  drop(): void;
};

export const REPEAT_AFTER_MS = 150;
export const REPEAT_EVERY_MS = 33;
/** A tap: shorter than this, and moving less than `TAP_PX`. */
const TAP_MS = 300;
const TAP_PX = 10;
/** A flick: a downward release faster than this (px per ms) over at least `FLICK_PX`. */
export const FLICK_SPEED = 0.8;
const FLICK_PX = 24;
/** The window the release speed is measured over. */
const SPEED_WINDOW_MS = 80;

type Timer = (fn: () => void, ms: number) => unknown;
type ClearTimer = (id: unknown) => void;

/** Drag, tap, soft drop and flick on `el` (the play area: `touch-action: none`). Returns a detach. */
export function attachTouch(el: HTMLElement, h: PlayHandlers, o: { cell: () => number; active: () => boolean }): () => void {
  let id: number | null = null;
  let x0 = 0;
  let y0 = 0;
  let t0 = 0;
  let lastX = 0;
  let moved = false;
  let softOn = false;
  let samples: { t: number; y: number }[] = [];

  const down = (e: PointerEvent) => {
    if (id !== null || !e.isPrimary || !o.active()) return;
    id = e.pointerId;
    x0 = lastX = e.clientX;
    y0 = e.clientY;
    t0 = e.timeStamp;
    moved = false;
    softOn = false;
    samples = [{ t: e.timeStamp, y: e.clientY }];
    el.setPointerCapture?.(e.pointerId);
    e.preventDefault();
  };
  const move = (e: PointerEvent) => {
    if (e.pointerId !== id) return;
    const cell = Math.max(1, o.cell());
    let dx = e.clientX - lastX;
    while (Math.abs(dx) >= cell) {
      const dir = dx > 0 ? 1 : -1;
      h.move(dir);
      lastX += dir * cell;
      dx -= dir * cell;
      moved = true;
    }
    const dy = e.clientY - y0;
    samples.push({ t: e.timeStamp, y: e.clientY });
    samples = samples.filter((s) => e.timeStamp - s.t <= SPEED_WINDOW_MS);
    if (!softOn && dy > cell && dy > Math.abs(e.clientX - x0)) {
      softOn = true;
      moved = true;
      h.soft(true);
    }
    if (Math.abs(e.clientX - x0) > TAP_PX || Math.abs(dy) > TAP_PX) moved = true;
  };
  const up = (e: PointerEvent) => {
    if (e.pointerId !== id) return;
    id = null;
    const dy = e.clientY - y0;
    samples.push({ t: e.timeStamp, y: e.clientY });
    const first = samples.find((s) => e.timeStamp - s.t <= SPEED_WINDOW_MS) ?? samples[0]!;
    const speed = (e.clientY - first.y) / Math.max(1, e.timeStamp - first.t);
    if (softOn) h.soft(false);
    if (!moved && e.timeStamp - t0 < TAP_MS) h.turn(1);
    else if (dy >= FLICK_PX && speed >= FLICK_SPEED) h.drop();
  };
  const cancel = (e: PointerEvent) => {
    if (e.pointerId !== id) return;
    id = null;
    if (softOn) h.soft(false);
  };
  el.addEventListener("pointerdown", down);
  el.addEventListener("pointermove", move);
  el.addEventListener("pointerup", up);
  el.addEventListener("pointercancel", cancel);
  return () => {
    el.removeEventListener("pointerdown", down);
    el.removeEventListener("pointermove", move);
    el.removeEventListener("pointerup", up);
    el.removeEventListener("pointercancel", cancel);
  };
}

export type KeyHandlers = PlayHandlers & {
  /** 1 to 6: the first trick held, on the player with that number (seat + 1). */
  useOn(seat: number): void;
};

/** The keys, on `target` (the window). `active`: a round is on and this box plays. */
export function attachKeys(target: EventTarget, h: KeyHandlers, o: { active: () => boolean; setTimer?: Timer; clearTimer?: ClearTimer }): () => void {
  const setTimer: Timer = o.setTimer ?? ((fn, ms) => setTimeout(fn, ms));
  const clearTimer: ClearTimer = o.clearTimer ?? ((t) => clearTimeout(t as ReturnType<typeof setTimeout>));
  let held: { key: string; dir: -1 | 1; timer: unknown } | null = null;
  let softKey = false;

  const stopRepeat = () => {
    if (held) clearTimer(held.timer);
    held = null;
  };
  const repeat = (key: string, dir: -1 | 1, ms: number) => {
    const timer = setTimer(() => {
      if (held?.key !== key) return;
      if (!o.active()) return stopRepeat();
      h.move(dir);
      repeat(key, dir, REPEAT_EVERY_MS);
    }, ms);
    held = { key, dir, timer };
  };

  const down = (ev: Event) => {
    const e = ev as KeyboardEvent;
    if (!o.active() || e.metaKey || e.ctrlKey || e.altKey) return;
    const k = e.key;
    if (k === "ArrowLeft" || k === "ArrowRight" || k === "ArrowUp" || k === "ArrowDown" || k === " " || e.code === "Space") e.preventDefault();
    if (e.repeat) return;
    if (k === "ArrowLeft" || k === "ArrowRight") {
      const dir = k === "ArrowLeft" ? -1 : 1;
      stopRepeat();
      h.move(dir);
      repeat(k, dir, REPEAT_AFTER_MS);
    } else if (k === "ArrowDown") {
      softKey = true;
      h.soft(true);
    } else if (k === "ArrowUp" || k === "x" || k === "X") h.turn(1);
    else if (k === "z" || k === "Z") h.turn(-1);
    else if (k === " " || e.code === "Space") h.drop();
    else if (/^[1-6]$/.test(k)) {
      e.preventDefault();
      h.useOn(Number(k) - 1);
    }
  };
  const up = (ev: Event) => {
    const e = ev as KeyboardEvent;
    // A Space let go would press a focused button.
    if (o.active() && (e.key === " " || e.code === "Space")) e.preventDefault();
    if (held && e.key === held.key) stopRepeat();
    if (e.key === "ArrowDown" && softKey) {
      softKey = false;
      h.soft(false);
    }
  };
  const blur = () => {
    stopRepeat();
    if (softKey) h.soft(false);
    softKey = false;
  };
  target.addEventListener("keydown", down);
  target.addEventListener("keyup", up);
  target.addEventListener("blur", blur);
  return () => {
    stopRepeat();
    target.removeEventListener("keydown", down);
    target.removeEventListener("keyup", up);
    target.removeEventListener("blur", blur);
  };
}

/** Which boxes a trick glows on by default: the opponents, or your own (spec §4.6). */
export const SELF_TRICKS: ReadonlySet<Trick> = new Set(["scoop", "settle", "nap", "bath"]);
export const aimsAtSelf = (t: Trick): boolean => SELF_TRICKS.has(t);

/**
 * Picking a trick's target: tap a trick to lift it (again to put it down), then tap a box; or
 * press on a trick and let go over a box. `targetAt` says which seat's box is under a point.
 */
export class TrickPicker {
  lifted: number | null = null;
  /** A trick being dragged: its slot and where the finger is. */
  drag: { slot: number; x: number; y: number } | null = null;
  private press: { slot: number; x: number; y: number; id: number } | null = null;

  constructor(
    private readonly o: { use: (slot: number, seat: number) => void; targetAt: (x: number, y: number) => number | null; changed?: () => void },
  ) {}

  /** A tap on the trick in `slot`. */
  tapTrick(slot: number): void {
    this.lifted = this.lifted === slot ? null : slot;
    this.o.changed?.();
  }

  /** A tap on `seat`'s box. True when it used the lifted trick. */
  tapBox(seat: number): boolean {
    if (this.lifted === null) return false;
    const slot = this.lifted;
    this.lifted = null;
    this.o.use(slot, seat);
    this.o.changed?.();
    return true;
  }

  cancel(): void {
    this.lifted = null;
    this.drag = null;
    this.press = null;
    this.o.changed?.();
  }

  /** Pointer events from a trick's slot (the slot's element listens; moves and ups are captured). */
  pointerDown(slot: number, e: PointerEvent): void {
    this.press = { slot, x: e.clientX, y: e.clientY, id: e.pointerId };
    (e.currentTarget as Element | null)?.setPointerCapture?.(e.pointerId);
  }

  pointerMove(e: PointerEvent): void {
    const p = this.press;
    if (!p || e.pointerId !== p.id) return;
    if (!this.drag && Math.hypot(e.clientX - p.x, e.clientY - p.y) < 12) return;
    this.drag = { slot: p.slot, x: e.clientX, y: e.clientY };
    this.o.changed?.();
  }

  pointerUp(e: PointerEvent): void {
    const p = this.press;
    if (!p || e.pointerId !== p.id) return;
    this.press = null;
    if (!this.drag) {
      this.tapTrick(p.slot);
      return;
    }
    this.drag = null;
    const seat = this.o.targetAt(e.clientX, e.clientY);
    if (seat !== null) {
      this.lifted = null;
      this.o.use(p.slot, seat);
    }
    this.o.changed?.();
  }
}
