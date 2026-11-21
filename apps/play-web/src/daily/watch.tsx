/**
 * A daily run on a TV (spec §8 "Watching a puzzle"): the browser TV hears
 * `{ t: "watch", game, puzzle, state }` frames and draws them with `<DailyWatch>`. Only the game's
 * watch view loads, in its own chunk: never its play screen, the host or the Dish.
 */
import { useEffect, useState } from "preact/hooks";

import { DAILY_WEB_GAMES } from "./registry";

import type { DailyWatchView } from "./host";
import type { DailyGameId } from "@pounce/play-api/daily/module";

/** `game`'s watch view, or null for a game this build doesn't know. */
export async function loadWatch(game: string): Promise<DailyWatchView<unknown, unknown> | null> {
  const entry = Object.hasOwn(DAILY_WEB_GAMES, game) ? DAILY_WEB_GAMES[game as DailyGameId] : undefined;
  if (!entry) return null;
  return (await entry.watch()).default as DailyWatchView<unknown, unknown>;
}

/** One frame of someone's run, read only. Draws nothing until the game's view has loaded. */
export function DailyWatch(props: { game: string; puzzle: unknown; state: unknown }) {
  const [View, setView] = useState<{ v: DailyWatchView<unknown, unknown> } | null>(null);
  useEffect(() => {
    let live = true;
    void loadWatch(props.game).then((v) => live && setView(v ? { v } : null));
    return () => {
      live = false;
    };
  }, [props.game]);
  return View ? <View.v puzzle={props.puzzle} state={props.state} /> : null;
}
