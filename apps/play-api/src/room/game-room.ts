import { DurableObject } from "cloudflare:workers";

import { devSpeed } from "../env";
import { catTower } from "../games/cat-tower";
import { deliverToPlayer } from "../notify/deliver";
import { gate } from "../notify/policy";
import { playAgainPush, yourMoveContext, yourMovePush } from "../notify/pushes";
import { player as playerRpc } from "../players/accounts";
import { PERSON_ID, PLAYER_ID } from "../players/ids";
import { parseClientMessage } from "../protocol";
import { FALLBACK_ZONE } from "../streaks/clock";
import { rememberLook, reportTable, unlocksFor, type PairViews } from "../streaks/pairs";
import { streaksOn } from "../streaks/profile";

import { newRoomCode } from "./codes";
import {
  RoomCore,
  type AdoptRule,
  type Look,
  type Outbound,
  type PushIntent,
  type RematchIntent,
  type RoomFeatures,
  type RoomState,
  type StreakIntent,
  type YourTurnIntent,
} from "./core";

import type { Env } from "../env";
import type { ClientMessage, ServerMessage } from "../protocol";

/** Internal header the Worker sets to the verified device id. */
export const DEVICE_HEADER = "x-play-device";
/** Internal header the Worker sets to the device's people and their players, as JSON `{personId: playerId}`. */
export const PLAYER_HEADER = "x-play-player";

const MAX_HEADER_PLAYERS = 16;

const BAD_MESSAGE: ServerMessage = { t: "error", code: "bad_message" };
const NORMAL_CLOSURE = 1000;
const ROOM_CODE_ATTEMPTS = 5;
const STREAK_ATTEMPTS = 2;

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
  /** Streak reports, and the "your move" pushes that follow them, go out one at a time, in turn order. */
  private streakChain: Promise<void> = Promise.resolve();
  /** Each player's latest views of their pairs at this table, for the next "your move" (§12.7). */
  private lastViews = new Map<string, PairViews[string]>();
  /** While dealing a pounce's table: the player whose deal-time "your move" is skipped. */
  private quietFor: string | null = null;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    void ctx.blockConcurrencyWhile(async () => {
      this.core = this.load();
      if (this.core) await this.dropStaleDevices(this.core);
    });
  }

  private features(): RoomFeatures {
    return { streaks: streaksOn(this.env) };
  }

  private createSchema(): void {
    this.ctx.storage.sql.exec(
      "CREATE TABLE IF NOT EXISTS room (id INTEGER PRIMARY KEY CHECK (id = 1), json TEXT)",
    );
    this.ctx.storage.sql.exec(
      "CREATE TABLE IF NOT EXISTS listed (id INTEGER PRIMARY KEY CHECK (id = 1), fingerprint TEXT, devices TEXT, players TEXT)",
    );
  }

  /**
   * Creates the room, or reports that the code is already taken. `name` is
   * already validated; `look` is the creator's last-used one (§9.4).
   */
  async init(code: string, hostDeviceId: string, name?: string, look?: Look): Promise<{ ok: true } | { exists: true }> {
    if (this.core) return { exists: true };
    this.createSchema();
    this.core = new RoomCore(
      RoomCore.create(code, hostDeviceId, Date.now(), name, look),
      Date.now,
      cryptoRng,
      catTower,
      devSpeed(this.env),
      this.features(),
    );
    await this.after([]);
    return { ok: true };
  }

  /**
   * "Play again" (§10.4), or a pounce's new game (§12.4): creates this room
   * from the given seats and deals at once. `first` is the player with the
   * first move, who gets "your move" from here.
   */
  async initRematch(
    code: string,
    spec: RematchIntent,
    /** A pounce's answerer, who is opening this table now: no "your move" push for them (§12.4). */
    quietFor?: string,
  ): Promise<{ ok: true; first: string | null } | { exists: true }> {
    if (this.core) return { exists: true };
    this.quietFor = quietFor ?? null;
    this.createSchema();
    this.core = new RoomCore(
      RoomCore.rematchState(code, spec, Date.now()),
      Date.now,
      cryptoRng,
      catTower,
      devSpeed(this.env),
      this.features(),
    );
    await this.after(this.core.deal());
    this.quietFor = null;
    const { state } = this.core;
    const actor = state.gameState ? catTower.currentActor(state.gameState) : null;
    return { ok: true, first: actor === null ? null : (state.seats[actor]?.playerId ?? null) };
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
    if (parsed.t === "setLook" && streaksOn(this.env)) {
      await this.setLook(deviceOf(ws), parsed);
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

  /** A look from the setter's own unlocks (§9.4, §17); the new look becomes their last-used one. */
  private async setLook(deviceId: string, msg: Extract<ClientMessage, { t: "setLook" }>): Promise<void> {
    const players = (this.core as RoomCore).lookPlayers(deviceId);
    const unlocks = await unlocksFor(this.env, players).catch(() => ({ backs: [], rugs: [] }));
    const core = this.core;
    if (!core) return;
    const out = core.handle(deviceId, msg, unlocks);
    const changed = out.some(({ message }) => message.t === "event" && message.event.kind === "look");
    if (changed && core.state.look) {
      this.ctx.waitUntil(rememberLook(this.env, players, core.state.look).catch(() => undefined));
    }
    await this.after(out);
  }

  /**
   * Hands a report to the table's pairs (§13.3): in turn order, retried once,
   * never fatal (a lost update is cosmetic and the game is saved). Each pair's
   * views then reach the sockets of the devices that speak for its people.
   */
  private reportStreak(intent: StreakIntent): void {
    if (new Set(intent.players).size < 2) return;
    // Who is looking at the table now: a milestone isn't pushed to them (§12.1).
    const awake = (this.core as RoomCore).awakePlayers();
    const run = async () => {
      let views: PairViews | null = null;
      for (let attempt = 0; attempt < STREAK_ATTEMPTS && views === null; attempt++) {
        views = await reportTable(this.env, intent, Date.now(), awake).catch(() => null);
      }
      if (views === null) {
        console.error("streak_report_failed");
        return;
      }
      for (const [playerId, list] of Object.entries(views)) this.lastViews.set(playerId, list);
      // The mover's reminders and learned timing (§12.3, §13.3 flow 1).
      if (intent.by) await playerRpc(this.env, intent.by).recordTurn(intent.at, Date.now()).catch(() => undefined);
      const core = this.core;
      if (!core) return;
      for (const [playerId, list] of Object.entries(views)) {
        for (const { deviceId, personId } of core.devicesFor(playerId)) {
          for (const ws of this.ctx.getWebSockets(deviceId)) {
            for (const { pair, view } of list) send(ws, { t: "streak", pair, person: personId, view });
          }
        }
      }
    };
    this.streakChain = this.streakChain.then(run).catch(() => undefined);
    this.ctx.waitUntil(this.streakChain);
  }

  /** Deals the "Play again" table under a fresh code and tells everyone here; on failure, it may be asked again. */
  private async dealRematch(spec: RematchIntent): Promise<void> {
    for (let i = 0; i < ROOM_CODE_ATTEMPTS; i++) {
      const code = newRoomCode(cryptoRng);
      const made = await this.env.ROOMS.get(this.env.ROOMS.idFromName(code))
        .initRematch(code, spec)
        .catch(() => null);
      if (made === null) break;
      if ("ok" in made) {
        if (this.core) {
          if (streaksOn(this.env)) this.ctx.waitUntil(this.pushPlayAgain(spec, code, made.first).catch(() => undefined));
          await this.after(this.core.rematchDealt(code));
        }
        return;
      }
    }
    console.error("rematch_failed");
    if (this.core) {
      this.core.rematchFailed();
      await this.after([]);
    }
  }

  /**
   * "Mia dealt a new game." (§10.4) to the new table's other players: not
   * the one who asked, not the first mover (who gets "your move"), and not
   * anyone looking at this table, who has just seen it.
   */
  private async pushPlayAgain(spec: RematchIntent, code: string, first: string | null): Promise<void> {
    const core = this.core as RoomCore;
    const asked = core.controlledSeats(spec.hostDeviceId)[0];
    const who = asked === undefined ? undefined : core.state.seats[asked]?.person;
    if (!who) return;
    const skip = new Set([...core.lookPlayers(spec.hostDeviceId), ...core.awakePlayers(), ...(first ? [first] : [])]);
    const others = new Set(spec.seats.flatMap((s) => (s.playerId && !skip.has(s.playerId) ? [s.playerId] : [])));
    const push = playAgainPush({ code, table: spec.name, who: { name: who.name, cat: who.cat } });
    const now = Date.now();
    await Promise.allSettled([...others].map((id) => playerRpc(this.env, id).status(push, now)));
  }

  /**
   * "Your move" with streaks on (§12.2, §12.5, §12.7): after this turn's
   * streak report, so it can say the turn keeps today and carry the pair's
   * state; quiet hours and the band rules come from the player.
   */
  private async pushYourMove(intent: YourTurnIntent & { playerId: string }): Promise<void> {
    const profile = await playerRpc(this.env, intent.playerId).pushProfile();
    if (!profile) return;
    const now = Date.now();
    const g = gate({
      kind: "your_move",
      band: profile.band,
      zone: profile.zone ?? FALLBACK_ZONE,
      settings: profile.settings,
      now,
      spacedAt: null,
      remindersToday: 0,
    });
    if (!g.send) return;
    const views = (this.lastViews.get(intent.playerId) ?? []).map((v) => v.view);
    const { streak, completesToday } = yourMoveContext(views, intent.code);
    const push = yourMovePush({
      code: intent.code,
      table: intent.tableName,
      to: intent.personName,
      from: intent.from ?? null,
      completesToday,
      streak,
    });
    await deliverToPlayer(this.env, profile, push, g.level, intent.code);
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
    return new RoomCore(
      JSON.parse(row.json) as RoomState,
      Date.now,
      cryptoRng,
      catTower,
      devSpeed(this.env),
      this.features(),
    );
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

    for (const intent of core.drainStreakIntents()) this.reportStreak(intent);
    for (const intent of core.drainPushIntents()) {
      if (intent.kind === "your_turn" && intent.playerId !== undefined && intent.playerId === this.quietFor) continue;
      if (intent.kind === "your_turn" && intent.playerId && streaksOn(this.env)) {
        const rich = { ...intent, playerId: intent.playerId };
        this.streakChain = this.streakChain.then(() => this.pushYourMove(rich)).catch(() => undefined);
        this.ctx.waitUntil(this.streakChain);
      } else {
        this.ctx.waitUntil(this.push(intent).catch(() => undefined));
      }
    }
    const rematch = core.drainRematch();
    if (rematch) this.ctx.waitUntil(this.dealRematch(rematch));

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
    const next = state.rematch?.code ?? null;
    const fingerprint = JSON.stringify([state.status, actor, state.name, [...devices], [...players], ...(next ? [next] : [])]);
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
    const entry = { code: state.code, name: state.name, status: state.status, updatedAt, ...(next ? { next } : {}) };
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
