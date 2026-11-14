import { DEFAULT_GAME, gameModule, type AnyGameEvent, type GameAction, type GameError, type GameId, type RoomGame } from "../games";
import { POUNCE_LIVE_MS, deadline, expired, liveState, type LiveRecord, type LiveState } from "../live/live";
import { PROTOCOL_VERSION } from "../protocol";
import { DEFAULT_BACK, DEFAULT_RUG } from "../streaks/catalog";

import { newMoveCode } from "./codes";
import { LINK_PING_MS, LinkTracker } from "./link";
import { defaultRoomName } from "./names";

import type { GameModule } from "../games/module";
import type {
  ClientMessage,
  ErrorCode,
  NudgeView,
  Person,
  Presence,
  RetireView,
  RoomEvent,
  RoomStatus,
  RoomView,
  SeatKind,
  SeatLink,
  ServerMessage,
} from "../protocol";
import type { Action, ApplyError, CatTowerState, GameEvent, Seat } from "../rules/engine";
import type { Rng, Seed } from "../rules/rng";
import type { CatTowerView } from "../rules/view";
import type { TilesEvent } from "../tiles/engine";
import type { TilesView } from "../tiles/view";

export type CatTowerModule = GameModule<CatTowerState, Action, CatTowerView, GameEvent, ApplyError>;

export type SeatInfo = {
  kind: SeatKind;
  person?: Person;
  /** The device that claimed the seat, or that it was last moved to. It controls the seat only when there is no player. */
  deviceId?: string;
  /**
   * The player in the seat: then the devices that speak for the player control it (§13.1). Seats
   * claimed before players existed, by an old app, or moved by code to another device have none.
   */
  playerId?: string;
  botLevel?: "house";
};

export type DeviceRecord = {
  presence: Presence;
  since: number;
  connected: boolean;
  /** personId → playerId for the people this device speaks for, as the Worker resolved them on connect. */
  players?: Record<string, string>;
  /** The ids of this device's latest applied moves, oldest first: a move sent again is applied once. */
  acks?: string[];
};

/**
 * `person`: backfill the seats `deviceId` holds, by person id, once its people have players.
 * `from`/`to`: hand one player's seats to another (a merge), or with null back to their devices.
 */
export type AdoptRule = { person: Record<string, string>; deviceId: string } | { from: string; to: string | null };

/**
 * `S` is the state of the room's game. It defaults to Cat Tower's, which is what every room held
 * before rooms had a choice of game; a room of another game is a `RoomState<ItsState>`.
 */
export type RoomState<S = CatTowerState> = {
  code: string;
  /** Rooms saved before tables had names lack it; `RoomCore` fills in the default. */
  name: string;
  /** The room's game, for good. Every room saved before there was a second game says "cat-tower". */
  game: GameId;
  hostDeviceId: string;
  status: RoomStatus;
  /** As many as the game seats at most in the lobby (6 for Cat Tower); compacted to the game's seats on start. */
  seats: SeatInfo[];
  gameState: S | null;
  seq: number;
  lastActivity: number;
  devices: Record<string, DeviceRecord>;
  moveCodes: Record<string, { seat: Seat; expires: number }>;
  /** Failed `claimMove` attempts per device, within a rolling window. */
  moveFailures: Record<string, { count: number; windowStart: number }>;
  /** Lobby renames (table and seats) per device, within a rolling window. Absent: none yet. */
  renames?: Record<string, { count: number; windowStart: number }>;
  timers: { botAt: number | null; nextRoundAt: number | null; cleanupAt: number };
  /** "<round>:<turn>:<turnSeq>" dedupe key for turn pushes. */
  pushedForTurn: string | null;
  /** The turn whose push the player's other devices were last told to clear. Absent in older rooms. */
  dismissedForTurn?: string | null;
  /** Seq of the latest `turn` or `roundStarted` event: tells one turn from the next. */
  turnSeq: number;
  /** The table's rug and card back (§9.4). Absent: the defaults. */
  look?: Look;
  /** When each device last changed the look, for the 10-second limit. */
  lookChangedAt?: Record<string, number>;
  /** Each player's last completed turn here: a pair forms once both have one (§6.1). */
  streakTurns?: Record<string, number>;
  /** The turn and status last reported to pairs, so a draw alone reports nothing. */
  streakKey?: string;
  /** "Play again" (§10.4): asked once, then the new table's code (null while it's being dealt). */
  rematch?: { code: string | null };
  /** Each device's live table here (§11.3), by device id. Absent: none. */
  live?: Record<string, LiveRecord>;
  /** Players who answered a pounce for this table with Play, and when: leaving soon after starts a live table. */
  livePounce?: Record<string, number>;
  /** The turn the live tables were last told about. */
  liveTurn?: string;
  /** The current turn (`turnKey`) and when it began, for a nudge's wait. Absent in older rooms. */
  turnAt?: { turn: string; at: number };
  /** Each nudging seat's last nudge here (by seat index): its turn and when. Absent: none yet. */
  nudges?: Record<string, { turn: string; at: number }>;
  /** The turn (`turnKey`) whose holder was last warned that their seat can soon be retired. */
  retireWarned?: string;
};

export type Look = { rug: string; back: string };

/**
 * Which optional behaviour a room has. Streaks (and looks and Play again) stay off until `STREAKS` is set.
 * `link`: heartbeats, move acks and each seat's connection quality (`LINK`).
 */
export type RoomFeatures = {
  streaks: boolean;
  live?: boolean;
  link?: boolean;
  nudge?: boolean;
  /**
   * The games new tables may be dealt for (the `GAMES` flag, `gamesOn`). Absent: Cat Tower only.
   * A room of a game that is no longer listed plays on, but "Play again" there deals nothing.
   */
  games?: readonly GameId[];
};

/** Why a live table ended: the round or game is over, its device came back, or a limit passed (§11.3). */
export type LiveEnd = "over" | "back" | "idle" | "cap" | "replaced";

/**
 * A Live Activity push for one device (§11.3), from that device's view. The
 * Durable Object adds the pair's paws, checks the player's toggle and hands it
 * to the device's `DeviceIndex`, which holds the tokens.
 */
export type LiveIntent = {
  kind: "start" | "update" | "end";
  deviceId: string;
  code: string;
  /** The player in the device's first seat with one: whose toggle and paws. */
  playerId: string | null;
  state: LiveState;
  /** An update that brings the move to this device: rung, for the person whose move it is. */
  alert?: { to: string; from: string | null };
  reason?: LiveEnd;
  /** A limit ended it on this device's move: the "your move" it held back, sent quietly to this device. */
  yourMove?: YourTurnIntent;
};

/**
 * A change pairs hear about (§13.3): a completed turn by a player (`by`), and
 * who holds the move now (`holder`: a player, or null for a bot, a seat with no
 * player, or between rounds). `over`: the table is no longer in play.
 */
export type StreakIntent = {
  code: string;
  at: number;
  by: string | null;
  holder: string | null;
  players: string[];
  turnedAt: Record<string, number>;
  over: boolean;
  /**
   * Players whose every seat here forfeited (§5.13): the table is over for any pair with one of
   * them, and later turns here don't count for that pair. Absent: nobody.
   */
  out?: string[];
};

/**
 * What "Play again" needs to deal the new table: the same people and bots, name and look, and
 * the same game (absent: Cat Tower, which is also what a pounce's new table is).
 */
export type RematchIntent = { name: string; look: Look; seats: SeatInfo[]; hostDeviceId: string; game?: GameId };

/** The card backs and rugs the people a device speaks for have unlocked. */
export type Unlocks = { backs: readonly string[]; rugs: readonly string[] };

export type YourTurnIntent = {
  kind: "your_turn";
  /** The seat's device. */
  deviceId: string;
  /** Set when the seat has a player: the push goes to all of the player's devices. */
  playerId?: string;
  seat: Seat;
  personName: string;
  /** The table's name, for the notification text. */
  tableName: string;
  /** The room code, so the app can open the right game from the notification. */
  code: string;
  /** With streaks on: the human whose turn just ended, for "Mia played." (§12.2). */
  from?: { name: string; cat: number };
};

/**
 * A nudge to push (the person in `seat` isn't at the table): to the seat's player's devices, under
 * their own rules (quiet hours, a teen's night, a kitten's consent for `fromPlayer`).
 */
export type NudgeIntent = {
  /** The seat's player; a seat with none gets the nudge in the app only. */
  playerId: string;
  seat: Seat;
  personName: string;
  tableName: string;
  code: string;
  from: { name: string; cat: number };
  /** The nudger's player, for a kitten's consent (null: a seat with none, which no consent approves). */
  fromPlayer: string | null;
};

/**
 * A push about retiring a stalled seat, to the seat's player under their own rules (quiet hours, a
 * teen's night, a kitten's consent). "soon": a day before the others may retire it. "done": someone
 * (`from`) did.
 */
export type RetireIntent = {
  kind: "soon" | "done";
  playerId: string;
  seat: Seat;
  personName: string;
  tableName: string;
  code: string;
  /** "done" only: who retired the seat, and their player for a kitten's consent (null: none). */
  from?: { name: string; cat: number };
  fromPlayer?: string | null;
};

/** A background push telling a player's other devices to clear a table's notifications (§12.5). */
export type DismissIntent = { kind: "dismiss"; playerId: string; exceptDeviceId: string; code: string };

export type PushIntent = YourTurnIntent | DismissIntent;

export type Outbound = {
  /** "all" or a deviceId. */
  to: "all" | string;
  message: ServerMessage;
};

type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;

const MS_PER_MINUTE = 60_000;
const MS_PER_DAY = 24 * 60 * MS_PER_MINUTE;
/** A lobby nobody started, or a finished game, closes this long after the last thing that happened in it. */
export const CLEANUP_AFTER_MS = 7 * MS_PER_DAY;
/** A game in play closes only after this long with no move: a holiday doesn't end it. */
export const GAME_CLEANUP_AFTER_MS = 30 * MS_PER_DAY;
/**
 * A turn this old makes its seat retirable: any other person still in the game may forfeit it for
 * its holder (divided by the dev speed).
 */
export const RETIRE_AFTER_MS = 3 * MS_PER_DAY;
/** The holder is warned by push this long before their seat becomes retirable. */
export const RETIRE_WARNING_MS = MS_PER_DAY;
const MOVE_CODE_TTL_MS = 10 * MS_PER_MINUTE;
const MOVE_FAILURE_WINDOW_MS = 10 * MS_PER_MINUTE;
const MAX_MOVE_FAILURES = 5;
/** Renames (the table's and its seats') one device may make in the lobby, per window. */
export const RENAMES_PER_WINDOW = 5;
export const RENAME_WINDOW_MS = MS_PER_MINUTE;
const UINT32_RANGE = 2 ** 32;
const BOT_DELAY_MS = 1200;
const NEXT_ROUND_DELAY_MS = 6000;
const ASLEEP_AFTER_MS = 5 * MS_PER_MINUTE;
/** A game's phase as a room's saved `streakKey` has always spelled it (Cat Tower's own status words). */
const STREAK_STATUS = { playing: "playing", between: "roundOver", over: "gameOver" } as const;
const PRESENCE_RANK: Record<Presence, number> = { asleep: 0, away: 1, awake: 2 };
const LOOK_EVERY_MS = 10_000;
const NO_UNLOCKS: Unlocks = { backs: [], rugs: [] };
/** Move ids remembered per device: far more than one app ever has in flight. */
const ACKS_KEPT = 16;
/** A turn has to be this old before anyone may nudge it (divided by the dev speed). */
export const NUDGE_AFTER_MS = 2 * MS_PER_MINUTE;
/** Between two nudges from the same seat at a table, on any turns (divided by the dev speed). */
export const NUDGE_EVERY_MS = 10 * MS_PER_MINUTE;

/**
 * The room state machine. Pure: it mutates `state` and returns the messages
 * to deliver; the Durable Object persists the state and does the delivery.
 */
export class RoomCore<S = CatTowerState> {
  state: RoomState<S>;
  private readonly now: () => number;
  private readonly rng: Rng;
  /** The room's game. Everything the room needs to know about a game it asks here. */
  private readonly game: RoomGame<S>;
  /** Divides the bot and next-round delays (`DEV_SPEED` on the dev server; 1 everywhere else). */
  private readonly speed: number;
  private readonly features: RoomFeatures;
  /** Not persisted: the Durable Object drains it after every call. */
  private pushIntents: PushIntent[] = [];
  private streakIntents: StreakIntent[] = [];
  private rematchIntent: RematchIntent | null = null;
  private liveIntents: LiveIntent[] = [];
  private nudgeIntents: NudgeIntent[] = [];
  private retireIntents: RetireIntent[] = [];
  /** The player whose action is being applied ended their turn. */
  private turnBy: string | null = null;
  /** The person whose action is being applied ended their turn: "your move" names them. */
  private movedBy: Person | null = null;
  /** Each device's connection quality (not persisted). */
  private readonly link = new LinkTracker();

  /** `game`: left out, the module `state.game` names; tests pass a stand-in. */
  constructor(
    state: RoomState<S>,
    now: () => number,
    rng: Rng,
    game?: RoomGame<S>,
    speed = 1,
    features: RoomFeatures = { streaks: false },
  ) {
    this.state = state;
    (state as Partial<RoomState>).name ??= defaultRoomName(state.code);
    // Every saved room names its game; one that somehow doesn't is Cat Tower, the only game there was.
    (state as Partial<RoomState>).game ??= DEFAULT_GAME;
    this.now = now;
    this.rng = rng;
    this.game = game ?? (gameModule(state.game) as RoomGame<S>);
    this.speed = speed;
    this.features = features;
  }

  /** A new lobby; `name` is already validated (`parseRoomName`) when given. `game`: left out, Cat Tower. */
  static create<S = CatTowerState>(
    code: string,
    hostDeviceId: string,
    now: number,
    name?: string,
    look?: Look,
    game: GameId = DEFAULT_GAME,
  ): RoomState<S> {
    return {
      ...(look ? { look } : {}),
      code,
      name: name ?? defaultRoomName(code),
      game,
      hostDeviceId,
      status: "lobby",
      seats: Array.from({ length: gameModule(game).maxSeats }, (_, i): SeatInfo => ({
        kind: i < 2 ? "open" : "closed",
      })),
      gameState: null,
      seq: 0,
      lastActivity: now,
      devices: {},
      moveCodes: {},
      moveFailures: {},
      timers: { botAt: null, nextRoundAt: null, cleanupAt: now + CLEANUP_AFTER_MS },
      pushedForTurn: null,
      turnSeq: 0,
    };
  }

  /**
   * The new table "Play again" deals (§10.4): the old seats as they were,
   * then `deal()` starts it with no lobby.
   */
  static rematchState<S = CatTowerState>(code: string, spec: RematchIntent, now: number): RoomState<S> {
    const state = RoomCore.create<S>(code, spec.hostDeviceId, now, spec.name, spec.look, spec.game);
    state.seats = [
      ...spec.seats.map((s) => ({ ...s })),
      ...Array.from({ length: state.seats.length - spec.seats.length }, (): SeatInfo => ({ kind: "closed" })),
    ];
    return state;
  }

  /** The room's game's own check of an `act` message's action (`parseClientMessage`). */
  parseAction = (raw: unknown): GameAction | null => this.game.parseAction(raw) as GameAction | null;

  /** The seat that must act next; null in the lobby and whenever nobody is to act. */
  actor(): Seat | null {
    const game = this.state.gameState;
    return game === null ? null : this.game.currentActor(game);
  }

  /** Per seat: forfeited, out of the game for good. Empty until someone is. */
  outSeats(): readonly boolean[] {
    const game = this.state.gameState;
    return game === null ? [] : this.game.forfeited(game);
  }

  /** Dealt and in play: not the lobby, not between two deals, not over. */
  private midGame(): boolean {
    const { state } = this;
    return state.status === "playing" && state.gameState !== null && this.game.phase(state.gameState) === "playing";
  }

  /**
   * Never throws: any unexpected failure becomes `error: internal`. `unlocks`
   * are what the device's people may put on the table (`setLook`), resolved
   * by the Durable Object first; the defaults need none.
   */
  handle(deviceId: string, msg: ClientMessage, unlocks: Unlocks = NO_UNLOCKS): Outbound[] {
    this.heard(deviceId, this.now());
    try {
      return this.dispatch(deviceId, msg, unlocks);
    } catch {
      return [this.fail(deviceId, "internal")];
    }
  }

  /** `players`: the people this device speaks for, mapped to their players. Old apps send none. */
  connect(deviceId: string, players: Record<string, string> = {}): Outbound[] {
    // Everyone else hears about the seat holder waking up; the connecting
    // device gets a snapshot that already includes those events' seq.
    const events = this.presenceChange(
      deviceId,
      () => {
        this.state.devices[deviceId] = {
          presence: "awake",
          since: this.now(),
          connected: true,
          ...(Object.keys(players).length > 0 ? { players } : {}),
        };
      },
      deviceId,
    );
    this.link.connected(deviceId, this.now());
    // Back at the table in the app: its live table goes (§11.3).
    this.endLive(deviceId, "back");
    return [...events, ...this.linkCheck(deviceId), { to: deviceId, message: this.snapshotFor(deviceId) }];
  }

  /**
   * A ping or message from a connected device at `at` (the Durable Object
   * passes each socket's last auto-answered ping before a tick).
   */
  heard(deviceId: string, at: number): void {
    if (this.state.devices[deviceId]?.connected) this.link.hear(deviceId, at);
  }

  /**
   * A closed socket never starts a live table (§11.3): the app closes it in
   * the foreground too (Home, another table), and says `background` first
   * when it leaves or the phone locks.
   */
  /** `asked`: the app closed the socket itself; otherwise the seat shows as reconnecting for a while. */
  disconnect(deviceId: string, asked = true): Outbound[] {
    const device = this.state.devices[deviceId];
    if (!device) return [];
    this.link.disconnected(deviceId, this.now(), asked);
    const out = this.presenceChange(deviceId, () => {
      device.connected = false;
      if (device.presence !== "away") device.since = this.now();
      device.presence = "away";
    });
    return [...out, ...this.linkCheck()];
  }

  /**
   * Gives seats to players: backfilled by person id once a device's people
   * have players, or moved on a merge or an account deletion. Only seats that
   * change send snapshots. Connected devices' maps follow, so an open socket
   * keeps the seats it had.
   */
  adopt(rule: AdoptRule): Outbound[] {
    this.adoptDevices(rule);
    let changed = false;
    for (const seat of this.state.seats) {
      if (seat.kind !== "human") continue;
      if ("person" in rule) {
        // Only the uploading device's own seats: a person id is visible to everyone at the table.
        const playerId = rule.person[(seat.person as Person).id];
        if (seat.deviceId !== rule.deviceId || playerId === undefined || seat.playerId !== undefined) continue;
        seat.playerId = playerId;
      } else {
        if (seat.playerId !== rule.from) continue;
        if (rule.to === null) delete seat.playerId;
        else seat.playerId = rule.to;
      }
      changed = true;
    }
    if (!changed) return [];
    this.state.seq += 1;
    return this.snapshots();
  }

  private adoptDevices(rule: AdoptRule): void {
    if ("person" in rule) {
      const device = this.state.devices[rule.deviceId];
      if (device) device.players = { ...device.players, ...rule.person };
      return;
    }
    for (const device of Object.values(this.state.devices)) {
      if (!device.players) continue;
      for (const [person, playerId] of Object.entries(device.players)) {
        if (playerId !== rule.from) continue;
        if (rule.to === null) delete device.players[person];
        else device.players[person] = rule.to;
      }
    }
  }

  /** The players of every connected device that is awake here: they see what happens at once. */
  awakePlayers(): string[] {
    const awake = Object.values(this.state.devices).filter((d) => d.connected && d.presence === "awake");
    return [...new Set(awake.flatMap((d) => Object.values(d.players ?? {})))];
  }

  /** Every player holding a seat, once each. */
  seatPlayers(): string[] {
    return [...new Set(this.state.seats.flatMap((s) => (s.playerId ? [s.playerId] : [])))];
  }

  /**
   * Runs everything that is due; the alarm may fire late, so one call can do
   * a round advance, a bot step, presence decay and cleanup together.
   */
  tick(): Outbound[] {
    const { state } = this;
    const { timers } = state;
    const out: Outbound[] = [];

    if (timers.nextRoundAt !== null && timers.nextRoundAt <= this.now()) {
      timers.nextRoundAt = null;
      const next = this.game.betweenAction;
      if (next !== null) out.push(...this.applyAndAfter(0, next));
    }

    if (timers.botAt !== null && timers.botAt <= this.now()) {
      timers.botAt = null;
      out.push(...this.botStep());
    }

    for (const [deviceId, device] of Object.entries(state.devices)) {
      if (device.presence === "away" && device.since + ASLEEP_AFTER_MS <= this.now()) {
        out.push(
          ...this.presenceChange(deviceId, () => {
            device.presence = "asleep";
            device.since = this.now();
          }),
        );
      }
    }

    this.expireLive(this.now());
    out.push(...this.linkCheck());
    this.warnStalled();

    // A game dealt under the old 7-day limit gets the longer one.
    timers.cleanupAt = Math.max(timers.cleanupAt, state.lastActivity + this.cleanupAfter());
    if (timers.cleanupAt <= this.now()) {
      for (const deviceId of Object.keys(state.live ?? {})) this.endLive(deviceId, "over");
      state.status = "over";
      this.queueStreak(true);
      out.push({ to: "all", message: { t: "error", code: "room_closed" } });
    }
    return out;
  }

  nextAlarm(): number {
    const { botAt, nextRoundAt, cleanupAt } = this.state.timers;
    const decays = Object.values(this.state.devices)
      .filter((device) => device.presence === "away")
      .map((device) => device.since + ASLEEP_AFTER_MS);
    const link = this.linkWatched() ? this.link.nextChange(this.now()) : null;
    return Math.min(
      ...[botAt, nextRoundAt, cleanupAt, link, this.retireWarningAt(), ...decays, ...Object.values(this.state.live ?? {}).map(deadline)].filter(
        (t): t is number => t !== null,
      ),
    );
  }

  /** Hands over and forgets the pushes queued since the last call. */
  drainPushIntents(): PushIntent[] {
    const drained = this.pushIntents;
    this.pushIntents = [];
    return drained;
  }

  /** Hands over and forgets the nudge pushes queued since the last call. */
  drainNudgeIntents(): NudgeIntent[] {
    const drained = this.nudgeIntents;
    this.nudgeIntents = [];
    return drained;
  }

  /** Hands over and forgets the retire pushes queued since the last call. */
  drainRetireIntents(): RetireIntent[] {
    const drained = this.retireIntents;
    this.retireIntents = [];
    return drained;
  }

  /** Hands over and forgets the streak reports queued since the last call. */
  drainStreakIntents(): StreakIntent[] {
    const drained = this.streakIntents;
    this.streakIntents = [];
    return drained;
  }

  /** Hands over and forgets a "Play again" the room has accepted and not yet dealt. */
  /** Hands over and forgets the Live Activity pushes queued since the last call. */
  drainLiveIntents(): LiveIntent[] {
    const drained = this.liveIntents;
    this.liveIntents = [];
    return drained;
  }

  /** `playerId` answered a pounce for this table with Play: leaving within the hour starts a live table (§11.3). */
  notePounce(playerId: string): void {
    if (!this.features.live) return;
    const marks = this.freshPounces(this.now());
    marks[playerId] = this.now();
  }

  /** The device's start went nowhere (no token, the toggle off, a kitten): no record to update. */
  liveDropped(deviceId: string): void {
    if (this.state.live) delete this.state.live[deviceId];
  }

  /**
   * The device's live table moved to another table (at most one per device):
   * this one's record goes, and on its move the held-back "your move" comes back.
   */
  liveReplaced(deviceId: string): void {
    this.endLive(deviceId, "replaced");
  }

  /** Ends the live tables whose 30 minutes or 2 hours have passed (§11.3). */
  expireLive(now: number): void {
    for (const [deviceId, record] of Object.entries(this.state.live ?? {})) {
      const why = expired(record, now);
      if (why) this.endLive(deviceId, why);
    }
  }

  private freshPounces(now: number): Record<string, number> {
    const marks = (this.state.livePounce ??= {});
    for (const [playerId, at] of Object.entries(marks)) if (now - at >= POUNCE_LIVE_MS) delete marks[playerId];
    return marks;
  }

  /**
   * Leaving the table (§11.3): a live table starts for this device when the
   * game is mid-round, the device holds a seat, and someone else is awake at
   * the table, or one of its players just answered a pounce here with Play.
   */
  private maybeStartLive(deviceId: string): void {
    const { state } = this;
    if (!this.features.live || state.live?.[deviceId]) return;
    if (!this.midGame()) return;
    const mine = this.controlledSeats(deviceId);
    if (mine.length === 0) return;
    const now = this.now();
    const othersAwake = state.seats.some((s, i) => s.kind === "human" && !mine.includes(i) && this.seatPresence(i) === "awake");
    if (!othersAwake && !this.takePounce(deviceId, now)) return;
    state.live = { ...state.live, [deviceId]: { startedAt: now, movedAt: now } };
    this.liveIntents.push({ kind: "start", deviceId, code: state.code, playerId: this.livePlayer(deviceId), state: this.liveView(deviceId) });
  }

  private takePounce(deviceId: string, now: number): boolean {
    const marks = this.freshPounces(now);
    const player = Object.values((this.state.devices[deviceId] as DeviceRecord).players ?? {}).find((p) => marks[p] !== undefined);
    if (player === undefined) return false;
    delete marks[player];
    return true;
  }

  private endLive(deviceId: string, reason: LiveEnd): void {
    const { state } = this;
    if (!state.live?.[deviceId]) return;
    delete state.live[deviceId];
    // Turned off (the kill switch): records left behind go quietly; DeviceIndex lets its own lapse.
    if (!this.features.live) return;
    const view = this.liveView(deviceId);
    const held = reason === "idle" || reason === "cap" || reason === "replaced";
    const yourMove = held && view.mine ? this.heldYourMove(view.turn as Seat) : null;
    this.liveIntents.push({
      kind: "end",
      deviceId,
      code: state.code,
      playerId: this.livePlayer(deviceId),
      state: view,
      reason,
      ...(yourMove ? { yourMove } : {}),
    });
  }

  /** The "your move" a live table stood in for: the seat's, as the turn's push had it. */
  private heldYourMove(seat: Seat): YourTurnIntent {
    const info = this.state.seats[seat] as SeatInfo;
    return {
      kind: "your_turn",
      deviceId: info.deviceId as string,
      ...(info.playerId ? { playerId: info.playerId } : {}),
      seat,
      personName: (info.person as Person).name,
      tableName: this.state.name,
      code: this.state.code,
    };
  }

  /** The device's live table as it should look now. */
  private liveView(deviceId: string): LiveState {
    const { state } = this;
    const game = state.gameState as S;
    const marks = this.game.progress(game);
    return liveState({
      table: state.name,
      seats: state.seats.slice(0, marks.length),
      // Cat Tower's state is the shelves, as it always was; another game's adds its own count beside them.
      ...(this.game.progressKind === "shelf" ? { phases: marks } : { phases: [], pieces: marks }),
      controlled: this.controlledSeats(deviceId),
      turn: this.midGame() ? this.game.currentActor(game) : null,
      streak: null,
    });
  }

  private livePlayer(deviceId: string): string | null {
    return this.controlledSeats(deviceId).flatMap((seat) => this.state.seats[seat]?.playerId ?? [])[0] ?? null;
  }

  /** After a game change: every live table hears about a new turn, and goes when the round or game is over. */
  private liveAfterGame(from: Person | null): void {
    const { state } = this;
    if (!this.features.live) return;
    const game = state.gameState as S;
    if (this.game.phase(game) !== "playing") {
      for (const deviceId of Object.keys(state.live ?? {})) this.endLive(deviceId, "over");
      return;
    }
    const key = this.turnKey();
    if (key === state.liveTurn) return;
    state.liveTurn = key;
    const actor = this.game.currentActor(game) as Seat;
    for (const [deviceId, record] of Object.entries(state.live ?? {})) {
      record.movedAt = this.now();
      // Rung only when the move is this device's and nobody is at the table for it (§12.1).
      const mine = this.controlledSeats(deviceId).includes(actor) && this.seatPresence(actor) !== "awake";
      this.liveIntents.push({
        kind: "update",
        deviceId,
        code: state.code,
        playerId: this.livePlayer(deviceId),
        state: this.liveView(deviceId),
        ...(mine ? { alert: { to: ((state.seats[actor] as SeatInfo).person as Person).name, from: from?.name ?? null } } : {}),
      });
    }
  }

  drainRematch(): RematchIntent | null {
    const drained = this.rematchIntent;
    this.rematchIntent = null;
    return drained;
  }

  /** The new table is dealt: everyone here is told where it is. */
  rematchDealt(code: string): Outbound[] {
    this.state.rematch = { code };
    return [{ to: "all", message: { t: "rematch", code } }];
  }

  /** Dealing the new table failed: "Play again" may be asked again. */
  rematchFailed(): void {
    delete this.state.rematch;
  }

  /** Starts the game with the seats as they are: "Play again" deals at once (§10.4). */
  deal(): Outbound[] {
    const { state } = this;
    const playing = state.seats.flatMap((s, i) =>
      s.kind === "human" || s.kind === "bot" ? [{ seat: s, from: i }] : [],
    );
    const gameState = this.game.create(playing.length, this.newSeed());

    // Move codes address seats by index, and compaction renumbers them. Codes
    // only exist for human seats, which are never dropped.
    const renumbered = new Map(playing.map((p, to) => [p.from, to]));
    for (const entry of Object.values(state.moveCodes)) {
      entry.seat = renumbered.get(entry.seat) as Seat;
    }
    state.seats = playing.map((p) => p.seat);
    state.gameState = gameState;
    state.status = "playing";
    const out = this.changed();
    state.turnSeq = state.seq;
    this.afterGameChange();
    return out;
  }

  /** The players in the seats `deviceId` controls: whose unlocks a `setLook` from it may use. */
  lookPlayers(deviceId: string): string[] {
    const ids = this.controlledSeats(deviceId).flatMap((i) => {
      const playerId = this.state.seats[i]?.playerId;
      return playerId ? [playerId] : [];
    });
    return [...new Set(ids)];
  }

  /** Each connected device that speaks for `playerId`, and the person on it who is that player. */
  devicesFor(playerId: string): { deviceId: string; personId: string }[] {
    return Object.entries(this.state.devices).flatMap(([deviceId, device]) =>
      device.connected
        ? Object.entries(device.players ?? {})
            .filter(([, p]) => p === playerId)
            .map(([personId]) => ({ deviceId, personId }))
        : [],
    );
  }

  private look(): Look {
    return this.state.look ?? { rug: DEFAULT_RUG, back: DEFAULT_BACK };
  }

  snapshotFor(deviceId: string): Snapshot {
    const { state } = this;
    const controlled = this.controlledSeats(deviceId);
    const links = this.seatLinks();
    const seats: RoomView["seats"] = state.seats.map((s, i) => {
      const link = links[i];
      return {
        kind: s.kind,
        ...(s.person ? { person: s.person } : {}),
        yours: controlled.includes(i),
        presence: s.kind === "human" ? this.seatPresence(i) : null,
        ...(link ? { link } : {}),
      };
    });
    return {
      t: "snapshot",
      protocol: PROTOCOL_VERSION,
      seq: state.seq,
      room: {
        code: state.code,
        name: state.name,
        status: state.status,
        youAreHost: deviceId === state.hostDeviceId,
        seats,
        ...this.gameFields(controlled),
        ...(this.features.streaks ? { look: this.look() } : {}),
        ...(state.rematch?.code ? { rematch: state.rematch.code } : {}),
        ...(this.features.link ? { link: { ping: LINK_PING_MS, acks: [...(state.devices[deviceId]?.acks ?? [])] } } : {}),
        ...this.nudgeField(deviceId),
        ...this.retireField(deviceId),
      },
    };
  }

  /**
   * A snapshot's view of the game. Cat Tower's is under `game`, as it always was. Any other
   * game's is under the key of its own id, with `gameId` saying which and `game` null, so an app
   * never has to guess what it is decoding.
   */
  private gameFields(controlled: Seat[]): Pick<RoomView, "game" | "gameId" | "tiles"> {
    const { state } = this;
    const view = state.gameState === null ? null : this.game.view(state.gameState, controlled);
    if (state.game !== "tiles") return { game: view as CatTowerView | null };
    return { game: null, gameId: "tiles", ...(view === null ? {} : { tiles: view as TilesView }) };
  }

  /** A game event as the room sends it: Cat Tower's as `game`, any other game's under its own id. */
  private gameEvent(event: unknown): RoomEvent {
    return this.state.game === "tiles"
      ? { kind: "tiles", event: event as TilesEvent }
      : { kind: "game", event: event as GameEvent };
  }

  /** Links are watched while a game is on with the feature on. */
  private linkWatched(): boolean {
    return this.features.link === true && this.state.status === "playing";
  }

  /** Each seat's link now; all null unless watched (and for every seat but a human's). */
  private seatLinks(): (SeatLink | null)[] {
    const now = this.now();
    const devices = Object.keys(this.state.devices);
    return this.state.seats.map((s, i) =>
      this.linkWatched() && s.kind === "human" ? this.link.seat(devices.filter((id) => this.controls(id, i)), now) : null,
    );
  }

  /** A `{t:"link"}` to every connected device (but `exclude`) when a seat's link changed since the last one. */
  private linkCheck(exclude?: string): Outbound[] {
    if (!this.features.link) return [];
    const seats = this.seatLinks();
    if (!this.link.show(seats)) return [];
    return Object.entries(this.state.devices)
      .filter(([id, device]) => device.connected && id !== exclude)
      .map(([id]) => ({ to: id, message: { t: "link", seats } }));
  }

  /** Seats of every player the device speaks for, plus seats with no player that the device holds. */
  controlledSeats(deviceId: string): Seat[] {
    const out: Seat[] = [];
    this.state.seats.forEach((_, i) => {
      if (this.controls(deviceId, i)) out.push(i);
    });
    return out;
  }

  private controls(deviceId: string, seat: Seat): boolean {
    // Callers have bounds-checked the seat.
    const s = this.state.seats[seat] as SeatInfo;
    if (s.playerId === undefined) return s.deviceId === deviceId;
    return Object.values(this.state.devices[deviceId]?.players ?? {}).includes(s.playerId);
  }

  /** The best presence among the devices that control the seat; away when none has been seen. */
  private seatPresence(seat: Seat): Presence {
    let best: Presence | null = null;
    for (const [id, device] of Object.entries(this.state.devices)) {
      if (!this.controls(id, seat)) continue;
      if (best === null || PRESENCE_RANK[device.presence] > PRESENCE_RANK[best]) best = device.presence;
    }
    return best ?? "away";
  }

  private dispatch(deviceId: string, msg: ClientMessage, unlocks: Unlocks): Outbound[] {
    switch (msg.t) {
      case "rematch":
        return this.features.streaks ? this.rematch(deviceId) : [this.fail(deviceId, "bad_message")];
      case "setLook":
        return this.features.streaks ? this.setLook(deviceId, msg, unlocks) : [this.fail(deviceId, "bad_message")];
      case "claim":
        return this.claim(deviceId, msg.seat, msg.person);
      case "configure":
        return this.configure(deviceId, msg.seat, msg.kind);
      case "start":
        return this.start(deviceId);
      case "leave":
        return this.leave(deviceId, msg.seat);
      case "moveSeat":
        return this.moveSeat(deviceId, msg.seat);
      case "claimMove":
        return this.claimMove(deviceId, msg.code);
      case "act":
        return this.act(deviceId, msg.seat, msg.action, msg.id);
      case "ping":
        // The Durable Object answers pings itself; one that gets here still gets its pong.
        return [{ to: deviceId, message: { t: "pong" } }];
      case "link":
        this.link.report(deviceId, msg.state === "weak");
        return this.linkCheck();
      case "presence":
        return this.presence(deviceId, msg.state);
      case "rename":
        return this.rename(deviceId, msg.name);
      case "renameSeat":
        return this.renameSeat(deviceId, msg.seat, msg.name);
      case "nudge":
        return this.features.nudge ? this.nudge(deviceId, msg.seat) : [this.fail(deviceId, "bad_message")];
      case "retire":
        return this.retire(deviceId, msg.seat);
      default:
        return [this.fail(deviceId, "bad_message")];
    }
  }

  private claim(deviceId: string, seat: Seat, person: Person): Outbound[] {
    const target = this.state.seats[seat];
    if (this.state.status !== "lobby") return [this.fail(deviceId, "not_lobby")];
    if (!target) return [this.fail(deviceId, "bad_seat")];
    // A person takes over a House Cat's seat (a first table's cat holds it for whoever comes).
    if (target.kind !== "open" && target.kind !== "bot") return [this.fail(deviceId, "seat_taken")];
    const playerId = this.state.devices[deviceId]?.players?.[person.id];
    if (this.state.seats.some((s) => s.person?.id === person.id || (playerId && s.playerId === playerId))) {
      return [this.fail(deviceId, "person_seated")];
    }
    this.state.seats[seat] = { kind: "human", person, deviceId, ...(playerId ? { playerId } : {}) };
    return this.changed();
  }

  // MARK: nudges

  /** The seat a device nudges as: its first seat still in the game (null: none). */
  private nudger(deviceId: string): Seat | null {
    const out = this.outSeats();
    return this.controlledSeats(deviceId).find((seat) => out[seat] !== true) ?? null;
  }

  /** When the current turn began; an older room's (no record) counts from its last activity. */
  private turnStartedAt(): number {
    const { turnAt } = this.state;
    return turnAt && turnAt.turn === this.turnKey() ? turnAt.at : this.state.lastActivity;
  }

  /** Whether `from` may nudge this turn now: already did, or how long until it may (0: now). */
  private nudgeState(from: Seat, now: number): { sent: boolean; wait: number } {
    const last = this.state.nudges?.[String(from)];
    if (last?.turn === this.turnKey()) return { sent: true, wait: 0 };
    const ready = Math.max(
      this.turnStartedAt() + NUDGE_AFTER_MS / this.speed,
      last ? last.at + NUDGE_EVERY_MS / this.speed : -Infinity,
    );
    return { sent: false, wait: Math.max(0, Math.ceil(ready - now)) };
  }

  /**
   * The seat this device could nudge now: mid-round, the move with a person on another phone
   * (never a bot, never one of this device's seats), and this device still in the game.
   */
  private nudgeTarget(deviceId: string): { seat: Seat; from: Seat } | null {
    const { state } = this;
    if (!this.midGame()) return null;
    const seat = this.actor();
    if (seat === null || state.seats[seat]?.kind !== "human" || this.controls(deviceId, seat)) return null;
    const from = this.nudger(deviceId);
    return from === null ? null : { seat, from };
  }

  /** A snapshot's `nudge` for this device (`NUDGE` on): absent when there's nobody to nudge. */
  private nudgeField(deviceId: string): { nudge?: NudgeView } {
    if (!this.features.nudge) return {};
    const target = this.nudgeTarget(deviceId);
    if (!target) return {};
    return { nudge: { seat: target.seat, ...this.nudgeState(target.from, this.now()) } };
  }

  /**
   * Nudges the person whose move it is (`NUDGE`): once per turn per nudging seat, not before the
   * turn is `NUDGE_AFTER_MS` old, and `NUDGE_EVERY_MS` after that seat's last nudge here. Their
   * devices at the table get `nudged` (the app shows it); anyone not at the table gets a push.
   */
  private nudge(deviceId: string, seat: Seat): Outbound[] {
    const { state } = this;
    if (!this.midGame()) return [this.fail(deviceId, "not_playing")];
    const target = state.seats[seat];
    if (!target || target.kind !== "human" || this.controls(deviceId, seat)) return [this.fail(deviceId, "bad_seat")];
    const from = this.nudger(deviceId);
    if (from === null) return [this.fail(deviceId, "not_seated")];
    if (this.actor() !== seat) return [this.fail(deviceId, "not_their_turn")];
    const now = this.now();
    const ready = this.nudgeState(from, now);
    if (ready.sent || ready.wait > 0) return [this.fail(deviceId, "too_soon")];
    state.nudges = { ...state.nudges, [String(from)]: { turn: this.turnKey(), at: now } };
    const out: Outbound[] = [{ to: deviceId, message: { t: "nudgeSent", seat } }];
    for (const [id, device] of Object.entries(state.devices)) {
      if (device.connected && this.controls(id, seat)) out.push({ to: id, message: { t: "nudged", seat, from } });
    }
    const sender = state.seats[from] as SeatInfo;
    // Someone at the table sees it there; a push would only say it twice.
    if (this.seatPresence(seat) !== "awake" && target.playerId) {
      const person = sender.person as Person;
      this.nudgeIntents.push({
        playerId: target.playerId,
        seat,
        personName: (target.person as Person).name,
        tableName: state.name,
        code: state.code,
        from: { name: person.name, cat: person.cat },
        fromPlayer: sender.playerId ?? null,
      });
    }
    return out;
  }

  // MARK: retiring a stalled seat

  /** When the move has waited since: the current turn's start mid-round, else null. */
  waitingSince(): number | null {
    return this.midGame() ? this.turnStartedAt() : null;
  }

  /** Ms until the current turn's seat may be retired (0: now). */
  private retireWait(now: number): number {
    return Math.max(0, Math.ceil(this.turnStartedAt() + RETIRE_AFTER_MS / this.speed - now));
  }

  /** A snapshot's `retire` for this device: the stalled seat it may retire, and how long until it may. */
  private retireField(deviceId: string): { retire?: RetireView } {
    const target = this.nudgeTarget(deviceId);
    return target ? { retire: { seat: target.seat, wait: this.retireWait(this.now()) } } : {};
  }

  /**
   * The seat holding the move when someone could retire it: a person's, with a device at the
   * table that doesn't control it and still has a seat in the game.
   */
  private stalledSeat(): Seat | null {
    const { state } = this;
    if (!this.midGame()) return null;
    const seat = this.actor();
    if (seat === null || state.seats[seat]?.kind !== "human") return null;
    const other = Object.keys(state.devices).some((id) => !this.controls(id, seat) && this.nudger(id) !== null);
    return other ? seat : null;
  }

  /** When the current turn's holder should be warned; null with nobody to warn, or once warned. */
  private retireWarningAt(): number | null {
    if (this.stalledSeat() === null || this.state.retireWarned === this.turnKey()) return null;
    return this.turnStartedAt() + (RETIRE_AFTER_MS - RETIRE_WARNING_MS) / this.speed;
  }

  /** Once per turn, a day before the seat becomes retirable: a push to its holder. */
  private warnStalled(): void {
    const at = this.retireWarningAt();
    if (at === null || at > this.now()) return;
    const { state } = this;
    const seat = this.stalledSeat() as Seat;
    const holder = state.seats[seat] as SeatInfo;
    state.retireWarned = this.turnKey();
    if (!holder.playerId) return;
    this.retireIntents.push({
      kind: "soon",
      playerId: holder.playerId,
      seat,
      personName: (holder.person as Person).name,
      tableName: state.name,
      code: state.code,
    });
  }

  /**
   * Retires a stalled seat: once the move has waited `RETIRE_AFTER_MS` on a person, anyone else
   * still in the game (on another phone) forfeits that seat for them, under the forfeit's own
   * rules (§5.13): out for the rest of the game, last place, the streak reports. One tap, no
   * vote: a vote would stall again on the next slow person. The holder is told by push.
   */
  private retire(deviceId: string, seat: Seat): Outbound[] {
    const { state } = this;
    if (!this.midGame()) return [this.fail(deviceId, "not_playing")];
    const target = state.seats[seat];
    if (!target || target.kind !== "human" || this.controls(deviceId, seat)) return [this.fail(deviceId, "bad_seat")];
    const from = this.nudger(deviceId);
    if (from === null) return [this.fail(deviceId, "not_seated")];
    if (this.actor() !== seat) return [this.fail(deviceId, "not_their_turn")];
    if (this.retireWait(this.now()) > 0) return [this.fail(deviceId, "too_soon")];
    // The seat on the move is in the game, so its forfeit is never refused.
    const applied = this.applyGame(seat, this.game.forfeitAction) as { out: Outbound[] };
    const sender = state.seats[from] as SeatInfo;
    if (target.playerId) {
      const person = sender.person as Person;
      this.retireIntents.push({
        kind: "done",
        playerId: target.playerId,
        seat,
        personName: (target.person as Person).name,
        tableName: state.name,
        code: state.code,
        from: { name: person.name, cat: person.cat },
        fromPlayer: sender.playerId ?? null,
      });
    }
    this.touch();
    const woke = this.wake(deviceId);
    this.afterGameChange();
    return [...applied.out, ...woke, ...this.snapshots()];
  }

  /**
   * Whether `deviceId` may rename now: at most `RENAMES_PER_WINDOW` renames (the table's and its
   * seats' together) every `RENAME_WINDOW_MS`. Counts the one being asked for.
   */
  private renameAllowed(deviceId: string): boolean {
    const now = this.now();
    const prior = this.state.renames?.[deviceId];
    const window = prior && now - prior.windowStart < RENAME_WINDOW_MS ? prior : { count: 0, windowStart: now };
    if (window.count >= RENAMES_PER_WINDOW) return false;
    this.state.renames = { ...this.state.renames, [deviceId]: { count: window.count + 1, windowStart: window.windowStart } };
    return true;
  }

  /**
   * The host, or any phone holding a seat, names the table in the lobby. Once the game has
   * started the name is frozen: it is on every phone and in push text, so it can't be changed
   * under the people playing.
   */
  private rename(deviceId: string, name: string): Outbound[] {
    const { state } = this;
    if (state.status === "over") return [this.fail(deviceId, "game_over")];
    if (state.status !== "lobby") return [this.fail(deviceId, "in_game")];
    if (deviceId !== state.hostDeviceId && this.controlledSeats(deviceId).length === 0) {
      return [this.fail(deviceId, "not_seated")];
    }
    if (name === state.name) return [];
    if (!this.renameAllowed(deviceId)) return [this.fail(deviceId, "too_soon")];
    state.name = name;
    return this.changed();
  }

  /**
   * Renames the person in one of the device's seats, in the lobby only (names are frozen once
   * the game has started), so every phone at the table sees the new name in its next snapshot.
   */
  private renameSeat(deviceId: string, seat: Seat, name: string): Outbound[] {
    if (this.state.status === "over") return [this.fail(deviceId, "game_over")];
    if (this.state.status !== "lobby") return [this.fail(deviceId, "in_game")];
    const target = this.state.seats[seat];
    if (!target) return [this.fail(deviceId, "bad_seat")];
    if (!this.controls(deviceId, seat) || !target.person) return [this.fail(deviceId, "not_your_seat")];
    if (target.person.name === name) return [];
    if (!this.renameAllowed(deviceId)) return [this.fail(deviceId, "too_soon")];
    target.person = { ...target.person, name };
    return this.changed();
  }

  private configure(deviceId: string, seat: Seat, kind: "open" | "bot" | "closed"): Outbound[] {
    const target = this.state.seats[seat];
    if (this.state.status !== "lobby") return [this.fail(deviceId, "not_lobby")];
    if (this.controlledSeats(deviceId).length === 0) return [this.fail(deviceId, "not_seated")];
    if (!target) return [this.fail(deviceId, "bad_seat")];
    if (target.kind === "human") return [this.fail(deviceId, "seat_taken")];
    this.state.seats[seat] = kind === "bot" ? { kind: "bot", botLevel: "house" } : { kind };
    return this.changed();
  }

  private start(deviceId: string): Outbound[] {
    const { state } = this;
    if (state.status !== "lobby") return [this.fail(deviceId, "not_lobby")];
    if (this.controlledSeats(deviceId).length === 0) return [this.fail(deviceId, "not_seated")];
    if (state.seats.some((s) => s.kind === "open")) return [this.fail(deviceId, "seats_open")];
    const playing = state.seats.flatMap((s, i) =>
      s.kind === "human" || s.kind === "bot" ? [{ seat: s, from: i }] : [],
    );
    if (playing.length < this.game.minSeats) return [this.fail(deviceId, "not_enough_players")];
    return this.deal();
  }

  /** Anyone seated changes the table's rug or card back, from their own unlocks (§9.4, §17). */
  private setLook(deviceId: string, msg: { rug?: string; back?: string }, unlocks: Unlocks): Outbound[] {
    const seats = this.controlledSeats(deviceId);
    if (seats.length === 0) return [this.fail(deviceId, "not_seated")];
    const now = this.now();
    const last = this.state.lookChangedAt?.[deviceId];
    if (last !== undefined && now - last < LOOK_EVERY_MS) return [this.fail(deviceId, "too_soon")];
    const rugOk = msg.rug === undefined || msg.rug === DEFAULT_RUG || unlocks.rugs.includes(msg.rug);
    const backOk = msg.back === undefined || msg.back === DEFAULT_BACK || unlocks.backs.includes(msg.back);
    if (!rugOk || !backOk) return [this.fail(deviceId, "not_unlocked")];
    const look = { rug: msg.rug ?? this.look().rug, back: msg.back ?? this.look().back };
    this.state.look = look;
    this.state.lookChangedAt = { ...this.state.lookChangedAt, [deviceId]: now };
    return this.broadcast(() => ({ kind: "look", seat: seats[0] as Seat, ...look }));
  }

  /** "Play again" (§10.4): once the game is over, once per room, from anyone seated. */
  private rematch(deviceId: string): Outbound[] {
    const { state } = this;
    if (state.status !== "over") return [this.fail(deviceId, "not_over")];
    if (this.controlledSeats(deviceId).length === 0) return [this.fail(deviceId, "not_seated")];
    if (state.rematch) {
      const { code } = state.rematch;
      return code ? [{ to: deviceId, message: { t: "rematch", code } }] : [];
    }
    // The game was turned off since this table was dealt: it plays on to the end, and no new one is dealt.
    if (state.game !== DEFAULT_GAME && !this.features.games?.includes(state.game)) return [this.fail(deviceId, "game_off")];
    state.rematch = { code: null };
    this.rematchIntent = {
      name: state.name,
      look: this.look(),
      // The first seat rotates: everyone moves one on.
      seats: [...state.seats.slice(1), ...state.seats.slice(0, 1)].map((s) => ({ ...s })),
      hostDeviceId: deviceId,
      // The same game again. Cat Tower's intent is as it always was.
      ...(state.game === DEFAULT_GAME ? {} : { game: state.game }),
    };
    return [];
  }

  /** Four uint32 words from the room's rng, which is crypto-backed in production. */
  private newSeed(): Seed {
    const word = () => Math.floor(this.rng() * UINT32_RANGE);
    return [word(), word(), word(), word()];
  }

  private leave(deviceId: string, seat: Seat): Outbound[] {
    const target = this.state.seats[seat];
    if (this.state.status !== "lobby") return [this.fail(deviceId, "in_game")];
    if (!target) return [this.fail(deviceId, "bad_seat")];
    if (!this.controls(deviceId, seat)) return [this.fail(deviceId, "not_your_seat")];
    this.state.seats[seat] = { kind: "open" };
    this.dropMoveCodes((entry) => entry.seat === seat);
    return this.changed();
  }

  private moveSeat(deviceId: string, seat: Seat): Outbound[] {
    if (this.state.status === "over") return [this.fail(deviceId, "game_over")];
    const target = this.state.seats[seat];
    if (!target) return [this.fail(deviceId, "bad_seat")];
    if (!this.controls(deviceId, seat)) return [this.fail(deviceId, "not_your_seat")];

    const now = this.now();
    // One live code per seat; expired ones are pruned as we go.
    this.dropMoveCodes((entry) => entry.seat === seat || entry.expires <= now);
    let code = newMoveCode(this.rng);
    while (this.state.moveCodes[code]) code = newMoveCode(this.rng);
    this.state.moveCodes[code] = { seat, expires: now + MOVE_CODE_TTL_MS };
    // The code reaches only the sender and no other device's view changes,
    // so this is not a state-changing message: seq stays put.
    return [{ to: deviceId, message: { t: "moveCode", seat, code } }];
  }

  private claimMove(deviceId: string, code: string): Outbound[] {
    const { state } = this;
    if (state.status === "over") return [this.fail(deviceId, "game_over")];

    const now = this.now();
    const prior = state.moveFailures[deviceId];
    const failures = prior && now - prior.windowStart < MOVE_FAILURE_WINDOW_MS ? prior : undefined;
    if (failures && failures.count >= MAX_MOVE_FAILURES) {
      return [this.fail(deviceId, "too_many_attempts")];
    }

    const entry = state.moveCodes[code];
    if (!entry || entry.expires <= now) {
      delete state.moveCodes[code];
      state.moveFailures[deviceId] = {
        count: (failures?.count ?? 0) + 1,
        windowStart: failures?.windowStart ?? now,
      };
      return [this.fail(deviceId, "bad_code")];
    }

    // The seat goes to this device, whoever it speaks for.
    const moved = state.seats[entry.seat] as SeatInfo;
    moved.deviceId = deviceId;
    delete moved.playerId;
    delete state.moveCodes[code];
    return this.changed();
  }

  private dropMoveCodes(drop: (entry: { seat: Seat; expires: number }) => boolean): void {
    for (const [code, entry] of Object.entries(this.state.moveCodes)) {
      if (drop(entry)) delete this.state.moveCodes[code];
    }
  }

  private act(deviceId: string, seat: Seat, action: GameAction, id?: string): Outbound[] {
    const device = this.state.devices[deviceId];
    // Sent again after a reconnect, already applied: the snapshot says so.
    if (id !== undefined && device?.acks?.includes(id)) return [{ to: deviceId, message: this.snapshotFor(deviceId) }];
    if (!this.controlledSeats(deviceId).includes(seat)) return [this.fail(deviceId, "not_your_seat")];
    if (this.state.status !== "playing") return [this.fail(deviceId, "not_playing")];
    const turn = this.turnKey();
    const applied = this.applyGame(seat, action);
    if ("error" in applied) return [this.fail(deviceId, applied.error)];
    if (id !== undefined && device) device.acks = [...(device.acks ?? []), id].slice(-ACKS_KEPT);
    const mover = this.state.seats[seat]?.playerId;
    const ended = this.game.endsTurn(action, applied.events, seat);
    if (mover && ended) this.turnBy = mover;
    if (ended) this.movedBy = (this.state.seats[seat] as SeatInfo).person as Person;
    this.dismissPushed(deviceId, seat, turn);
    this.touch();
    // Acting proves the device is in use, whatever it last reported.
    const woke = this.wake(deviceId);
    this.afterGameChange();
    return [...applied.out, ...woke, ...this.snapshots()];
  }

  /**
   * Once a player acts on a turn that was pushed, their other devices are
   * told to clear that notification. Once per turn.
   */
  private dismissPushed(deviceId: string, seat: Seat, turn: string): void {
    const { state } = this;
    const playerId = state.seats[seat]?.playerId;
    if (!playerId || state.pushedForTurn !== turn || state.dismissedForTurn === turn) return;
    state.dismissedForTurn = turn;
    this.pushIntents.push({ kind: "dismiss", playerId, exceptDeviceId: deviceId, code: state.code });
  }

  private turnKey(): string {
    return `${this.game.turnKey(this.state.gameState as S)}:${this.state.turnSeq}`;
  }

  /** Marks a device awake; returns the presence events if that was a change. */
  private wake(deviceId: string): Outbound[] {
    this.endLive(deviceId, "back");
    const device = this.state.devices[deviceId];
    if (!device || device.presence === "awake") return [];
    return this.presenceChange(deviceId, () => {
      device.presence = "awake";
      device.since = this.now();
    });
  }

  private presence(deviceId: string, state: "active" | "background"): Outbound[] {
    if (state === "active") return this.wake(deviceId);
    const device = this.state.devices[deviceId];
    if (!device || device.presence === "away") return [];
    const wasAwake = device.presence === "awake";
    const out = this.presenceChange(deviceId, () => {
      device.presence = "away";
      device.since = this.now();
    });
    if (wasAwake) this.maybeStartLive(deviceId);
    return out;
  }

  /**
   * Applies a game action. On success the new state is stored, every event
   * gets its own seq and each connected device receives its filtered copy.
   * On failure nothing changes. The events only animate: every caller that
   * applies an action successfully then runs `afterGameChange()` and sends
   * each connected device its own snapshot at the seq of the last event
   * (`snapshots()`), which carries the truth (drawn cards, a fresh deal, the
   * new discard top, a finished room).
   */
  private applyGame(seat: Seat, action: unknown): { out: Outbound[]; events: AnyGameEvent[] } | { error: GameError } {
    const { state } = this;
    const result = this.game.apply(state.gameState as S, seat, action);
    if (!result.ok) return { error: result.error };
    state.gameState = result.state;
    const out = result.events.flatMap((event) => {
      if (this.game.startsTurn(event)) state.turnSeq = state.seq + 1;
      return this.broadcast((deviceId) => this.gameEvent(this.game.filterEvent(event, this.controlledSeats(deviceId))));
    });
    return { out, events: result.events as AnyGameEvent[] };
  }

  /**
   * A tick's own action: applied, then timers and pushes follow the new state
   * and, on success, every device gets its snapshot.
   */
  private applyAndAfter(seat: Seat, action: unknown): Outbound[] {
    const applied = this.applyGame(seat, action);
    this.afterGameChange();
    return "out" in applied ? [...applied.out, ...this.snapshots()] : [];
  }

  private botStep(): Outbound[] {
    const game = this.state.gameState as S;
    const actor = this.game.currentActor(game) as Seat;
    const action = this.game.botAction(game, actor, this.rng);
    let applied = this.applyGame(actor, action);
    // The bot should never be rejected. If it is, make a plain legal move (the
    // game's own `fallbackAction`) so the game cannot stall.
    if ("error" in applied) applied = this.applyGame(actor, this.game.fallbackAction(game, actor));
    if ("error" in applied) {
      // Retrying would spin forever: stop the bot clock and report it.
      this.state.timers.botAt = null;
      return [{ to: "all", message: { t: "error", code: "bot_stalled" } }];
    }
    this.afterGameChange();
    return [...applied.out, ...this.snapshots()];
  }

  /**
   * Re-derives the timers after any game change, closes the room when the
   * game is over, and queues a push when a human's turn begins while their
   * device is not awake.
   */
  private afterGameChange(): void {
    const { state } = this;
    const { timers } = state;
    const phase = this.game.phase(state.gameState as S);
    const now = this.now();
    this.queueStreak(phase === "over");
    const from = this.movedBy;
    this.movedBy = null;
    this.liveAfterGame(from);

    if (phase === "over") {
      state.status = "over";
      // A finished game keeps the short limit, from its last move.
      timers.cleanupAt = state.lastActivity + CLEANUP_AFTER_MS;
      timers.botAt = null;
      timers.nextRoundAt = null;
      return;
    }
    if (phase === "between") {
      timers.nextRoundAt = now + NEXT_ROUND_DELAY_MS / this.speed;
      timers.botAt = null;
      return;
    }

    timers.nextRoundAt = null;
    const turn = this.turnKey();
    if (state.turnAt?.turn !== turn) state.turnAt = { turn, at: now };
    const actor = this.actor() as Seat;
    const seat = state.seats[actor] as SeatInfo;
    if (seat.kind === "bot") {
      timers.botAt = now + BOT_DELAY_MS / this.speed;
      return;
    }
    timers.botAt = null;

    const key = this.turnKey();
    if (this.seatPresence(actor) !== "awake" && state.pushedForTurn !== key) {
      state.pushedForTurn = key;
      this.pushIntents.push({
        deviceId: seat.deviceId as string,
        kind: "your_turn",
        ...(seat.playerId ? { playerId: seat.playerId } : {}),
        seat: actor,
        personName: (seat.person as Person).name,
        tableName: state.name,
        code: state.code,
        ...(this.features.streaks && from ? { from: { name: from.name, cat: from.cat } } : {}),
      });
    }
  }

  /**
   * Queues a report for the pairs at the table (§13.3) when a player ended a
   * turn, the move went somewhere new, or the table stopped being in play.
   */
  private queueStreak(over: boolean): void {
    const by = this.turnBy;
    this.turnBy = null;
    if (!this.features.streaks) return;
    const { state } = this;
    const now = this.now();
    const out = this.outPlayers();
    // Only a closing lobby reports with no game, and that report is `over`.
    const status = over ? "over" : STREAK_STATUS[this.game.phase(state.gameState as S)];
    // A forfeit is news to the pairs even when the move stays put.
    const key = `${state.turnSeq}:${status}${out.length > 0 ? `:out${out.length}` : ""}`;
    if (by === null && key === state.streakKey) return;
    state.streakKey = key;
    if (by) state.streakTurns = { ...state.streakTurns, [by]: now };
    const actor = over ? null : this.actor();
    const holder = actor === null ? null : (state.seats[actor]?.playerId ?? null);
    this.streakIntents.push({
      code: state.code,
      at: now,
      by,
      holder,
      players: this.seatPlayers(),
      turnedAt: { ...state.streakTurns },
      over,
      ...(out.length > 0 ? { out } : {}),
    });
  }

  /** The players at the table whose every seat forfeited (§5.13). */
  outPlayers(): string[] {
    const out = this.outSeats();
    return this.seatPlayers().filter((playerId) => this.state.seats.every((s, i) => s.playerId !== playerId || out[i] === true));
  }

  /** True when the seats `seats` all forfeited: the game is over for whoever holds them (§5.13). */
  allOut(seats: readonly Seat[]): boolean {
    const out = this.outSeats();
    return seats.length > 0 && seats.every((seat) => out[seat] === true);
  }

  /**
   * Applies a change to one device's presence and returns a presence event
   * for each of its seats whose presence, the best of all the devices that
   * control it, changed as a result.
   */
  private presenceChange(deviceId: string, change: () => void, exclude?: string): Outbound[] {
    const before = this.state.seats.map((_, i) => this.seatPresence(i));
    change();
    return this.controlledSeats(deviceId).flatMap((seat) => {
      const presence = this.seatPresence(seat);
      return presence === before[seat] ? [] : this.broadcast(() => ({ kind: "presence", seat, presence }), exclude);
    });
  }

  /** Gives `event` the next seq and addresses it to each connected device. */
  private broadcast(event: (deviceId: string) => RoomEvent, exclude?: string): Outbound[] {
    this.state.seq += 1;
    const { seq } = this.state;
    return Object.entries(this.state.devices)
      .filter(([id, device]) => device.connected && id !== exclude)
      .map(([id]) => ({ to: id, message: { t: "event", seq, event: event(id) } }));
  }

  /** How long the room lasts with nothing happening: longer once a game is in play. */
  private cleanupAfter(): number {
    return this.state.status === "playing" ? GAME_CLEANUP_AFTER_MS : CLEANUP_AFTER_MS;
  }

  private touch(): void {
    const now = this.now();
    this.state.lastActivity = now;
    this.state.timers.cleanupAt = now + this.cleanupAfter();
  }

  /** Records a state change and sends every connected device its own snapshot. */
  private changed(): Outbound[] {
    this.state.seq += 1;
    this.touch();
    return this.snapshots();
  }

  /** Every connected device's own snapshot at the current seq. */
  private snapshots(): Outbound[] {
    return Object.entries(this.state.devices)
      .filter(([, device]) => device.connected)
      .map(([id]) => ({ to: id, message: this.snapshotFor(id) }));
  }

  private fail(deviceId: string, code: ErrorCode): Outbound {
    return { to: deviceId, message: { t: "error", code } };
  }
}
