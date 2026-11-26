import { PROTOCOL_VERSION } from "@pounce/play-api/protocol";

declare const __BUILD__: string;
declare const __VERSION__: string;

/** This build's id (the commit), as `/play/version.json` says it. */
export const BUILD: string = typeof __BUILD__ === "string" ? __BUILD__ : "test";
/** The version the server and the funnel see (the build's UTC time). */
export const VERSION: string = typeof __VERSION__ === "string" ? __VERSION__ : "2026.1115.1200";

/** The protocol this bundle speaks: the server's own constant, compiled in. */
export const PROTOCOL = PROTOCOL_VERSION;

/**
 * Every game the web player can draw (`X-Pounce-Games`, and `games=` on its sockets). Cat Tower is
 * always implied. `dish` says it shows the Daily Dish, so the server sends it the Dish's reminder
 * (docs/daily-protocol.md); no table is a game called `dish`.
 */
export const GAMES = "cat-tower,tiles,birdwatch,dish";

/** `X-Pounce-App`: who is asking. The server never holds the web player to an app minimum. */
export const APP_HEADER = `platform=web; version=${VERSION}; protocol=${PROTOCOL}`;

/** Pounce's own keys: in memory, written in idle time (lib/kv.ts). */
export { store } from "./kv";
