/**
 * One's own Toy Tumble box, run on the frame clock (spec §4.2 to §4.6, §6.3): gravity, the
 * set-down wait, moves, turns and drops, junk's wait, and the events this device sends for its
 * box. Every change goes through the shared engine, so the server and every replayer get the same
 * box from the same events. Input is applied the moment it arrives and shows on the next frame.
 */
import { applyHit, fits, newBox, receiveJunk, setDown, turn as turnToy, useTrick, type Box } from "@pounce/play-api/tumble/box";
import { toyAt } from "@pounce/play-api/tumble/queue";
import { spawn, type Rot, type ToyId } from "@pounce/play-api/tumble/toys";

import { Batcher } from "./batcher";
import { gravityMs, hitOf, junkOf, JUNK_WAIT_MS, MAX_RESETS, MAX_ROUND_MS, SET_DOWN_MS, SOFT_MS, TRICK_MS, type Fx } from "./rules";

import type { Seed } from "@pounce/play-api/rules/rng";
import type { BoxSync, ClientEvent, HitWire } from "@pounce/play-api/tumble/wire";

export type Toy = { n: number; id: ToyId; rot: Rot; x: number; y: number };
export type LocalView = {
  box: Box;
  toy: Toy | null;
  /** The y the toy in hand would set down at: the paw-print outline. */
  landing: number;
  waiting: { id: number; rows: number; leftMs: number }[];
  catnipLeft: number;
  napLeft: number;
};

export type LocalOptions = {
  r: number;
  seat: number;
  roundSeed: Seed;
  trickSeed: Seed;
  /** When the round starts, on the device's clock (epoch ms). */
  startsAt: number;
  send: (ev: ClientEvent[]) => void;
  /** The box to start from (a sync); otherwise a new one. */
  box?: Box;
  /** The device's clock, for input and hits between frames. Without one, the last frame's time. */
  now?: () => number;
};

export class LocalBox {
  readonly r: number;
  readonly seat: number;
  /** True while the box waits for a sync (a hidden tab, a gap): it doesn't step. */
  stale = false;
  private box: Box;
  private toy: Toy | null = null;
  private readonly roundSeed: Seed;
  private readonly startsAt: number;
  private readonly batcher: Batcher;
  private readonly clock: (() => number) | null;
  private t: number;
  private lastFall = 0;
  private restSince: number | null = null;
  private resets = 0;
  private softOn = false;
  /** Each waiting junk's ack time. */
  private ackAt = new Map<number, number>();
  private catnipUntil = -Infinity;
  private napUntil = -Infinity;
  private fx: Fx[] = [];
  /** Bumped on every change, so a drawing can tell it is stale. */
  version = 0;

  constructor(o: LocalOptions) {
    this.r = o.r;
    this.seat = o.seat;
    this.roundSeed = o.roundSeed;
    this.startsAt = o.startsAt;
    this.box = o.box ?? newBox(o.trickSeed);
    this.batcher = new Batcher(o.send);
    this.clock = o.now ?? null;
    this.t = o.startsAt;
  }

  private now(): number {
    return this.clock ? this.clock() : this.t;
  }

  /** Runs the box up to `now`: the toy appears, falls and sets down. Pending events go out. */
  step(now: number): void {
    this.t = Math.max(this.t, now);
    if (!this.stale && !this.box.out && now >= this.startsAt) {
      if (!this.toy) this.spawnToy(now);
      this.fall(now);
    }
    this.batcher.step(now);
  }

  move(dx: -1 | 1): void {
    const toy = this.live();
    if (!toy || !fits(this.box, toy.id, toy.rot, toy.x + dx, toy.y)) return;
    toy.x += dx;
    this.moved();
  }

  turn(dir: 1 | -1): void {
    const toy = this.live();
    if (!toy) return;
    const to = turnToy(this.box, toy.id, toy.rot, toy.x, toy.y, dir);
    if (!to) return;
    toy.rot = to.rot;
    toy.x = to.x;
    toy.y = to.y;
    this.moved();
  }

  soft(on: boolean): void {
    if (on && !this.softOn) this.lastFall = Math.min(this.lastFall, this.now());
    this.softOn = on;
  }

  drop(): void {
    const toy = this.live();
    if (!toy) return;
    toy.y = this.landingY(toy);
    this.setDownNow(this.now());
  }

  /** Uses the trick in `slot` on `seat`. */
  use(slot: number, seat: number): void {
    if (this.stale || this.box.out || this.now() < this.startsAt) return;
    const used = useTrick(this.box, slot);
    if (!used) return;
    this.box = used.box;
    this.version++;
    this.batcher.push(["u", slot, seat], this.now());
  }

  /** A hit aimed at this box: applied and acked at once; junk starts its wait at the ack. */
  hit(h: HitWire): void {
    if (h.to !== this.seat || h.r !== this.r || h.k === "napped") return;
    const now = this.now();
    if (h.k === "junk") {
      const w = junkOf(h);
      if (!w) return;
      this.box = receiveJunk(this.box, w);
      if (!this.box.out) this.ackAt.set(w.id, now);
    } else {
      const hit = hitOf(h);
      if (!hit) return;
      const before = this.box.held.length;
      this.box = applyHit(this.box, hit).box;
      if (this.box.held.length > before) this.fx.push({ k: "pocket", seat: this.seat });
      if (hit.k === "catnip") this.catnipUntil = now + TRICK_MS;
      if (hit.k === "nap") this.napUntil = now + TRICK_MS;
      if (hit.k === "bath") this.ackAt.clear();
      this.afterChange();
    }
    this.version++;
    this.batcher.push(["a", h.id], now);
  }

  /** The box as the server has it. The toy in hand starts again at the top. */
  sync(b: BoxSync, now = this.now()): void {
    this.t = Math.max(this.t, now);
    this.box = b.box;
    this.ackAt = new Map(b.box.waiting.map((w, i) => [w.id, now - (JUNK_WAIT_MS - (b.waitingLeft[i] ?? JUNK_WAIT_MS))]));
    this.catnipUntil = b.catnipLeft > 0 ? now + b.catnipLeft : -Infinity;
    this.napUntil = b.napLeft > 0 ? now + b.napLeft : -Infinity;
    this.batcher.clear();
    this.stale = false;
    this.toy = null;
    if (!this.box.out && now >= this.startsAt) this.spawnToy(now);
    this.version++;
  }

  /** The tab went out of sight: stop until a sync says where the box is. */
  hide(): void {
    this.stale = true;
    this.softOn = false;
  }

  /** The server put this box out (a lost connection, the round's end). */
  knockOut(): void {
    if (this.box.out) return;
    this.box = { ...this.box, out: true };
    this.toy = null;
    this.fx.push({ k: "out", seat: this.seat });
    this.version++;
  }

  view(): LocalView {
    const now = this.now();
    const toy = this.toy ? { ...this.toy } : null;
    return {
      box: this.box,
      toy,
      landing: this.toy ? this.landingY(this.toy) : 0,
      waiting: this.box.waiting.map((w) => ({ id: w.id, rows: w.rows, leftMs: Math.max(0, JUNK_WAIT_MS - (now - (this.ackAt.get(w.id) ?? now))) })),
      catnipLeft: Math.max(0, this.catnipUntil - now),
      napLeft: Math.max(0, this.napUntil - now),
    };
  }

  /** What happened since the last call, for the screen to play. */
  takeFx(): Fx[] {
    const fx = this.fx;
    this.fx = [];
    return fx;
  }

  private live(): Toy | null {
    if (this.stale || this.box.out || !this.toy) return null;
    return this.toy;
  }

  private spawnToy(now: number): void {
    const id = toyAt(this.roundSeed, this.box.next);
    const at = spawn(id);
    this.toy = { n: this.box.next, id, rot: at.rot, x: at.x, y: at.y };
    this.lastFall = now;
    this.restSince = null;
    this.resets = 0;
    this.version++;
  }

  private resting(toy: Toy): boolean {
    return !fits(this.box, toy.id, toy.rot, toy.x, toy.y - 1);
  }

  private landingY(toy: Toy): number {
    let y = toy.y;
    while (fits(this.box, toy.id, toy.rot, toy.x, y - 1)) y--;
    return y;
  }

  private fall(now: number): void {
    const toy = this.toy;
    if (!toy) return;
    const g = gravityMs(now - this.startsAt, now < this.catnipUntil);
    const every = this.softOn ? Math.min(g, SOFT_MS) : g;
    let fell = false;
    while (now - this.lastFall >= every && !this.resting(toy)) {
      toy.y--;
      this.lastFall += every;
      fell = true;
    }
    if (fell) {
      this.version++;
      this.batcher.push(["m", toy.n, toy.rot, toy.x, toy.y], now);
    }
    if (!this.resting(toy)) {
      this.restSince = null;
      return;
    }
    // Resting: the fall clock waits with it, so a toy slid off a ledge falls a full row later.
    this.lastFall = Math.max(this.lastFall, now - every);
    this.restSince ??= now;
    if (now - this.restSince >= SET_DOWN_MS) this.setDownNow(now);
  }

  private moved(): void {
    const toy = this.toy as Toy;
    const now = this.now();
    if (this.restSince !== null && this.resets < MAX_RESETS) {
      this.resets++;
      this.restSince = this.resting(toy) ? now : null;
    }
    this.version++;
    this.batcher.push(["m", toy.n, toy.rot, toy.x, toy.y], now);
  }

  /** Sets the toy in hand down where it is: junk whose wait is over lands if nothing clears. */
  private setDownNow(now: number): void {
    const toy = this.toy;
    if (!toy) return;
    const ms = Math.min(MAX_ROUND_MS, Math.max(0, Math.round(now - this.startsAt)));
    let r = setDown(this.box, this.roundSeed, toy.n, toy.rot, toy.x, toy.y, []);
    if ("error" in r) return;
    let landed: number[] = [];
    if (r.cleared === 0) {
      for (const w of this.box.waiting) {
        const at = this.ackAt.get(w.id);
        if (at === undefined || now - at < JUNK_WAIT_MS) break;
        landed.push(w.id);
      }
      if (landed.length > 0) {
        const withJunk = setDown(this.box, this.roundSeed, toy.n, toy.rot, toy.x, toy.y, landed);
        if ("error" in withJunk) landed = [];
        else r = withJunk;
      }
    }
    this.box = r.box;
    for (const id of [...this.ackAt.keys()]) if (!this.box.waiting.some((w) => w.id === id)) this.ackAt.delete(id);
    this.toy = null;
    this.version++;
    this.fx.push({ k: "set", seat: this.seat });
    if (r.cleared > 0) this.fx.push({ k: "clear", seat: this.seat, rows: r.cleared });
    if (r.pocketed.length > 0) this.fx.push({ k: "pocket", seat: this.seat });
    this.batcher.push(["l", toy.n, toy.rot, toy.x, toy.y, ms, landed], now);
    if (this.box.out) this.fx.push({ k: "out", seat: this.seat });
    else this.spawnToy(now);
  }

  /** After a hit changed the box: the toy in hand moves up out of anything now in its way. */
  private afterChange(): void {
    if (this.box.out) {
      this.toy = null;
      this.fx.push({ k: "out", seat: this.seat });
      return;
    }
    const toy = this.toy;
    if (!toy) return;
    let lifted = false;
    while (!fits(this.box, toy.id, toy.rot, toy.x, toy.y) && toy.y < 25) {
      toy.y++;
      lifted = true;
    }
    if (lifted) this.batcher.push(["m", toy.n, toy.rot, toy.x, toy.y], this.now());
  }
}

