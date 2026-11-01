import { catTower } from "../games/cat-tower";
import { PROTOCOL_VERSION } from "../protocol";
import { card } from "../rules/cards";

import { newMoveCode } from "./codes";

import type { GameModule } from "../games/module";
import type {
  ClientMessage,
  ErrorCode,
  Person,
  Presence,
  RoomEvent,
  RoomStatus,
  RoomView,
  SeatKind,
  ServerMessage,
} from "../protocol";
import type { Action, ApplyError, CatTowerState, GameEvent, Seat } from "../rules/engine";
import type { Rng, Seed } from "../rules/rng";
import type { CatTowerView } from "../rules/view";

export type CatTowerModule = GameModule<CatTowerState, Action, CatTowerView, GameEvent, ApplyError>;

export type SeatInfo = {
  kind: SeatKind;
  person?: Person;
  deviceId?: string;
  botLevel?: "house";
};

export type RoomState = {
  code: string;
  game: "cat-tower";
  hostDeviceId: string;
  status: RoomStatus;
  /** Length 6 in the lobby; compacted to the game's seats on start. */
  seats: SeatInfo[];
  gameState: CatTowerState | null;
  seq: number;
  lastActivity: number;
  devices: Record<string, { presence: Presence; since: number; connected: boolean }>;
  moveCodes: Record<string, { seat: Seat; expires: number }>;
  /** Failed `claimMove` attempts per device, within a rolling window. */
  moveFailures: Record<string, { count: number; windowStart: number }>;
  timers: { botAt: number | null; nextRoundAt: number | null; cleanupAt: number };
  /** "<round>:<turn>:<turnSeq>" dedupe key for turn pushes. */
  pushedForTurn: string | null;
  /** Seq of the latest `turn` or `roundStarted` event: tells one turn from the next. */
  turnSeq: number;
};

export type PushIntent = {
  deviceId: string;
  kind: "your_turn";
  seat: Seat;
  personName: string;
  /** The room code, so the app can open the right game from the notification. */
  code: string;
};

export type Outbound = {
  /** "all" or a deviceId. */
  to: "all" | string;
  message: ServerMessage;
};

type Snapshot = Extract<ServerMessage, { t: "snapshot" }>;

const LOBBY_SEATS = 6;
const MS_PER_MINUTE = 60_000;
const CLEANUP_AFTER_MS = 7 * 24 * 60 * MS_PER_MINUTE;
const MOVE_CODE_TTL_MS = 10 * MS_PER_MINUTE;
const MOVE_FAILURE_WINDOW_MS = 10 * MS_PER_MINUTE;
const MAX_MOVE_FAILURES = 5;
const UINT32_RANGE = 2 ** 32;
const BOT_DELAY_MS = 1200;
const NEXT_ROUND_DELAY_MS = 6000;
const ASLEEP_AFTER_MS = 5 * MS_PER_MINUTE;

/**
 * The room state machine. Pure: it mutates `state` and returns the messages
 * to deliver; the Durable Object persists the state and does the delivery.
 */
export class RoomCore {
  state: RoomState;
  private readonly now: () => number;
  private readonly rng: Rng;
  private readonly game: CatTowerModule;
  /** Not persisted: the Durable Object drains it after every call. */
  private pushIntents: PushIntent[] = [];

  constructor(state: RoomState, now: () => number, rng: Rng, game: CatTowerModule = catTower) {
    this.state = state;
    this.now = now;
    this.rng = rng;
    this.game = game;
  }

  static create(code: string, hostDeviceId: string, now: number): RoomState {
    return {
      code,
      game: "cat-tower",
      hostDeviceId,
      status: "lobby",
      seats: Array.from({ length: LOBBY_SEATS }, (_, i): SeatInfo => ({
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

  /** Never throws: any unexpected failure becomes `error: internal`. */
  handle(deviceId: string, msg: ClientMessage): Outbound[] {
    try {
      return this.dispatch(deviceId, msg);
    } catch {
      return [this.fail(deviceId, "internal")];
    }
  }

  connect(deviceId: string): Outbound[] {
    const wasAwake = this.state.devices[deviceId]?.presence === "awake";
    this.state.devices[deviceId] = { presence: "awake", since: this.now(), connected: true };
    // Everyone else hears about the seat holder waking up; the connecting
    // device gets a snapshot that already includes those events' seq.
    const events = wasAwake ? [] : this.presenceEvents(deviceId, "awake", deviceId);
    return [...events, { to: deviceId, message: this.snapshotFor(deviceId) }];
  }

  disconnect(deviceId: string): Outbound[] {
    const device = this.state.devices[deviceId];
    if (!device) return [];
    const wasAway = device.presence === "away";
    device.connected = false;
    device.presence = "away";
    if (!wasAway) device.since = this.now();
    return wasAway ? [] : this.presenceEvents(deviceId, "away");
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
      out.push(...this.applyAndAfter(0, { type: "nextRound" }));
    }

    if (timers.botAt !== null && timers.botAt <= this.now()) {
      timers.botAt = null;
      out.push(...this.botStep());
    }

    for (const [deviceId, device] of Object.entries(state.devices)) {
      if (device.presence === "away" && device.since + ASLEEP_AFTER_MS <= this.now()) {
        device.presence = "asleep";
        device.since = this.now();
        out.push(...this.presenceEvents(deviceId, "asleep"));
      }
    }

    if (timers.cleanupAt <= this.now()) {
      state.status = "over";
      out.push({ to: "all", message: { t: "error", code: "room_closed" } });
    }
    return out;
  }

  nextAlarm(): number {
    const { botAt, nextRoundAt, cleanupAt } = this.state.timers;
    const decays = Object.values(this.state.devices)
      .filter((device) => device.presence === "away")
      .map((device) => device.since + ASLEEP_AFTER_MS);
    return Math.min(
      ...[botAt, nextRoundAt, cleanupAt, ...decays].filter((t): t is number => t !== null),
    );
  }

  /** Hands over and forgets the pushes queued since the last call. */
  drainPushIntents(): PushIntent[] {
    const drained = this.pushIntents;
    this.pushIntents = [];
    return drained;
  }

  snapshotFor(deviceId: string): Snapshot {
    const { state } = this;
    const controlled = this.controlledSeats(deviceId);
    const seats: RoomView["seats"] = state.seats.map((s) => ({
      kind: s.kind,
      ...(s.person ? { person: s.person } : {}),
      yours: s.deviceId === deviceId,
      presence: s.kind === "human" ? (state.devices[s.deviceId as string]?.presence ?? "away") : null,
    }));
    return {
      t: "snapshot",
      protocol: PROTOCOL_VERSION,
      seq: state.seq,
      room: {
        code: state.code,
        status: state.status,
        youAreHost: deviceId === state.hostDeviceId,
        seats,
        game: state.gameState ? this.game.view(state.gameState, controlled) : null,
      },
    };
  }

  controlledSeats(deviceId: string): Seat[] {
    const out: Seat[] = [];
    this.state.seats.forEach((s, i) => {
      if (s.deviceId === deviceId) out.push(i);
    });
    return out;
  }

  private dispatch(deviceId: string, msg: ClientMessage): Outbound[] {
    switch (msg.t) {
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
        return this.act(deviceId, msg.seat, msg.action);
      case "presence":
        return this.presence(deviceId, msg.state);
      default:
        return [this.fail(deviceId, "bad_message")];
    }
  }

  private claim(deviceId: string, seat: Seat, person: Person): Outbound[] {
    const target = this.state.seats[seat];
    if (this.state.status !== "lobby") return [this.fail(deviceId, "not_lobby")];
    if (!target) return [this.fail(deviceId, "bad_seat")];
    if (target.kind !== "open") return [this.fail(deviceId, "seat_taken")];
    if (this.state.seats.some((s) => s.person?.id === person.id)) {
      return [this.fail(deviceId, "person_seated")];
    }
    this.state.seats[seat] = { kind: "human", person, deviceId };
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

  /** Four uint32 words from the room's rng, which is crypto-backed in production. */
  private newSeed(): Seed {
    const word = () => Math.floor(this.rng() * UINT32_RANGE);
    return [word(), word(), word(), word()];
  }

  private leave(deviceId: string, seat: Seat): Outbound[] {
    const target = this.state.seats[seat];
    if (this.state.status !== "lobby") return [this.fail(deviceId, "in_game")];
    if (!target) return [this.fail(deviceId, "bad_seat")];
    if (target.deviceId !== deviceId) return [this.fail(deviceId, "not_your_seat")];
    this.state.seats[seat] = { kind: "open" };
    this.dropMoveCodes((entry) => entry.seat === seat);
    return this.changed();
  }

  private moveSeat(deviceId: string, seat: Seat): Outbound[] {
    if (this.state.status === "over") return [this.fail(deviceId, "game_over")];
    const target = this.state.seats[seat];
    if (!target) return [this.fail(deviceId, "bad_seat")];
    if (target.deviceId !== deviceId) return [this.fail(deviceId, "not_your_seat")];

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

    state.seats[entry.seat]!.deviceId = deviceId;
    delete state.moveCodes[code];
    return this.changed();
  }

  private dropMoveCodes(drop: (entry: { seat: Seat; expires: number }) => boolean): void {
    for (const [code, entry] of Object.entries(this.state.moveCodes)) {
      if (drop(entry)) delete this.state.moveCodes[code];
    }
  }

  private act(deviceId: string, seat: Seat, action: Action): Outbound[] {
    if (!this.controlledSeats(deviceId).includes(seat)) return [this.fail(deviceId, "not_your_seat")];
    if (this.state.status !== "playing") return [this.fail(deviceId, "not_playing")];
    const applied = this.applyGame(seat, action);
    if ("error" in applied) return [this.fail(deviceId, applied.error)];
    this.touch();
    // Acting proves the device is in use, whatever it last reported.
    const woke = this.wake(deviceId);
    this.afterGameChange();
    return [...applied.out, ...woke, ...this.snapshots()];
  }

  /** Marks a device awake; returns the presence events if that was a change. */
  private wake(deviceId: string): Outbound[] {
    const device = this.state.devices[deviceId];
    if (!device || device.presence === "awake") return [];
    device.presence = "awake";
    device.since = this.now();
    return this.presenceEvents(deviceId, "awake");
  }

  private presence(deviceId: string, state: "active" | "background"): Outbound[] {
    if (state === "active") return this.wake(deviceId);
    const device = this.state.devices[deviceId];
    if (!device || device.presence === "away") return [];
    device.presence = "away";
    device.since = this.now();
    return this.presenceEvents(deviceId, "away");
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
  private applyGame(seat: Seat, action: Action): { out: Outbound[] } | { error: ApplyError } {
    const { state } = this;
    const result = this.game.apply(state.gameState as CatTowerState, seat, action);
    if (!result.ok) return { error: result.error };
    state.gameState = result.state;
    const out = result.events.flatMap((event) => {
      if (event.kind === "turn" || event.kind === "roundStarted") state.turnSeq = state.seq + 1;
      return this.broadcast((deviceId) => ({
        kind: "game",
        event: this.game.filterEvent(event, this.controlledSeats(deviceId)),
      }));
    });
    return { out };
  }

  /**
   * A tick's own action: applied, then timers and pushes follow the new state
   * and, on success, every device gets its snapshot.
   */
  private applyAndAfter(seat: Seat, action: Action): Outbound[] {
    const applied = this.applyGame(seat, action);
    this.afterGameChange();
    return "out" in applied ? [...applied.out, ...this.snapshots()] : [];
  }

  private botStep(): Outbound[] {
    const game = this.state.gameState as CatTowerState;
    const actor = this.game.currentActor(game) as Seat;
    const action = this.game.botAction(game, actor, this.rng);
    let applied = this.applyGame(actor, action);
    // The bot should never be rejected. If it is, make a plain legal move so
    // the game cannot stall.
    if ("error" in applied) applied = this.applyGame(actor, this.fallbackAction(game, actor));
    if ("error" in applied) {
      // Retrying would spin forever: stop the bot clock and report it.
      this.state.timers.botAt = null;
      return [{ to: "all", message: { t: "error", code: "bot_stalled" } }];
    }
    this.afterGameChange();
    return [...applied.out, ...this.snapshots()];
  }

  /**
   * Draw from the deck; when playing, discard a number card, else Yarn, else
   * whatever is left (a Cucumber, aimed the way the engine requires).
   */
  private fallbackAction(game: CatTowerState, seat: Seat): Action {
    if (game.step === "draw") return { type: "draw", from: "deck" };
    const hand = game.hands[seat] as number[];
    const pick =
      hand.find((id) => card(id).kind === "number") ??
      hand.find((id) => card(id).kind === "yarn") ??
      (hand[0] as number);
    const target = Array.from({ length: game.seats }, (_, i) => i).find(
      (i) => i !== seat && !game.pendingSkip[i],
    );
    return card(pick).kind === "cucumber" && target !== undefined
      ? { type: "discard", card: pick, skipTarget: target }
      : { type: "discard", card: pick };
  }

  /**
   * Re-derives the timers after any game change, closes the room when the
   * game is over, and queues a push when a human's turn begins while their
   * device is not awake.
   */
  private afterGameChange(): void {
    const { state } = this;
    const { timers } = state;
    const game = state.gameState as CatTowerState;
    const now = this.now();

    if (game.status === "gameOver") {
      state.status = "over";
      timers.botAt = null;
      timers.nextRoundAt = null;
      return;
    }
    if (game.status === "roundOver") {
      timers.nextRoundAt = now + NEXT_ROUND_DELAY_MS;
      timers.botAt = null;
      return;
    }

    timers.nextRoundAt = null;
    const actor = this.game.currentActor(game) as Seat;
    const seat = state.seats[actor] as SeatInfo;
    if (seat.kind === "bot") {
      timers.botAt = now + BOT_DELAY_MS;
      return;
    }
    timers.botAt = null;

    const deviceId = seat.deviceId as string;
    const key = `${game.round}:${game.turn}:${state.turnSeq}`;
    const presence = state.devices[deviceId]?.presence ?? "away";
    if (presence !== "awake" && state.pushedForTurn !== key) {
      state.pushedForTurn = key;
      this.pushIntents.push({
        deviceId,
        kind: "your_turn",
        seat: actor,
        personName: (seat.person as Person).name,
        code: state.code,
      });
    }
  }

  /** One presence event per seat the device holds. */
  private presenceEvents(deviceId: string, presence: Presence, exclude?: string): Outbound[] {
    return this.controlledSeats(deviceId).flatMap((seat) =>
      this.broadcast(() => ({ kind: "presence", seat, presence }), exclude),
    );
  }

  /** Gives `event` the next seq and addresses it to each connected device. */
  private broadcast(event: (deviceId: string) => RoomEvent, exclude?: string): Outbound[] {
    this.state.seq += 1;
    const { seq } = this.state;
    return Object.entries(this.state.devices)
      .filter(([id, device]) => device.connected && id !== exclude)
      .map(([id]) => ({ to: id, message: { t: "event", seq, event: event(id) } }));
  }

  private touch(): void {
    const now = this.now();
    this.state.lastActivity = now;
    this.state.timers.cleanupAt = now + CLEANUP_AFTER_MS;
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
