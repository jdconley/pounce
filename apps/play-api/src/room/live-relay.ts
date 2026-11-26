/**
 * A live relay: one device streams small updates (Purrtrait's ink, Toy Tumble's moves), the room
 * passes each on to the devices that show them, and keeps what was sent for the current key (a
 * turn) in memory only, so a device that joins late can catch up.
 *
 * The relay knows nothing of any game. A game supplies its rate, how a fresh tally starts (its own
 * checking state: next stroke id, points so far) and how to compact its log into the smallest
 * catch-up that looks the same. The room decides who may send and who hears it.
 *
 * What it owns:
 * - The log for one key, in memory, never in `RoomState` or storage. A new key starts it empty;
 *   null ends it.
 * - A per-device rolling one-second rate limit (`admit`).
 * - A lost log: a room rebuilt from storage with a key still live (`lost`) has none until the
 *   sender sends a batch that restarts it. `askResend` asks the sender for it, and its reply is
 *   exempt from the rate limit once, for `resendMs` from the reply's first message.
 * - Fan-out to chosen devices, and the catch-up for one, as the room's `Outbound[]`.
 *
 * Usage:
 *
 * ```ts
 * const relay = new LiveRelay<Op, Tally>({ perSecond: 25, start: (rebuilt) => fresh(rebuilt), compact }, now);
 * relay.follow(liveKey(state));                      // after every change: a new key drops the log
 * if (!relay.admit(device, wipes(ops))) return [];   // over the limit: dropped
 * const base = relay.base(wipes(ops));               // null: nothing live, or a lost log not restarted
 * const checked = base && check(ops, base);          // the game's own check
 * if (checked?.ok) { relay.record(ops, checked.tally); return relay.fanOut([screen, device], message); }
 * // On connect: relay.missing ? relay.askResend(sender, resendMsg) : relay.catchUp(device, syncMsg)
 * ```
 */

import type { ServerMessage } from "../protocol";
import type { Outbound } from "./core";

export type LiveRelayConfig<Op, Tally> = {
  /** Most messages one device may send in a rolling second; more are dropped. */
  perSecond: number;
  /**
   * A fresh log's tally, the game's own checking state. `rebuilt`: it stands in for a log the room
   * lost (a resend), so the game may relax what it can no longer know (Purrtrait: stroke ids).
   */
  start(rebuilt: boolean): Tally;
  /** The log made as small as it can be while showing the same: what a late joiner gets. */
  compact(log: readonly Op[]): Op[];
  /** How long a resend reply is exempt from the rate limit, from its first message. Default 1000 ms. */
  resendMs?: number;
};

const WINDOW_MS = 1000;
/** The log is compacted once it grows this much past its last compacted size. */
const COMPACT_SLACK = 256;

export class LiveRelay<Op, Tally> {
  private current: string | null = null;
  private log: Op[] | null = null;
  private tally: Tally | null = null;
  private lostLog = false;
  private compactedAt = 0;
  private readonly times = new Map<string, number[]>();
  /** "armed": asked for a resend, reply not begun. A number: the reply's exemption ends then. */
  private readonly exempt = new Map<string, "armed" | number>();

  constructor(
    private readonly config: LiveRelayConfig<Op, Tally>,
    private readonly now: () => number,
  ) {}

  /** The live key (a turn), or null when nothing is live. */
  get key(): string | null {
    return this.current;
  }

  /** The key is live but its log was lost (`lost`), and nothing has restarted it yet. */
  get missing(): boolean {
    return this.lostLog;
  }

  /** How many ops the log holds now (after its own compaction). */
  get size(): number {
    return this.log?.length ?? 0;
  }

  /** Follows the room: `key` is what is live now. A new key starts an empty log; null ends it; the same key changes nothing. */
  follow(key: string | null): void {
    if (key === this.current) return;
    this.current = key;
    this.log = key === null ? null : [];
    this.tally = key === null ? null : this.config.start(false);
    this.lostLog = false;
    this.compactedAt = 0;
    this.exempt.clear();
  }

  /** A room rebuilt from storage with `key` live: its log is gone until a batch restarts it. */
  lost(key: string): void {
    this.current = key;
    this.log = null;
    this.tally = null;
    this.lostLog = true;
    this.exempt.clear();
  }

  /**
   * Counts one message from `device` against its rolling second; false: drop it. `restarts`: the
   * message begins again from nothing (a wipe), so it can open a resend reply's exemption.
   */
  admit(device: string, restarts = false): boolean {
    const now = this.now();
    const exempt = this.exempt.get(device);
    if (exempt === "armed" && restarts) {
      this.exempt.set(device, now + (this.config.resendMs ?? WINDOW_MS));
      return true;
    }
    if (typeof exempt === "number") {
      if (now < exempt) return true;
      this.exempt.delete(device);
    }
    const recent = (this.times.get(device) ?? []).filter((at) => at > now - WINDOW_MS);
    if (recent.length >= this.config.perSecond) {
      this.times.set(device, recent);
      return false;
    }
    this.times.set(device, [...recent, now]);
    return true;
  }

  /**
   * The tally to check a message against: the live one, or a fresh one for a message that restarts
   * a lost log. Null: nothing is live, or the log is lost and this message can't restart it.
   */
  base(restarts: boolean): Tally | null {
    if (this.current === null) return null;
    if (this.lostLog) return restarts ? this.config.start(true) : null;
    return this.tally;
  }

  /** Keeps an accepted message, and the game's tally after it. A lost log starts again from it. */
  record(ops: readonly Op[], tally: Tally): void {
    // Null only while lost: this message restarts it.
    if (this.log === null) {
      this.log = [];
      this.lostLog = false;
      this.compactedAt = 0;
    }
    this.log.push(...ops);
    this.tally = tally;
    if (this.log.length > 2 * this.compactedAt + COMPACT_SLACK) {
      this.log = this.config.compact(this.log);
      this.compactedAt = this.log.length;
    }
  }

  /** `message` to each of `devices`, once each. */
  fanOut(devices: Iterable<string>, message: ServerMessage): Outbound[] {
    return [...new Set(devices)].map((to) => ({ to, message }));
  }

  /** For a device joining late: the compacted log, built into the game's message. Nothing when there is no log. */
  catchUp(device: string, build: (key: string, ops: Op[]) => ServerMessage): Outbound[] {
    if (this.current === null || this.log === null) return [];
    return [{ to: device, message: build(this.current, this.config.compact(this.log)) }];
  }

  /** While the log is lost: asks `device`, the sender, for all of it. Its reply is then exempt from the limit once. */
  askResend(device: string, build: (key: string) => ServerMessage): Outbound[] {
    if (!this.lostLog) return [];
    this.exempt.set(device, "armed");
    return [{ to: device, message: build(this.current as string) }];
  }
}
