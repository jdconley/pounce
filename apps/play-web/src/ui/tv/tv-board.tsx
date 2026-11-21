/**
 * Tonight's board on the TV (daily games design §8): the Daily Dish board a phone linked, live,
 * read from across the room. The Dish on the left, each game's board on the right, a cheer when a
 * result lands, the card that offers to watch a run, and the run itself after Watch. Back opens the
 * menu: Play a game, sound, Unlink. Nothing is typed.
 */
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "preact/hooks";

import { art } from "../../lib/art";
import { onSettings, setSettings, settings } from "../../lib/settings";
import { play } from "../../lib/sound";
import { tvApi } from "../../net/api";
import { TvBoardStore, type TvBoardState } from "../../store/tv-board";
import { tvMenu } from "../../table/ct-layout";
import { Cat, useSize } from "../common";
import { QrCode } from "../qr";

import { isBack } from "./focus";
import { gameTitle, resultWords, ROWS_SHOWN, visibleRows, type BoardScreen, type Cheer } from "./tv-board-model";
import { MenuButton } from "./tv-table";
import { TvWatch, TvWatchCard } from "./tv-watch";

import type { BoardRow, DishRow, GameBoard } from "@pounce/play-api/daily/board";
import type { BoardAnswer } from "@pounce/play-api/daily/messages";
import "./tv-board.css";

const NO_INSETS = { top: 0, right: 0, bottom: 0, left: 0 };

function useBoard(store: TvBoardStore): TvBoardState {
  const [state, setState] = useState(store.state);
  useEffect(() => store.subscribe({ change: setState }), [store]);
  return state;
}

/**
 * The board this TV shows, from its kept token. `onGone` when the server no longer knows it (an
 * unlink from the phone, 30 days up); `onHome` for Play a game; `onUnlink` from the menu.
 */
export function TvBoardRoom(props: { board: string; asleep: boolean; onGone: () => void; onHome: () => void; onUnlink: () => void }) {
  const store = useMemo(() => new TvBoardStore({ api: tvApi, board: props.board }), [props.board]);
  const state = useBoard(store);
  const [menu, setMenu] = useState(false);
  const [frameRef, frame] = useSize<HTMLDivElement>();
  const latest = useRef(props);
  latest.current = props;
  const screen = state.screen;

  useEffect(() => {
    const off = store.subscribe({
      news: (n) => {
        if (n.kind === "gone") latest.current.onGone();
        else if (n.kind === "offer") play("pop", 0.6);
        else play(n.solved ? "fanfare" : "sparkle", 0.8);
      },
    });
    store.start();
    const visible = () => {
      if (document.visibilityState === "visible") store.reconnectNow();
    };
    const online = () => store.reconnectNow();
    document.addEventListener("visibilitychange", visible);
    window.addEventListener("online", online);
    return () => {
      off();
      document.removeEventListener("visibilitychange", visible);
      window.removeEventListener("online", online);
      store.stop();
    };
  }, [store]);

  // Back: out of a watched run to the board, else the menu, and back out of it. Listening from the
  // moment the board is drawn, not a frame later.
  const watching = useRef(false);
  watching.current = screen.watching !== null;
  useLayoutEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!isBack(e)) return;
      e.preventDefault();
      if (watching.current) store.stopWatching();
      else setMenu((m) => !m);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [store]);

  const live = !menu && !props.asleep;
  const offline = state.everConnected && !state.online;
  return (
    <div class="tv-room" ref={frameRef}>
      {screen.watching ? (
        <TvWatch watching={screen.watching} frame={screen.frames[screen.watching.player]} ended={screen.ended} onBack={() => store.stopWatching()} />
      ) : (
        <TvBoard screen={screen} connecting={!state.everConnected} />
      )}
      {screen.offer && !screen.watching && live ? <TvWatchCard key={`${screen.offer.player}:${screen.offer.until}`} offer={screen.offer} onWatch={() => store.watch()} onNotNow={() => store.notNow()} /> : null}
      {screen.watching ? null : <MenuButton rect={topRight(tvMenu(frame.width || 1920, frame.height || 1080, NO_INSETS), frame.height || 1080)} live={live} onMenu={() => setMenu(true)} />}
      {offline ? (
        <div class="tv-note" role="status">
          <span class="dot" /> Reconnecting
        </div>
      ) : null}
      {menu ? <TvBoardMenu onClose={() => setMenu(false)} onHome={() => latest.current.onHome()} onUnlink={() => latest.current.onUnlink()} /> : null}
    </div>
  );
}

/** The menu's paw on the board: mirrored to the top right, beside a card's title, since the bottom corner holds rows. */
const topRight = (r: { x: number; y: number; w: number; h: number }, height: number) => ({ ...r, y: height - r.y - r.h });

/** "Monday, November 23": the board's own day. */
export const boardDay = (date: string): string => new Date(`${date}T12:00:00Z`).toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric", timeZone: "UTC" });

/** The board: the Dish, then a card per game. */
export function TvBoard(props: { screen: BoardScreen; connecting: boolean }) {
  const board = props.screen.board;
  const cheer = props.screen.cheer;
  const games = board?.games ?? [];
  return (
    <section class="tv-board" aria-label="Tonight's board">
      <aside class="tv-dish">
        <h1 class="tv-dish-title outlined">Tonight's board</h1>
        <p class="tv-dish-day">{board ? boardDay(board.date) : " "}</p>
        <Dish board={board} cheer={cheer} connecting={props.connecting} />
      </aside>
      <div class={`tv-board-games n${Math.max(1, Math.min(games.length, 5))}`}>
        {games.map((g) => (
          <GameCard key={g.game} game={g} cheer={cheer} max={ROWS_SHOWN} />
        ))}
      </div>
    </section>
  );
}

function Dish(props: { board: BoardAnswer | null; cheer: Cheer | null; connecting: boolean }) {
  const rows = props.board?.dish.rows ?? [];
  if (rows.length === 0) {
    return (
      <div class="tv-dish-empty">
        <Cat cat={0} pose="asleep" size="calc(var(--u) * 220)" />
        <p class="outlined">{props.connecting ? "Finding your board" : "Nobody has played yet"}</p>
      </div>
    );
  }
  return (
    <ol class="tv-dish-rows">
      {rows.slice(0, 7).map((r) => {
        const cheer = props.cheer?.player === r.player ? props.cheer : null;
        return <DishLine key={cheer ? `${r.player}:${cheer.until}` : r.player} row={r} cheer={cheer} />;
      })}
    </ol>
  );
}

function DishLine(props: { row: DishRow; cheer: Cheer | null }) {
  const { row, cheer } = props;
  return (
    <li class={`tv-dish-row${cheer ? " cheer" : ""}`} data-player={row.player} aria-label={`${row.rank}. ${row.name}, ${row.points} points`}>
      <Rank rank={row.rank} />
      <Cat cat={row.cat} pose="idle" size="calc(var(--u) * 72)" />
      <span class="tv-row-name">{row.name}</span>
      <span class="tv-dish-crowns" aria-hidden="true">
        {row.crowns.slice(0, 4).map((c) => (
          <img key={c} src={art("crown")} alt="" />
        ))}
      </span>
      <span class="tv-dish-points">{row.points}</span>
    </li>
  );
}

function Rank(props: { rank: number | null }) {
  const tone = props.rank === 1 ? "gold" : props.rank === 2 ? "silver" : props.rank === 3 ? "bronze" : "plain";
  return <span class={`tv-rank ${tone}`}>{props.rank ?? ""}</span>;
}

function GameCard(props: { game: GameBoard; cheer: Cheer | null; max: number }) {
  const { game } = props;
  const shown = visibleRows(game, props.max);
  return (
    <article class="tv-board-game" data-game={game.game} aria-label={gameTitle(game.game)}>
      <header class="tv-board-game-top">
        <h2 class="tv-board-game-title outlined">{gameTitle(game.game)}</h2>
        {game.number > 0 ? <span class="tv-board-game-number">#{game.number}</span> : null}
      </header>
      {game.rows.length === 0 ? (
        <p class="tv-board-game-empty">Nobody yet</p>
      ) : (
        <ol class="tv-board-rows">
          {shown.rows.map((r) => {
            const cheer = props.cheer?.player === r.player && props.cheer.game === game.game ? props.cheer : null;
            return <GameRow key={cheer ? `${r.player}:${cheer.until}` : r.player} row={r} cheer={cheer} />;
          })}
        </ol>
      )}
      {shown.more > 0 ? <p class="tv-board-more">+{shown.more} more</p> : null}
    </article>
  );
}

function GameRow(props: { row: BoardRow; cheer: Cheer | null }) {
  const { row, cheer } = props;
  const r = row.result;
  const solved = r && (r.outcome === "solved" || r.outcome === "done");
  return (
    <li
      class={`tv-board-row${cheer ? " cheer" : ""}${row.playing ? " playing" : ""}`}
      data-player={row.player}
      aria-label={r ? `${row.rank}. ${row.name}, ${resultWords(r)}${r.hints ? `, ${r.hints} hint${r.hints > 1 ? "s" : ""}` : ""}` : `${row.name}, playing`}
    >
      {row.playing ? <img class="tv-rank playing" src={art("icon-play")} alt="" /> : <Rank rank={row.rank} />}
      <Cat cat={row.cat} pose={cheer ? "leap" : row.playing ? "awake" : "idle"} size="calc(var(--u) * 72)" class="tv-row-cat" />
      <span class="tv-row-name">{row.name}</span>
      {r ? (
        <span class={`tv-row-result${solved ? "" : " unsolved"}`}>
          {r.hints > 0 ? <span class="tv-row-hint">Hint</span> : null}
          {resultWords(r)}
        </span>
      ) : (
        <span class="tv-row-playing" aria-hidden="true">
          <span class="tv-row-bar" style={{ "--p": String(row.playing?.progress ?? 0) }} />
        </span>
      )}
    </li>
  );
}

/** The board's menu: Play a game (home, the board kept), sound, and Unlink. */
function TvBoardMenu(props: { onClose: () => void; onHome: () => void; onUnlink: () => void }) {
  const [sound, setSound] = useState(settings().sound);
  useEffect(() => onSettings((s) => setSound(s.sound)), []);
  const press = (fn: () => void) => () => {
    play("pop", 0.5);
    fn();
  };
  return (
    <div class="tv-menu" role="dialog" aria-label="Menu">
      <div class="tv-menu-scrim" onClick={props.onClose} />
      <div class="tv-menu-card">
        <button type="button" class="tv-menu-item violet" data-tv data-tv-default onClick={press(props.onHome)}>
          <img src={art("icon-dice")} alt="" />
          <span>Play a game</span>
        </button>
        <button
          type="button"
          class="tv-menu-item teal"
          data-tv
          onClick={() => {
            setSettings({ sound: !sound });
            play("pop", 0.5);
          }}
        >
          <img src={art(sound ? "icon-sound-on" : "icon-sound-off")} alt="" />
          <span>{sound ? "Sound on" : "Sound off"}</span>
        </button>
        <button type="button" class="tv-menu-item magenta" data-tv onClick={press(props.onUnlink)}>
          <img src={art("icon-leave")} alt="" />
          <span>Unlink</span>
        </button>
      </div>
    </div>
  );
}

/** Tonight's board, before a phone linked one: home's link, big, with the words for the Dish. */
export function TvBoardLink(props: { link: { code: string; url: string } | null; offline: boolean; onBack: () => void }) {
  const { link } = props;
  const back = useRef<HTMLButtonElement>(null);
  useLayoutEffect(() => back.current?.focus({ preventScroll: true }), []);
  return (
    <div class="tv-menu tv-board-link" role="dialog" aria-label="Tonight's board">
      <div class="tv-menu-scrim" onClick={props.onBack} />
      <div class="tv-menu-card tv-link-card" aria-busy={link ? undefined : "true"}>
        <div class="tv-qr-window">
          {link ? <QrCode url={link.url} label="QR code to show your board on this TV" class="tv-qr" /> : <div class="qr tv-qr" aria-hidden="true" />}
        </div>
        <div class="tv-link-side">
          <p class="tv-board-link-title outlined">Tonight's board</p>
          <p class="tv-scan outlined">Scan from the Dish on your phone</p>
          <p class="tv-code" aria-label={link ? `Code ${link.code.split("").join(" ")}` : undefined}>
            {link ? link.code : " "}
          </p>
          {props.offline ? (
            <p class="tv-link-note" role="status">
              <span class="dot" /> Reconnecting
            </p>
          ) : null}
          <button type="button" class="tv-menu-item violet tv-link-back" data-tv data-tv-default ref={back} onClick={props.onBack}>
            <img src={art("icon-back")} alt="" />
            <span>Back</span>
          </button>
        </div>
      </div>
    </div>
  );
}
