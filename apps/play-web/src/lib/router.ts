/** The web player's few routes, all under /play/. */
import { ROOM_CODE as CODE } from "@pounce/play-api/room/codes";

import type { DailyGameId } from "@pounce/play-api/daily/module";

export type Route =
  | { kind: "home" }
  | { kind: "table"; code: string }
  | { kind: "join"; code: string }
  /** The TV's QR at a Purrtrait table (`/e/<CODE>?near=<KEY>`, design §5.2): join with the TV's key. */
  | { kind: "easel"; code: string; near?: string }
  | { kind: "pounce"; token: string }
  | { kind: "keypad" }
  /** The TV page: it shows a link, then a table. */
  | { kind: "tv" }
  /** A phone that scanned a TV's QR, choosing which table to put on it. */
  | { kind: "tvLink"; token: string }
  /** The Daily Dish: today's puzzles, the board, stats. */
  | { kind: "dish" }
  /** One of today's daily puzzles, being played. */
  | { kind: "daily"; game: DailyGameId };

const DAILY_GAME_IDS: readonly DailyGameId[] = ["sniff", "nine-lives", "cat-nap", "box-fort", "test"];

const TOKEN = /^[A-Za-z0-9_-]{22}$/;
/** A near key, or the typed code that carries its first letters. */
const NEAR = /^[A-Za-z0-9]{2,16}$/;

export function parseRoute(pathname: string, search = ""): Route {
  const parts = pathname.replace(/^\/play\/?/, "").split("/").filter(Boolean);
  const [head, arg] = parts;
  const code = arg?.toUpperCase();
  if (head === "t" && code && CODE.test(code)) return { kind: "table", code };
  if (head === "j" && code && CODE.test(code)) return { kind: "join", code };
  if (head === "e" && code && CODE.test(code)) {
    const near = new URLSearchParams(search).get("near");
    return near && NEAR.test(near) ? { kind: "easel", code, near: near.toUpperCase() } : { kind: "easel", code };
  }
  if (head === "p" && arg && TOKEN.test(arg)) return { kind: "pounce", token: arg };
  if (head === "join") return { kind: "keypad" };
  if (head === "tv" && parts.length === 1) return { kind: "tv" };
  if (head === "tv-link" && arg && TOKEN.test(arg)) return { kind: "tvLink", token: arg };
  if (head === "daily") return arg && (DAILY_GAME_IDS as readonly string[]).includes(arg) ? { kind: "daily", game: arg as DailyGameId } : { kind: "dish" };
  return { kind: "home" };
}

export function pathFor(route: Route): string {
  switch (route.kind) {
    case "table":
      return `/play/t/${route.code}`;
    case "join":
      return `/play/j/${route.code}`;
    case "easel":
      return `/play/e/${route.code}`;
    case "pounce":
      return `/play/p/${route.token}`;
    case "keypad":
      return "/play/join";
    case "tv":
      return "/play/tv";
    case "tvLink":
      return `/play/tv-link/${route.token}`;
    case "dish":
      return "/play/daily";
    case "daily":
      return `/play/daily/${route.game}`;
    default:
      return "/play/";
  }
}

const listeners = new Set<(r: Route) => void>();

export const currentRoute = (): Route => parseRoute(location.pathname, location.search);

export function navigate(route: Route, replace = false): void {
  const path = pathFor(route);
  if (path !== location.pathname) {
    if (replace) history.replaceState(null, "", path);
    else history.pushState(null, "", path);
  }
  for (const l of [...listeners]) l(route);
}

export function onRoute(listener: (r: Route) => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

if (typeof window !== "undefined") {
  window.addEventListener("popstate", () => {
    const route = currentRoute();
    for (const l of [...listeners]) l(route);
  });
}

/**
 * What "Join with code" was typed: a room code (5), or a Purrtrait table's TV code (8: the room
 * code and the near key's first 3 letters, design §5.2). Null when it is neither.
 */
export function typedCode(raw: string): { code: string; near?: string } | null {
  const clean = raw.toUpperCase().replace(/[^A-Z0-9]/g, "");
  const code = clean.slice(0, 5);
  if (!CODE.test(code)) return null;
  if (clean.length === 5) return { code };
  if (clean.length === 8) return { code, near: clean };
  return null;
}

export const isRoomCode = (code: string): boolean => CODE.test(code);
