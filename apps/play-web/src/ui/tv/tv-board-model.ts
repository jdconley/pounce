/**
 * What the TV's board shows (Tonight's board: daily games design §6, §8), worked out from the
 * board socket's messages (docs/daily-protocol.md, "The board socket"): pure, so it is tested
 * without a page. The Apple TV's `TVBoardState.swift` is the same, rule for rule.
 */
import type { GameBoard, BoardRow } from "@pounce/play-api/daily/board";
import type { BoardAnswer, BoardMessage } from "@pounce/play-api/daily/messages";
import type { DailyResult } from "@pounce/play-api/daily/module";

/** How long the watch card stays up. */
export const OFFER_MS = 20_000;
/** How long a watched run's result shows before the board comes back. */
export const ENDED_MS = 6_000;
/** How long a row cheers when its result lands. */
export const CHEER_MS = 2_400;
/** How long a TV keeps its board token (the server's own limit). */
export const BOARD_DAYS = 30;
/** Rows a game's card shows before "+N more". */
export const ROWS_SHOWN = 4;

/** Someone turned on Show on TV: the card, until `until`. */
export type Offer = { player: string; name: string; cat: number; game: string; until: number };
/** A row whose result just landed. */
export type Cheer = { player: string; game: string; solved: boolean; until: number };
export type Watching = { player: string; name: string; cat: number; game: string };

export type BoardScreen = {
  board: BoardAnswer | null;
  offer: Offer | null;
  /** The latest frame of each run offered to this TV, by player, kept from the offer on. */
  frames: Record<string, { game: string; state: unknown }>;
  /** Who the TV is watching, after Watch. */
  watching: Watching | null;
  /** The watched run's result, shown over its last frame until `until`. */
  ended: { result: DailyResult; name: string; until: number } | null;
  cheer: Cheer | null;
};

export const EMPTY_SCREEN: BoardScreen = { board: null, offer: null, frames: {}, watching: null, ended: null, cheer: null };

const TITLES: Record<string, string> = { sniff: "Sniff", "nine-lives": "Nine Lives", "cat-nap": "Cat Nap", "box-fort": "Box Fort", test: "Test" };

/** A game's name, as the Dish says it. */
export const gameTitle = (game: string): string => TITLES[game] ?? game;

/** The board after one message from the socket, at `now`. */
export function boardStep(s: BoardScreen, m: BoardMessage, now: number): BoardScreen {
  switch (m.t) {
    case "board":
      return { ...s, board: m.board };
    case "result":
      return { ...s, cheer: { player: m.player, game: m.result.game, solved: m.result.outcome === "solved" || m.result.outcome === "done", until: now + CHEER_MS } };
    case "progress": {
      if (!s.board) return s;
      let moved = false;
      const games = s.board.games.map((g) =>
        g.game !== m.game
          ? g
          : {
              ...g,
              rows: g.rows.map((r) => {
                if (r.player !== m.player || !r.playing) return r;
                moved = true;
                return { ...r, playing: { progress: m.progress } };
              }),
            },
      );
      return moved ? { ...s, board: { ...s.board, games } } : s;
    }
    case "watchOffer":
      return { ...s, offer: { player: m.player, name: m.name, cat: m.cat, game: m.game, until: now + OFFER_MS } };
    case "watch":
      return { ...s, frames: { ...s.frames, [m.player]: { game: m.game, state: m.state } } };
    case "watchEnd": {
      const frames = { ...s.frames };
      delete frames[m.player];
      const offer = s.offer?.player === m.player ? null : s.offer;
      if (s.watching?.player !== m.player) return { ...s, frames, offer };
      if (m.result) return { ...s, frames, offer, ended: { result: m.result, name: s.watching.name, until: now + ENDED_MS } };
      return { ...s, frames, offer, watching: null, ended: null };
    }
    default:
      return s;
  }
}

/** Watch, on the card: the offered run, from its latest frame. */
export function watch(s: BoardScreen): BoardScreen {
  if (!s.offer) return s;
  const { player, name, cat, game } = s.offer;
  return { ...s, offer: null, ended: null, watching: { player, name, cat, game } };
}

/** Not now, on the card. The frames stay, so a later offer's Watch shows the latest at once. */
export const notNow = (s: BoardScreen): BoardScreen => (s.offer ? { ...s, offer: null } : s);

/** Back from watching: the board. */
export const stopWatching = (s: BoardScreen): BoardScreen => (s.watching || s.ended ? { ...s, watching: null, ended: null } : s);

/** What time does: the card goes, a result shown gives way to the board, a cheer ends. */
export function tick(s: BoardScreen, now: number): BoardScreen {
  let next = s;
  if (next.offer && now > next.offer.until) next = { ...next, offer: null };
  if (next.ended && now > next.ended.until) next = { ...next, ended: null, watching: null };
  if (next.cheer && now > next.cheer.until) next = { ...next, cheer: null };
  return next;
}

/** When `tick` next has something to do, or null. */
export function nextTick(s: BoardScreen): number | null {
  const times = [s.offer?.until, s.ended?.until, s.cheer?.until].filter((t): t is number => t !== undefined);
  return times.length ? Math.min(...times) + 1 : null;
}

/** The card: "Mom is playing Sniff. Spoilers." */
export const offerWords = (o: Pick<Offer, "name" | "game">): string => `${o.name} is playing ${gameTitle(o.game)}. Spoilers.`;

/** A time as m:ss, or h:mm:ss. */
export function clock(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const sec = String(total % 60).padStart(2, "0");
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${sec}` : `${m}:${sec}`;
}

/** What a row says for its result. */
export function resultWords(r: DailyResult): string {
  if (r.outcome === "gaveUp") return "Gave up";
  if (r.outcome === "closed") return "Closed";
  if (r.outcome === "missed") return "Missed";
  if (r.points !== undefined) return r.points.toLocaleString("en-US");
  if (r.guesses !== undefined) return `${r.guesses} of 6`;
  return clock(r.timeMs);
}

/** A game's rows to draw: the first four (results first, as ranked, then people playing), and how many more. */
export function visibleRows(g: GameBoard, max = ROWS_SHOWN): { rows: BoardRow[]; more: number } {
  return { rows: g.rows.slice(0, max), more: Math.max(0, g.rows.length - max) };
}

/** The kept token, if it is one and still live. */
export function keptBoard(raw: string | null, now: number): string | null {
  if (!raw) return null;
  try {
    const kept = JSON.parse(raw) as { token?: unknown; until?: unknown };
    if (typeof kept.token !== "string" || !/^[A-Za-z0-9_-]{22}$/.test(kept.token)) return null;
    if (typeof kept.until !== "number" || now > kept.until) return null;
    return kept.token;
  } catch {
    return null;
  }
}

/** The token to keep, for 30 days from `now`. */
export const boardToKeep = (token: string, now: number): string => JSON.stringify({ token, until: now + BOARD_DAYS * 86_400_000 });
