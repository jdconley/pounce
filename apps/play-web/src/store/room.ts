/**
 * One table, as this device sees it (`RoomStore.swift`): the last snapshot, the events since,
 * paced so each one can be seen, and the move in flight. Events only animate; the snapshot that
 * follows them carries the truth and replaces what they folded in.
 */
import { PROTOCOL } from "../lib/env";
import { RoomSocket, type LinkQuality, type SocketEvent } from "../net/socket";

import type { ClientMessage, ErrorCode, GameAim, RoomEvent, RoomView, ServerMessage } from "@pounce/play-api/protocol";
import type { GameEvent, Action } from "@pounce/play-api/rules/engine";
import type { TilesAction, TilesEvent } from "@pounce/play-api/tiles/engine";


export type RoomPhase = "connecting" | "lobby" | "playing" | "over" | "closed" | "notFound" | "locked" | "needsUpdate";

export type Paced = { seq: number; event: RoomEvent };

export type RoomState = {
  code: string;
  phase: RoomPhase;
  /** The room as shown: the last snapshot with the events played so far folded in. */
  room: RoomView | null;
  /** The last snapshot as the server sent it. */
  truth: RoomView | null;
  online: boolean;
  /** Ever connected: an offline state before the first snapshot is just "connecting". */
  everConnected: boolean;
  link: LinkQuality;
  /** The move sent and not yet answered. */
  pending: { id: string; seat: number; action: Action | TilesAction } | null;
  /** The last error the server sent this device, with a counter so the same one twice is seen twice. */
  error: { code: ErrorCode; n: number } | null;
  moveCode: { seat: number; code: string } | null;
  rematch: string | null;
  /** Where each seat is pointing right now, for a screen to show. */
  aims: Record<number, GameAim>;
  /** A TV is showing this table. */
  screen: boolean;
};

/** The most aims sent: one per this many milliseconds (the server relays 10 a second). */
export const AIM_EVERY_MS = 120;

export type RoomListener = {
  /** A room event, as it is played (after the ones before it have had their moment). */
  event?: (e: Paced, room: RoomView | null) => void;
  change?: (s: RoomState) => void;
};

/** How long each kind of event holds the stage before the next one plays. */
export function eventPause(e: RoomEvent): number {
  if (e.kind === "game") {
    const k = e.event.kind;
    if (k === "roundOver") return 1600;
    if (k === "gameOver") return 600;
    if (k === "turn" || k === "reshuffled") return 120;
    if (k === "skipped") return 700;
    return 420;
  }
  if (e.kind === "tiles") {
    const k = e.event.kind;
    if (k === "played") return 700;
    if (k === "turn") return 120;
    return 380;
  }
  return 0;
}

/** Folds what an event says into the shown room, for timing only. The next snapshot replaces it. */
export function foldEvent(room: RoomView, e: RoomEvent): RoomView {
  if (e.kind === "presence") {
    const seats = room.seats.map((s, i) => (i === e.seat ? { ...s, presence: e.presence } : s));
    return { ...room, seats };
  }
  if (e.kind === "game" && room.game) return { ...room, game: foldCatTower(room.game, e.event) };
  if (e.kind === "tiles" && room.tiles) return { ...room, tiles: foldTiles(room.tiles, e.event) };
  return room;
}

function foldCatTower(g: NonNullable<RoomView["game"]>, e: GameEvent): NonNullable<RoomView["game"]> {
  const handCounts = [...g.handCounts];
  switch (e.kind) {
    case "drew": {
      handCounts[e.seat] = (handCounts[e.seat] ?? 0) + 1;
      const hands = { ...g.hands };
      if (e.card !== undefined && hands[e.seat]) hands[e.seat] = [...hands[e.seat], e.card];
      if (e.from === "deck") return { ...g, handCounts, hands, deckCount: Math.max(0, g.deckCount - 1), step: "play" };
      return { ...g, handCounts, hands, discardCount: Math.max(0, g.discardCount - 1), discardTop: null, step: "play" };
    }
    case "discarded": {
      handCounts[e.seat] = Math.max(0, (handCounts[e.seat] ?? 0) - 1);
      const hands = { ...g.hands };
      if (hands[e.seat]) hands[e.seat] = hands[e.seat].filter((c) => c !== e.card);
      return { ...g, handCounts, hands, discardTop: e.card, discardCount: g.discardCount + 1 };
    }
    case "laidDown": {
      const n = e.groups.reduce((sum, grp) => sum + grp.cards.length, 0);
      handCounts[e.seat] = Math.max(0, (handCounts[e.seat] ?? 0) - n);
      const laid = [...g.laid];
      laid[e.seat] = e.groups;
      const hands = { ...g.hands };
      const used = new Set(e.groups.flatMap((grp) => grp.cards));
      if (hands[e.seat]) hands[e.seat] = hands[e.seat].filter((c) => !used.has(c));
      return { ...g, handCounts, laid, hands };
    }
    case "hit": {
      handCounts[e.seat] = Math.max(0, (handCounts[e.seat] ?? 0) - 1);
      const laid = [...g.laid];
      const groups = [...(laid[e.target.seat] ?? [])];
      groups[e.target.group] = e.group;
      laid[e.target.seat] = groups;
      const hands = { ...g.hands };
      if (hands[e.seat]) hands[e.seat] = hands[e.seat].filter((c) => c !== e.card);
      return { ...g, handCounts, laid, hands };
    }
    case "turn":
      return { ...g, turn: e.seat, step: "draw" };
    case "roundOver":
      return { ...g, status: "roundOver", scores: e.scores, phase: e.phase };
    case "gameOver":
      return { ...g, status: "gameOver", winners: e.winners };
    case "forfeited": {
      const forfeited = [...g.forfeited];
      forfeited[e.seat] = true;
      return { ...g, forfeited };
    }
    default:
      return g;
  }
}

function foldTiles(t: NonNullable<RoomView["tiles"]>, e: TilesEvent): NonNullable<RoomView["tiles"]> {
  const rackCounts = [...t.rackCounts];
  switch (e.kind) {
    case "drew": {
      rackCounts[e.seat] = (rackCounts[e.seat] ?? 0) + 1;
      const racks = { ...t.racks };
      if (e.tile !== undefined && racks[e.seat]) racks[e.seat] = [...racks[e.seat], e.tile];
      return { ...t, rackCounts, racks, poolCount: e.poolCount };
    }
    case "played": {
      rackCounts[e.seat] = Math.max(0, (rackCounts[e.seat] ?? 0) - e.placed.length);
      const racks = { ...t.racks };
      const placed = new Set(e.placed);
      if (racks[e.seat]) racks[e.seat] = racks[e.seat].filter((id) => !placed.has(id));
      const opened = [...t.opened];
      opened[e.seat] = true;
      return { ...t, rackCounts, racks, table: e.table, opened };
    }
    case "passed": {
      const passed = [...t.passed];
      passed[e.seat] = true;
      return { ...t, passed };
    }
    case "turn":
      return { ...t, turn: e.seat };
    case "forfeited": {
      const forfeited = [...t.forfeited];
      forfeited[e.seat] = true;
      return { ...t, forfeited };
    }
    case "gameOver":
      return { ...t, status: "gameOver", winners: e.winners, scores: e.scores };
    default:
      return t;
  }
}

export function phaseOf(room: RoomView | null): RoomPhase {
  if (!room) return "connecting";
  if (room.status === "lobby") return "lobby";
  if (room.status === "over") return "over";
  return "playing";
}

/** A room's turn and status, as one comparable value: when it changes, shown aims are stale. */
function turnAndStatus(room: RoomView): string {
  const g = room.game ?? room.tiles;
  return `${room.status}|${g?.status ?? ""}|${g?.turn ?? ""}`;
}

export function newMoveId(): string {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
  return [...crypto.getRandomValues(new Uint8Array(16))].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export type RoomStoreOptions = {
  code: string;
  token: () => Promise<string>;
  dropToken?: () => void;
  origin?: string;
  socket?: RoomSocket;
  /** Paced timers; tests pass instant ones. */
  setTimer?: (fn: () => void, ms: number) => unknown;
  clearTimer?: (id: unknown) => void;
  reducedMotion?: () => boolean;
  /** "screen": this device is the table's TV, not a seat at it. */
  role?: "screen";
  now?: () => number;
};

export class RoomStore {
  state: RoomState;
  readonly socket: RoomSocket;
  private listeners = new Set<RoomListener>();
  private queue: Paced[] = [];
  private playing = false;
  private pendingSnapshot: { seq: number; room: RoomView } | null = null;
  /**
   * The move the server applied (or, without move ids, answered) while events were still queued,
   * and the seq of that answer: the move settles the moment the event at that seq is shown, so a
   * tap the table shows as live after it always counts, however much else is queued behind.
   */
  private settle: { id: string; seq: number } | null = null;
  /** The seq of the last event put on stage. */
  private shownSeq = -1;
  private errorCount = 0;
  private timer: unknown = null;
  private readonly setTimer: (fn: () => void, ms: number) => unknown;
  private readonly clearTimer: (id: unknown) => void;
  private readonly reducedMotion: () => boolean;
  /** The seq of the last snapshot or event applied. */
  private seq = -1;
  /** Counts connections, so a move is sent again only on a connection that didn't carry it. */
  private connection = 0;
  private sentOn = -1;
  private readonly now: () => number;
  private lastAimAt = -Infinity;
  private trailingAim: { seat: number; aim: GameAim } | null = null;
  private aimTimer: unknown = null;

  constructor(options: RoomStoreOptions) {
    this.state = {
      code: options.code,
      phase: "connecting",
      room: null,
      truth: null,
      online: false,
      everConnected: false,
      link: "good",
      pending: null,
      error: null,
      moveCode: null,
      rematch: null,
      aims: {},
      screen: false,
    };
    this.now = options.now ?? (() => performance.now());
    this.setTimer = options.setTimer ?? ((fn, ms) => setTimeout(fn, ms));
    this.clearTimer = options.clearTimer ?? ((id) => clearTimeout(id as ReturnType<typeof setTimeout>));
    this.reducedMotion = options.reducedMotion ?? (() => false);
    this.socket =
      options.socket ??
      new RoomSocket({ code: options.code, token: options.token, dropToken: options.dropToken, origin: options.origin, role: options.role });
    this.socket.on((e) => this.onSocket(e));
  }

  subscribe(listener: RoomListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  start(): void {
    this.socket.start();
  }

  stop(): void {
    if (this.timer !== null) this.clearTimer(this.timer);
    if (this.aimTimer !== null) this.clearTimer(this.aimTimer);
    this.aimTimer = this.trailingAim = null;
    this.socket.stop();
  }

  private set(patch: Partial<RoomState>): void {
    this.state = { ...this.state, ...patch };
    for (const l of [...this.listeners]) l.change?.(this.state);
  }

  /** Sends a lobby or room message. False when offline. */
  send(message: ClientMessage): boolean {
    return this.socket.send(message);
  }

  /** Sends a move with a move id; it is sent again after a reconnect unless the server applied it. */
  act(seat: number, action: Action | TilesAction): boolean {
    if (this.state.pending) return false;
    const id = newMoveId();
    this.set({ pending: { id, seat, action } });
    if (this.socket.send({ t: "act", seat, action, id })) this.sentOn = this.connection;
    return true;
  }

  /** Leaves the game for good for `seat` (any time, anyone's turn), with a move id like any move. */
  forfeit(seat: number): boolean {
    return this.socket.send({ t: "act", seat, action: { type: "forfeit" }, id: newMoveId() });
  }

  /**
   * Tells the table's TV where `seat` is pointing, or (null) that it stopped. The first aim goes at
   * once, then at most one per `AIM_EVERY_MS` with the latest value last; a clear goes at once and
   * drops any aim still waiting.
   */
  aim(seat: number, aim: GameAim | null): void {
    if (aim === null) {
      if (this.aimTimer !== null) this.clearTimer(this.aimTimer);
      this.aimTimer = this.trailingAim = null;
      this.socket.send({ t: "aim", seat });
      return;
    }
    const wait = this.lastAimAt + AIM_EVERY_MS - this.now();
    if (wait <= 0 && this.aimTimer === null) {
      this.sendAim(seat, aim);
      return;
    }
    this.trailingAim = { seat, aim };
    if (this.aimTimer !== null) return;
    this.aimTimer = this.setTimer(() => {
      this.aimTimer = null;
      const last = this.trailingAim;
      this.trailingAim = null;
      if (last) this.sendAim(last.seat, last.aim);
    }, Math.max(0, wait));
  }

  private sendAim(seat: number, aim: GameAim): void {
    this.lastAimAt = this.now();
    this.socket.send({ t: "aim", seat, aim });
  }

  /** The aims that survive a new snapshot: all of them, unless the turn or status moved on. */
  private aimsAfter(next: RoomView): Record<number, GameAim> {
    const prev = this.state.truth;
    if (!prev || Object.keys(this.state.aims).length === 0) return this.state.aims;
    return turnAndStatus(prev) === turnAndStatus(next) ? this.state.aims : {};
  }

  private onSocket(e: SocketEvent): void {
    switch (e.kind) {
      case "connected":
        this.connection += 1;
        this.set({ online: true, everConnected: true, link: "good" });
        return;
      case "disconnected":
      case "connecting":
        if (this.state.online) this.set({ online: false });
        return;
      case "link":
        this.set({ link: e.quality });
        return;
      case "notFound":
        this.set({ phase: "notFound", online: false });
        return;
      case "locked":
        this.set({ phase: "locked", online: false });
        return;
      case "closed":
        this.set({ phase: "closed", online: false });
        return;
      case "refused":
        this.set({ phase: "needsUpdate", online: false });
        return;
      case "message":
        this.onMessage(e.message);
    }
  }

  private onMessage(m: ServerMessage): void {
    switch (m.t) {
      case "snapshot":
        if (m.protocol !== PROTOCOL) {
          this.set({ phase: "needsUpdate" });
          return;
        }
        this.onSnapshot(m.seq, m.room);
        return;
      case "event":
        if (m.seq <= this.seq) return;
        this.seq = m.seq;
        this.queue.push({ seq: m.seq, event: m.event });
        this.pump();
        return;
      case "error": {
        this.errorCount += 1;
        // A refused move: nothing is in flight any more.
        this.set({ error: { code: m.code, n: this.errorCount }, pending: null });
        return;
      }
      case "moveCode":
        this.set({ moveCode: { seat: m.seat, code: m.code } });
        return;
      case "rematch":
        this.set({ rematch: m.code });
        return;
      case "aim": {
        const aims = { ...this.state.aims };
        if (m.aim) aims[m.seat] = m.aim;
        else delete aims[m.seat];
        this.set({ aims });
        return;
      }
      case "link": {
        const room = this.state.room;
        if (!room) return;
        const seats = room.seats.map((s, i) => {
          const link = m.seats[i];
          const rest = { ...s };
          delete rest.link;
          return link ? { ...rest, link } : rest;
        });
        this.set({ room: { ...room, seats } });
        return;
      }
      default:
        return;
    }
  }

  private onSnapshot(seq: number, room: RoomView): void {
    // The move in flight: applied (its id is in acks), or to be sent again on this connection.
    const pending = this.state.pending;
    let stillPending = pending;
    // Without move ids (a server with LINK off) nothing can be sent again safely: the move is
    // either in this snapshot or lost, and the player sees which.
    if (pending && (!room.link || room.link.acks.includes(pending.id))) stillPending = null;
    const resend = stillPending !== null && this.sentOn !== this.connection;
    if (this.playing || this.queue.length > 0) {
      // Let the events play out first; this snapshot lands after them. The move stays in flight
      // until its own answer has been shown, so a second tap can't send it twice; it settles as
      // soon as it has, even with later events (the next player's turn) still queued.
      this.pendingSnapshot = { seq, room };
      this.seq = Math.max(this.seq, seq);
      if (pending && stillPending === null) {
        // Already shown (its last event is on stage now): settled at once.
        if (seq <= this.shownSeq) this.set({ pending: null });
        else this.settle = { id: pending.id, seq };
      }
      return;
    }
    this.seq = Math.max(this.seq, seq);
    this.set({ truth: room, room, phase: phaseOf(room), pending: stillPending, rematch: room.rematch ?? this.state.rematch, aims: this.aimsAfter(room), screen: room.screen === true });
    if (resend && pending) {
      // Reconnected before the server heard it: send it again, with the same id.
      if (this.socket.send({ t: "act", seat: pending.seat, action: pending.action, id: pending.id })) this.sentOn = this.connection;
    }
  }

  /** True when showing `seq` settles the move in flight (and forgets that it was due). */
  private settled(seq: number): boolean {
    const due = this.settle;
    if (!due || seq < due.seq) return false;
    this.settle = null;
    return this.state.pending?.id === due.id;
  }

  private pump(): void {
    if (this.playing) return;
    const next = this.queue.shift();
    if (!next) {
      const snap = this.pendingSnapshot;
      this.pendingSnapshot = null;
      if (snap) {
        this.set({
          truth: snap.room,
          room: snap.room,
          phase: phaseOf(snap.room),
          rematch: snap.room.rematch ?? this.state.rematch,
          aims: this.aimsAfter(snap.room),
          screen: snap.room.screen === true,
          ...(this.settled(snap.seq) ? { pending: null } : {}),
        });
      }
      return;
    }
    this.playing = true;
    this.shownSeq = next.seq;
    const room = this.state.room ? foldEvent(this.state.room, next.event) : null;
    this.set({ room, ...(this.settled(next.seq) ? { pending: null } : {}) });
    for (const l of [...this.listeners]) l.event?.(next, room);
    // Others' moves get their moment on stage; our own were seen as they were made, so they
    // settle at once and the next tap counts.
    const ours = this.state.pending !== null && "event" in next.event && "seat" in next.event.event && next.event.event.seat === this.state.pending.seat;
    const full = ours ? Math.min(eventPause(next.event), 80) : eventPause(next.event);
    const pause = this.reducedMotion() ? Math.min(full, 200) : full;
    this.timer = this.setTimer(() => {
      this.timer = null;
      this.playing = false;
      this.pump();
    }, pause);
  }
}
