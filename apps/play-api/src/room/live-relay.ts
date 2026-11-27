/**
 * The shared live layer: what a real-time game streams through its room, in memory only, never in
 * `RoomState` or storage. Each game keeps its own messages, checks and fan-out choices; nothing
 * here knows any game. Two pieces:
 *
 * - `LiveRelay`, the rate limit any live game uses (Toy Tumble design §6.10): at most `perSecond`
 *   messages a second per key (a device), over any rolling second. Toy Tumble uses it as it is.
 * - `LiveStream`, for a game whose late joiners need the picture so far (Purrtrait's ink): one
 *   device streams small updates, the room passes each on to the devices that show them, and the
 *   stream keeps what was sent for the current key (a turn) so a device that joins late can catch
 *   up. Its per-device rate is a `LiveRelay`, with a resend exemption on top.
 *
 * A `LiveStream`'s game supplies its rate, how a fresh tally starts (its own checking state: next
 * stroke id, points so far) and how to compact its log into the smallest catch-up that looks the
 * same. The room decides who may send and who hears it.
 *
 * What a `LiveStream` owns:
 * - The log for one key. A new key starts it empty; null ends it.
 * - The per-device rolling one-second rate limit (`admit`), a `LiveRelay`.
 * - A lost log: a room rebuilt from storage with a key still live (`lost`) has none until the
 *   sender sends a batch that restarts it. `askResend` asks the sender for it, and its whole reply
 *   is exempt from the rate limit once: from its first message (one that restarts) to the one the
 *   sender marks as its last, or `resendMs` after the first, whichever comes sooner.
 * - Fan-out to chosen devices, and the catch-up for one, as the room's `Outbound[]`.
 *
 * Usage:
 *
 * ```ts
 * // Rate only (Toy Tumble):
 * const limit = new LiveRelay(30);
 * if (!limit.allow(device, now)) return [];          // over the limit: dropped
 * limit.clear();                                     // a new round starts everyone afresh
 *
 * // Log, catch-up and resend (Purrtrait):
 * const stream = new LiveStream<Op, Tally>({ perSecond: 25, start: (rebuilt) => fresh(rebuilt), compact }, now);
 * stream.follow(liveKey(state));                     // after every change: a new key drops the log
 * if (!stream.admit(device, { restarts: wipes(ops), last })) return [];   // over the limit: dropped
 * const base = stream.base(wipes(ops));              // null: nothing live, or a lost log not restarted
 * const checked = base && check(ops, base);          // the game's own check
 * if (checked?.ok) { stream.record(ops, checked.tally); return stream.fanOut([screen, device], message); }
 * // On connect: stream.missing ? stream.askResend(sender, resendMsg) : stream.catchUp(device, syncMsg)
 * ```
 */

import type { ServerMessage } from "../protocol";
import type { Outbound } from "./core";

export type LiveStreamConfig<Op, Tally> = {
  /** Most messages one device may send in a rolling second; more are dropped. */
  perSecond: number;
  /**
   * A fresh log's tally, the game's own checking state. `rebuilt`: it stands in for a log the room
   * lost (a resend), so the game may relax what it can no longer know (Purrtrait: stroke ids).
   */
  start(rebuilt: boolean): Tally;
  /** The log made as small as it can be while showing the same: what a late joiner gets. */
  compact(log: readonly Op[]): Op[];
  /**
   * The longest a resend reply is exempt from the rate limit, from its first message, should its
   * last never come (a sender that dropped mid-reply). Default 5000 ms.
   */
  resendMs?: number;
};

/** What the room knows of one message for the rate limit. */
export type AdmitInfo = {
  /** It begins again from nothing (a wipe), so it can open a resend reply. */
  restarts?: boolean;
  /** The sender marked it the last of a resend reply: the exemption ends after it. */
  last?: boolean;
};

const RESEND_MS = 5000;
/** The log is compacted once it grows this much past its last compacted size. */
const COMPACT_SLACK = 256;

/** At most `perSecond` messages a second per key, over any rolling second. */
export class LiveRelay {
  private readonly perSecond: number;
  private readonly sent = new Map<string, number[]>();

  constructor(perSecond: number) {
    this.perSecond = perSecond;
  }

  /** True, and counted, when `key` may send one more at `now`; false when it is over its limit. */
  allow(key: string, now: number): boolean {
    const recent = (this.sent.get(key) ?? []).filter((at) => at > now - 1000);
    if (recent.length >= this.perSecond) {
      this.sent.set(key, recent);
      return false;
    }
    recent.push(now);
    this.sent.set(key, recent);
    return true;
  }

  /** Forgets every key: a new round starts everyone afresh. */
  clear(): void {
    this.sent.clear();
  }
}

export class LiveStream<Op, Tally> {
  private current: string | null = null;
  private log: Op[] | null = null;
  private tally: Tally | null = null;
  private lostLog = false;
  private compactedAt = 0;
  /** The per-device rolling second. A new key keeps it: the rate is per device, not per turn. */
  private readonly rate: LiveRelay;
  /** "armed": asked for a resend, reply not begun. A number: the reply's exemption ends then. */
  private readonly exempt = new Map<string, "armed" | number>();

  constructor(
    private readonly config: LiveStreamConfig<Op, Tally>,
    private readonly now: () => number,
  ) {
    this.rate = new LiveRelay(config.perSecond);
  }

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
   * Counts one message from `device` against its rolling second; false: drop it. A resend reply,
   * from its first message (`restarts`) to its `last`, is free.
   */
  admit(device: string, info: AdmitInfo = {}): boolean {
    const now = this.now();
    const exempt = this.exempt.get(device);
    if (exempt === "armed" && info.restarts) {
      if (info.last) this.exempt.delete(device);
      else this.exempt.set(device, now + (this.config.resendMs ?? RESEND_MS));
      return true;
    }
    if (typeof exempt === "number") {
      if (now < exempt) {
        if (info.last) this.exempt.delete(device);
        return true;
      }
      this.exempt.delete(device);
    }
    return this.rate.allow(device, now);
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

  /** While the log is lost: asks `device`, the sender, for all of it. Its whole reply is then exempt from the limit, once. */
  askResend(device: string, build: (key: string) => ServerMessage): Outbound[] {
    if (!this.lostLog) return [];
    this.exempt.set(device, "armed");
    return [{ to: device, message: build(this.current as string) }];
  }
}
