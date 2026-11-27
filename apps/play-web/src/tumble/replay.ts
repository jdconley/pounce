/**
 * Every box this device doesn't play, replayed from what the server relays (spec §6.4 to §6.6):
 * each box's checked events in `q` order, hits kept until the target's own ack comes through its
 * stream, and whole boxes from a sync. A gap in `q`, or an event the engine refuses, stops that
 * box until a sync: nothing is ever replayed out of order.
 */
import { applyHit, fits, newBox, receiveJunk, setDown, useTrick, type Box } from "@pounce/play-api/tumble/box";
import { toyAt } from "@pounce/play-api/tumble/queue";
import { spawn, type Rot, type ToyId } from "@pounce/play-api/tumble/toys";

import { gravityMs, hitOf, junkOf, JUNK_WAIT_MS, TRICK_MS, type Fx } from "./rules";

import type { Seed } from "@pounce/play-api/rules/rng";
import type { BoxSync, ClientEvent, HitWire, TumbleServer } from "@pounce/play-api/tumble/wire";

export type SeatStatus = "ok" | "lag" | "out";
type ReplayToy = { n: number; id: ToyId; rot: Rot; x: number; y: number; at: number };
type Entry = {
  box: Box;
  /** The last `q` replayed; null before the first relay of a fresh round. */
  q: number | null;
  /** Waiting for a sync: a gap, or an event that didn't replay. */
  gap: boolean;
  toy: ReplayToy | null;
  status: SeatStatus;
  /** When each waiting junk was acked, on this device's clock. */
  ackAt: Map<number, number>;
  catnipUntil: number;
  napUntil: number;
  version: number;
};

export type ReplayView = {
  box: Box;
  /** The falling toy, its y gliding between position updates. */
  toy: { n: number; id: ToyId; rot: Rot; x: number; y: number } | null;
  landing: number;
  waiting: { id: number; rows: number; leftMs: number }[];
  status: SeatStatus;
  catnipLeft: number;
  napLeft: number;
  version: number;
};

export type ReplayOptions = {
  r: number;
  roundSeed: Seed;
  /** Every seat's trick seed, by seat. */
  trickSeeds: Seed[];
  /** The seats this device replays. */
  seats: number[];
  startsAt: number;
  now?: () => number;
};

export class Replay {
  readonly r: number;
  private readonly roundSeed: Seed;
  private readonly startsAt: number;
  private readonly now: () => number;
  private readonly boxes = new Map<number, Entry>();
  /** Hits not yet acked by their target, by id. */
  private readonly hits = new Map<number, HitWire>();
  private fx: Fx[] = [];

  constructor(o: ReplayOptions) {
    this.r = o.r;
    this.roundSeed = o.roundSeed;
    this.startsAt = o.startsAt;
    this.now = o.now ?? (() => Date.now());
    for (const s of o.seats) {
      const seed = o.trickSeeds[s] ?? ([s + 1, 1, 1, 1] as Seed);
      this.boxes.set(s, { box: newBox(seed), q: null, gap: false, toy: null, status: "ok", ackAt: new Map(), catnipUntil: -Infinity, napUntil: -Infinity, version: 0 });
    }
  }

  seats(): number[] {
    return [...this.boxes.keys()];
  }

  apply(msg: TumbleServer): void {
    if (msg.r !== this.r) return;
    switch (msg.t) {
      case "tumble":
        this.relay(msg.s, msg.q, msg.ev);
        return;
      case "tumbleHit":
        if (msg.k !== "napped" && this.boxes.has(msg.to)) this.hits.set(msg.id, msg);
        return;
      case "tumbleSync":
        for (const b of msg.boxes) this.sync(b);
        return;
      case "tumbleSeat": {
        const e = this.boxes.get(msg.s);
        if (e && e.status !== "out") {
          e.status = msg.st;
          e.version++;
        }
        return;
      }
    }
  }

  /** The server put `seat` out (the snapshot's `outs`). */
  knockOut(seat: number): void {
    const e = this.boxes.get(seat);
    if (!e || e.status === "out") return;
    e.status = "out";
    e.box = { ...e.box, out: true };
    e.toy = null;
    e.version++;
    this.fx.push({ k: "out", seat });
  }

  box(seat: number): Box | null {
    return this.boxes.get(seat)?.box ?? null;
  }

  toy(seat: number): ReplayToy | null {
    return this.boxes.get(seat)?.toy ?? null;
  }

  needsSync(): boolean {
    for (const e of this.boxes.values()) if (e.gap) return true;
    return false;
  }

  view(seat: number, now = this.now()): ReplayView | null {
    const e = this.boxes.get(seat);
    if (!e) return null;
    const toy = e.box.out || now < this.startsAt ? null : (e.toy ?? this.spawned(e, now));
    let shown: ReplayView["toy"] = null;
    let landing = 0;
    if (toy) {
      landing = this.landingY(e.box, toy);
      // A lagging box's toy hangs still; otherwise it glides down by gravity, up to a row.
      const g = gravityMs(now - this.startsAt, now < e.catnipUntil);
      const glide = e.status === "ok" && !e.gap ? Math.min(1, Math.max(0, (now - toy.at) / g)) : 0;
      shown = { n: toy.n, id: toy.id, rot: toy.rot, x: toy.x, y: Math.max(landing, toy.y - glide) };
    }
    return {
      box: e.box,
      toy: shown,
      landing,
      waiting: e.box.waiting.map((w) => ({ id: w.id, rows: w.rows, leftMs: Math.max(0, JUNK_WAIT_MS - (now - (e.ackAt.get(w.id) ?? now))) })),
      status: e.status,
      catnipLeft: Math.max(0, e.catnipUntil - now),
      napLeft: Math.max(0, e.napUntil - now),
      version: e.version,
    };
  }

  takeFx(): Fx[] {
    const fx = this.fx;
    this.fx = [];
    return fx;
  }

  private spawned(e: Entry, now: number): ReplayToy {
    const id = toyAt(this.roundSeed, e.box.next);
    const at = spawn(id);
    const toy = { n: e.box.next, id, rot: at.rot, x: at.x, y: at.y, at: Math.max(now, this.startsAt) };
    e.toy = toy;
    return toy;
  }

  private landingY(box: Box, toy: { id: ToyId; rot: Rot; x: number; y: number }): number {
    let y = toy.y;
    if (!fits(box, toy.id, toy.rot, toy.x, y)) return y;
    while (fits(box, toy.id, toy.rot, toy.x, y - 1)) y--;
    return y;
  }

  private sync(b: BoxSync): void {
    const e = this.boxes.get(b.s);
    if (!e) return;
    const now = this.now();
    e.box = b.box;
    e.q = b.q;
    e.gap = false;
    e.status = b.status;
    e.toy = null;
    e.ackAt = new Map(b.box.waiting.map((w, i) => [w.id, now - (JUNK_WAIT_MS - (b.waitingLeft[i] ?? JUNK_WAIT_MS))]));
    e.catnipUntil = b.catnipLeft > 0 ? now + b.catnipLeft : -Infinity;
    e.napUntil = b.napLeft > 0 ? now + b.napLeft : -Infinity;
    e.version++;
  }

  private relay(seat: number, q: number, ev: ClientEvent[]): void {
    const e = this.boxes.get(seat);
    if (!e) return;
    if (e.q !== null && q <= e.q) return;
    // The first relay of a round is q 1 (or 0); any other step than one is a gap.
    const expected = e.q === null ? q <= 1 : q === e.q + 1;
    if (!expected) e.gap = true;
    if (e.gap) return;
    e.q = q;
    const now = this.now();
    for (const event of ev) {
      if (!this.event(seat, e, event, now)) {
        e.gap = true;
        break;
      }
    }
    e.version++;
  }

  /** Replays one event on `seat`'s box. False when it doesn't replay: the box needs a sync. */
  private event(seat: number, e: Entry, event: ClientEvent, now: number): boolean {
    switch (event[0]) {
      case "m": {
        const [, n, rot, x, y] = event;
        if (n !== e.box.next) return true;
        e.toy = { n, id: toyAt(this.roundSeed, n), rot, x, y, at: now };
        return true;
      }
      case "l": {
        const [, n, rot, x, y, , landed] = event;
        const r = setDown(e.box, this.roundSeed, n, rot, x, y, landed);
        if ("error" in r) return false;
        e.box = r.box;
        for (const id of [...e.ackAt.keys()]) if (!e.box.waiting.some((w) => w.id === id)) e.ackAt.delete(id);
        e.toy = null;
        this.fx.push({ k: "set", seat });
        if (r.cleared > 0) this.fx.push({ k: "clear", seat, rows: r.cleared });
        if (r.out) {
          e.status = "out";
          this.fx.push({ k: "out", seat });
        }
        return true;
      }
      case "a": {
        const hit = this.hits.get(event[1]);
        if (!hit || hit.to !== seat) return false;
        this.hits.delete(event[1]);
        if (hit.k === "junk") {
          const w = junkOf(hit);
          if (!w) return false;
          e.box = receiveJunk(e.box, w);
          e.ackAt.set(w.id, now);
          return true;
        }
        const h = hitOf(hit);
        if (!h) return false;
        e.box = applyHit(e.box, h).box;
        if (h.k === "catnip") e.catnipUntil = now + TRICK_MS;
        if (h.k === "nap") e.napUntil = now + TRICK_MS;
        if (e.box.out && e.status !== "out") {
          e.status = "out";
          e.toy = null;
          this.fx.push({ k: "out", seat });
        }
        return true;
      }
      case "u": {
        const used = useTrick(e.box, event[1]);
        if (!used) return false;
        e.box = used.box;
        return true;
      }
    }
  }
}
