import {
  answeredBody,
  milestoneBody,
  napBody,
  pausedBody,
  playAgainBody,
  pounceBody,
  winbackBody,
  yourMoveBody,
  type Answer,
} from "./copy";

import type { Outgoing, StreakBlock } from "./types";
import type { StreakView } from "../streaks/pair-core";

/** The `streak` block of a push (§12.7) from a person's view of the pair. */
export function streakBlock(v: StreakView): StreakBlock {
  return { pair: v.pair, count: v.count, me: v.me, them: v.them, naps: v.naps, myMove: v.myMove, theirMove: v.theirMove };
}

/** This turn would keep today: the partner is in, you aren't, and the move here is yours. */
const completes = (v: StreakView, code: string) => v.myMove.includes(code) && v.them && !v.me && !v.kept && v.pausedUntil === null;

/**
 * Which of the recipient's pairs at this table a "your move" push carries:
 * one this turn would complete today, else one whose move is here, else any.
 */
export function yourMoveContext(views: StreakView[], code: string): { streak: StreakBlock | null; completesToday: boolean } {
  const best = views.find((v) => completes(v, code)) ?? views.find((v) => v.myMove.includes(code)) ?? views[0];
  return best ? { streak: streakBlock(best), completesToday: completes(best, code) } : { streak: null, completesToday: false };
}

/** A person as a push shows them: the name and the cat avatar. */
export type Face = { name: string; cat: number };

const withStreak = (streak: StreakBlock | null | undefined) => (streak ? { streak } : {});

/** "Your move" (§12.2): grouped and collapsed by the room code, as before. */
export function yourMovePush(p: {
  code: string;
  table: string;
  to: string;
  from: Face | null;
  completesToday: boolean;
  streak: StreakBlock | null;
}): Outgoing {
  return {
    kind: "your_move",
    title: p.to,
    body: yourMoveBody(p.from?.name ?? null, p.table, p.completesToday),
    code: p.code,
    thread: p.code,
    collapse: p.code,
    ...(p.from ? { from: p.from } : {}),
    ...withStreak(p.streak),
  };
}

/** A pounce (§12.4): one thread per sender (by pair id), the target as data for the "pick one" sheet. */
export function pouncePush(p: {
  id: string;
  pair: string;
  to: string;
  from: Face;
  target: { table: string; name: string } | "new" | "pick";
  streak: StreakBlock | null;
}): Outgoing {
  const table = typeof p.target === "object" ? p.target : null;
  return {
    kind: "pounce",
    title: p.to,
    body: pounceBody(p.from.name, table ? { table: table.name } : (p.target as "new" | "pick")),
    ...(table ? { code: table.table } : {}),
    thread: `pounce:${p.pair}`,
    collapse: `pounce:${p.id}`,
    from: p.from,
    ...withStreak(p.streak),
    data: { pounce: { id: p.id, target: table ? { table: table.table } : (p.target as "new" | "pick") } },
  };
}

/** "JD is coming." to the pounce's sender, titled with the sender's own name (§12.2). */
export function answeredPush(p: { id: string; pair: string | null; to: string; who: Face; answer: Answer; code: string | null }): Outgoing {
  return {
    kind: "pounce_answered",
    title: p.to,
    body: answeredBody(p.who.name, p.answer),
    ...(p.code ? { code: p.code } : {}),
    thread: `pounce:${p.pair ?? p.id}`,
    collapse: `answer:${p.id}`,
    from: p.who,
    data: { pounce: { id: p.id, answer: p.answer } },
  };
}

/**
 * The streak status pushes (§12.1): nap, win-back, paused and milestone.
 * `title` is the shared table's name, or the partner's (§12.2).
 */
export function statusPush(p: {
  kind: "nap" | "winback" | "milestone" | "paused";
  pair: string;
  title: string;
  /** The count for nap, win-back and milestone; the days for paused. */
  count: number;
  who?: Face;
  streak: StreakBlock | null;
}): Outgoing {
  const body =
    p.kind === "nap"
      ? napBody(p.count)
      : p.kind === "winback"
        ? winbackBody(p.count)
        : p.kind === "milestone"
          ? milestoneBody(p.count)
          : pausedBody((p.who as Face).name, p.count);
  return {
    kind: p.kind,
    title: p.title,
    body,
    thread: `pair:${p.pair}`,
    collapse: p.kind === "milestone" ? `milestone:${p.pair}:${p.count}` : `${p.kind}:${p.pair}`,
    ...(p.who ? { from: p.who } : {}),
    ...withStreak(p.streak),
    data: { pair: p.pair },
  };
}

/** "Mia dealt a new game." (§10.4), opening the new table. */
export function playAgainPush(p: { code: string; table: string; who: Face }): Outgoing {
  return {
    kind: "play_again",
    title: p.table,
    body: playAgainBody(p.who.name),
    code: p.code,
    thread: p.code,
    collapse: `play_again:${p.code}`,
    from: p.who,
  };
}
