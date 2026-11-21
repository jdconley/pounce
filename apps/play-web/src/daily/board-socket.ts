/**
 * The family board, live (docs/daily-protocol.md "The board socket"): a phone's socket to its
 * person's board. Browsers can't send headers, so the device token rides as the subprotocol
 * `pounce.token.<token>` beside `pounce`, and `person` in the query. It hears the board snapshot,
 * results, progress and the TV count; anything else (a TV's watch frames, a kind added later) is
 * skipped. Reconnects with backoff; a 404 (the Dish off) ends it.
 */
import { BACKOFF, wsUrl, type SocketFactory, type SocketLike } from "../net/socket";

import type { BoardAnswer } from "@pounce/play-api/daily/messages";
import type { DailyResult } from "@pounce/play-api/daily/module";

export type BoardEvent =
  | { kind: "board"; board: BoardAnswer }
  | { kind: "result"; player: string; result: DailyResult }
  | { kind: "progress"; player: string; game: string; progress: number }
  | { kind: "tvs"; count: number }
  /** The server has no board for this person (the Dish is off): stop asking. */
  | { kind: "gone" };

export type BoardSocketOptions = {
  person: string;
  origin?: string;
  token: () => Promise<string>;
  /** Forget a token the server refused (4401): the next connect mints one. */
  dropToken?: () => void;
  factory?: SocketFactory;
  setTimer?: (fn: () => void, ms: number) => unknown;
  clearTimer?: (id: unknown) => void;
};

const PING_MS = 3000;

/** A message as the server sent it, as an event, or null for one this client doesn't use. */
export function boardEvent(raw: unknown): BoardEvent | null {
  if (typeof raw !== "object" || raw === null) return null;
  const m = raw as Record<string, unknown>;
  switch (m.t) {
    case "board":
      return typeof m.board === "object" && m.board !== null ? { kind: "board", board: m.board as BoardAnswer } : null;
    case "result":
      return typeof m.player === "string" && typeof m.result === "object" && m.result !== null
        ? { kind: "result", player: m.player, result: m.result as DailyResult }
        : null;
    case "progress":
      return typeof m.player === "string" && typeof m.game === "string" && typeof m.progress === "number"
        ? { kind: "progress", player: m.player, game: m.game, progress: m.progress }
        : null;
    case "tvs":
      return typeof m.count === "number" ? { kind: "tvs", count: m.count } : null;
    default:
      return null;
  }
}

export class BoardSocket {
  private ws: SocketLike | null = null;
  private stopped = false;
  private failures = 0;
  private timer: unknown = null;
  private ping: unknown = null;
  private on: (e: BoardEvent) => void = () => undefined;
  private readonly setTimer: (fn: () => void, ms: number) => unknown;
  private readonly clearTimer: (id: unknown) => void;

  constructor(private readonly options: BoardSocketOptions) {
    this.setTimer = options.setTimer ?? ((fn, ms) => setTimeout(fn, ms));
    this.clearTimer = options.clearTimer ?? ((id) => clearTimeout(id as ReturnType<typeof setTimeout>));
  }

  start(on: (e: BoardEvent) => void): void {
    this.on = on;
    void this.connect();
  }

  stop(): void {
    this.stopped = true;
    this.clearTimers();
    this.close();
  }

  private clearTimers(): void {
    if (this.timer !== null) this.clearTimer(this.timer);
    if (this.ping !== null) this.clearTimer(this.ping);
    this.timer = this.ping = null;
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

  private async connect(): Promise<void> {
    if (this.stopped) return;
    let token: string;
    try {
      token = await this.options.token();
    } catch {
      return this.retry();
    }
    if (this.stopped) return;
    const origin = this.options.origin ?? location.origin;
    const url = new URL(wsUrl(origin, "/v1/daily/board/ws"));
    url.searchParams.set("person", this.options.person);
    const factory: SocketFactory = this.options.factory ?? ((u, p) => new WebSocket(u, p) as unknown as SocketLike);
    const ws = factory(url.toString(), ["pounce", `pounce.token.${token}`]);
    this.ws = ws;
    ws.onopen = () => {
      this.failures = 0;
      this.schedulePing();
    };
    ws.onmessage = (ev) => {
      let raw: unknown;
      try {
        raw = JSON.parse(String(ev.data));
      } catch {
        return;
      }
      const event = boardEvent(raw);
      if (event) this.on(event);
    };
    ws.onclose = (ev) => {
      this.ws = null;
      if (this.ping !== null) this.clearTimer(this.ping);
      this.ping = null;
      if (this.stopped) return;
      if (ev.code === 4404 || ev.code === 4403) {
        this.stopped = true;
        return this.on({ kind: "gone" });
      }
      if (ev.code === 4401) this.options.dropToken?.();
      this.retry();
    };
    ws.onerror = () => undefined;
  }

  private schedulePing(): void {
    this.ping = this.setTimer(() => {
      this.ping = null;
      try {
        this.ws?.send(JSON.stringify({ t: "ping" }));
      } catch {
        // Closing: onclose reconnects.
      }
      if (this.ws) this.schedulePing();
    }, PING_MS);
  }

  private retry(): void {
    if (this.stopped || this.timer !== null) return;
    const wait = BACKOFF[Math.min(this.failures, BACKOFF.length - 1)] as number;
    this.failures += 1;
    this.timer = this.setTimer(() => {
      this.timer = null;
      void this.connect();
    }, wait);
  }
}
