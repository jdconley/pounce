/**
 * The Daily Dish's state, in memory: whether the server has it on, today's board, the stats and
 * how many TVs show it. Screens read it and re-render; the network lives here. While any Dish
 * screen is up (Home's Today, the Dish, a puzzle) the board socket keeps it live.
 *
 * The Dish is "off" only on a 404 from the board (the server's `DAILY` flag off, or no player): it
 * stays hidden then. Offline, or refused (a 403: a new player's first profile save hasn't landed
 * yet), it stays "unknown" (also hidden) and the next load decides. The profile save landing
 * (`profileSaved`) is one: Home asks for the board as soon as a new player is named, which can
 * be before the server knows them.
 */
import { useEffect, useState } from "preact/hooks";

import { api, ApiError } from "../net/api";
import { useApp } from "../store/app";

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
  /** Load again if the one out now fails: it was asked before the server knew this player. */
  private again = false;
  /** Counts the socket's TV counts heard: a load asked before the latest one keeps its count. */
  private tvsHeard = 0;

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
      this.again = false;
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
    this.loading ??= this.load().finally(() => {
      this.loading = null;
      if (!this.again) return;
      this.again = false;
      // Only when the load that was out didn't show the Dish: it was answered before the save
      // landed (a 403, or a 404 while the new player is still being made).
      if (this.state.status !== "on") void this.refresh();
    });
    return this.loading;
  }

  /** `person`'s profile reached the server: a Dish not shown yet (refused before) loads now. */
  profileSaved(person: string): void {
    if (person !== this.person || this.state.status === "on") return;
    if (this.loading) this.again = true;
    else void this.refresh();
  }

  private async load(): Promise<void> {
    const person = this.person;
    if (!person) return;
    const heard = this.tvsHeard;
    let board: BoardAnswer;
    try {
      board = (await (await this.deps.call("GET", dailyPath("/v1/daily/board", person))).json()) as BoardAnswer;
    } catch (error) {
      if (person === this.person && error instanceof ApiError && error.status === 404) this.set({ status: "off" });
      return;
    }
    if (person !== this.person) return;
    // The socket's word since this load was asked is newer than the answer's: a TV linked while
    // it was out may not be counted in it yet.
    this.set({ status: "on", board, tvs: heard === this.tvsHeard ? board.tvs : this.state.tvs });
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
        this.tvsHeard += 1;
        return this.set({ status: "on", board: e.board, tvs: e.board.tvs });
      case "tvs":
        this.tvsHeard += 1;
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
  // The server's id for this person arrives with each profile save.
  const { players } = useApp();
  const saved = person ? players[person] : undefined;
  useEffect(() => dishStore.listen(() => setN((n) => n + 1)), []);
  useEffect(() => (person ? dishStore.retain(person) : undefined), [person]);
  useEffect(() => {
    if (person && saved) dishStore.profileSaved(person);
  }, [person, saved]);
  return dishStore.state;
}
