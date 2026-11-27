import { wordGroup, wordText, type Group, type Level, type PurrPhase, type PurrState } from "./engine";

import type { Seat } from "../rules/engine";

/** What one device may see: the drawer's device alone gets the word and the ink (design §10.2). */
export type PurrView = {
  seats: number;
  timer: 45 | 60 | 90;
  rounds: 2;
  phase: PurrPhase;
  round: number;
  drawer: Seat | null;
  order: Seat[];
  scores: number[];
  out: boolean[];
  group: Group | null;
  level: Level | null;
  /** The phase's clock at snapshot time. The engine has no clock: the room fills these in. */
  remainingMs: number | null;
  paused: boolean;
  turn: string;
  last: { word: string; guesser: Seat | null; points: number } | null;
  winners: Seat[];
  choices?: { easy: string; tricky: string };
  word?: string;
  youDraw?: true;
};

export type Viewer = { drawerDevice: boolean; easyOnly: boolean };

export const turnKey = (s: PurrState): string => `${s.round}:${s.turnIndex}`;

/**
 * `viewer` absent means the drawer's own device, not a kitten's. Only the devices controlling the
 * drawer seat can see `choices`; after the pick only `drawerDevice` sees `word` and `youDraw`.
 */
export function view(s: PurrState, controlled: readonly Seat[], viewer: Viewer = { drawerDevice: true, easyOnly: false }): PurrView {
  const v: PurrView = {
    seats: s.seats,
    timer: s.timer,
    rounds: 2,
    phase: s.phase,
    round: s.round,
    drawer: s.drawer,
    order: s.out.flatMap((o, seat) => (o ? [] : [seat])),
    scores: [...s.scores],
    out: [...s.out],
    group: s.word === null ? null : wordGroup(s.word),
    level: s.level,
    remainingMs: null,
    paused: false,
    turn: turnKey(s),
    last: s.last === null ? null : { ...s.last },
    winners: [...s.winners],
  };
  const drives = s.drawer !== null && controlled.includes(s.drawer);
  if (drives && s.phase === "choosing" && s.offer !== null) {
    v.choices = { easy: wordText(s.offer.easy), tricky: wordText(viewer.easyOnly ? s.offer.easy2 : s.offer.tricky) };
  }
  if (drives && s.phase === "drawing" && s.word !== null && viewer.drawerDevice) {
    v.word = wordText(s.word);
    v.youDraw = true;
  }
  return v;
}
