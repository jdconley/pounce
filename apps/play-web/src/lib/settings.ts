/**
 * The player's settings on this device: sound and vibration, remembered. A TV page keeps its own
 * (`keepTvSettings`): a phone and a TV page in one browser are two devices, so turning the TV's
 * sound off leaves the phone's on.
 */
import { store } from "./env";

export type Settings = { sound: boolean; haptics: boolean };

const KEY = "pounce.settings";
/** The TV page's settings, apart from the phone's. */
export const TV_SETTINGS_KEY = "pounce.tv.settings";

const load = (key: string): Settings => ({ sound: true, haptics: true, ...(store.json<Partial<Settings>>(key) ?? {}) });

let key = KEY;
let current: Settings = load(KEY);
const listeners = new Set<(s: Settings) => void>();

export const settings = (): Settings => current;

export function setSettings(patch: Partial<Settings>): void {
  current = { ...current, ...patch };
  store.set(key, JSON.stringify(current));
  for (const l of [...listeners]) l(current);
}

export function onSettings(listener: (s: Settings) => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/**
 * This page is a TV: from now on its settings (what `settings()` gives, what `setSettings`
 * keeps, and so what `play` obeys) are the TV's own, under their own key.
 */
export function keepTvSettings(): void {
  if (key === TV_SETTINGS_KEY) return;
  key = TV_SETTINGS_KEY;
  current = load(TV_SETTINGS_KEY);
  for (const l of [...listeners]) l(current);
}

/** True when the player asked for less motion. */
export const reducedMotion = (): boolean =>
  typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;
