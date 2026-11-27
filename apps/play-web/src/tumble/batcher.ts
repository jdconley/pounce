/**
 * Batches one box's events for the socket (spec §6.3, `docs/live-protocol.md`): a batch at most
 * every 50 ms while something changes, at once on a set-down, a trick or an ack, and only the
 * latest position. Driven by the frame clock, so it needs no timer of its own.
 */
import type { ClientEvent } from "@pounce/play-api/tumble/wire";

export const BATCH_MS = 50;
/** The wire takes up to 64 events in a batch. */
const MAX_EVENTS = 64;

export class Batcher {
  private pending: ClientEvent[] = [];
  private lastSent = -Infinity;

  constructor(
    private readonly send: (ev: ClientEvent[]) => void,
    private readonly every = BATCH_MS,
  ) {}

  push(e: ClientEvent, now: number): void {
    if (e[0] === "m") this.pending = this.pending.filter((p) => p[0] !== "m");
    this.pending.push(e);
    if (e[0] !== "m" || now - this.lastSent >= this.every || this.pending.length >= MAX_EVENTS) this.flush(now);
  }

  /** Sends what waits once 50 ms have passed since the last batch. */
  step(now: number): void {
    if (this.pending.length > 0 && now - this.lastSent >= this.every) this.flush(now);
  }

  flush(now: number): void {
    if (this.pending.length === 0) return;
    const ev = this.pending;
    this.pending = [];
    this.lastSent = now;
    this.send(ev);
  }

  /** Drops what waits: the box was replaced by a sync. */
  clear(): void {
    this.pending = [];
  }
}
