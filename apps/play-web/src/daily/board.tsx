/**
 * The family board (spec §6): the Dish overall, then a tab per game. Only people who played show,
 * best first; someone playing now shows a "playing" mark and spoiler-free progress. Never "last",
 * never who didn't play.
 */
import { Cat } from "../ui/common";

import { resultWords } from "./format";
import { CrownMark, lookOf } from "./treats";

import type { BoardRow, DishRow } from "@pounce/play-api/daily/board";
import type { BoardAnswer } from "@pounce/play-api/daily/messages";
import type { DailyGameId } from "@pounce/play-api/daily/module";

function Rank(props: { rank: number | null }) {
  return <span class={`dd-rank r${props.rank ?? 0}`}>{props.rank ?? ""}</span>;
}

function DishRows(props: { rows: DishRow[] }) {
  return (
    <ol class="dd-rows">
      {props.rows.map((r) => (
        <li key={r.player} class={`dd-row dish ${r.player === "me" ? "mine" : ""}`}>
          <Rank rank={r.rank} />
          <Cat cat={r.cat} pose={r.rank === 1 ? "celebrate" : "idle"} size={40} />
          <span class="dd-name">{r.name}</span>
          <span class="dd-crowns">
            {r.crowns.map((g) => (
              <CrownMark key={g} game={g} />
            ))}
          </span>
          <span class="dd-score">{r.points === 1 ? "1 pt" : `${r.points} pts`}</span>
        </li>
      ))}
    </ol>
  );
}

function GameRows(props: { rows: BoardRow[] }) {
  return (
    <ol class="dd-rows">
      {props.rows.map((r) => (
        <li key={r.player} class={`dd-row game ${r.player === "me" ? "mine" : ""} ${r.playing ? "playing" : ""}`}>
          <Rank rank={r.rank} />
          <Cat cat={r.cat} pose={r.playing ? "awake" : r.rank === 1 ? "celebrate" : "idle"} size={40} />
          <span class="dd-name">{r.name}</span>
          {r.result ? (
            <span class="dd-score">
              {r.result.hints > 0 ? <span class="dd-hint-mark">Hint</span> : null}
              {resultWords(r.result)}
            </span>
          ) : (
            <span class="dd-score dd-progress" aria-label={`Playing, ${Math.round((r.playing?.progress ?? 0) * 100)} percent`}>
              <span class="dd-bar-track" aria-hidden="true">
                <i style={{ transform: `scaleX(${Math.min(1, Math.max(0.04, r.playing?.progress ?? 0))})` }} />
              </span>
              Playing
            </span>
          )}
        </li>
      ))}
    </ol>
  );
}

export function BoardView(props: { board: BoardAnswer; games: DailyGameId[]; tab: string; onTab: (tab: string) => void; onStats: (game: DailyGameId) => void }) {
  const { board, games, tab } = props;
  const tabs = [{ id: "dish", title: "Dish" }, ...games.map((g) => ({ id: g, title: lookOf(g).title }))];
  const current = tabs.some((t) => t.id === tab) ? tab : "dish";
  const game = board.games.find((g) => g.game === current);
  const rows = current === "dish" ? board.dish.rows : (game?.rows ?? []);
  const look = current === "dish" ? null : lookOf(current);
  return (
    <div class="dd-board" style={look ? { "--c": look.color, "--d": look.deep } : undefined}>
      <div class="dd-tabs" role="tablist" aria-label="Board">
        {tabs.map((t) => (
          <button
            type="button"
            role="tab"
            key={t.id}
            id={`tab-${t.id}`}
            aria-selected={t.id === current}
            aria-controls="board-panel"
            class={`dd-tab ${t.id === current ? "on" : ""}`}
            style={t.id === "dish" ? undefined : { "--c": lookOf(t.id).color }}
            onClick={() => props.onTab(t.id)}
          >
            {t.title}
          </button>
        ))}
      </div>
      <div class="dd-panel" role="tabpanel" id="board-panel" aria-labelledby={`tab-${current}`}>
        {rows.length === 0 ? <p class="dd-empty">No results yet.</p> : current === "dish" ? <DishRows rows={board.dish.rows} /> : <GameRows rows={rows as BoardRow[]} />}
        {current !== "dish" ? (
          <button type="button" class="dd-stats-link" onClick={() => props.onStats(current as DailyGameId)}>
            Stats
          </button>
        ) : null}
      </div>
    </div>
  );
}
