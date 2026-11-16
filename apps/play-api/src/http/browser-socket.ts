/**
 * Game sockets from a browser (web player design, "Talking to the server"). A browser's
 * WebSocket can send no `Authorization` or custom header, and can't read a refused upgrade's
 * status. So a browser offers the subprotocols `pounce` and `pounce.token.<device token>`, and
 * puts what the app headers would say in the query (`games`, `app`). The Worker moves them into
 * the headers the rest of the server reads, and answers with the `pounce` subprotocol. A refusal
 * becomes a socket that opens and closes at once with a code the page can read: 4000 plus the
 * HTTP status (4404, 4429, 4426, 4401).
 *
 * Only a request offering `pounce` is a browser's: the iOS app's sockets never reach here.
 */
import { APP_HEADER } from "../app/version";
import { GAMES_HEADER } from "../games";

/** The subprotocol a browser offers, and the one the Worker answers with. */
export const BROWSER_PROTOCOL = "pounce";
/** The subprotocol that carries the device token. */
export const TOKEN_PROTOCOL = "pounce.token.";
/** The close code of a refused browser socket is this plus the HTTP status. */
export const REFUSED_BASE = 4000;

const MAX_QUERY_VALUE = 200;

const offered = (request: Request): string[] =>
  (request.headers.get("sec-websocket-protocol") ?? "")
    .split(",")
    .map((p) => p.trim())
    .filter(Boolean);

/** True for a socket upgrade from the web player. */
export function isBrowserSocket(request: Request): boolean {
  return request.headers.get("upgrade")?.toLowerCase() === "websocket" && offered(request).includes(BROWSER_PROTOCOL);
}

/**
 * The browser's upgrade as the iOS app would have sent it: the token as `Authorization`, the
 * query's `games` and `app` as `X-Pounce-Games` and `X-Pounce-App`, and no query. Anything the
 * browser sent in those headers itself is dropped, so only what it offered counts.
 */
export function asAppSocket(request: Request): Request {
  const url = new URL(request.url);
  const headers = new Headers(request.headers);
  headers.delete("authorization");
  headers.delete(GAMES_HEADER);
  headers.delete(APP_HEADER);
  const token = offered(request)
    .find((p) => p.startsWith(TOKEN_PROTOCOL))
    ?.slice(TOKEN_PROTOCOL.length);
  if (token) headers.set("authorization", `Bearer ${token}`);
  const games = url.searchParams.get("games");
  if (games !== null && games.length <= MAX_QUERY_VALUE) headers.set(GAMES_HEADER, games);
  const app = url.searchParams.get("app");
  if (app !== null && app.length <= MAX_QUERY_VALUE) headers.set(APP_HEADER, app);
  url.search = "";
  return new Request(url.toString(), { method: request.method, headers });
}

/** A socket that opens and closes at once with `code`: how a browser hears a refusal. */
function closedSocket(code: number, reason: string): Response {
  const pair = new WebSocketPair();
  const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
  server.accept();
  server.close(code, reason.slice(0, 120));
  return new Response(null, { status: 101, webSocket: client, headers: { "sec-websocket-protocol": BROWSER_PROTOCOL } });
}

/**
 * The answer a browser can use: an accepted socket with the `pounce` subprotocol, or a socket
 * closed with `4000 + status` (and the refusal's `error`, when it has one, as the reason).
 */
export async function browserAnswer(response: Response): Promise<Response> {
  if (response.status === 101 && response.webSocket) {
    const headers = new Headers(response.headers);
    headers.set("sec-websocket-protocol", BROWSER_PROTOCOL);
    return new Response(null, { status: 101, webSocket: response.webSocket, headers });
  }
  let reason = "";
  try {
    const body = (await response.json()) as { error?: unknown };
    if (typeof body.error === "string") reason = body.error;
  } catch {
    // No JSON body: the code says enough.
  }
  const status = response.status >= 400 && response.status <= 599 ? response.status : 500;
  return closedSocket(REFUSED_BASE + status, reason);
}
