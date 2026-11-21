/**
 * The Daily Dish's state, in memory: whether the server has it on, today's board, the stats and
 * how many TVs show it. Screens read it and re-render; the network lives here. While any Dish
 * screen is up (Home's Today, the Dish, a puzzle) the board socket keeps it live.
 *
 * The Dish is "off" only on a 404 from the board (the server's `DAILY` flag off, or no player): it
 * stays hidden then. Offline it stays "unknown" (also hidden) and the next load decides.
 */
import { useEffect, useState } from "preact/hooks";

import { api, ApiError } from "../net/api";
import { profileSynced } from "../store/app";

import { BoardSocket, type BoardEvent } from "./board-socket";
import { dailyPath } from "./client";

import type { BoardRow, Stats } from "@pounce/play-api/daily/board";
import type { BoardAnswer } from "@pounce/play-api/daily/messages";

export type DishState = {
  status: "unknown" | "off" | "on";
  board: BoardAnswer | null;
  stats: Record<string, Stats> | null;
  tvs: number;
};

type Socket = { start: (on: (e: BoardEvent) => void) => void; stop: () => void };

export type DishDeps = {
  /** The profile upload in flight, if any: until it lands the server may not know a new player (a 403). */
  profileSynced: () => Promise<void>;
  call: (method: string, path: string, body?: unknown) => Promise<Response>;
  socket: (person: string) => Socket;
};

const EMPTY: DishState = { status: "unknown", board: null, stats: null, tvs: 0 };

/** The board owner's own row in `game`, or null when they haven't played it. */
export function myRow(board: BoardAnswer | null, game: string): BoardRow | null {
  return board?.games.find((g) => g.game === game)?.rows.find((r) => r.player === "me") ?? null;
}

/** The top of `game`'s board (a result, not someone still playing), or null. */
export function bestRow(board: BoardAnswer | null, game: string): BoardRow | null {
  const top = board?.games.find((g) => g.game === game)?.rows[0];
  return top?.result ? top : null;
}

export class DishStore {
  state: DishState = EMPTY;
  private person: string | null = null;
  private holds = 0;
  private socket: Socket | null = null;
  private readonly listeners = new Set<() => void>();
  private loading: Promise<void> | null = null;

  constructor(private readonly deps: DishDeps) {}

  listen(l: () => void): () => void {
    this.listeners.add(l);
    return () => void this.listeners.delete(l);
  }

  private set(patch: Partial<DishState>): void {
    this.state = { ...this.state, ...patch };
    for (const l of [...this.listeners]) l();
  }

  /** A screen that shows the Dish for `person`: loads it, and keeps it live until released. */
  retain(person: string): () => void {
    if (person !== this.person) {
      this.socket?.stop();
      this.socket = null;
      this.person = person;
      this.state = EMPTY;
      this.loading = null;
    }
    this.holds += 1;
    if (this.state.status !== "off") void this.refresh();
    let released = false;
    return () => {
      if (released) return;
      released = true;
      this.holds -= 1;
      if (this.holds === 0) {
        this.socket?.stop();
        this.socket = null;
      }
    };
  }

  /** Loads the board and stats again (after a run ends, on coming back online). */
  refresh(): Promise<void> {
    this.loading ??= this.load().finally(() => (this.loading = null));
    return this.loading;
  }

  private async load(): Promise<void> {
    const person = this.person;
    if (!person) return;
    await this.deps.profileSynced();
    if (person !== this.person) return;
    let board: BoardAnswer;
    try {
      board = (await (await this.deps.call("GET", dailyPath("/v1/daily/board", person))).json()) as BoardAnswer;
    } catch (error) {
      if (person === this.person && error instanceof ApiError && error.status === 404) this.set({ status: "off" });
      return;
    }
    if (person !== this.person) return;
    this.set({ status: "on", board, tvs: board.tvs });
    if (this.holds > 0 && !this.socket) {
      this.socket = this.deps.socket(person);
      this.socket.start((e) => this.hear(e));
    }
    await this.loadStats();
  }

  async loadStats(): Promise<void> {
    const person = this.person;
    if (!person) return;
    try {
      const body = (await (await this.deps.call("GET", dailyPath("/v1/daily/stats", person))).json()) as { games: Record<string, Stats> };
      if (person === this.person) this.set({ stats: body.games });
    } catch {
      // The board still shows; stats come with the next load.
    }
  }

  private hear(e: BoardEvent): void {
    const board = this.state.board;
    switch (e.kind) {
      case "board":
        return this.set({ status: "on", board: e.board, tvs: e.board.tvs });
      case "tvs":
        return this.set({ tvs: e.count });
      case "gone":
        this.socket = null;
        return this.set({ status: "off" });
      case "result":
      case "progress": {
        if (!board) return;
        const games = board.games.map((g) => {
          if (g.game !== (e.kind === "result" ? e.result.game : e.game)) return g;
          return {
            ...g,
            rows: g.rows.map((r) =>
              r.player !== e.player
                ? r
                : e.kind === "result"
                  ? { ...r, result: e.result, playing: null }
                  : r.result
                    ? r
                    : { ...r, playing: { progress: e.progress } },
            ),
          };
        });
        this.set({ board: { ...board, games } });
        if (e.kind === "result" && e.player === "me") void this.loadStats();
        return;
      }
    }
  }
}

export const dishStore = new DishStore({
  profileSynced,
  call: (m, p, b) => api.call(m, p, b),
  socket: (person) =>
    new BoardSocket({
      person,
      token: async () => (await api.credential()).token,
      dropToken: () => api.forget(),
    }),
});

/** The Dish for `person` (the device's owner), live while the calling screen is up. */
export function useDish(person: string | undefined): DishState {
  const [, setN] = useState(0);
  useEffect(() => dishStore.listen(() => setN((n) => n + 1)), []);
  useEffect(() => (person ? dishStore.retain(person) : undefined), [person]);
  return dishStore.state;
}
