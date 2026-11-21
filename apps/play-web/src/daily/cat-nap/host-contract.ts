/**
 * A copy of the Dish's web host contract (`src/daily/host.tsx` and `client.ts` at dfd9955 on H2's
 * branch), only the parts Cat Nap uses, kept here until H2 and S1 merge. Then this file goes and
 * `dish.tsx` and `watch.tsx` import `../host` and `../client`. As final in H2's PR #127: a watch
 * view is its own module and gets `{ puzzle, state }`; `DailyGame` has no `Watch`.
 */
import type { DailyGameId, DailyResult } from "@pounce/play-api/daily/module";
import type { ComponentType } from "preact";

export type StartAnswer<P = unknown, S = unknown> = {
  run: string;
  game: DailyGameId;
  date: string;
  number: number;
  level: number;
  startedAt: number;
  now: number;
  puzzle: P;
  state: S;
  seq: number;
  hints: number;
  result: DailyResult | null;
  closesAt: number;
};

export type RunEvent<S = unknown, R = unknown> =
  | { kind: "accepted"; seq: number; reveals: R[]; progress: number }
  | { kind: "hint"; reveal: R; hints: number }
  | { kind: "resync"; state: S; seq: number }
  | { kind: "result"; result: DailyResult }
  | { kind: "link"; status: "ok" | "retrying" };

export type SendOptions = { urgent?: boolean };

export interface RunSession<P = unknown, S = unknown, M = unknown, R = unknown> {
  readonly start: StartAnswer<P, S>;
  readonly game: DailyGameId;
  readonly result: DailyResult | null;
  readonly hints: number;
  send(move: M, options?: SendOptions): Promise<R | null>;
  flush(): Promise<void>;
  hint(): Promise<R | null>;
  giveUp(): Promise<DailyResult | null>;
  subscribe(listener: (event: RunEvent<S, R>) => void): () => void;
  serverNow(): number;
  elapsedMs(): number;
}

export type DailyGameScreenProps<P = unknown, S = unknown, M = unknown, R = unknown> = { session: RunSession<P, S, M, R>; playing: boolean };
export type DailyGameScreen<P = unknown, S = unknown, M = unknown, R = unknown> = ComponentType<DailyGameScreenProps<P, S, M, R>>;
export type DailyWatchView<P = unknown, S = unknown> = ComponentType<{ puzzle: P; state: S }>;
export type ShareMark = "full" | "half" | "none";
export type ShareGrid = ShareMark[][];

export interface DailyGame<P = unknown, S = unknown, M = unknown, R = unknown> {
  id: DailyGameId;
  Screen: DailyGameScreen<P, S, M, R>;
  share?: (state: S, result: DailyResult) => ShareGrid | null;
}
