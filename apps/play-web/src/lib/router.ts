/** The web player's few routes, all under /play/. */
import { ROOM_CODE as CODE } from "@pounce/play-api/room/codes";

export type Route =
  | { kind: "home" }
  | { kind: "table"; code: string }
  | { kind: "join"; code: string }
  | { kind: "pounce"; token: string }
  | { kind: "keypad" }
  /** The TV page: it shows a link, then a table. */
  | { kind: "tv" }
  /** A phone that scanned a TV's QR, choosing which table to put on it. */
  | { kind: "tvLink"; token: string };

const TOKEN = /^[A-Za-z0-9_-]{22}$/;

export function parseRoute(pathname: string): Route {
  const parts = pathname.replace(/^\/play\/?/, "").split("/").filter(Boolean);
  const [head, arg] = parts;
  const code = arg?.toUpperCase();
  if (head === "t" && code && CODE.test(code)) return { kind: "table", code };
  if (head === "j" && code && CODE.test(code)) return { kind: "join", code };
  if (head === "p" && arg && TOKEN.test(arg)) return { kind: "pounce", token: arg };
  if (head === "join") return { kind: "keypad" };
  if (head === "tv" && parts.length === 1) return { kind: "tv" };
  if (head === "tv-link" && arg && TOKEN.test(arg)) return { kind: "tvLink", token: arg };
  return { kind: "home" };
}

export function pathFor(route: Route): string {
  switch (route.kind) {
    case "table":
      return `/play/t/${route.code}`;
    case "join":
      return `/play/j/${route.code}`;
    case "pounce":
      return `/play/p/${route.token}`;
    case "keypad":
      return "/play/join";
    case "tv":
      return "/play/tv";
    case "tvLink":
      return `/play/tv-link/${route.token}`;
    default:
      return "/play/";
  }
}

const listeners = new Set<(r: Route) => void>();

export const currentRoute = (): Route => parseRoute(location.pathname);

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

export const isRoomCode = (code: string): boolean => CODE.test(code);
