/**
 * How things move on the table. Every card and piece has a pose (where it sits, turned and
 * scaled) computed by the table's layout, written as one `transform`. When a pose changes, the
 * element animates from where it was to where it is with the Web Animations API, on transform
 * alone: compositor-only, no layout or paint per frame, so it holds 60 fps on a mid-range phone
 * and 120 Hz where the screen has it. Nothing is measured per frame; the old pose is known.
 */
export type Pose = { x: number; y: number; r?: number; s?: number; z?: number };

export const transformOf = (p: Pose): string =>
  `translate3d(${p.x.toFixed(1)}px, ${p.y.toFixed(1)}px, 0) rotate(${(p.r ?? 0).toFixed(2)}deg) scale(${(p.s ?? 1).toFixed(3)})`;

const same = (a: Pose, b: Pose): boolean =>
  Math.abs(a.x - b.x) < 0.5 && Math.abs(a.y - b.y) < 0.5 && Math.abs((a.r ?? 0) - (b.r ?? 0)) < 0.2 && Math.abs((a.s ?? 1) - (b.s ?? 1)) < 0.005;

export type MoveStyle = { duration: number; easing: string; delay?: number };

export const MOVE: MoveStyle = { duration: 340, easing: "cubic-bezier(0.2, 0.9, 0.25, 1.08)" };

/**
 * Tracks each keyed element's last pose and animates the change. `spawn` gives where a key that
 * wasn't on the table comes from (the deck, a player's cat). Without one it is simply there, at
 * its pose's size, whole. Cards never show smaller first or see-through: a hand card that starts
 * small and grows reads as a glitch, and a faded card is hard to read (and shows the next one
 * through it). With reduced motion a card just goes to its new place.
 */
export class Motion {
  private poses = new Map<string, Pose>();
  /** Each arriving element's flight: a card dealt or drawn is grabbed only once it has landed. */
  private flights = new WeakMap<HTMLElement, Animation>();
  private spawns = new Map<string, Pose>();
  constructor(private reduced: () => boolean) {}

  /** The next time `key` appears, it comes from `from`. */
  spawnFrom(key: string, from: Pose): void {
    this.spawns.set(key, from);
  }

  /** Where `key` was last put. */
  last(key: string): Pose | undefined {
    return this.poses.get(key);
  }

  /** The element is somewhere new without an animation (a drag moved it): remember it there. */
  place(key: string, pose: Pose): void {
    this.poses.set(key, pose);
  }

  forget(key: string): void {
    this.poses.delete(key);
  }

  /**
   * After a render: animate each element whose pose changed. `els` maps key to element; its
   * style already holds the new transform. Returns how many moved.
   */
  apply(els: Map<string, HTMLElement>, poses: Map<string, Pose>, style: (key: string) => MoveStyle = () => MOVE): number {
    let moved = 0;
    const reduced = this.reduced();
    for (const [key, to] of poses) {
      const el = els.get(key);
      if (!el) continue;
      const known = this.poses.get(key);
      const from = known ?? this.spawns.get(key);
      // Coming onto the table from somewhere (a drawn card from the deck), not shifting within it.
      const arriving = !known && from !== undefined;
      this.spawns.delete(key);
      this.poses.set(key, to);
      if (!from) continue;
      if (same(from, to)) continue;
      moved++;
      // Mid-flight: start from where it is now, not where it was headed.
      let start = transformOf(from);
      const running = el.getAnimations();
      if (running.length > 0) {
        start = getComputedStyle(el).transform || start;
        for (const a of running) a.cancel();
      }
      if (reduced) continue;
      const s = style(key);
      const flight = el.animate([{ transform: start }, { transform: transformOf(to) }], { duration: s.duration, easing: s.easing, delay: s.delay ?? 0, fill: "backwards" });
      if (arriving) this.land(el, flight);
    }
    // Keys gone from the table are forgotten, so they spawn afresh if they come back.
    for (const key of [...this.poses.keys()]) if (!poses.has(key)) this.poses.delete(key);
    return moved;
  }

  /**
   * While an arriving `el` flies in it takes no taps: they reach what's under it (a drawn card
   * crossing the Discard button mustn't eat the tap on it). Cards shifting within the hand stay
   * grabbable. Taps come back when this flight, not a later one, ends.
   */
  private land(el: HTMLElement, flight: Animation): void {
    this.flights.set(el, flight);
    el.style.pointerEvents = "none";
    const landed = () => {
      if (this.flights.get(el) !== flight) return;
      this.flights.delete(el);
      el.style.pointerEvents = "";
    };
    flight.finished.then(landed, landed);
  }
}

/** A short hop for something refused: shake on the spot. */
export function wiggle(el: HTMLElement | null | undefined): void {
  if (!el) return;
  el.animate(
    [{ translate: "0 0" }, { translate: "-8px 0" }, { translate: "7px 0" }, { translate: "-4px 0" }, { translate: "0 0" }],
    { duration: 320, easing: "ease-in-out", composite: "add" },
  );
}

/** A pop on the spot (a card landing, a set completing). */
export function bump(el: HTMLElement | null | undefined, amount = 1.12): void {
  if (!el) return;
  el.animate([{ scale: "1" }, { scale: String(amount) }, { scale: "1" }], { duration: 260, easing: "cubic-bezier(0.34, 1.56, 0.64, 1)" });
}
