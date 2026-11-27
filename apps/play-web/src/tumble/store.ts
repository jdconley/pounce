/**
 * Toy Tumble at one table (spec §6): the round from the snapshot's `tumble` field, this device's
 * own box (`LocalBox`) and every other box (`Replay`), fed by the room socket's live stream. It
 * sends this box's events, and asks for a sync after a gap, a lost connection or a hidden tab, so
 * a box never replays a burst of frames or anything out of order.
 */
import { mySeats } from "../store/lobby";
import { newMoveId, type RoomStore } from "../store/room";

import { LocalBox } from "./local";
import { Replay, type SeatStatus } from "./replay";
import { gravityMs, type Fx } from "./rules";

import type { TumbleView } from "@pounce/play-api/games/tumble";
import type { RoomView } from "@pounce/play-api/protocol";
import type { Seed } from "@pounce/play-api/rules/rng";
import type { Box } from "@pounce/play-api/tumble/box";
import type { Rot, ToyId } from "@pounce/play-api/tumble/toys";
import type { ClientEvent, TumbleServer } from "@pounce/play-api/tumble/wire";

export type TumbleStatus = "countdown" | "playing" | "between" | "over";
export type Cats = "easy" | "quick";

/** The snapshot's `room.tumble` (`docs/live-protocol.md`): times are the server's clock. */
export type TumbleRoom = TumbleView;

/** A Toy Tumble room's state, or null in any other room. */
export const tumbleOf = (room: RoomView | null | undefined): TumbleRoom | null => room?.tumble ?? null;

/** A room of Toy Tumble. */
export const isTumble = (room: Pick<RoomView, "gameId"> | null | undefined): boolean => room?.gameId === "tumble";

/** The table's House Cat level (the lobby's two pills): Easy unless it chose Quick. */
export const catsOf = (room: RoomView): Cats => ((room.options as { cats?: Cats } | undefined)?.cats === "quick" ? "quick" : (tumbleOf(room)?.cats ?? "easy"));

/** How long the next round waits for a missing device before the host may go on without it. */
export const PLAY_WITHOUT_AFTER_MS = 20_000;

/**
 * The host's "Play without Sam": the seats whose devices are missing sit out (Away) until they
 * are back. The room works out who; any seat of the host's sends it.
 */
export function playWithout(store: RoomStore, room: RoomView): void {
  const seat = mySeats(room)[0];
  if (seat !== undefined) store.send({ t: "act", seat, action: { k: "playWithout" } as never, id: newMoveId() });
}

/** Leave: the seat is out of the game for good (Toy Tumble's forfeit, spec §5.1). */
export function leave(store: RoomStore, seat: number): void {
  store.send({ t: "act", seat, action: { k: "leave" } as never, id: newMoveId() });
}

/** The lobby's two pills, and the TV lobby's line. */
export const CATS_WORDS: Record<Cats, string> = { easy: "Cats: Easy", quick: "Cats: Quick" };

/** Who won the game: the seats with the most round wins (none before anyone has one). */
export function tumbleWinners(t: TumbleRoom): number[] {
  const most = Math.max(0, ...t.wins);
  return most === 0 ? [] : t.wins.flatMap((w, s) => (w === most ? [s] : []));
}

/** "1 win", "3 wins". */
export const winsWords = (n: number): string => `${n} ${n === 1 ? "win" : "wins"}`;

/** A seat as everyone sees it: in play, lagging, out this round, sitting out (Away), or gone for good. */
export type SeatState = SeatStatus | "away" | "left";

export type BoxView = {
  box: Box;
  toy: { n: number; id: ToyId; rot: Rot; x: number; y: number } | null;
  landing: number;
  waiting: { id: number; rows: number; leftMs: number }[];
  state: SeatState;
  catnipLeft: number;
  napLeft: number;
  /** ms per row now, for a toy gliding on the TV. */
  gravity: number;
};

export type TumbleStoreOptions = {
  room: RoomStore;
  /** The device's clock, epoch ms (the round's `startsAt` is the server's). */
  now?: () => number;
  /** This device is the table's TV: it never sends `tumble`. */
  screen?: boolean;
};

/** The longest a sync request waits before it is asked again. */
export const SYNC_EVERY_MS = 1000;
/** A screen that lost a box's stream connects again for it, at most this often. */
export const SCREEN_SYNC_EVERY_MS = 5000;

export class TumbleStore {
  local: LocalBox | null = null;
  replay: Replay | null = null;
  /** The round the boxes are for. */
  r: number | null = null;
  /** The seat this device plays, while it has a box this round. */
  mySeat: number | null = null;
  private t: TumbleRoom | null = null;
  private truth: RoomView | null = null;
  /** The server's clock minus this device's (ms). */
  private offset = 0;
  private seats: number[] = [];
  private readonly store: RoomStore;
  private readonly screen: boolean;
  private readonly now: () => number;
  private lastAsk = -Infinity;
  /** Asked for a sync and not had one yet. */
  private asked = false;
  private hidden = false;
  private online = true;
  /** Live messages for a round not built yet (a sync can beat the snapshot). */
  private early: TumbleServer[] = [];
  private fx: Fx[] = [];
  private listeners = new Set<() => void>();
  private unsubscribe: (() => void) | null = null;

  constructor(o: TumbleStoreOptions) {
    this.store = o.room;
    this.screen = o.screen ?? false;
    this.now = o.now ?? (() => performance.timeOrigin + performance.now());
  }

  start(): void {
    if (this.unsubscribe) return;
    this.unsubscribe = this.store.subscribe({
      change: (s) => {
        if (s.online !== this.online) {
          this.online = s.online;
          // Offline, nothing this box does reaches the server: hold it, and ask for the truth when back.
          if (!s.online) this.local?.hide();
          else if (this.local) this.askSync(true);
        }
        this.onRoom(s.truth);
      },
      live: (m) => this.onLive(m),
    });
    this.onRoom(this.store.state.truth);
    // What came before this store listened: from the last sync on (the one a device or screen gets
    // on connecting), so nothing already applied is applied twice.
    const kept = this.store.recentLive();
    let from = -1;
    for (let i = kept.length - 1; i >= 0; i--) {
      if (kept[i]!.t === "tumbleSync") {
        from = i;
        break;
      }
    }
    if (from >= 0) for (const m of kept.slice(from)) this.onLive(m);
  }

  stop(): void {
    this.unsubscribe?.();
    this.unsubscribe = null;
  }

  /** Called on round changes (a new round, its end), for the screen to draw again. */
  subscribe(fn: () => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  get room(): TumbleRoom | null {
    return this.t;
  }

  /** The seats in the round, in seat order. */
  get players(): number[] {
    return this.seats;
  }

  /** One frame: this device's box steps; a box that needs the truth asks for it. */
  frame(now = this.now()): void {
    this.local?.step(now);
    const need = (this.local?.stale ?? false) || (this.replay?.needsSync() ?? false);
    if (need) this.askSync();
    else this.asked = false;
  }

  /** The page went out of sight (true) or came back (false). */
  setHidden(hidden: boolean): void {
    if (hidden === this.hidden) return;
    this.hidden = hidden;
    if (hidden) this.local?.hide();
    else if (this.local) this.askSync(true);
  }

  /** Ms until the round starts (0 once it has). */
  countdown(now = this.now()): number {
    return this.t && (this.t.status === "countdown" || this.t.status === "playing") ? Math.max(0, this.startsAt() - now) : 0;
  }

  /** The server's clock now, from the device's and the last snapshot's `now`. */
  serverNow(): number {
    return this.now() + this.offset;
  }

  /** When the round starts, on this device's clock. */
  private startsAt(): number {
    return (this.t?.startsAt ?? 0) - this.offset;
  }

  /** A seat's box as shown, or null for a seat not in the round. */
  view(seat: number, now = this.now()): BoxView | null {
    const t = this.t;
    if (!t) return null;
    const elapsed = now - this.startsAt();
    if (this.local && seat === this.mySeat) {
      const v = this.local.view();
      return { ...v, state: this.seatState(seat), gravity: gravityMs(elapsed, v.catnipLeft > 0) };
    }
    const v = this.replay?.view(seat, now);
    if (!v) return null;
    return { box: v.box, toy: v.toy, landing: v.landing, waiting: v.waiting, state: this.seatState(seat), catnipLeft: v.catnipLeft, napLeft: v.napLeft, gravity: gravityMs(elapsed, v.catnipLeft > 0) };
  }

  seatState(seat: number): SeatState {
    const t = this.t;
    if (t?.left[seat]) return "left";
    if (t?.away[seat]) return "away";
    if (t?.outs.includes(seat)) return "out";
    if (this.local && seat === this.mySeat) return this.local.view().box.out ? "out" : "ok";
    return this.replay?.view(seat)?.status ?? "ok";
  }

  /** What to animate since the last call. */
  takeFx(): Fx[] {
    const fx = [...this.fx, ...(this.local?.takeFx() ?? []), ...(this.replay?.takeFx() ?? [])];
    this.fx = [];
    return fx;
  }

  /** Sends this device's events for its box. */
  private send(ev: ClientEvent[]): void {
    if (this.r === null) return;
    this.store.send({ t: "tumble", r: this.r, ev });
  }

  /** An empty batch asks for a sync of every box. */
  private askSync(now = false): void {
    if (this.r === null) return;
    const at = this.now();
    // A screen may not send `tumble`: it gets every box again by connecting again.
    const every = this.screen ? SCREEN_SYNC_EVERY_MS : SYNC_EVERY_MS;
    if (!now && this.asked && at - this.lastAsk < every) return;
    this.asked = true;
    this.lastAsk = at;
    if (this.screen) this.store.socket.reconnectNow();
    else this.store.send({ t: "tumble", r: this.r, ev: [] });
  }

  private changed(): void {
    for (const fn of [...this.listeners]) fn();
  }

  private onRoom(room: RoomView | null): void {
    const t = isTumble(room) ? tumbleOf(room) : null;
    const was = this.t;
    this.t = t;
    // A new snapshot: keep how far the server's clock is from this device's (spec §6.2, `now`).
    if (room !== this.truth) {
      this.truth = room;
      if (typeof t?.now === "number") this.offset = t.now - this.now();
    }
    // The round's shape changed (a countdown, its end, a winner, someone away or out): draw again.
    const shape = (x: TumbleRoom | null) => (x ? `${x.r}|${x.status}|${x.winner}|${x.outs.join()}|${x.away.join()}|${x.left.join()}|${x.wins.join()}` : "");
    if (shape(was) !== shape(t)) this.changed();
    if (!room || !t || (t.status !== "countdown" && t.status !== "playing") || !t.roundSeed || !t.trickSeeds) {
      if (this.r !== null || this.local || this.replay) {
        this.local = this.replay = null;
        this.r = this.mySeat = null;
        this.seats = [];
        this.changed();
      }
      return;
    }
    if (this.r !== t.r) this.newRound(room, t);
    for (const s of t.outs) {
      if (this.local && s === this.mySeat) this.local.knockOut();
      else this.replay?.knockOut(s);
    }
  }

  private newRound(room: RoomView, t: TumbleRoom): void {
    const seeds = t.trickSeeds as Seed[];
    const roundSeed = t.roundSeed as Seed;
    this.r = t.r;
    this.seats = room.seats.flatMap((s, i) => ((s.kind === "human" || s.kind === "bot") && !t.left[i] && !t.away[i] ? [i] : []));
    const mine = mySeats(room).find((s) => this.seats.includes(s)) ?? null;
    this.mySeat = mine !== null && !t.outs.includes(mine) ? mine : null;
    this.local =
      this.mySeat === null
        ? null
        : new LocalBox({ r: t.r, seat: this.mySeat, roundSeed, trickSeed: seeds[this.mySeat] as Seed, startsAt: this.startsAt(), send: (ev) => this.send(ev), now: this.now });
    if (this.local && this.hidden) this.local.hide();
    this.replay = new Replay({ r: t.r, roundSeed, trickSeeds: seeds, seats: this.seats.filter((s) => s !== this.mySeat), startsAt: this.startsAt(), now: this.now });
    this.asked = false;
    const early = this.early.filter((m) => m.r === t.r);
    this.early = [];
    for (const m of early) this.onLive(m);
    this.changed();
  }

  private onLive(m: TumbleServer): void {
    if (this.r === null || m.r !== this.r) {
      if (this.r === null || m.r > this.r) this.early = [...this.early.slice(-63), m];
      return;
    }
    switch (m.t) {
      case "tumbleHit":
        this.fx.push({ k: "hit", from: m.from, to: m.to, kind: m.k });
        if (this.local && m.to === this.mySeat) this.local.hit(m);
        else this.replay?.apply(m);
        return;
      case "tumbleSync": {
        const mine = m.boxes.find((b) => b.s === this.mySeat);
        if (mine && this.local) this.local.sync(mine);
        const rest = m.boxes.filter((b) => b.s !== this.mySeat || !this.local);
        if (rest.length > 0) this.replay?.apply({ ...m, boxes: rest });
        this.asked = false;
        return;
      }
      case "tumble":
      case "tumbleSeat":
        if (this.local && m.s === this.mySeat) return;
        this.replay?.apply(m);
        return;
    }
  }
}
