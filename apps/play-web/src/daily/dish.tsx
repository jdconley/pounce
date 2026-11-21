/**
 * The Daily Dish (spec §7): today's puzzles as big cards (number, your result, the best on your
 * board), the family board (overall, then a tab per game), stats, and the board on the TV. Loaded
 * with the puzzle host, in its own chunk.
 */
import { useEffect, useRef, useState } from "preact/hooks";

import { navigate } from "../lib/router";
import { useApp } from "../store/app";
import { Button, Cat, IconButton, learnTip, Tip } from "../ui/common";
import { TvIcon } from "../ui/show-on-tv";

import { BoardView } from "./board";
import { BoardTvSheet, unlinkBoard } from "./board-tv";
import { dishGames } from "./dish-home";
import { bestRow, dishStore, myRow, useDish } from "./dish-store";
import { puzzleNumber, resultWords } from "./format";
import { StatsSheet } from "./stats";
import { lookOf, Treat } from "./treats";

import type { BoardAnswer } from "@pounce/play-api/daily/messages";
import type { DailyGameId } from "@pounce/play-api/daily/module";

function DishCard(props: { game: DailyGameId; board: BoardAnswer; first: boolean }) {
  const { game, board } = props;
  const look = lookOf(game);
  const number = board.games.find((g) => g.game === game)?.number ?? 0;
  const mine = myRow(board, game);
  const best = bestRow(board, game);
  const open = () => {
    learnTip("dish.first");
    navigate({ kind: "daily", game });
  };
  return (
    <article class={`dd-card ${mine?.result ? "done" : ""}`} style={{ "--c": look.color, "--d": look.deep }}>
      <Treat game={game} size={64} />
      <div class="dd-card-body">
        <h3 class="outlined">{look.title}</h3>
        {puzzleNumber(number) ? <span class="dd-num">No. {puzzleNumber(number)}</span> : null}
        {best && best.player !== "me" ? (
          <span class="dd-best">
            <Cat cat={best.cat} size={22} />
            <span class="dd-best-name">{best.name}</span>
            <b>{resultWords(best.result!)}</b>
          </span>
        ) : null}
      </div>
      {mine?.result ? (
        <button type="button" class="dd-mine" id={props.first ? "dish-first" : undefined} onClick={open} aria-label={`${look.title}: ${resultWords(mine.result)}. Result`}>
          <span class="dd-tick" aria-hidden="true" />
          {resultWords(mine.result)}
        </button>
      ) : (
        <Button size="small" class="dd-card-play" id={props.first ? "dish-first" : undefined} aria-label={`Play ${look.title}`} onClick={open}>
          {mine?.playing ? "Resume" : "Play"}
        </Button>
      )}
    </article>
  );
}

export function DishScreen(props: { say: (words: string) => void }) {
  const { people } = useApp();
  const person = people.owner?.id;
  const dish = useDish(person);
  const [tab, setTab] = useState("dish");
  const [stats, setStats] = useState<DailyGameId | null>(null);
  const [tv, setTv] = useState(false);
  const unlinking = useRef(false);

  useEffect(() => {
    if (dish.status === "off") navigate({ kind: "home" }, true);
  }, [dish.status]);

  const games = dishGames(dish.board);
  const board = dish.board;
  if (!person || !board || games.length === 0) return <main class="screen dd-dish violet-bg" aria-busy="true" />;

  const unlink = async () => {
    if (unlinking.current) return;
    unlinking.current = true;
    try {
      await unlinkBoard(person);
      props.say("Unlinked");
      void dishStore.refresh();
    } catch {
      props.say("Couldn't reach Pounce.");
    } finally {
      unlinking.current = false;
    }
  };

  return (
    <main class="screen dd-dish">
      <header class="dd-top">
        <IconButton icon="icon-back" label="Home" onClick={() => navigate({ kind: "home" })} />
        <h1 class="title outlined">Daily Dish</h1>
        <span class="dd-top-space" />
      </header>

      <section class="dd-cards" aria-label="Today's puzzles">
        {games.map((g, i) => (
          <DishCard key={g} game={g} board={board} first={i === 0} />
        ))}
      </section>

      <section class="dd-board-wrap panel" aria-labelledby="board-h">
        <div class="dd-board-top">
          <h2 class="outlined section-h" id="board-h">
            Today's board
          </h2>
          <div class="dd-tv-actions">
            {dish.tvs > 0 ? (
              <Button size="small" variant="violet" onClick={() => void unlink()}>
                Unlink
              </Button>
            ) : null}
            <Button size="small" variant="teal" id="dish-tv" aria-label="Show board on TV" onClick={() => setTv(true)}>
              <TvIcon size={28} /> On TV
            </Button>
          </div>
        </div>
        <BoardView board={board} games={games} tab={tab} onTab={setTab} onStats={setStats} />
      </section>

      <Tip id="dish.first" anchor="dish-first" text="New puzzles every day." show={!stats && !tv} place="below" />
      {stats ? <StatsSheet game={stats} stats={dish.stats?.[stats] ?? null} today={board.date} onClose={() => setStats(null)} /> : null}
      {tv ? (
        <BoardTvSheet
          person={person}
          onClose={() => setTv(false)}
          onShown={() => {
            setTv(false);
            props.say("On the TV");
            void dishStore.refresh();
          }}
        />
      ) : null}
    </main>
  );
}
