/**
 * Home's Today: the Daily Dish as a row of treats, each showing whether it's done and your result
 * once it is (spec §7 "Home"). Tapping a treat plays it (or shows its result); Open goes to the
 * Dish. Hidden while the server has the Dish off, and while it isn't known yet.
 */
import "./daily.css";

import { navigate } from "../lib/router";
import { useApp } from "../store/app";
import { Button } from "../ui/common";

import { myRow, useDish } from "./dish-store";
import { resultWords, unfinished } from "./format";
import { DAILY_WEB_GAMES } from "./registry";
import { lookOf, Treat } from "./treats";

import type { BoardAnswer } from "@pounce/play-api/daily/messages";
import type { DailyGameId } from "@pounce/play-api/daily/module";

/** The board's games this player can play here, in the Dish's order. */
export function dishGames(board: BoardAnswer | null): DailyGameId[] {
  return (board?.games ?? []).map((g) => g.game).filter((id) => Object.hasOwn(DAILY_WEB_GAMES, id));
}

/** True once the Dish is known to be on (Home rebalances around it). */
export function useDishOn(): boolean {
  const { people } = useApp();
  const dish = useDish(people.owner?.id);
  return dish.status === "on" && dishGames(dish.board).length > 0;
}

export function TodayDish() {
  const { people } = useApp();
  const dish = useDish(people.owner?.id);
  const games = dishGames(dish.board);
  if (dish.status !== "on" || games.length === 0) return null;
  const done = games.filter((g) => myRow(dish.board, g)?.result).length;
  return (
    <section class="home-section dd-today" aria-labelledby="dish-h">
      <div class="dd-today-top">
        <h2 class="outlined section-h" id="dish-h">
          Daily Dish <span class="chip dd-done">{done === games.length ? "All done" : `${done} of ${games.length}`}</span>
        </h2>
        <Button size="small" variant="teal" id="dish-open" aria-label="Open the Dish" onClick={() => navigate({ kind: "dish" })}>
          Open
        </Button>
      </div>
      <div class="dd-today-row">
        {games.map((game) => {
          const mine = myRow(dish.board, game);
          const look = lookOf(game);
          const words = mine?.result ? resultWords(mine.result) : mine?.playing ? "Playing" : "Play";
          // Finished: a tick and a white pill. Ended without finishing: neither, as on the board.
          const finished = !!mine?.result && !unfinished(mine.result);
          return (
            <button
              type="button"
              key={game}
              class={`dd-tile ${finished ? "done" : mine?.result ? "ended" : ""}`}
              style={{ "--c": look.color, "--d": look.deep }}
              onClick={() => navigate({ kind: "daily", game })}
            >
              <Treat game={game} size={52} />
              <span class="dd-tile-title">{look.title}</span>
              <span class="dd-tile-sub">{words}</span>
              {finished ? <span class="dd-tick" aria-hidden="true" /> : null}
            </button>
          );
        })}
      </div>
    </section>
  );
}
