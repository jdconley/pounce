/**
 * The TV's board socket (docs/daily-protocol.md, "The board socket"): the Daily Dish board it was
 * linked to, live. It connects as the TV's own device with its board token, pings, and reconnects
 * when the network drops. A board the server no longer knows (404, 4404 for a browser) or one
 * closed for good (1000 `revoked` or `expired`) is `gone`: the TV forgets its token and goes home.
 */
import { BACKOFF, wsUrl, type SocketFactory, type SocketLike } from "./socket";

import type { Api } from "./api";
import type { BoardMessage } from "@pounce/play-api/daily/messages";

export type BoardSocketEvent = { kind: "message"; message: BoardMessage } | { kind: "online" } | { kind: "offline" } | { kind: "gone" };

export type BoardSocketOptions = {
  api: Api;
  board: string;
  origin?: string;
  factory?: SocketFactory;
  setTimer?: (fn: () => void, ms: number) => unknown;
  clearTimer?: (id: unknown) => void;
  backoff?: number[];
};

const PING_MS = 25_000;
const GONE_REASONS = new Set(["revoked", "expired"]);

export class BoardSocket {
  private listeners = new Set<(e: BoardSocketEvent) => void>();
  private ws: SocketLike | null = null;
  private stopped = true;
  private generation = 0;
  private attempt = 0;
  private retryTimer: unknown = null;
  private pingTimer: unknown = null;
  private readonly factory: SocketFactory;
  private readonly setTimer: (fn: () => void, ms: number) => unknown;
  private readonly clearTimer: (id: unknown) => void;
  private readonly backoff: number[];

  constructor(private readonly options: BoardSocketOptions) {
    this.factory = options.factory ?? ((url, protocols) => new WebSocket(url, protocols) as unknown as SocketLike);
    this.setTimer = options.setTimer ?? ((fn, ms) => setTimeout(fn, ms));
    this.clearTimer = options.clearTimer ?? ((id) => clearTimeout(id as ReturnType<typeof setTimeout>));
    this.backoff = options.backoff ?? BACKOFF;
  }

  on(listener: (e: BoardSocketEvent) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private emit(e: BoardSocketEvent): void {
    for (const listener of [...this.listeners]) listener(e);
  }

  start(): void {
    if (!this.stopped) return;
    this.stopped = false;
    this.attempt = 0;
    void this.connect(++this.generation);
  }

  stop(): void {
    this.stopped = true;
    this.generation += 1;
    this.clearTimers();
    this.close();
  }

  /** Back in view, or the network is back: try now rather than after the backoff. */
  reconnectNow(): void {
    if (this.stopped || this.ws) return;
    this.clearTimers();
    this.attempt = 0;
    void this.connect(++this.generation);
  }

  private clearTimers(): void {
    if (this.retryTimer !== null) this.clearTimer(this.retryTimer);
    if (this.pingTimer !== null) this.clearTimer(this.pingTimer);
    this.retryTimer = this.pingTimer = null;
  }

  private close(): void {
    const ws = this.ws;
    this.ws = null;
    if (!ws) return;
    ws.onopen = ws.onmessage = ws.onclose = ws.onerror = null;
    try {
      ws.close(1000);
    } catch {
      // Already closed.
    }
  }

  private async connect(gen: number): Promise<void> {
    let token: string;
    try {
      token = (await this.options.api.credential()).token;
    } catch {
      if (gen === this.generation && !this.stopped) this.retry(gen);
      return;
    }
    if (gen !== this.generation || this.stopped) return;
    const origin = this.options.origin ?? location.origin;
    let ws: SocketLike;
    try {
      ws = this.factory(wsUrl(origin, `/v1/daily/board/ws?board=${encodeURIComponent(this.options.board)}`), ["pounce", `pounce.token.${token}`]);
    } catch {
      this.retry(gen);
      return;
    }
    this.ws = ws;
    ws.onerror = () => undefined;
    ws.onopen = () => {
      if (ws !== this.ws) return;
      this.attempt = 0;
      this.emit({ kind: "online" });
      this.ping(ws);
    };
    ws.onmessage = (ev) => {
      if (ws !== this.ws) return;
      let message: BoardMessage;
      try {
        message = JSON.parse(String(ev.data)) as BoardMessage;
      } catch {
        return;
      }
      if (typeof message?.t !== "string") return;
      this.emit({ kind: "message", message });
    };
    ws.onclose = (ev) => {
      if (ws !== this.ws) return;
      this.ws = null;
      this.clearTimers();
      if (ev.code === 4404 || (ev.code === 1000 && GONE_REASONS.has(ev.reason))) {
        this.stopped = true;
        this.emit({ kind: "gone" });
        return;
      }
      if (ev.code === 4401) this.options.api.forget();
      this.emit({ kind: "offline" });
      this.retry(this.generation);
    };
  }

  private ping(ws: SocketLike): void {
    this.pingTimer = this.setTimer(() => {
      this.pingTimer = null;
      if (ws !== this.ws) return;
      try {
        ws.send(JSON.stringify({ t: "ping" }));
      } catch {
        // The close handler takes it from here.
      }
      this.ping(ws);
    }, PING_MS);
  }

  private retry(gen: number): void {
    const delay = this.backoff.length === 0 ? 0 : this.backoff[Math.min(this.attempt, this.backoff.length - 1)]!;
    this.attempt += 1;
    if (this.retryTimer !== null) this.clearTimer(this.retryTimer);
    this.retryTimer = this.setTimer(() => {
      this.retryTimer = null;
      if (gen === this.generation && !this.stopped) void this.connect(gen);
    }, delay);
  }
}

/**
 * Whether the server has the Daily Dish on: its board socket, asked without an upgrade, answers
 * 426 when on and 404 when off (docs/daily-protocol.md). Any failure reads as off.
 */
export async function dailyOn(api: Api, origin: string = location.origin, fetcher: typeof fetch = fetch): Promise<boolean> {
  try {
    const token = (await api.credential()).token;
    const res = await fetcher(`${origin}/v1/daily/board/ws`, { method: "GET", headers: { authorization: `Bearer ${token}` } });
    return res.status === 426;
  } catch {
    return false;
  }
}
