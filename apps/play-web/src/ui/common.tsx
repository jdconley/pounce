import { useEffect, useLayoutEffect, useRef, useState } from "preact/hooks";


import { art, catArt, CAT_NAMES, type CatPose } from "../lib/art";
import { store } from "../lib/env";
import { buzz } from "../lib/haptics";
import { play } from "../lib/sound";

import type { ButtonHTMLAttributes, ComponentChildren, RefObject, TargetedMouseEvent } from "preact";

/** A cat, by index and pose. Decorative unless given a label. */
export function Cat(props: { cat: number; pose?: CatPose; size?: number | string; label?: string; class?: string }) {
  const size = typeof props.size === "number" ? `${props.size}px` : (props.size ?? "100%");
  return (
    <img
      class={`cat-img ${props.class ?? ""}`}
      src={catArt(props.cat, props.pose)}
      width={160}
      height={160}
      style={{ width: size, height: size }}
      alt={props.label ?? ""}
      aria-hidden={props.label ? undefined : "true"}
      decoding="async"
      draggable={false}
    />
  );
}

export const catName = (cat: number): string => CAT_NAMES[Math.min(Math.max(cat, 0), 7)] ?? "Cat";

export function Icon(props: { name: string; alt?: string; size?: number }) {
  return (
    <img
      src={art(props.name)}
      alt={props.alt ?? ""}
      aria-hidden={props.alt ? undefined : "true"}
      width={props.size ?? 32}
      height={props.size ?? 32}
      draggable={false}
      decoding="async"
    />
  );
}

/** A toy button: sound and a tap of vibration on press. */
export function Button(
  props: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: string; size?: "small" | "big"; wide?: boolean; quiet?: boolean },
) {
  const { variant, size, wide, quiet, class: klass, onClick, ...rest } = props;
  const classes = ["btn", variant, size, wide ? "wide" : "", klass ?? ""].filter(Boolean).join(" ");
  return (
    <button
      type="button"
      {...rest}
      class={classes}
      onClick={(e) => {
        if (!quiet) {
          play("pop", 0.5);
          buzz("tap");
        }
        (onClick as ((e: TargetedMouseEvent<HTMLButtonElement>) => void) | undefined)?.(e);
      }}
    />
  );
}

export function IconButton(props: { icon: string; label: string; onClick: () => void; plain?: boolean; id?: string; class?: string }) {
  return (
    <button
      type="button"
      id={props.id}
      class={`icon-btn ${props.plain ? "plain" : ""} ${props.class ?? ""}`}
      aria-label={props.label}
      title={props.label}
      onClick={() => {
        play("pop", 0.4);
        buzz("tap");
        props.onClick();
      }}
    >
      <Icon name={props.icon} />
    </button>
  );
}

/** A bottom sheet (a centred card on a wide screen). Escape or a tap outside closes it. */
export function Sheet(props: { title: string; onClose: () => void; children: ComponentChildren; labelledBy?: string }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const before = document.activeElement as HTMLElement | null;
    const first = ref.current?.querySelector<HTMLElement>("button, input, [tabindex]");
    first?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") props.onClose();
      if (e.key === "Tab" && ref.current) {
        // Keep focus inside the sheet.
        const items = [...ref.current.querySelectorAll<HTMLElement>("button:not(:disabled), input, a[href], [tabindex='0']")];
        if (items.length === 0) return;
        const [head, tail] = [items[0], items[items.length - 1]];
        if (e.shiftKey && document.activeElement === head) {
          e.preventDefault();
          tail.focus();
        } else if (!e.shiftKey && document.activeElement === tail) {
          e.preventDefault();
          head.focus();
        }
      }
    };
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("keydown", onKey);
      before?.focus?.();
    };
  }, []);
  return (
    <div
      class="scrim"
      onPointerDown={(e) => {
        if (e.target === e.currentTarget) props.onClose();
      }}
    >
      <div class="sheet" role="dialog" aria-modal="true" aria-label={props.title} ref={ref}>
        <h2 class="outlined">{props.title}</h2>
        {props.children}
      </div>
    </div>
  );
}

const LEARNED = "pounce.tips";

function learnedSet(): Set<string> {
  return new Set(store.json<string[]>(LEARNED) ?? []);
}

export const tipLearned = (id: string): boolean => learnedSet().has(id);

export function learnTip(id: string): void {
  const set = learnedSet();
  if (set.has(id)) return;
  set.add(id);
  store.set(LEARNED, JSON.stringify([...set]));
  for (const l of [...tipListeners]) l();
}

const tipListeners = new Set<() => void>();

/** Re-renders when a tip is learned anywhere. */
export function useTipsVersion(): number {
  const [n, setN] = useState(0);
  useEffect(() => {
    const l = () => setN((x) => x + 1);
    tipListeners.add(l);
    return () => void tipListeners.delete(l);
  }, []);
  return n;
}

/**
 * One short tip pointing at the thing it is about (`CoachMark.swift`): shown while `show` is
 * true and it hasn't been learned, dismissed by its X (or by using the thing: the caller calls
 * `learnTip`), and never shown again.
 */
export function Tip(props: { id: string; anchor: string; text: string; show: boolean; place?: "above" | "below" }) {
  useTipsVersion();
  const ref = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ left: number; top: number; arrow: number; place: "above" | "below" } | null>(null);
  const visible = props.show && !tipLearned(props.id);
  useLayoutEffect(() => {
    if (!visible) return;
    const place = () => {
      const target = document.getElementById(props.anchor);
      const tip = ref.current;
      if (!target || !tip) return;
      const t = target.getBoundingClientRect();
      const w = tip.offsetWidth;
      const h = tip.offsetHeight;
      const vw = window.innerWidth;
      const below = props.place ? props.place === "below" : t.top - h - 16 < 8;
      const left = Math.min(Math.max(t.left + t.width / 2 - w / 2, 12), vw - w - 12);
      const top = below ? t.bottom + 14 : t.top - h - 14;
      setPos({ left, top, arrow: Math.min(Math.max(t.left + t.width / 2 - left, 22), w - 22), place: below ? "below" : "above" });
    };
    place();
    const ro = new ResizeObserver(place);
    ro.observe(document.body);
    window.addEventListener("resize", place);
    const id = window.setInterval(place, 600);
    return () => {
      ro.disconnect();
      window.removeEventListener("resize", place);
      window.clearInterval(id);
    };
  }, [visible, props.anchor]);
  if (!visible) return null;
  return (
    <div
      ref={ref}
      class={`tip ${pos?.place ?? "above"}`}
      role="status"
      style={{
        position: "fixed",
        left: `${pos?.left ?? -9999}px`,
        top: `${pos?.top ?? -9999}px`,
        ["--arrow-x" as string]: `${pos?.arrow ?? 0}px`,
      }}
    >
      <span>{props.text}</span>
      <button type="button" aria-label="Dismiss tip" onClick={() => learnTip(props.id)}>
        <CloseMark />
      </button>
    </div>
  );
}

/** An X, drawn: never a text glyph a platform might show as an emoji. */
export function CloseMark(props: { size?: number }) {
  const n = props.size ?? 14;
  return (
    <svg width={n} height={n} viewBox="0 0 14 14" aria-hidden="true">
      <path d="M2 2 12 12M12 2 2 12" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" fill="none" />
    </svg>
  );
}

/** Re-renders on a media query change. */
export function useMedia(query: string): boolean {
  const [match, setMatch] = useState(() => typeof matchMedia === "function" && matchMedia(query).matches);
  useEffect(() => {
    const mq = matchMedia(query);
    const on = () => setMatch(mq.matches);
    mq.addEventListener("change", on);
    return () => mq.removeEventListener("change", on);
  }, [query]);
  return match;
}

/** The element's size, read once per resize (one layout read, never per frame). */
export function useSize<T extends HTMLElement>(): [RefObject<T | null>, { width: number; height: number }] {
  const ref = useRef<T>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const read = () => {
      const r = el.getBoundingClientRect();
      setSize((s) => (Math.abs(s.width - r.width) < 0.5 && Math.abs(s.height - r.height) < 0.5 ? s : { width: r.width, height: r.height }));
    };
    read();
    const ro = new ResizeObserver(read);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  return [ref, size];
}
