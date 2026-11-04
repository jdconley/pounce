import { DurableObject } from "cloudflare:workers";

import { devSpeed } from "../env";
import { catTower } from "../games/cat-tower";
import { PERSON_ID, PLAYER_ID } from "../players/ids";
import { parseClientMessage } from "../protocol";

import { RoomCore, type AdoptRule, type Outbound, type PushIntent, type RoomState } from "./core";

import type { Env } from "../env";
import type { ServerMessage } from "../protocol";

/** Internal header the Worker sets to the verified device id. */
export const DEVICE_HEADER = "x-play-device";
/** Internal header the Worker sets to the device's people and their players, as JSON `{personId: playerId}`. */
export const PLAYER_HEADER = "x-play-player";

const MAX_HEADER_PLAYERS = 16;

const BAD_MESSAGE: ServerMessage = { t: "error", code: "bad_message" };
const NORMAL_CLOSURE = 1000;

const cryptoRng = (): number => (crypto.getRandomValues(new Uint32Array(1))[0] as number) / 2 ** 32;

/**
 * One instance per room code. Holds the room's state in SQLite, the devices'
 * hibernatable WebSockets, and the alarm that drives bots and timers. All game
 * logic lives in `RoomCore`; this class persists and delivers.
 */
export class GameRoom extends DurableObject<Env> {
  private core: RoomCore | null = null;
  /**
   * Status, actor, name and seat holders when the tables index was last updated,
   * and the devices it listed this room for. Persisted in `listed` so an
   * instance woken from hibernation still knows whom to remove.
   */
  private tablesFingerprint = "";
  private tableDevices = new Set<string>();
  private tablePlayers = new Set<string>();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => {
      this.core = this.load();
      if (this.core) await this.dropStaleDevices(this.core);
    });
  }

  /** Creates the room, or reports that the code is already taken. `name` is already validated. */
  async init(code: string, hostDeviceId: string, name?: string): Promise<{ ok: true } | { exists: true }> {
    if (this.core) return { exists: true };
    this.ctx.storage.sql.exec(
      "CREATE TABLE IF NOT EXISTS room (id INTEGER PRIMARY KEY CHECK (id = 1), json TEXT)",
    );
    this.ctx.storage.sql.exec(
      "CREATE TABLE IF NOT EXISTS listed (id INTEGER PRIMARY KEY CHECK (id = 1), fingerprint TEXT, devices TEXT, players TEXT)",
    );
    this.core = new RoomCore(
      RoomCore.create(code, hostDeviceId, Date.now(), name),
      Date.now,
      cryptoRng,
      catTower,
      devSpeed(this.env),
    );
    await this.after([]);
    return { ok: true };
  }

  /** WebSocket upgrade only. The Worker has verified the device token. */
  async fetch(request: Request): Promise<Response> {
    const deviceId = request.headers.get(DEVICE_HEADER);
    if (!this.core) return new Response(null, { status: 404 });
    if (!deviceId) return new Response(null, { status: 400 });
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      return new Response(null, { status: 426 });
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
    this.ctx.acceptWebSocket(server, [deviceId]);
    server.serializeAttachment({ deviceId });
    await this.after(this.core.connect(deviceId, parsePlayers(request.headers.get(PLAYER_HEADER))));
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws: WebSocket, data: string | ArrayBuffer): Promise<void> {
    const core = this.core;
    if (!core) {
      ws.close(NORMAL_CLOSURE);
      return;
    }
    const parsed = typeof data === "string" ? parseClientMessage(data) : null;
    if (parsed === null || "error" in parsed) {
      send(ws, BAD_MESSAGE);
      return;
    }
    await this.after(core.handle(deviceOf(ws), parsed));
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
    try {
      ws.close(code, reason);
    } catch {
      // Already closed, or a code that may not be sent back (1005, 1006).
    }
    await this.dropped(ws);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    await this.dropped(ws);
  }

  async alarm(): Promise<void> {
    if (this.core) await this.after(this.core.tick());
  }

  /** Hands seats to players (§13.1): a backfill after a profile upload, a merge, or an account deletion. */
  async adopt(rule: AdoptRule): Promise<void> {
    if (this.core) await this.after(this.core.adopt(rule));
  }

  private load(): RoomCore | null {
    const sql = this.ctx.storage.sql;
    // Reading sqlite_master creates nothing, so probing an unused code leaves
    // no storage behind.
    const table = sql.exec("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'room'").toArray();
    if (table.length === 0) return null;
    const row = sql.exec<{ json: string }>("SELECT json FROM room WHERE id = 1").toArray()[0];
    if (!row) return null;
    // Rooms made before players have no `players` column.
    const columns = sql.exec<{ name: string }>("PRAGMA table_info(listed)").toArray();
    if (!columns.some((c) => c.name === "players")) sql.exec("ALTER TABLE listed ADD COLUMN players TEXT");
    const listed = sql
      .exec<{ fingerprint: string; devices: string; players: string | null }>(
        "SELECT fingerprint, devices, players FROM listed WHERE id = 1",
      )
      .toArray()[0];
    if (listed) {
      this.tablesFingerprint = listed.fingerprint;
      this.tableDevices = new Set(JSON.parse(listed.devices) as string[]);
      this.tablePlayers = new Set(JSON.parse(listed.players ?? "[]") as string[]);
    }
    return new RoomCore(JSON.parse(row.json) as RoomState, Date.now, cryptoRng, catTower, devSpeed(this.env));
  }

  /**
   * A restart closes every socket without a close callback, so devices saved
   * as connected may have none left. Mark those away; the events reach only
   * sockets that still exist.
   */
  private async dropStaleDevices(core: RoomCore): Promise<void> {
    const stale = Object.entries(core.state.devices)
      .filter(([id, device]) => device.connected && !this.hasOpenSocket(id))
      .map(([id]) => id);
    if (stale.length === 0) return;
    await this.after(stale.flatMap((id) => core.disconnect(id)));
  }

  private hasOpenSocket(deviceId: string, except?: WebSocket): boolean {
    return this.ctx
      .getWebSockets(deviceId)
      .some((s) => s !== except && s.readyState === WebSocket.OPEN);
  }

  /** A device is disconnected only when its last open socket goes. */
  private async dropped(ws: WebSocket): Promise<void> {
    if (!this.core) return;
    const deviceId = deviceOf(ws);
    if (!this.hasOpenSocket(deviceId, ws)) await this.after(this.core.disconnect(deviceId));
  }

  /** Delivers, pushes, persists, re-arms the alarm and updates the tables index. */
  private async after(out: Outbound[]): Promise<void> {
    const core = this.core as RoomCore;
    const { state } = core;

    for (const { to, message } of out) {
      const sockets = to === "all" ? this.ctx.getWebSockets() : this.ctx.getWebSockets(to);
      for (const ws of sockets) send(ws, message);
    }

    for (const intent of core.drainPushIntents()) {
      this.ctx.waitUntil(this.push(intent).catch(() => undefined));
    }

    this.ctx.storage.sql.exec(
      "INSERT INTO room (id, json) VALUES (1, ?) ON CONFLICT (id) DO UPDATE SET json = excluded.json",
      JSON.stringify(state),
    );
    await this.ctx.storage.setAlarm(core.nextAlarm());

    if (out.some(({ message }) => message.t === "error" && message.code === "bot_stalled")) {
      console.error("bot_stalled", state.code);
    }
    if (out.some(({ message }) => message.t === "error" && message.code === "room_closed")) {
      await this.close(core);
      return;
    }
    await this.updateTables(core);
  }

  /**
   * "Your turn" goes to every device of the seat's player, or to the device
   * holding a seat with no player; a dismiss goes to the player's other
   * devices (§12.5).
   */
  private async push(intent: PushIntent): Promise<void> {
    const playerDevices = intent.playerId ? await this.player(intent.playerId).deviceIds() : [];
    const targets =
      intent.kind === "your_turn"
        ? new Set(intent.playerId ? playerDevices : [intent.deviceId])
        : new Set(playerDevices.filter((d) => d !== intent.exceptDeviceId));
    await Promise.all([...targets].map((deviceId) => this.index(deviceId).push(intent).catch(() => undefined)));
  }

  private async updateTables(core: RoomCore): Promise<void> {
    const { state } = core;
    const actor = state.status === "playing" && state.gameState ? catTower.currentActor(state.gameState) : null;
    const devices = tableDevices(state);
    const players = new Set(core.seatPlayers());
    const fingerprint = JSON.stringify([state.status, actor, state.name, [...devices], [...players]]);
    if (fingerprint === this.tablesFingerprint) return;
    this.tablesFingerprint = fingerprint;

    const gone = [...this.tableDevices].filter((d) => !devices.has(d));
    const gonePlayers = [...this.tablePlayers].filter((p) => !players.has(p));
    this.tableDevices = devices;
    this.tablePlayers = players;
    // Saved before the RPCs: an eviction mid-update must not lose who is listed.
    this.ctx.storage.sql.exec(
      `INSERT INTO listed (id, fingerprint, devices, players) VALUES (1, ?, ?, ?)
       ON CONFLICT (id) DO UPDATE SET fingerprint = excluded.fingerprint, devices = excluded.devices,
         players = excluded.players`,
      fingerprint,
      JSON.stringify([...devices]),
      JSON.stringify([...players]),
    );
    const updatedAt = Date.now();
    const entry = { code: state.code, name: state.name, status: state.status, updatedAt };
    await Promise.all([
      ...[...devices].map((deviceId) =>
        this.index(deviceId).upsertTable({
          ...entry,
          yourTurn: actor !== null && core.controlledSeats(deviceId).includes(actor),
        }),
      ),
      ...[...players].map((playerId) =>
        this.player(playerId).upsertTable({
          ...entry,
          yourTurn: actor !== null && state.seats[actor]?.playerId === playerId,
        }),
      ),
      ...gone.map((deviceId) => this.index(deviceId).removeTable(state.code)),
      ...gonePlayers.map((playerId) => this.player(playerId).removeTable(state.code)),
    ]).catch((error: unknown) => {
      // A stale tables list is cosmetic; the room itself is saved.
      console.error("tables_update_failed", state.code, String(error));
    });
  }

  /** The room has expired: tell everyone, forget it everywhere, delete it. */
  private async close(core: RoomCore): Promise<void> {
    const { code } = core.state;
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.close(NORMAL_CLOSURE, "room_closed");
      } catch {
        // Already closing.
      }
    }
    const devices = new Set([...tableDevices(core.state), ...this.tableDevices]);
    const players = new Set([...core.seatPlayers(), ...this.tablePlayers]);
    await Promise.all([
      ...[...devices].map((deviceId) => this.index(deviceId).removeTable(code)),
      ...[...players].map((playerId) => this.player(playerId).removeTable(code)),
    ]).catch(
      (error: unknown) => {
        console.error("tables_update_failed", code, String(error));
      },
    );
    this.core = null;
    this.tablesFingerprint = "";
    this.tableDevices = new Set();
    this.tablePlayers = new Set();
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
  }

  private index(deviceId: string) {
    return this.env.DEVICES.get(this.env.DEVICES.idFromName(deviceId));
  }

  private player(playerId: string) {
    return this.env.PLAYERS.get(this.env.PLAYERS.idFromName(playerId));
  }
}

/** The Worker's `x-play-player` header, or no players when it is missing or malformed. */
function parsePlayers(header: string | null): Record<string, string> {
  if (!header) return {};
  try {
    const value: unknown = JSON.parse(header);
    if (typeof value !== "object" || value === null || Array.isArray(value)) return {};
    const entries = Object.entries(value as Record<string, unknown>);
    if (entries.length > MAX_HEADER_PLAYERS) return {};
    if (!entries.every(([person, p]) => PERSON_ID.test(person) && typeof p === "string" && PLAYER_ID.test(p))) return {};
    return Object.fromEntries(entries) as Record<string, string>;
  } catch {
    return {};
  }
}

/** Every device holding a seat, plus the host. */
function tableDevices(state: RoomState): Set<string> {
  const out = new Set<string>([state.hostDeviceId]);
  for (const seat of state.seats) if (seat.deviceId) out.add(seat.deviceId);
  return out;
}

function deviceOf(ws: WebSocket): string {
  return (ws.deserializeAttachment() as { deviceId: string }).deviceId;
}

function send(ws: WebSocket, message: ServerMessage): void {
  try {
    ws.send(JSON.stringify(message));
  } catch {
    // The socket closed under us; its close handler deals with it.
  }
}
