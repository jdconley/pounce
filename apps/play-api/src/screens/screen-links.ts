import { DurableObject } from "cloudflare:workers";

import { devSpeed } from "../env";
import { DEVICE_HEADER } from "../room/game-room";

import { linkDecision, SCREEN_LINK_TTL_MS } from "./screens";

import type { Env } from "../env";

const PING = '{"t":"ping"}';
const PONG = '{"t":"pong"}';
const NORMAL_CLOSURE = 1000;

type LinkRow = { owner: string; code: string; showing: string | null; spent: number; room: string | null; expires: number };

const notFound = () => new Response(JSON.stringify({ error: "not_found" }), { status: 404, headers: { "content-type": "application/json" } });

/**
 * One screen link, as two kinds of instance. `token:<token>` is the link itself: the TV that
 * made it, the table it shows, whether a phone used it, and the TV's waiting sockets.
 * `code:<code>` finds the token from its backup code. Both forget everything at expiry.
 */
export class ScreenLinks extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    // Link meters ping; answered without waking the instance.
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair(PING, PONG));
  }

  /**
   * The tables, made on the first write and again after `deleteAll` drops them on an instance
   * that stays loaded. Reads never make them, so asking after a token that never existed leaves
   * nothing behind.
   */
  private schema(): void {
    this.ctx.storage.sql.exec(
      "CREATE TABLE IF NOT EXISTS link (id INTEGER PRIMARY KEY CHECK (id = 1), owner TEXT, token TEXT, code TEXT, showing TEXT, spent INTEGER, room TEXT, expires INTEGER)",
    );
    this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS code (id INTEGER PRIMARY KEY CHECK (id = 1), token TEXT, expires INTEGER)");
  }

  /** Divided like the room's timers, so a dev server's links expire as fast as its games run. */
  private ttl(): number {
    return SCREEN_LINK_TTL_MS / devSpeed(this.env);
  }

  private has(table: "link" | "code"): boolean {
    return this.ctx.storage.sql.exec("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", table).toArray().length > 0;
  }

  private row(): LinkRow | null {
    if (!this.has("link")) return null;
    return this.ctx.storage.sql.exec<LinkRow>("SELECT owner, code, showing, spent, room, expires FROM link WHERE id = 1").toArray()[0] ?? null;
  }

  /** Token instance: a new link for the TV `owner`. */
  async open(owner: string, token: string, code: string, showing: string | null, now: number): Promise<void> {
    this.schema();
    const expires = now + this.ttl();
    this.ctx.storage.sql.exec(
      "INSERT OR REPLACE INTO link (id, owner, token, code, showing, spent, room, expires) VALUES (1, ?, ?, ?, ?, 0, NULL, ?)",
      owner,
      token,
      code,
      showing,
      expires,
    );
    await this.ctx.storage.setAlarm(expires);
  }

  /** Code instance: holds the code for `token`. False when it is live for another link. */
  async reserve(token: string, now: number): Promise<boolean> {
    this.schema();
    const held = this.ctx.storage.sql.exec<{ token: string; expires: number }>("SELECT token, expires FROM code WHERE id = 1").toArray()[0];
    if (held && held.expires > now && held.token !== token) return false;
    const expires = now + this.ttl();
    this.ctx.storage.sql.exec("INSERT OR REPLACE INTO code (id, token, expires) VALUES (1, ?, ?)", token, expires);
    await this.ctx.storage.setAlarm(expires);
    return true;
  }

  /** Code instance: the token it stands for, while it lives. */
  tokenFor(now: number): string | null {
    if (!this.has("code")) return null;
    const held = this.ctx.storage.sql.exec<{ token: string; expires: number }>("SELECT token, expires FROM code WHERE id = 1").toArray()[0];
    return held && held.expires > now ? held.token : null;
  }

  /**
   * Token instance: a phone at `room` links it. On `link` the room lists the TV as a screen
   * first, so the socket the TV opens next is a member's, and then the TV is told. `seated`:
   * the TV's device sits or hosts at that table, so it can't be its screen.
   */
  async link(room: string, move: boolean, now: number): Promise<"link" | "already" | "showing" | "gone" | "seated"> {
    const row = this.row();
    const decision = linkDecision(row && { showing: row.showing, spent: row.spent === 1, expires: row.expires }, room, move, now);
    if (decision !== "link" || !row) return decision;
    // Spent before anything is awaited, so two phones can't both use it.
    this.ctx.storage.sql.exec("UPDATE link SET spent = 1, room = ? WHERE id = 1", room);
    let added = false;
    try {
      added = await this.env.ROOMS.get(this.env.ROOMS.idFromName(room)).addScreen(row.owner);
    } finally {
      if (!added) this.ctx.storage.sql.exec("UPDATE link SET spent = 0, room = NULL WHERE id = 1");
    }
    if (!added) return "seated";
    const linked = JSON.stringify({ t: "linked", room });
    for (const ws of this.ctx.getWebSockets()) send(ws, linked);
    return "link";
  }

  /** Token instance: the TV's waiting socket. Only the device that made the link may wait on it. */
  async fetch(request: Request): Promise<Response> {
    const row = this.row();
    if (!row || row.expires <= Date.now() || request.headers.get(DEVICE_HEADER) !== row.owner) return notFound();
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") return new Response(null, { status: 426 });
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
    this.ctx.acceptWebSocket(server);
    // A TV that connects after the link happened is told at once.
    if (row.room !== null) send(server, JSON.stringify({ t: "linked", room: row.room }));
    return new Response(null, { status: 101, webSocket: client });
  }

  /** The TV says nothing on this socket but pings, which are answered without waking. */
  webSocketMessage(): void {}

  webSocketClose(ws: WebSocket, code: number, reason: string): void {
    try {
      ws.close(code, reason);
    } catch {
      // Already closed, or a code that may not be sent back (1005, 1006).
    }
  }

  /** Expiry: the TV is told, its sockets close, and the link is forgotten. */
  async alarm(): Promise<void> {
    const expired = JSON.stringify({ t: "expired" });
    for (const ws of this.ctx.getWebSockets()) {
      send(ws, expired);
      try {
        ws.close(NORMAL_CLOSURE, "expired");
      } catch {
        // Already closing.
      }
    }
    await this.ctx.storage.deleteAll();
  }
}

function send(ws: WebSocket, message: string): void {
  try {
    ws.send(message);
  } catch {
    // A socket that is closing hears nothing more.
  }
}
