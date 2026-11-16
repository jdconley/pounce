/** Vibration where the browser has it (Android), at the moments iOS taps the Taptic Engine. */
import { settings } from "./settings";

const PATTERNS = { tap: 8, pick: 12, drop: 18, nope: [30, 40, 30], turn: [20, 60, 20], win: [30, 50, 30, 50, 60] } as const;

export type Haptic = keyof typeof PATTERNS;

export function buzz(kind: Haptic): void {
  if (!settings().haptics || typeof navigator.vibrate !== "function") return;
  try {
    navigator.vibrate(PATTERNS[kind] as number | number[]);
  } catch {
    // Not allowed here (no user gesture yet).
  }
}
