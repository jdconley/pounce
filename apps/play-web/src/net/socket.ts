/**
 * One room's socket, as `RoomSocket.swift` runs it: connect, reconnect with backoff, heartbeats
 * and the link meter, and a clear end for a room that is gone, a lockout or a refusal. Browsers
 * can't send headers on a socket, so the token rides as a subprotocol and the app headers in the
 * query (play-api `http/browser-socket.ts`); a refusal arrives as a close code.
 */
import { APP_HEADER, GAMES } from "../lib/env";

import type { ClientMessage, ServerMessage } from "@pounce/play-api/protocol";


export type LinkQuality = "good" | "weak";

export type SocketEvent =
  | { kind: "connecting" }
  | { kind: "connected" }
  | { kind: "message"; message: ServerMessage }
  | { kind: "disconnected" }
  /** No such table (a bad code, or a table that closed and was deleted). */
  | { kind: "notFound" }
  /** Too many wrong codes from this device lately. */
  | { kind: "locked" }
  /** The room closed for good. */
  | { kind: "closed" }
  /** The server says this build is too old: reload. */
  | { kind: "refused" }
  | { kind: "link"; quality: LinkQuality };

/** What a WebSocket needs to be, so tests can stand one in. */
export interface SocketLike {
  readonly readyState: number;
  send(data: string): void;
  close(code?: number, reason?: string): void;
  onopen: ((ev: Event) => void) | null;
  onmessage: ((ev: MessageEvent) => void) | null;
  onclose: ((ev: CloseEvent) => void) | null;
  onerror: ((ev: Event) => void) | null;
}

export type SocketFactory = (url: string, protocols: string[]) => SocketLike;

export type MeterConfig = { pingEvery: number; weakAfter: number; goodUnder: number; goodPongs: number; deadAfter: number };

const METER: MeterConfig = { pingEvery: 3000, weakAfter: 1500, goodUnder: 1000, goodPongs: 2, deadAfter: 10_000 };
export const BACKOFF = [250, 500, 1000, 2000, 4000, 8000];
const TICK = 500;
/** How long a connect may take before it counts as a failure. */
const CONNECT_TIMEOUT = 15_000;

/** The link meter (`LinkMeter.swift`): one heartbeat out at a time, weak when slow, dead when silent. */
export class LinkMeter {
  quality: LinkQuality = "good";
  lastRoundTrip: number | null = null;
  private outstanding: number | null = null;
  private lastPing: number | null = null;
  private lastHeard: number;
  private fast = 0;

  constructor(
    public config: MeterConfig,
    now: number,
  ) {
    this.lastHeard = now;
  }

  shouldPing(now: number): boolean {
    if (this.outstanding !== null) return false;
    return this.lastPing === null || now - this.lastPing >= this.config.pingEvery;
  }

  pingSent(now: number): void {
    this.outstanding = now;
    this.lastPing = now;
  }

  pong(now: number): void {
    this.lastHeard = Math.max(this.lastHeard, now);
    if (this.outstanding === null) return;
    const trip = now - this.outstanding;
    this.outstanding = null;
    this.lastRoundTrip = trip;
    if (trip >= this.config.weakAfter) {
      this.quality = "weak";
      this.fast = 0;
    } else if (trip < this.config.goodUnder) {
      this.fast += 1;
      if (this.fast >= this.config.goodPongs) this.quality = "good";
    } else {
      this.fast = 0;
    }
  }

  heard(now: number): void {
    this.lastHeard = Math.max(this.lastHeard, now);
  }

  /** "dead": a ping out and nothing heard for `deadAfter`. */
  tick(now: number): "alive" | "dead" {
    if (this.outstanding === null) return "alive";
    if (now - this.outstanding >= this.config.weakAfter) {
      this.quality = "weak";
      this.fast = 0;
    }
    return now - this.outstanding >= this.config.deadAfter && now - this.lastHeard >= this.config.deadAfter ? "dead" : "alive";
  }
}

/** A socket URL on `origin` (http becomes ws, https wss), with the app's headers as its query. */
export function wsUrl(origin: string, path: string, role?: "screen"): string {
  const url = new URL(path, origin);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.searchParams.set("games", GAMES);
  url.searchParams.set("app", APP_HEADER);
  if (role) url.searchParams.set("role", role);
  return url.toString();
}

/** The socket URL for a room on `origin`; a TV joins it as the table's `screen`. */
export function socketUrl(origin: string, code: string, role?: "screen"): string {
  return wsUrl(origin, `/v1/rooms/${encodeURIComponent(code)}/ws`, role);
}

export type RoomSocketOptions = {
  code: string;
  origin?: string;
  /** "screen": a TV watching the table, not a seat at it. */
  role?: "screen";
  token: () => Promise<string>;
  /** Forget a token the server refused (4401): the next connect mints one. */
  dropToken?: () => void;
  factory?: SocketFactory;
  now?: () => number;
  setTimer?: (fn: () => void, ms: number) => unknown;
  clearTimer?: (id: unknown) => void;
  backoff?: number[];
};

export class RoomSocket {
  private listeners = new Set<(e: SocketEvent) => void>();
  private ws: SocketLike | null = null;
  private generation = 0;
  private attempt = 0;
  private finished = false;
  private started = false;
  private meter: LinkMeter | null = null;
  private appPings: number | null = null;
  private shown: LinkQuality = "good";
  private beatTimer: unknown = null;
  private retryTimer: unknown = null;
  private readonly factory: SocketFactory;
  private readonly now: () => number;
  private readonly setTimer: (fn: () => void, ms: number) => unknown;
  private readonly clearTimer: (id: unknown) => void;
  private readonly backoff: number[];
  private readonly url: string;

  constructor(private readonly options: RoomSocketOptions) {
    this.factory = options.factory ?? ((url, protocols) => new WebSocket(url, protocols) as unknown as SocketLike);
    this.now = options.now ?? (() => performance.now());
    this.setTimer = options.setTimer ?? ((fn, ms) => setTimeout(fn, ms));
    this.clearTimer = options.clearTimer ?? ((id) => clearTimeout(id as ReturnType<typeof setTimeout>));
    this.backoff = options.backoff ?? BACKOFF;
    this.url = socketUrl(options.origin ?? location.origin, options.code, options.role);
  }

  on(listener: (e: SocketEvent) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private emit(event: SocketEvent): void {
    for (const listener of [...this.listeners]) listener(event);
  }

  get connected(): boolean {
    return this.ws !== null && this.ws.readyState === 1 && this.meter !== null;
  }

  start(): void {
    if (this.started || this.finished) return;
    this.started = true;
    void this.run();
  }

  /** Sends a message; false when there is no open connection to send it on. */
  send(message: ClientMessage): boolean {
    if (!this.connected || !this.ws) return false;
    try {
      this.ws.send(JSON.stringify(message));
      return true;
    } catch {
      return false;
    }
  }

  /** Connect again now (the network came back, the tab woke up), with the backoff reset. */
  reconnectNow(): void {
    if (this.finished) return;
    this.started = true;
    this.attempt = 0;
    const had = this.ws !== null;
    this.drop();
    if (had) this.emit({ kind: "disconnected" });
    void this.run();
  }

  stop(): void {
    if (this.finished) return;
    this.finish();
  }

  private finish(): void {
    this.finished = true;
    this.generation += 1;
    this.drop();
    if (this.retryTimer !== null) this.clearTimer(this.retryTimer);
  }

  private drop(): void {
    if (this.beatTimer !== null) this.clearTimer(this.beatTimer);
    this.beatTimer = null;
    this.meter = null;
    const ws = this.ws;
    this.ws = null;
    if (ws) {
      ws.onopen = ws.onmessage = ws.onclose = ws.onerror = null;
      try {
        ws.close(1000);
      } catch {
        // Already closed.
      }
    }
  }

  private async run(): Promise<void> {
    if (this.retryTimer !== null) this.clearTimer(this.retryTimer);
    this.retryTimer = null;
    const gen = ++this.generation;
    this.emit({ kind: "connecting" });
    let token: string;
    try {
      token = await this.options.token();
    } catch {
      if (gen === this.generation && !this.finished) this.retry(gen);
      return;
    }
    if (gen !== this.generation || this.finished) return;
    let ws: SocketLike;
    try {
      ws = this.factory(this.url, ["pounce", `pounce.token.${token}`]);
    } catch {
      this.retry(gen);
      return;
    }
    this.ws = ws;
    let opened = false;
    const timeout = this.setTimer(() => {
      if (!opened && gen === this.generation) this.lost(gen);
    }, CONNECT_TIMEOUT);
    ws.onopen = () => {
      if (gen !== this.generation) return;
      opened = true;
      this.clearTimer(timeout);
      this.meter = new LinkMeter({ ...METER, ...(this.appPings ? { pingEvery: this.appPings } : {}) }, this.now());
      this.shown = "good";
      this.emit({ kind: "connected" });
      this.scheduleBeat(gen);
    };
    ws.onmessage = (ev) => {
      if (gen !== this.generation) return;
      this.meter?.heard(this.now());
      let message: ServerMessage;
      try {
        message = JSON.parse(String(ev.data)) as ServerMessage;
      } catch {
        return;
      }
      if (message.t === "pong") {
        this.pong();
        return;
      }
      if (message.t === "snapshot") {
        this.attempt = 0;
        this.appPings = message.room.link ? Math.min(Math.max(message.room.link.ping, 1000), 30_000) : null;
        if (this.meter && this.appPings) this.meter.config.pingEvery = this.appPings;
      }
      this.emit({ kind: "message", message });
      if (message.t === "error" && message.code === "room_closed") {
        this.emit({ kind: "closed" });
        this.finish();
      }
    };
    ws.onerror = () => undefined;
    ws.onclose = (ev) => {
      if (gen !== this.generation) return;
      this.clearTimer(timeout);
      const code = ev.code;
      if (code === 4404) return this.end({ kind: "notFound" });
      if (code === 4429) return this.end({ kind: "locked" });
      if (code === 4426) return this.end({ kind: "refused" });
      if (code === 4401) this.options.dropToken?.();
      this.lost(gen);
    };
  }

  private end(event: SocketEvent): void {
    this.finish();
    this.emit(event);
  }

  /** The connection is gone: say so and try again after the backoff. */
  private lost(gen: number): void {
    if (gen !== this.generation || this.finished) return;
    this.drop();
    this.emit({ kind: "disconnected" });
    this.retry(gen);
  }

  private retry(gen: number): void {
    if (this.finished) return;
    const delay = this.backoff.length === 0 ? 0 : this.backoff[Math.min(this.attempt, this.backoff.length - 1)];
    this.attempt += 1;
    this.retryTimer = this.setTimer(() => {
      if (gen === this.generation && !this.finished) void this.run();
    }, delay);
  }

  private scheduleBeat(gen: number): void {
    this.beatTimer = this.setTimer(() => this.beat(gen), TICK);
  }

  /** Every tick: a heartbeat when one is due (only to a server that answers them), then the meter's verdict. */
  private beat(gen: number): void {
    if (gen !== this.generation || !this.meter || !this.ws) return;
    const now = this.now();
    if (this.appPings !== null && this.meter.shouldPing(now)) {
      this.meter.pingSent(now);
      try {
        this.ws.send(JSON.stringify({ t: "ping" }));
      } catch {
        // The meter notices.
      }
    }
    const verdict = this.meter.tick(now);
    this.show(this.meter.quality);
    if (verdict === "dead") {
      this.lost(gen);
      return;
    }
    this.scheduleBeat(gen);
  }

  private pong(): void {
    if (!this.meter) return;
    this.meter.pong(this.now());
    this.show(this.meter.quality);
  }

  private show(quality: LinkQuality): void {
    if (quality === this.shown) return;
    this.shown = quality;
    this.emit({ kind: "link", quality });
    if (this.appPings !== null && this.ws) {
      try {
        this.ws.send(JSON.stringify({ t: "link", state: quality }));
      } catch {
        // Not sent.
      }
    }
  }
}
