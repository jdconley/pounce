/** The player's settings on this device: sound and vibration, remembered. */
import { store } from "./env";

export type Settings = { sound: boolean; haptics: boolean };

const KEY = "pounce.settings";

let current: Settings = { sound: true, haptics: true, ...(store.json<Partial<Settings>>(KEY) ?? {}) };
const listeners = new Set<(s: Settings) => void>();

export const settings = (): Settings => current;

export function setSettings(patch: Partial<Settings>): void {
  current = { ...current, ...patch };
  store.set(KEY, JSON.stringify(current));
  for (const l of [...listeners]) l(current);
}

export function onSettings(listener: (s: Settings) => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/** True when the player asked for less motion. */
export const reducedMotion = (): boolean =>
  typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;
