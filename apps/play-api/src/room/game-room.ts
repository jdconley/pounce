import { DurableObject } from "cloudflare:workers";

import { servedAt, storeKnown } from "../app/live";
import { gameUnsupported } from "../app/status";
import { APP_HEADER, parseApp } from "../app/version";
import { devSpeed, linkOn, nudgeOn } from "../env";
import { reached } from "../funnel/funnel";
import { roomSteps } from "../funnel/room";
import { DEFAULT_GAME, GAMES_HEADER, gamesListed, gamesOn, gameTitle, type GameId } from "../games";
import { endBody, startAlert, startBody, updateBody, type LiveState } from "../live/live";
import { isGeneratedName } from "../names/filter";
import { yourMoveBody } from "../notify/copy";
import { deliverToPlayer } from "../notify/deliver";
import { gate } from "../notify/policy";
import { nudgePush, playAgainPush, retirePush, yourMoveContext, yourMovePush } from "../notify/pushes";
import { player as playerRpc } from "../players/accounts";
import { PERSON_ID, PLAYER_ID } from "../players/ids";
import { parseClientMessage } from "../protocol";
import { anyBlocked } from "../safety/safety";
import { FALLBACK_ZONE } from "../streaks/clock";
import { myStreaks, rememberLook, reportTable, unlocksFor, type PairViews } from "../streaks/pairs";
import { liveOn, notifyOn, streaksOn, trophyOn } from "../streaks/profile";

import { newRoomCode } from "./codes";
import {
  RoomCore,
  type AdoptRule,
  type LiveIntent,
  type Look,
  type NudgeIntent,
  type RetireIntent,
  type Outbound,
  type PushIntent,
  type RematchIntent,
  type RoomFeatures,
  type RoomState,
  type StreakIntent,
  type YourTurnIntent,
} from "./core";

import type { Env } from "../env";
import type { ClientMessage, ErrorCode, ServerMessage } from "../protocol";
import type { TableSeat } from "./tables";

/** A room of whichever game: this class persists and delivers, and never looks inside the game's state. */
type Room = RoomCore<unknown>;

/** Internal header the Worker sets to the verified device id. */
export const DEVICE_HEADER = "x-play-device";
/** Internal header the Worker sets to the device's people and their players, as JSON `{personId: playerId}`. */
export const PLAYER_HEADER = "x-play-player";

const MAX_HEADER_PLAYERS = 16;

const BAD_MESSAGE: ServerMessage = { t: "error", code: "bad_message" };
const NORMAL_CLOSURE = 1000;
/** The app closed the socket itself (leaving the table, going to the background). */
const ASKED_CLOSURES = [NORMAL_CLOSURE, 1001];
/** The heartbeat the room answers without waking (the bad connection indicator). */
const PING = '{"t":"ping"}';
const PONG = '{"t":"pong"}';
const ROOM_CODE_ATTEMPTS = 5;
const STREAK_ATTEMPTS = 2;

const cryptoRng = (): number => (crypto.getRandomValues(new Uint32Array(1))[0] as number) / 2 ** 32;

/**
 * One instance per room code. Holds the room's state in SQLite, the devices'
 * hibernatable WebSockets, and the alarm that drives bots and timers. All game
 * logic lives in `RoomCore`; this class persists and delivers.
 */
export class GameRoom extends DurableObject<Env> {
  private core: Room | null = null;
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
  /** The funnel steps this instance already reported (`roomSteps`), and the device whose move was just accepted. */
  private funnelTold = new Set<string>();
  private movedNow: string | null = null;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair(PING, PONG));
    void ctx.blockConcurrencyWhile(async () => {
      this.core = this.load();
      if (this.core) await this.dropStaleDevices(this.core);
    });
  }

  private features(): RoomFeatures {
    return { streaks: streaksOn(this.env), live: liveOn(this.env), link: linkOn(this.env), nudge: nudgeOn(this.env), games: gamesOn(this.env) };
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
  async init(
    code: string,
    hostDeviceId: string,
    name?: string,
    look?: Look,
    game?: GameId,
  ): Promise<{ ok: true } | { exists: true } | { off: true }> {
    if (this.core) return { exists: true };
    // The Worker has checked; the room checks again, so no caller can deal a game the flag doesn't list.
    if (!gamesOn(this.env).includes(game ?? DEFAULT_GAME)) return { off: true };
    this.createSchema();
    this.core = new RoomCore<unknown>(
      RoomCore.create(code, hostDeviceId, Date.now(), name, look, game),
      Date.now,
      cryptoRng,
      undefined,
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
  ): Promise<{ ok: true; first: string | null } | { exists: true } | { off: true }> {
    if (this.core) return { exists: true };
    // No new table of a game the `GAMES` flag doesn't list, whoever asks (the room that asked checks too).
    if (!gamesOn(this.env).includes(spec.game ?? DEFAULT_GAME)) return { off: true };
    this.quietFor = quietFor ?? null;
    this.createSchema();
    this.core = new RoomCore<unknown>(
      RoomCore.rematchState(code, spec, Date.now()),
      Date.now,
      cryptoRng,
      undefined,
      devSpeed(this.env),
      this.features(),
    );
    // The pounce's answerer is opening this table: leaving it soon makes it live for them (§11.3).
    if (quietFor) this.core.notePounce(quietFor);
    await this.after(this.core.deal());
    this.quietFor = null;
    const { state } = this.core;
    const actor = this.core.actor();
    return { ok: true, first: actor === null ? null : (state.seats[actor]?.playerId ?? null) };
  }

  /** WebSocket upgrade only. The Worker has verified the device token. */
  async fetch(request: Request): Promise<Response> {
    const deviceId = request.headers.get(DEVICE_HEADER);
    servedAt(request.url);
    if (!this.core) return new Response(null, { status: 404 });
    // An app that can't draw this room's game (it lists its games; one that lists none draws Cat
    // Tower) is told there is no such table, which every version of the app knows how to show.
    if (!gamesListed(request.headers.get(GAMES_HEADER)).includes(this.core.state.game)) {
      const { game } = this.core.state;
      // An app that said what it is (1.1 on) is told why instead: the game, by id and by name,
      // in headers too, since the app can't read a refused upgrade's body.
      if (parseApp(request.headers.get(APP_HEADER))) {
        const refusal = gameUnsupported(game, gameTitle(game));
        return new Response(JSON.stringify(refusal.body), {
          status: 426,
          headers: { ...refusal.headers, "content-type": "application/json", "cache-control": "no-store" },
        });
      }
      // Version 1.0 can only be told there is no such table. A push can say the rest (design §5).
      if (deviceId && notifyOn(this.env)) {
        this.ctx.waitUntil(this.askToUpdate(deviceId, parsePlayers(request.headers.get(PLAYER_HEADER))).catch(() => undefined));
      }
      return new Response(null, { status: 404 });
    }
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
    const parsed = typeof data === "string" ? parseClientMessage(data, core.parseAction) : null;
    if (parsed === null || "error" in parsed) {
      send(ws, parsed === null ? BAD_MESSAGE : { t: "error", code: parsed.error });
      return;
    }
    const refused = await this.refusal(deviceOf(ws), parsed).catch(() => null);
    if (refused) {
      send(ws, refused);
      return;
    }
    if (!this.core) return;
    if (parsed.t === "setLook" && streaksOn(this.env)) {
      await this.setLook(deviceOf(ws), parsed);
      return;
    }
    const out = core.handle(deviceOf(ws), parsed);
    if (parsed.t === "act" && !out.some(({ message }) => message.t === "error")) this.movedNow = deviceOf(ws);
    await this.after(out);
  }

  /**
   * What the room's own rules can't see (they know no ages and no blocks): the answer to send
   * in place of handling `msg`, or null to handle it.
   *
   * A kitten's device types no names (spec §14.1): it can't rename the table, and a seat's
   * name must be one the dice rolled. A player the host blocked can't take a seat. A nudge at
   * someone who blocked the sender is dropped, and the sender is told it went.
   */
  private async refusal(deviceId: string, msg: ClientMessage): Promise<ServerMessage | null> {
    const core = this.core as Room;
    const error = (code: ErrorCode): ServerMessage => ({ t: "error", code });
    const mine = () => Object.values(core.state.devices[deviceId]?.players ?? {});
    if (msg.t === "rename" || msg.t === "renameSeat" || msg.t === "claim") {
      const kitten = (await this.index(deviceId).ageBand()) === "kitten";
      if (kitten && msg.t === "rename") return error("not_allowed");
      if (kitten && !isGeneratedName(msg.t === "claim" ? msg.person.name : msg.name)) return error("bad_name");
    }
    if (msg.t === "claim") {
      const hosts = Object.values(core.state.devices[core.state.hostDeviceId]?.players ?? {});
      if (deviceId !== core.state.hostDeviceId && (await anyBlocked(this.env, hosts, mine()))) return error("blocked");
    }
    if (msg.t === "nudge") {
      const target = core.state.seats[msg.seat]?.playerId;
      if (target && (await anyBlocked(this.env, [target], mine()))) return { t: "nudgeSent", seat: msg.seat };
    }
    return null;
  }

  /**
   * How well the room knows a device, for the guard on joining by code: `member` (the host, a
   * seat's device, or one that has been here before), `exists` (a stranger to a real room) or
   * `none` (no such room).
   */
  knows(deviceId: string): "member" | "exists" | "none" {
    const core = this.core;
    if (!core) return "none";
    const { state } = core;
    const member = deviceId === state.hostDeviceId || state.devices[deviceId] !== undefined || core.controlledSeats(deviceId).length > 0;
    return member ? "member" : "exists";
  }

  /**
   * What an invite page (`/j/<code>`) may say of this table: its name, its game, whether it's
   * over, and who invited, meaning the person in the host's seat, else the first person seated.
   * Null: no such table. The Worker guards this like a guess at the code (`peekInvite`).
   */
  invite(): { table: string; game: GameId; over: boolean; host: { name: string; cat: number } | null; hostDeviceId: string } | null {
    const core = this.core;
    if (!core) return null;
    const { state } = core;
    const people = state.seats.filter((s) => s.kind === "human" && s.person);
    const seat = people.find((s) => s.deviceId === state.hostDeviceId) ?? people[0];
    const host = seat?.person ? { name: seat.person.name, cat: seat.person.cat } : null;
    return { table: state.name, game: state.game, over: state.status === "over", host, hostDeviceId: state.hostDeviceId };
  }

  /**
   * The person `personId` at this table, for a report or a block from `deviceId`: null unless
   * the device is at the table (the host or seated) and the person sits in someone else's seat.
   */
  seatOf(
    deviceId: string,
    personId: string,
  ): { table: string; name: string; playerId: string | null; deviceId: string | null; byPlayer: string | null } | null {
    const core = this.core;
    if (!core) return null;
    const { state } = core;
    const mine = core.controlledSeats(deviceId);
    if (deviceId !== state.hostDeviceId && mine.length === 0) return null;
    const index = state.seats.findIndex((s) => s.kind === "human" && s.person?.id.toLowerCase() === personId.toLowerCase());
    const seat = state.seats[index];
    if (!seat?.person || mine.includes(index)) return null;
    const byPlayer = mine.map((i) => state.seats[i]?.playerId).find((id) => id !== undefined) ?? null;
    return { table: state.name, name: seat.person.name, playerId: seat.playerId ?? null, deviceId: seat.deviceId ?? null, byPlayer };
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
    try {
      ws.close(code, reason);
    } catch {
      // Already closed, or a code that may not be sent back (1005, 1006).
    }
    await this.dropped(ws, ASKED_CLOSURES.includes(code));
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    await this.dropped(ws, false);
  }

  async alarm(): Promise<void> {
    if (!this.core) return;
    this.heardPings(this.core);
    await this.after(this.core.tick());
  }

  /** Each open socket's last auto-answered ping, for the seats' links. */
  private heardPings(core: Room): void {
    for (const ws of this.ctx.getWebSockets()) {
      const at = this.ctx.getWebSocketAutoResponseTimestamp(ws);
      if (at && ws.readyState === WebSocket.OPEN) core.heard(deviceOf(ws), at.getTime());
    }
  }

  /** `playerId` answered a pounce for this table with Play (§11.3): leaving it soon starts a live table. */
  async pounced(playerId: string): Promise<void> {
    if (!this.core) return;
    this.core.notePounce(playerId);
    await this.after([]);
  }

  /** This device's live table moved to another table (§11.3): forget it here, giving back a held "your move". */
  async liveReplaced(deviceId: string): Promise<void> {
    if (!this.core) return;
    this.core.liveReplaced(deviceId);
    await this.after([]);
  }

  /** Ends live tables whose limits have passed by `now` (the alarm does this; tests call it with a later clock). */
  async checkLive(now: number): Promise<void> {
    if (!this.core) return;
    this.core.expireLive(now);
    await this.after([]);
  }

  /** Hands seats to players (§13.1): a backfill after a profile upload, a merge, or an account deletion. */
  async adopt(rule: AdoptRule): Promise<void> {
    if (this.core) await this.after(this.core.adopt(rule));
  }

  /** A look from the setter's own unlocks (§9.4, §17); the new look becomes their last-used one. */
  private async setLook(deviceId: string, msg: Extract<ClientMessage, { t: "setLook" }>): Promise<void> {
    const players = (this.core as Room).lookPlayers(deviceId);
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
    const awake = (this.core as Room).awakePlayers();
    const run = async () => {
      // Your own streak (trophy room design D1): a turn at a table with another person counts, once per report.
      // Someone who forfeited (§5.13) no longer counts as that other person.
      const withSomeone = new Set(intent.players.filter((p) => !intent.out?.includes(p))).size >= 2;
      if (intent.by && withSomeone && trophyOn(this.env)) await playerRpc(this.env, intent.by).recordPersonalTurn(intent.at, Date.now()).catch(() => undefined);
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
      if (intent.by && notifyOn(this.env)) await playerRpc(this.env, intent.by).recordTurn(intent.at, Date.now()).catch(() => undefined);
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

  /** Runs `step` after everything queued on the room's chain, never fatal. */
  private chain(step: () => Promise<void>): void {
    this.streakChain = this.streakChain.then(step).catch(() => undefined);
    this.ctx.waitUntil(this.streakChain);
  }

  /** Deals the "Play again" table under a fresh code and tells everyone here; on failure, it may be asked again. */
  private async dealRematch(spec: RematchIntent): Promise<void> {
    for (let i = 0; i < ROOM_CODE_ATTEMPTS; i++) {
      const code = newRoomCode(cryptoRng);
      const made = await this.env.ROOMS.get(this.env.ROOMS.idFromName(code))
        .initRematch(code, spec)
        .catch(() => null);
      if (made === null || "off" in made) break;
      if ("ok" in made) {
        if (this.core) {
          if (notifyOn(this.env)) this.ctx.waitUntil(this.pushPlayAgain(spec, code, made.first).catch(() => undefined));
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
    const core = this.core as Room;
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
  private async pushYourMove(intent: YourTurnIntent & { playerId: string }, only?: string): Promise<void> {
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
    // A live table's held-back move goes quietly, to that device only (§11.3).
    const to = only ? { ...profile, devices: [only] } : profile;
    await deliverToPlayer(this.env, to, push, only ? "passive" : g.level, intent.code, this.otherHumans(intent.playerId), this.otherGame(), this.later);
  }

  /** Work that outlives a delivery (a lookup of the App Store's version): kept alive until it ends. */
  private later = (work: Promise<unknown>): void => this.ctx.waitUntil(work);

  /**
   * A device whose app can't draw this table's game just tried to open it: someone asked it
   * here. It is pushed, once, who that was and that Pounce needs an update, under the rules of
   * the people on it: nothing in a teen's night, quiet in quiet hours, nothing between people
   * who blocked each other. The someone is the host, as the table shows them; a table whose host
   * has no seat yet names nobody, so nothing is sent.
   */
  private async askToUpdate(deviceId: string, players: Record<string, string>): Promise<void> {
    const core = this.core;
    if (!core) return;
    const { state } = core;
    if (deviceId === state.hostDeviceId) return;
    const hosts = Object.values(state.devices[state.hostDeviceId]?.players ?? {});
    const seat = state.seats.find(
      (s) => s.kind === "human" && s.person && (s.deviceId === state.hostDeviceId || (s.playerId !== undefined && hosts.includes(s.playerId))),
    );
    if (!seat?.person) return;
    const mine = Object.values(players);
    const theirs = seat.playerId ? [seat.playerId] : hosts;
    if (theirs.some((id) => mine.includes(id))) return;
    if ((await anyBlocked(this.env, mine, theirs)) || (await anyBlocked(this.env, theirs, mine))) return;
    let level: "active" | "passive" = "active";
    const profile = mine[0] === undefined ? null : await playerRpc(this.env, mine[0]).pushProfile();
    if (profile) {
      const g = gate({ kind: "update", band: profile.band, zone: profile.zone ?? FALLBACK_ZONE, settings: profile.settings, now: Date.now(), spacedAt: null, remindersToday: 0 });
      if (!g.send) return;
      level = g.level;
    }
    await this.index(deviceId).pushUpdate(
      { code: state.code, title: state.name, from: { name: seat.person.name, cat: seat.person.cat }, game: state.game, gameTitle: gameTitle(state.game) },
      level,
      // What Apple last said is live; a lookup that is due runs after this, for the next time.
      (await storeKnown(this.env, this.later)).store,
    );
  }

  /**
   * A nudge to someone away from the table, under their own rules like "your move": nothing in a
   * teen's night, silent in quiet hours. A kitten's device takes it only from a sender their
   * parent approved (consent design, plan decision 16); otherwise they see it only in the app.
   */
  private async pushNudge(intent: NudgeIntent): Promise<void> {
    const profile = await playerRpc(this.env, intent.playerId).pushProfile();
    if (!profile) return;
    const now = Date.now();
    const g = gate({
      kind: "nudge",
      band: profile.band,
      zone: profile.zone ?? FALLBACK_ZONE,
      settings: profile.settings,
      now,
      spacedAt: null,
      remindersToday: 0,
    });
    if (!g.send) return;
    const push = nudgePush({ code: intent.code, table: intent.tableName, to: intent.personName, from: intent.from });
    await deliverToPlayer(this.env, profile, push, g.level, intent.code, [intent.fromPlayer], this.otherGame(), this.later);
  }

  /**
   * A stalled seat's pushes, under the holder's own rules like a nudge: nothing in a teen's night,
   * silent in quiet hours. A kitten's device takes the warning only when everyone else at the
   * table is approved (like "your move"), and the news only from an approved sender.
   */
  private async pushRetire(intent: RetireIntent): Promise<void> {
    const profile = await playerRpc(this.env, intent.playerId).pushProfile();
    if (!profile) return;
    const g = gate({
      kind: intent.kind === "soon" ? "retire_soon" : "retired",
      band: profile.band,
      zone: profile.zone ?? FALLBACK_ZONE,
      settings: profile.settings,
      now: Date.now(),
      spacedAt: null,
      remindersToday: 0,
    });
    if (!g.send) return;
    const push = retirePush({ code: intent.code, table: intent.tableName, to: intent.personName, from: intent.from ?? null });
    const senders = intent.kind === "soon" ? this.otherHumans(intent.playerId) : [intent.fromPlayer ?? null];
    await deliverToPlayer(this.env, profile, push, g.level, intent.kind === "soon" ? intent.code : undefined, senders, this.otherGame(), this.later);
  }

  /**
   * The live table's pushes (§11.3), in order: the pair's paws from this
   * table's latest views, the player's toggle for a start, the copy for an
   * update that rings. A start that went nowhere is dropped so nothing
   * waits on it; an end on a timeout sends the "your move" it held back.
   */
  private async sendLive(list: LiveIntent[]): Promise<void> {
    for (const intent of list) {
      try {
        await this.sendOneLive(intent);
      } catch {
        if (intent.kind === "start") this.dropLive(intent.deviceId);
      }
    }
  }

  private async sendOneLive(intent: LiveIntent): Promise<void> {
    const now = Date.now();
    const device = this.index(intent.deviceId);
    const { streak, completesToday } = await this.livePaws(intent, now);
    const state: LiveState = { ...intent.state, streak };
    if (intent.kind === "start") {
      const allowed = await this.liveAllowed(intent.playerId);
      const started = allowed ? await device.liveStart(intent.code, startBody(intent.code, state, now, startAlert(state)), state, now) : null;
      if (!started?.sent) this.dropLive(intent.deviceId);
      if (started?.replaced) {
        const old = started.replaced;
        await this.env.ROOMS.get(this.env.ROOMS.idFromName(old)).liveReplaced(intent.deviceId).catch(() => undefined);
      }
      return;
    }
    if (intent.kind === "update") {
      const rings = intent.alert && (await this.ringsNow(intent.playerId, now));
      const alert = rings && intent.alert ? { title: intent.alert.to, body: yourMoveBody(intent.alert.from, state.table, completesToday) } : null;
      await device.liveUpdate(intent.code, updateBody(state, now, alert), state, alert ? 10 : 5, now);
      return;
    }
    await device.liveEnd(intent.code, endBody(state, now), now);
    const held = intent.yourMove;
    if (!held) return;
    if (held.playerId) await this.pushYourMove({ ...held, playerId: held.playerId }, intent.deviceId);
    else await device.push(held, undefined, this.otherGame());
  }

  /** The paws: the device player's pair at this table, from the latest report or (first) from the pairs. */
  private async livePaws(intent: LiveIntent, now: number): Promise<{ streak: LiveState["streak"]; completesToday: boolean }> {
    const playerId = intent.playerId;
    if (!playerId) return { streak: null, completesToday: false };
    if (!this.lastViews.has(playerId) && intent.kind === "start") {
      const mine = await myStreaks(this.env, playerId, now).catch(() => []);
      const here = mine.filter((v) => v.myMove.includes(intent.code) || v.theirMove.includes(intent.code));
      if (here.length > 0) this.lastViews.set(playerId, here.map((view) => ({ pair: view.pair, view })));
    }
    const views = (this.lastViews.get(playerId) ?? []).map((v) => v.view);
    const { streak, completesToday } = yourMoveContext(views, intent.code);
    return { streak: streak ? { count: streak.count, me: streak.me, them: streak.them } : null, completesToday };
  }

  /**
   * A live table rings like "your move" would (§12.1, §12.3): not in the
   * player's quiet hours, where it updates silently instead.
   */
  private async ringsNow(playerId: string | null, now: number): Promise<boolean> {
    if (!playerId) return true;
    const profile = await playerRpc(this.env, playerId).pushProfile();
    if (!profile) return true;
    const g = gate({ kind: "your_move", band: profile.band, zone: profile.zone ?? FALLBACK_ZONE, settings: profile.settings, now, spacedAt: null, remindersToday: 0 });
    return g.send && g.level === "active";
  }

  /** The player's live table toggle (§12.6); a seat with no player has the default, on. */
  private async liveAllowed(playerId: string | null): Promise<boolean> {
    if (!playerId) return true;
    const profile = await playerRpc(this.env, playerId).pushProfile();
    return profile ? profile.settings.liveTable : true;
  }

  private dropLive(deviceId: string): void {
    if (!this.core) return;
    this.core.liveDropped(deviceId);
    this.persist(this.core);
  }

  private persist(core: Room): void {
    this.ctx.storage.sql.exec(
      "INSERT INTO room (id, json) VALUES (1, ?) ON CONFLICT (id) DO UPDATE SET json = excluded.json",
      JSON.stringify(core.state),
    );
  }

  private load(): Room | null {
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
    return new RoomCore<unknown>(
      JSON.parse(row.json) as RoomState<unknown>,
      Date.now,
      cryptoRng,
      undefined,
      devSpeed(this.env),
      this.features(),
    );
  }

  /**
   * A restart closes every socket without a close callback, so devices saved
   * as connected may have none left. Mark those away; the events reach only
   * sockets that still exist.
   */
  private async dropStaleDevices(core: Room): Promise<void> {
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

  /** A device is disconnected only when its last open socket goes. `asked`: the app closed it. */
  private async dropped(ws: WebSocket, asked: boolean): Promise<void> {
    if (!this.core) return;
    const deviceId = deviceOf(ws);
    if (!this.hasOpenSocket(deviceId, ws)) await this.after(this.core.disconnect(deviceId, asked));
  }

  /** Delivers, pushes, persists, re-arms the alarm and updates the tables index. */
  private async after(out: Outbound[]): Promise<void> {
    const core = this.core as Room;
    const { state } = core;

    for (const { to, message } of out) {
      const sockets = to === "all" ? this.ctx.getWebSockets() : this.ctx.getWebSockets(to);
      for (const ws of sockets) send(ws, message);
    }

    for (const intent of core.drainStreakIntents()) this.reportStreak(intent);
    // Live table pushes go after the turn's streak report (fresh paws) and before
    // the pushes, so an end has cleared the device before a "your move" checks it.
    const live = core.drainLiveIntents();
    if (live.length > 0) this.chain(() => this.sendLive(live));
    const chained = liveOn(this.env);
    for (const intent of core.drainPushIntents()) {
      if (intent.kind === "your_turn" && intent.playerId !== undefined && intent.playerId === this.quietFor) continue;
      if (intent.kind === "your_turn" && intent.playerId && notifyOn(this.env)) {
        const rich = { ...intent, playerId: intent.playerId };
        this.chain(() => this.pushYourMove(rich));
      } else if (chained) {
        this.chain(() => this.push(intent));
      } else {
        this.ctx.waitUntil(this.push(intent).catch(() => undefined));
      }
    }
    // Behind the turn's own pushes, so a nudge lands after the "your move" it stands in for.
    for (const intent of core.drainNudgeIntents()) {
      if (notifyOn(this.env)) this.chain(() => this.pushNudge(intent));
    }
    for (const intent of core.drainRetireIntents()) {
      if (notifyOn(this.env)) this.chain(() => this.pushRetire(intent));
    }
    const rematch = core.drainRematch();
    if (rematch) this.ctx.waitUntil(this.dealRematch(rematch));

    this.persist(core);
    await this.ctx.storage.setAlarm(core.nextAlarm());

    if (out.some(({ message }) => message.t === "error" && message.code === "bot_stalled")) {
      console.error("bot_stalled", state.code);
    }
    if (out.some(({ message }) => message.t === "error" && message.code === "room_closed")) {
      await this.close(core);
      return;
    }
    this.reportFunnel(core);
    await this.updateTables(core);
  }

  /** Seats, a first move and a finished game, for the first-run funnel. Never waits, never fails the turn. */
  private reportFunnel(core: Room): void {
    const steps = roomSteps(core.state, this.funnelTold, this.movedNow);
    this.movedNow = null;
    if (steps.length > 0) this.ctx.waitUntil(reached(this.env, steps, Date.now()).catch(() => undefined));
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
    // A consented kitten's device takes a dismiss (no alert); "your move" comes the rich way (plan decision 16).
    const gate = intent.kind === "dismiss" ? { recipient: intent.playerId, senders: [] } : undefined;
    await Promise.all([...targets].map((deviceId) => this.index(deviceId).push(intent, gate, this.otherGame()).catch(() => undefined)));
  }

  /**
   * The room's game when it isn't Cat Tower, for everything sent beyond the room's own sockets
   * (pushes, the tables lists): only an app that can draw the game hears of the table. Undefined
   * for a Cat Tower room, which sends exactly what it always did.
   */
  private otherGame(): GameId | undefined {
    const game = this.core?.state.game;
    return game === undefined || game === DEFAULT_GAME ? undefined : game;
  }

  /**
   * The people behind a "your move" for `playerId`: every other human seat's
   * player, null for a human seat with no player. A consented kitten's device
   * takes it only when they're all approved (parent consent, plan decision 16).
   */
  private otherHumans(playerId: string): (string | null)[] {
    // No room state: nobody can be checked, so nobody counts as approved (review M7).
    if (!this.core) return [null];
    const seats = this.core.state.seats;
    return seats.flatMap((s) => (s.kind !== "human" || s.playerId === playerId ? [] : [s.playerId ?? null]));
  }

  private async updateTables(core: Room): Promise<void> {
    const { state } = core;
    const actor = state.status === "playing" ? core.actor() : null;
    const devices = tableDevices(state);
    const players = new Set(core.seatPlayers());
    const next = state.rematch?.code ?? null;
    // Who sits where, and as whom: a join, a rename or a new cat reaches Home's cards.
    const faces = state.seats.map((s) => [s.kind, s.person?.id, s.person?.name, s.person?.cat, s.playerId ?? s.deviceId]);
    const out = core.outSeats();
    const movedAt = core.waitingSince();
    const fingerprint = JSON.stringify([state.status, actor, state.name, [...devices], [...players], faces, out, movedAt, ...(next ? [next] : [])]);
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
    const entry = {
      code: state.code,
      name: state.name,
      status: state.status,
      updatedAt,
      ...(next ? { next } : {}),
      ...(movedAt === null ? {} : { movedAt }),
      ...(this.otherGame() ? { game: this.otherGame() } : {}),
    };
    await Promise.all([
      ...[...devices].map((deviceId) =>
        this.index(deviceId).upsertTable({
          ...entry,
          // Every seat this device holds forfeited: the table is over for it (§5.13), whoever plays on.
          ...(core.allOut(core.controlledSeats(deviceId)) ? { status: "over" } : {}),
          yourTurn: actor !== null && core.controlledSeats(deviceId).includes(actor),
          seats: tableSeats(state, core.controlledSeats(deviceId)),
        }),
      ),
      ...[...players].map((playerId) =>
        this.player(playerId).upsertTable({
          ...entry,
          ...(core.allOut(state.seats.flatMap((s, i) => (s.playerId === playerId ? [i] : []))) ? { status: "over" } : {}),
          yourTurn: actor !== null && state.seats[actor]?.playerId === playerId,
          seats: tableSeats(
            state,
            state.seats.flatMap((s, i) => (s.playerId === playerId ? [i] : [])),
          ),
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
  private async close(core: Room): Promise<void> {
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
/** The seats as a tables list shows them, with `yours` on the list owner's (`mine`). */
function tableSeats(state: RoomState<unknown>, mine: number[]): TableSeat[] {
  return state.seats.map((s, i) => ({
    kind: s.kind,
    ...(s.person ? { person: { id: s.person.id, name: s.person.name, cat: s.person.cat } } : {}),
    ...(mine.includes(i) ? { yours: true as const } : {}),
  }));
}

function tableDevices(state: RoomState<unknown>): Set<string> {
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
