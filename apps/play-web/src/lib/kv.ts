/**
 * The one place the web player touches the browser's storage (docs/main-thread.md: the rendering
 * thread only does UI work). `localStorage` is synchronous disk access, so it is read once, the
 * first time anything asks, into memory; every later read is from memory, and writes reach the
 * disk in idle time (or as the page is hidden or closed), never inside a frame.
 */
const PREFIX = "pounce.";
const IDLE_TIMEOUT_MS = 2000;

let memory: Map<string, string> | null = null;
const dirty = new Map<string, string | null>();
let scheduled = false;

function disk(): Storage | null {
  try {
    return typeof localStorage === "undefined" ? null : localStorage;
  } catch {
    // Blocked storage (a private window, site data off): memory only.
    return null;
  }
}

/** Everything Pounce keeps, read in one pass the first time it is needed. */
function loaded(): Map<string, string> {
  if (memory) return memory;
  memory = new Map();
  const d = disk();
  if (d) {
    try {
      for (let i = 0; i < d.length; i++) {
        const key = d.key(i);
        if (key?.startsWith(PREFIX)) memory.set(key, d.getItem(key) ?? "");
      }
    } catch {
      // Unreadable: start empty.
    }
  }
  if (typeof document !== "undefined") {
    // Whatever is still unwritten goes as the page is hidden or closed.
    document.addEventListener("visibilitychange", () => document.visibilityState === "hidden" && flushNow());
    addEventListener("pagehide", flushNow);
  }
  return memory;
}

/** Writes what changed, now. Called in idle time, as the page hides, and before a reload. */
export function flushNow(): void {
  scheduled = false;
  const d = disk();
  for (const [key, value] of dirty) {
    try {
      if (value === null) d?.removeItem(key);
      else d?.setItem(key, value);
    } catch {
      // Full or blocked: kept in memory for this visit.
    }
  }
  dirty.clear();
}

function schedule(): void {
  if (scheduled) return;
  scheduled = true;
  const idle = (globalThis as { requestIdleCallback?: (fn: () => void, o?: { timeout: number }) => number }).requestIdleCallback;
  if (idle) idle(flushNow, { timeout: IDLE_TIMEOUT_MS });
  else setTimeout(flushNow, 0);
}

export const store = {
  get(key: string): string | null {
    return loaded().get(key) ?? null;
  },
  set(key: string, value: string): void {
    loaded().set(key, value);
    dirty.set(key, value);
    schedule();
  },
  remove(key: string): void {
    loaded().delete(key);
    dirty.set(key, null);
    schedule();
  },
  json<T>(key: string): T | null {
    const raw = store.get(key);
    if (raw === null) return null;
    try {
      return JSON.parse(raw) as T;
    } catch {
      return null;
    }
  },
};
