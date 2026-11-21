/**
 * Tonight's board on the TV: the board socket, the board's state (`tv-board-model.ts`) and the
 * clock that ends the watch card, a watched result and a cheer. The screens read `state` and
 * hear `news` (a sound to play, the board gone); presses come back as `watch`, `notNow` and
 * `stopWatching`.
 */
import { BoardSocket, type BoardSocketOptions } from "../net/tv-board-socket";
import { boardStep, EMPTY_SCREEN, nextTick, notNow, stopWatching, tick, watch, type BoardScreen } from "../ui/tv/tv-board-model";

export type TvBoardState = { screen: BoardScreen; online: boolean; everConnected: boolean };

/** What the screens act on once: a cheer's sound, an offer's pop, the board gone. */
export type TvBoardNews = { kind: "cheer"; solved: boolean } | { kind: "offer" } | { kind: "gone" };

export type TvBoardListener = { change?: (s: TvBoardState) => void; news?: (n: TvBoardNews) => void };

export type TvBoardOptions = BoardSocketOptions & { now?: () => number };

export class TvBoardStore {
  state: TvBoardState = { screen: EMPTY_SCREEN, online: false, everConnected: false };
  private listeners = new Set<TvBoardListener>();
  private readonly socket: BoardSocket;
  private readonly now: () => number;
  private readonly setTimer: (fn: () => void, ms: number) => unknown;
  private readonly clearTimer: (id: unknown) => void;
  private timer: unknown = null;
  private off: (() => void) | null = null;

  constructor(options: TvBoardOptions) {
    this.socket = new BoardSocket(options);
    this.now = options.now ?? (() => Date.now());
    this.setTimer = options.setTimer ?? ((fn, ms) => setTimeout(fn, ms));
    this.clearTimer = options.clearTimer ?? ((id) => clearTimeout(id as ReturnType<typeof setTimeout>));
  }

  subscribe(listener: TvBoardListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  start(): void {
    this.off?.();
    this.off = this.socket.on((e) => {
      if (e.kind === "online") this.set({ online: true, everConnected: true });
      else if (e.kind === "offline") this.set({ online: false });
      else if (e.kind === "gone") this.tell({ kind: "gone" });
      else {
        const m = e.message;
        this.screen(boardStep(this.state.screen, m, this.now()));
        if (m.t === "result") this.tell({ kind: "cheer", solved: m.result.outcome === "solved" || m.result.outcome === "done" });
        else if (m.t === "watchOffer") this.tell({ kind: "offer" });
      }
    });
    this.socket.start();
  }

  stop(): void {
    this.off?.();
    this.off = null;
    this.socket.stop();
    if (this.timer !== null) this.clearTimer(this.timer);
    this.timer = null;
  }

  reconnectNow(): void {
    this.socket.reconnectNow();
  }

  watch(): void {
    this.screen(watch(this.state.screen));
  }

  notNow(): void {
    this.screen(notNow(this.state.screen));
  }

  stopWatching(): void {
    this.screen(stopWatching(this.state.screen));
  }

  private screen(next: BoardScreen): void {
    if (next !== this.state.screen) this.set({ screen: next });
    this.schedule();
  }

  /** One timer, for the next thing time ends. */
  private schedule(): void {
    if (this.timer !== null) this.clearTimer(this.timer);
    this.timer = null;
    const at = nextTick(this.state.screen);
    if (at === null) return;
    this.timer = this.setTimer(() => {
      this.timer = null;
      this.screen(tick(this.state.screen, this.now()));
    }, Math.max(0, at - this.now()));
  }

  private set(patch: Partial<TvBoardState>): void {
    this.state = { ...this.state, ...patch };
    for (const l of [...this.listeners]) l.change?.(this.state);
  }

  private tell(n: TvBoardNews): void {
    for (const l of [...this.listeners]) l.news?.(n);
  }
}
