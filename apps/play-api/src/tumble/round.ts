import { applyHit, contents, landWaiting, newBox, receiveJunk, setDown, useTrick, TOTAL, W, type Box, type Hit, type Trick, type Waiting } from "./box";
import { rngFloat, rngNext } from "./rng";

import type { ClientEvent, HitKind, HitWire, TumbleClient, TumbleRelay, TumbleSeat, TumbleSync, BoxSync } from "./wire";
import type { Seed } from "../rules/rng";

/**
 * The referee of one Toy Tumble round (spec §6). It keeps every box as the server sees it,
 * checks each device's events before relaying them, issues hits with the server's own
 * randomness, applies what devices owe and don't do, notices quiet devices, and says who is out
 * and who won. In memory only: the room stores nothing of a round but its result.
 */

export const MOVE_RELAY_MS = 66;
export const ACK_MS = 3000;
export const JUNK_WAIT_MS = 2000;
export const OWED_MS = 4000;
export const LAG_MS = 3000;
export const DROP_MS = 15_000;
export const EFFECT_MS = 10_000;

export type SeatKind = "human" | "cat" | "away";
export type RoundSeat = { kind: SeatKind };
export type Target = "all" | { seat: number } | { except: number };
export type RoundMessage = TumbleRelay | HitWire | TumbleSync | TumbleSeat;
export type RoundOut = { to: Target; message: RoundMessage };

type Issued = { id: number; from: number; to: number; k: HitKind; x?: Record<string, unknown>; issuedAt: number; done: boolean };
type SeatState = {
  kind: SeatKind;
  box: Box;
  q: number;
  heardAt: number;
  lag: boolean;
  lastMs: number;
  move: ClientEvent | null;
  movedAt: number;
  /** Server time each waiting junk was acknowledged, by id. */
  junkAt: Map<number, number>;
  napUntil: number;
  catnipUntil: number;
};

const HARMLESS_TO_SELF: readonly Trick[] = ["scoop", "settle", "nap", "bath"];

export class TumbleRound {
  readonly r: number;
  private readonly roundSeed: Seed;
  private rng: Seed;
  private seats: SeatState[];
  private hits = new Map<number, Issued>();
  private nextHit = 1;
  /** Seats out this round, in order, with the server time each went. */
  private outOrder: { seat: number; at: number }[] = [];

  /** `boxes`: where each box starts, for tests; a round always starts from empty boxes otherwise. */
  constructor(o: { r: number; seats: RoundSeat[]; roundSeed: Seed; trickSeeds: Seed[]; startsAt: number; rng: Seed; boxes?: Box[] }) {
    this.r = o.r;
    this.roundSeed = o.roundSeed;
    this.rng = [...o.rng] as Seed;
    this.seats = o.seats.map((s, i) => ({
      kind: s.kind,
      box: o.boxes?.[i] ?? newBox(o.trickSeeds[i] as Seed),
      q: 0,
      heardAt: o.startsAt,
      lag: false,
      lastMs: 0,
      move: null,
      movedAt: 0,
      junkAt: new Map(),
      napUntil: 0,
      catnipUntil: 0,
    }));
  }

  /** The server's copy of a box. */
  box(seat: number): Box {
    return (this.seats[seat] as SeatState).box;
  }

  kind(seat: number): SeatKind {
    return (this.seats[seat] as SeatState).kind;
  }

  get seatCount(): number {
    return this.seats.length;
  }

  /** True while the seat plays this round: not away and not out. */
  live(seat: number): boolean {
    const s = this.seats[seat];
    return s !== undefined && s.kind !== "away" && !s.box.out;
  }

  napping(seat: number, now: number): boolean {
    return (this.seats[seat]?.napUntil ?? 0) > now;
  }

  private random(): number {
    const [u, next] = rngNext(this.rng);
    this.rng = next;
    return rngFloat(u);
  }

  private int(n: number): number {
    return Math.floor(this.random() * n);
  }

  /** A device's batch for its own seat. */
  input(seat: number, msg: TumbleClient, now: number): RoundOut[] {
    const s = this.seats[seat];
    if (msg.r !== this.r || !s || s.kind === "away") return [];
    const out: RoundOut[] = this.heard(seat, now);
    if (s.box.out) return out;
    if (msg.ev.length === 0) return [...out, { to: { seat }, message: this.sync("all", now) }];
    const relayed: ClientEvent[] = [];
    let refused = false;
    let corrected = false;
    for (const e of msg.ev) {
      const r = this.event(seat, e, now, out);
      if (r === "refused") {
        refused = true;
        break;
      }
      if (r === "corrected") corrected = true;
      if (r !== "held") relayed.push(e);
      if (s.box.out) break;
    }
    if (relayed.length > 0) out.unshift({ to: { except: seat }, message: this.relay(seat, relayed) });
    if (refused) out.push({ to: { seat }, message: this.sync([seat], now) });
    else if (corrected) out.push({ to: "all", message: this.sync([seat], now) });
    if (s.box.out) this.noteOut(seat, now);
    return out;
  }

  private relay(seat: number, ev: ClientEvent[]): TumbleRelay {
    const s = this.seats[seat] as SeatState;
    s.q += 1;
    return { t: "tumble", r: this.r, s: seat, q: s.q, ev };
  }

  /** One event. `held`: a move kept back for the next relay; `corrected`: accepted, but the server applied something the device owed. */
  private event(seat: number, e: ClientEvent, now: number, out: RoundOut[]): "ok" | "held" | "refused" | "corrected" {
    const s = this.seats[seat] as SeatState;
    switch (e[0]) {
      case "m": {
        if (e[1] !== s.box.next) return "held";
        s.move = e;
        if (now - s.movedAt < MOVE_RELAY_MS) return "held";
        s.movedAt = now;
        s.move = null;
        return "ok";
      }
      case "l": {
        const [, n, rot, x, y, ms, landed] = e;
        if (ms < s.lastMs) return "refused";
        const r = setDown(s.box, this.roundSeed, n, rot, x, y, landed);
        if ("error" in r) return "refused";
        s.move = null;
        s.lastMs = ms;
        for (const id of landed) s.junkAt.delete(id);
        for (const b of r.blocked) if (!r.box.waiting.some((w) => w.id === b.id)) s.junkAt.delete(b.id);
        s.box = r.box;
        let corrected = false;
        if (r.cleared === 0) {
          // Junk acknowledged more than 4 seconds ago must have landed by now (§6.5).
          let owed = 0;
          for (const w of s.box.waiting) {
            if ((s.junkAt.get(w.id) ?? now) + OWED_MS < now) owed++;
            else break;
          }
          if (owed > 0) {
            for (const w of s.box.waiting.slice(0, owed)) s.junkAt.delete(w.id);
            s.box = landWaiting(s.box, owed);
            corrected = true;
          }
        }
        if (r.sent > 0) this.attack(seat, r.sent, now, out);
        return corrected ? "corrected" : "ok";
      }
      case "a": {
        const hit = this.hits.get(e[1]);
        if (!hit || hit.to !== seat || hit.done) return "refused";
        this.applyIssued(hit, now);
        return "ok";
      }
      case "u": {
        const [, slot, target] = e;
        if (!this.live(target)) return "refused";
        const used = useTrick(s.box, slot);
        if (!used) return "refused";
        s.box = used.box;
        this.trick(seat, target, used.trick, now, out);
        return "ok";
      }
    }
  }

  /** Junk from a clear goes to every other box still in the round, unless it naps (§4.5). */
  private attack(from: number, rows: number, now: number, out: RoundOut[]): void {
    const gap = this.int(W);
    for (let to = 0; to < this.seats.length; to++) {
      if (to === from || !this.live(to) || this.napping(to, now)) continue;
      out.push({ to: "all", message: this.issue(from, to, "junk", { rows, gap }, now) });
    }
  }

  private trick(from: number, to: number, trick: Trick, now: number, out: RoundOut[]): void {
    const self = from === to && HARMLESS_TO_SELF.includes(trick);
    if (this.napping(to, now) && !self) {
      out.push({ to: "all", message: { t: "tumbleHit", r: this.r, id: this.nextHit++, from, to, k: "napped" } });
      return;
    }
    switch (trick) {
      case "hairball":
        out.push({ to: "all", message: this.issue(from, to, "hairball", { gap: this.int(W) }, now) });
        return;
      case "swipe":
        out.push({ to: "all", message: this.issue(from, to, "swipe", { shifts: Array.from({ length: TOTAL }, () => this.int(5) - 2) }, now) });
        return;
      case "swap": {
        if (from === to) return;
        const mine = contents(this.box(from));
        const theirs = contents(this.box(to));
        out.push({ to: "all", message: this.issue(from, to, "swap", mine, now) });
        out.push({ to: "all", message: this.issue(from, from, "swap", theirs, now) });
        return;
      }
      default:
        out.push({ to: "all", message: this.issue(from, to, trick, undefined, now) });
    }
  }

  private issue(from: number, to: number, k: HitKind, x: Record<string, unknown> | undefined, now: number): HitWire {
    const id = this.nextHit++;
    this.hits.set(id, { id, from, to, k, ...(x ? { x } : {}), issuedAt: now, done: false });
    return { t: "tumbleHit", r: this.r, id, from, to, k, ...(x ? { x } : {}) };
  }

  /** Applies an issued hit to the server's copy of its target, as the target's ack does. */
  private applyIssued(hit: Issued, now: number): void {
    hit.done = true;
    const s = this.seats[hit.to] as SeatState;
    if (s.box.out) return;
    if (hit.k === "junk") {
      const x = hit.x as { rows: number; gap: number };
      const w: Waiting = { id: hit.id, rows: x.rows, gap: x.gap };
      s.box = receiveJunk(s.box, w);
      s.junkAt.set(hit.id, now);
      return;
    }
    if (hit.k === "nap") s.napUntil = now + EFFECT_MS;
    if (hit.k === "catnip") s.catnipUntil = now + EFFECT_MS;
    s.box = applyHit(s.box, this.hitOf(hit)).box;
  }

  private hitOf(hit: Issued): Hit {
    switch (hit.k) {
      case "hairball":
        return { k: "hairball", gap: (hit.x as { gap: number }).gap };
      case "swipe":
        return { k: "swipe", shifts: (hit.x as { shifts: number[] }).shifts };
      case "swap": {
        const x = hit.x as { cells: number[]; tricks: number[] };
        return { k: "swap", cells: x.cells, tricks: x.tricks };
      }
      case "catnip":
      case "nap":
      case "scoop":
      case "settle":
      case "bath":
        return { k: hit.k };
      default:
        throw new Error(`no box effect for ${hit.k}`);
    }
  }

  /** Any message from a seat's device: it is there. A device back from lagging hears so, gets every box, and is sent its unacked hits again. */
  heard(seat: number, now: number): RoundOut[] {
    const s = this.seats[seat];
    if (!s || s.kind !== "human") return [];
    s.heardAt = now;
    if (!s.lag || s.box.out) return [];
    s.lag = false;
    const out: RoundOut[] = [
      { to: "all", message: { t: "tumbleSeat", r: this.r, s: seat, st: "ok" } },
      { to: { seat }, message: this.sync("all", now) },
    ];
    for (const hit of this.hits.values()) {
      if (hit.to !== seat || hit.done) continue;
      hit.issuedAt = now;
      out.push({ to: { seat }, message: { t: "tumbleHit", r: this.r, id: hit.id, from: hit.from, to: hit.to, k: hit.k, ...(hit.x ? { x: hit.x } : {}) } });
    }
    return out;
  }

  /**
   * The clock: held moves go out, hits nobody acknowledged in 3 seconds are applied by the server,
   * quiet devices lag at 3 seconds and are out at 15.
   */
  tick(now: number): RoundOut[] {
    const out: RoundOut[] = [];
    this.seats.forEach((s, seat) => {
      if (s.move && now - s.movedAt >= MOVE_RELAY_MS && !s.box.out) {
        s.movedAt = now;
        out.push({ to: { except: seat }, message: this.relay(seat, [s.move]) });
        s.move = null;
      }
    });
    const corrected = new Set<number>();
    for (const hit of this.hits.values()) {
      if (hit.done) continue;
      const target = this.seats[hit.to] as SeatState;
      if (target.box.out) {
        hit.done = true;
        continue;
      }
      if (target.lag || now - hit.issuedAt < ACK_MS) continue;
      this.applyIssued(hit, now);
      corrected.add(hit.to);
    }
    for (const seat of corrected) {
      out.push({ to: "all", message: this.sync([seat], now) });
      if (this.box(seat).out) this.noteOut(seat, now);
    }
    this.seats.forEach((s, seat) => {
      if (s.kind !== "human" || s.box.out) return;
      if (!s.lag && now - s.heardAt >= LAG_MS) {
        s.lag = true;
        out.push({ to: "all", message: { t: "tumbleSeat", r: this.r, s: seat, st: "lag" } });
      }
      if (now - s.heardAt >= DROP_MS) {
        s.box = { ...s.box, out: true };
        this.noteOut(seat, now);
        out.push({ to: "all", message: this.sync([seat], now) });
      }
    });
    return out;
  }

  private noteOut(seat: number, now: number): void {
    if (!this.outOrder.some((o) => o.seat === seat)) this.outOrder.push({ seat, at: now });
  }

  /** Every box (or the listed ones) as the server has it. */
  sync(seats: number[] | "all", now: number): TumbleSync {
    const list = seats === "all" ? this.seats.map((_, i) => i).filter((i) => this.seats[i]?.kind !== "away") : seats;
    const boxes: BoxSync[] = list.map((seat) => {
      const s = this.seats[seat] as SeatState;
      return {
        s: seat,
        box: s.box,
        q: s.q,
        waitingLeft: s.box.waiting.map((w) => Math.max(0, (s.junkAt.get(w.id) ?? now) + JUNK_WAIT_MS - now)),
        catnipLeft: Math.max(0, s.catnipUntil - now),
        napLeft: Math.max(0, s.napUntil - now),
        status: s.box.out ? "out" : s.lag ? "lag" : "ok",
      };
    });
    return { t: "tumbleSync", r: this.r, boxes };
  }

  /**
   * Whether the round is over, and who won (§4.4): the last box standing; with no person left,
   * the House Cat that cleared the most rows; nobody when the last boxes went out together.
   */
  result(): { over: boolean; winner: number | null; outs: number[] } {
    const outs = this.outOrder.map((o) => o.seat);
    const live = this.seats.map((_, i) => i).filter((i) => this.live(i));
    const humans = live.filter((i) => this.kind(i) === "human");
    if (live.length > 1 && humans.length > 0) return { over: false, winner: null, outs };
    if (live.length === 1) return { over: true, winner: live[0] as number, outs };
    if (live.length === 0) return { over: true, winner: null, outs };
    const best = [...live].sort((a, b) => this.box(b).rows - this.box(a).rows || a - b)[0] as number;
    return { over: true, winner: best, outs };
  }
}
