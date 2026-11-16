import { PROTOCOL_VERSION } from "@pounce/play-api/protocol";

declare const __BUILD__: string;
declare const __VERSION__: string;

/** This build's id (the commit), as `/play/version.json` says it. */
export const BUILD: string = typeof __BUILD__ === "string" ? __BUILD__ : "test";
/** The version the server and the funnel see (the build's UTC time). */
export const VERSION: string = typeof __VERSION__ === "string" ? __VERSION__ : "2026.1115.1200";

/** The protocol this bundle speaks: the server's own constant, compiled in. */
export const PROTOCOL = PROTOCOL_VERSION;

/** Every game the web player can draw (`X-Pounce-Games`). Cat Tower is always implied. */
export const GAMES = "cat-tower,tiles";

/** `X-Pounce-App`: who is asking. The server never holds the web player to an app minimum. */
export const APP_HEADER = `platform=web; version=${VERSION}; protocol=${PROTOCOL}`;

/** Local storage that never throws: a private window or blocked storage just forgets. */
export const store = {
  get(key: string): string | null {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  },
  set(key: string, value: string): void {
    try {
      localStorage.setItem(key, value);
    } catch {
      // Not kept: the next visit starts fresh.
    }
  },
  remove(key: string): void {
    try {
      localStorage.removeItem(key);
    } catch {
      // Nothing to do.
    }
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
