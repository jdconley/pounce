/**
 * A TV waiting to be linked: it asks for a token and code (`POST /v1/screens`), shows them, and
 * listens on the token's socket for the phone that scans or types them. The code is renewed
 * before it expires; once a phone links, the link is spent and this stops.
 */
import { BACKOFF, wsUrl, type SocketFactory, type SocketLike } from "./socket";

import type { Api } from "./api";

export type ScreenLinkEvent =
  | { kind: "code"; token: string; code: string; url: string }
  | { kind: "linked"; room: string }
  /** Waiting on the network: the code shown may not reach the server. */
  | { kind: "offline" };

export type ScreenLinkOptions = {
  api: Api;
  origin?: string;
  factory?: SocketFactory;
  setTimer?: (fn: () => void, ms: number) => unknown;
  clearTimer?: (id: unknown) => void;
  backoff?: number[];
};

/** The share of a code's life after which a new one is asked for. */
const RENEW_AT = 0.8;

export class ScreenLink {
  private listeners = new Set<(e: ScreenLinkEvent) => void>();
  private ws: SocketLike | null = null;
  /** The socket of the code being replaced: kept listening until the new one is open. */
  private old: SocketLike | null = null;
  private generation = 0;
  private attempt = 0;
  private stopped = true;
  private showing: string | undefined;
  private token = "";
  private renewTimer: unknown = null;
  private retryTimer: unknown = null;
  private readonly factory: SocketFactory;
  private readonly setTimer: (fn: () => void, ms: number) => unknown;
  private readonly clearTimer: (id: unknown) => void;
  private readonly backoff: number[];

  constructor(private readonly options: ScreenLinkOptions) {
    this.factory = options.factory ?? ((url, protocols) => new WebSocket(url, protocols) as unknown as SocketLike);
    this.setTimer = options.setTimer ?? ((fn, ms) => setTimeout(fn, ms));
    this.clearTimer = options.clearTimer ?? ((id) => clearTimeout(id as ReturnType<typeof setTimeout>));
    this.backoff = options.backoff ?? BACKOFF;
  }

  on(listener: (e: ScreenLinkEvent) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private emit(event: ScreenLinkEvent): void {
    for (const listener of [...this.listeners]) listener(event);
  }

  /** Asks for a code and starts listening for the link; `showing` is a table this TV already shows. */
  start(showing?: string): void {
    if (!this.stopped) return;
    this.stopped = false;
    this.showing = showing;
    this.attempt = 0;
    void this.renew();
  }

  stop(): void {
    this.stopped = true;
    this.generation += 1;
    this.closeSocket();
    this.clearTimers();
  }

  private clearTimers(): void {
    if (this.renewTimer !== null) this.clearTimer(this.renewTimer);
    if (this.retryTimer !== null) this.clearTimer(this.retryTimer);
    this.renewTimer = this.retryTimer = null;
  }

  private closeSocket(): void {
    const old = this.old;
    this.old = null;
    if (old) this.detach(old);
    const ws = this.ws;
    this.ws = null;
    if (ws) this.detach(ws);
  }

  private detach(ws: SocketLike): void {
    ws.onopen = ws.onmessage = ws.onclose = ws.onerror = null;
    try {
      ws.close(1000);
    } catch {
      // Already closed.
    }
  }

  /**
   * A new token and code, a new socket, the old socket closed. A timed renewal keeps the old
   * socket listening (a phone may link the old code meanwhile) until the new one is open.
   */
  private async renew(timed = false): Promise<void> {
    this.clearTimers();
    if (!timed) this.closeSocket();
    const gen = ++this.generation;
    let made: Awaited<ReturnType<Api["screens"]>>;
    try {
      made = await this.options.api.screens(this.showing);
    } catch {
      if (gen === this.generation && !this.stopped) {
        // A timed renewal that failed still has its old code and socket: try again, quietly.
        if (!timed) this.emit({ kind: "offline" });
        this.retry(gen, () => void this.renew(timed));
      }
      return;
    }
    if (gen !== this.generation || this.stopped) return;
    this.token = made.token;
    this.emit({ kind: "code", token: made.token, code: made.code, url: made.url });
    this.renewTimer = this.setTimer(() => void this.renew(true), Math.round(made.expiresIn * RENEW_AT));
    void this.connect(gen);
  }

  private async connect(gen: number): Promise<void> {
    let deviceToken: string;
    try {
      deviceToken = (await this.options.api.credential()).token;
    } catch {
      if (gen === this.generation && !this.stopped) this.retry(gen, () => void this.connect(gen));
      return;
    }
    if (gen !== this.generation || this.stopped) return;
    let ws: SocketLike;
    try {
      const origin = this.options.origin ?? location.origin;
      ws = this.factory(wsUrl(origin, `/v1/screens/${encodeURIComponent(this.token)}/ws`), ["pounce", `pounce.token.${deviceToken}`]);
    } catch {
      this.retry(gen, () => void this.connect(gen));
      return;
    }
    if (this.old) this.detach(this.old);
    this.old = this.ws;
    this.ws = ws;
    ws.onopen = () => {
      if (ws !== this.ws) return;
      this.attempt = 0;
      if (this.old) this.detach(this.old);
      this.old = null;
    };
    ws.onerror = () => undefined;
    ws.onmessage = (ev) => {
      if (ws !== this.ws && ws !== this.old) return;
      let message: { t?: string; room?: string };
      try {
        message = JSON.parse(String(ev.data)) as { t?: string; room?: string };
      } catch {
        return;
      }
      if (message.t === "ping") {
        try {
          ws.send(JSON.stringify({ t: "pong" }));
        } catch {
          // The server notices.
        }
      } else if (message.t === "linked" && typeof message.room === "string") {
        this.stop();
        this.emit({ kind: "linked", room: message.room });
      } else if (message.t === "expired") {
        void this.renew();
      }
    };
    ws.onclose = (ev) => {
      if (ws !== this.ws) return;
      const now = this.generation;
      this.closeSocket();
      // A token the server no longer knows (or a device token it refused) is replaced, not retried.
      if (ev.code === 4404 || ev.code === 4401) {
        void this.renew();
        return;
      }
      this.emit({ kind: "offline" });
      this.retry(now, () => void this.connect(now));
    };
  }

  private retry(gen: number, again: () => void): void {
    const delay = this.backoff.length === 0 ? 0 : this.backoff[Math.min(this.attempt, this.backoff.length - 1)];
    this.attempt += 1;
    if (this.retryTimer !== null) this.clearTimer(this.retryTimer);
    this.retryTimer = this.setTimer(() => {
      this.retryTimer = null;
      if (gen === this.generation && !this.stopped) again();
    }, delay);
  }
}
