/**
 * A TV is driven by a remote: arrow keys move focus to the nearest thing in that direction,
 * Enter presses it. Everything a remote can reach is marked `data-tv`; the one to land on when
 * nothing else has focus is marked `data-tv-default`.
 */
import { useEffect } from "preact/hooks";

import type { RefObject } from "preact";

export type Rect = { left: number; top: number; width: number; height: number };
export type Direction = "up" | "down" | "left" | "right";

const ARROWS: Record<string, Direction> = { ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right" };

/**
 * The candidate nearest `from` in `dir`. Only what lies wholly past `from`'s edge in that
 * direction counts. Distance is centre to centre along the direction, plus twice the off-axis
 * distance, so a thing straight ahead beats a nearer one off to the side. A tie goes to the
 * first candidate. Null when nothing lies that way.
 */
export function nearest(from: Rect, candidates: { id: string; rect: Rect }[], dir: Direction): string | null {
  const cx = from.left + from.width / 2;
  const cy = from.top + from.height / 2;
  let best: string | null = null;
  let bestScore = Infinity;
  for (const { id, rect } of candidates) {
    const past =
      dir === "up"
        ? rect.top + rect.height <= from.top
        : dir === "down"
          ? rect.top >= from.top + from.height
          : dir === "left"
            ? rect.left + rect.width <= from.left
            : rect.left >= from.left + from.width;
    if (!past) continue;
    const dx = Math.abs(rect.left + rect.width / 2 - cx);
    const dy = Math.abs(rect.top + rect.height / 2 - cy);
    const score = dir === "up" || dir === "down" ? dy + 2 * dx : dx + 2 * dy;
    if (score < bestScore) {
      bestScore = score;
      best = id;
    }
  }
  return best;
}

/** A remote's Back: Escape and Backspace on a keyboard, and the codes TV browsers send. */
export function isBack(e: KeyboardEvent): boolean {
  return e.key === "Escape" || e.key === "Backspace" || e.key === "GoBack" || e.key === "BrowserBack" || e.keyCode === 461 || e.keyCode === 10009;
}

function reachable(root: HTMLElement): HTMLElement[] {
  return [...root.querySelectorAll<HTMLElement>("[data-tv]")].filter((el) => !(el as HTMLButtonElement).disabled && el.getClientRects().length > 0);
}

function focusDefault(root: HTMLElement): void {
  const all = reachable(root);
  const target = all.find((el) => el.hasAttribute("data-tv-default")) ?? all[0];
  target?.focus({ preventScroll: true });
}

/**
 * Whether focus is somewhere a remote can act on: a `[data-tv]` element in `root`. One that has
 * left the remote's reach (a table's button under an open menu) doesn't count.
 */
const held = (root: HTMLElement): boolean => {
  const active = document.activeElement;
  return active instanceof HTMLElement && root.contains(active) && active.hasAttribute("data-tv") && !(active as HTMLButtonElement).disabled;
};

/**
 * Arrow keys move focus among `root`'s `[data-tv]` elements; focus is never left on nothing (a
 * removed or disabled button hands it to the `[data-tv-default]` one). The pointer works too:
 * hovering a button focuses it, as a TV remote's pointer does.
 */
export function useDpad(root: RefObject<HTMLElement | null>): void {
  useEffect(() => {
    const el = root.current;
    if (!el) return;
    let frame = 0;
    // Checked a frame later, once whatever took focus away has finished rendering.
    const keep = () => {
      if (frame) return;
      frame = requestAnimationFrame(() => {
        frame = 0;
        if (!held(el)) focusDefault(el);
      });
    };
    const onKey = (e: KeyboardEvent) => {
      const dir = ARROWS[e.key];
      if (!dir || e.defaultPrevented) return;
      e.preventDefault();
      const all = reachable(el);
      const active = document.activeElement as HTMLElement | null;
      if (!active || !all.includes(active)) {
        focusDefault(el);
        return;
      }
      const candidates = all.filter((c) => c !== active).map((c, n) => ({ id: String(n), rect: c.getBoundingClientRect(), el: c }));
      const id = nearest(active.getBoundingClientRect(), candidates, dir);
      if (id !== null) candidates[Number(id)]!.el.focus({ preventScroll: true });
    };
    const onPointer = (e: PointerEvent) => {
      if (e.pointerType !== "mouse") return;
      const target = (e.target as Element | null)?.closest<HTMLElement>("[data-tv]");
      if (target && el.contains(target) && target !== document.activeElement && !(target as HTMLButtonElement).disabled) target.focus({ preventScroll: true });
    };
    const watcher = new MutationObserver(keep);
    watcher.observe(el, { childList: true, subtree: true, attributes: true, attributeFilter: ["disabled", "data-tv"] });
    window.addEventListener("keydown", onKey);
    el.addEventListener("focusout", keep);
    el.addEventListener("pointerover", onPointer);
    keep();
    return () => {
      if (frame) cancelAnimationFrame(frame);
      watcher.disconnect();
      window.removeEventListener("keydown", onKey);
      el.removeEventListener("focusout", keep);
      el.removeEventListener("pointerover", onPointer);
    };
  }, [root]);
}
