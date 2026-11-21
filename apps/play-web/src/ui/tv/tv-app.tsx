/**
 * Pounce on the TV (`/play/tv`). A TV is no one's seat: it shows a link (a QR and a backup code)
 * that a phone scans to put its table here, or makes a table itself from one of the two game
 * posters. It runs on its own device credential (`tvApi`), never runs first run, and is driven by
 * a remote: arrow keys, Enter and Back, with the mouse as well.
 */
import { useEffect, useMemo, useRef, useState } from "preact/hooks";

import { art, RINGS } from "../../lib/art";
import { CATALOG, GAME_IDS, type GameId } from "../../lib/catalog";
import { store } from "../../lib/kv";
import { isRoomCode } from "../../lib/router";
import { play, unlockAudio } from "../../lib/sound";
import { tvApi } from "../../net/api";
import { ScreenLink } from "../../net/screen-link";
import { dailyOn } from "../../net/tv-board-socket";
import { reloadForUpdate, setSafeToReload } from "../../pwa";
import { RoomStore, type RoomPhase, type RoomState } from "../../store/room";
import { tvMenu } from "../../table/ct-layout";
import { Button, Cat, useSize } from "../common";
import { QrCode } from "../qr";

import { isBack, useDpad } from "./focus";
import { TvBoardLink, TvBoardRoom } from "./tv-board";
import { boardToKeep, keptBoard } from "./tv-board-model";
import { NOPE, TvLobby } from "./tv-lobby";
import { TvMenu } from "./tv-menu";
import { back, bootPhase, cheerStep, gameOf, NO_CHEER, otherGame, safeToReload, type MenuView } from "./tv-model";
import { MenuButton, TvOver, TvTable } from "./tv-table";
import "./tv.css";

/** The table this TV shows, so a reload goes back to it. */
const ROOM_KEY = "pounce.tv.room";

/** The Daily Dish board this TV shows (`{ token, until }`), so it opens to it every evening. */
const BOARD_KEY = "pounce.tv.board";

export type TvPhase = "start" | "home" | "board" | "lobby" | "table" | "over";

const keptRoom = (): string | null => {
  const code = store.get(ROOM_KEY);
  return code && isRoomCode(code) ? code : null;
};

const keepRoom = (code: string | null): void => {
  if (code) store.set(ROOM_KEY, code);
  else store.remove(ROOM_KEY);
};

const keptBoardToken = (): string | null => keptBoard(store.get(BOARD_KEY), Date.now());

const keepBoard = (token: string | null): void => {
  if (token) store.set(BOARD_KEY, boardToKeep(token, Date.now()));
  else store.remove(BOARD_KEY);
};

/** Keeps the screen on while the TV page shows, taken again whenever the page comes back. */
function useWakeLock(on: boolean): void {
  useEffect(() => {
    if (!on || !("wakeLock" in navigator)) return;
    let live = true;
    let held: WakeLockSentinel | null = null;
    // One request at a time: a second visibilitychange while one is out asks for nothing.
    let asking = false;
    const take = () => {
      if (asking || document.visibilityState !== "visible" || (held && !held.released)) return;
      asking = true;
      navigator.wakeLock
        .request("screen")
        .then((sentinel) => {
          if (live) held = sentinel;
          else void sentinel.release();
        })
        .catch(() => undefined)
        .finally(() => (asking = false));
    };
    take();
    document.addEventListener("visibilitychange", take);
    return () => {
      live = false;
      document.removeEventListener("visibilitychange", take);
      void held?.release().catch(() => undefined);
    };
  }, [on]);
}

/** Full screen, where the browser allows it: only in answer to a press. */
function fullScreen(): void {
  try {
    void document.documentElement.requestFullscreen?.().catch(() => undefined);
  } catch {
    // No full screen here (an iframe, an old TV browser): the page still plays.
  }
}

export function TvApp() {
  const root = useRef<HTMLElement>(null);
  // A TV that kept a table (a reload, a new deploy, the TV turned off and on) goes straight back to
  // it; a new one starts at Start.
  const [kept] = useState(keptRoom);
  const [board, setBoard] = useState<string | null>(keptBoardToken);
  const [phase, setPhase] = useState<TvPhase>(() => bootPhase(kept, board));
  const [room, setRoom] = useState<string | null>(kept);
  // Sound and full screen wait for a press: Start is one. A TV that went straight to its table
  // asks for one ("Press OK for sound"), and any press does.
  const [pressed, setPressed] = useState(false);
  useDpad(root);
  useWakeLock(phase !== "start");

  const woke = useRef(false);
  const wake = () => {
    if (woke.current) return;
    woke.current = true;
    unlockAudio();
    fullScreen();
    setPressed(true);
  };

  useEffect(() => {
    if (pressed) return;
    // Back is no press a browser counts (Escape never is): it leaves the question up.
    const onKey = (e: KeyboardEvent) => {
      if (!isBack(e)) wake();
    };
    window.addEventListener("keydown", onKey);
    window.addEventListener("pointerdown", wake);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("pointerdown", wake);
    };
  }, [pressed]);

  const goHome = () => {
    keepRoom(null);
    setRoom(null);
    setPhase("home");
  };

  const openRoom = (code: string) => {
    keepRoom(code);
    setRoom(code);
    setPhase("lobby");
  };

  /** A phone linked this TV to its board (or the TV opens the one it kept): a table shown is let go. */
  const openBoard = (token: string) => {
    keepBoard(token);
    keepRoom(null);
    setRoom(null);
    setBoard(token);
    setPhase("board");
  };

  /** Unlink, or a board the server no longer knows: forgotten, and home. */
  const forgetBoard = () => {
    keepBoard(null);
    setBoard(null);
    goHome();
  };

  const start = () => {
    wake();
    const code = keptRoom();
    const token = keptBoardToken();
    if (code) openRoom(code);
    else if (token) openBoard(token);
    else setPhase("home");
  };

  // Back never leaves the app. A key's default is stopped (a table's own Back opens its menu).
  // Some remotes' Back is the browser's own Back instead, which no key handler sees: for those the
  // page keeps one history entry of its own on top. Their Back pops it (popstate), the page puts it
  // back and acts as a Back key would, so the page never goes back past /play/tv.
  // Browsers differ here. Chromium (Chrome, Edge, and the Tizen and webOS browsers) skips a history
  // entry a page added before anyone pressed anything on it: until the TV's first press (Start, or
  // "Press OK for sound") its Back still leaves the page, and after it the entry holds. Firefox and
  // Safari keep the entry as pushed. Most TV remotes send Back as a key instead (461 on webOS, 10009
  // on Tizen), which the key handler takes in every browser.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (isBack(e)) e.preventDefault();
    };
    history.pushState({ tv: true }, "");
    const onPop = () => {
      history.pushState({ tv: true }, "");
      window.dispatchEvent(new KeyboardEvent("keydown", { key: "GoBack", cancelable: true }));
    };
    window.addEventListener("keydown", onKey);
    window.addEventListener("popstate", onPop);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("popstate", onPop);
    };
  }, []);

  const atHome = phase === "start" || phase === "home";
  return (
    <main class={`tv tv-at-${phase}`} ref={root}>
      <div class="tv-bg" style={{ backgroundImage: `url(${art(atHome ? "home-bg" : "room-bg")})` }} aria-hidden="true" />
      {phase === "start" ? <TvStart onStart={start} /> : null}
      {phase === "home" ? <TvHome board={board} onLinked={openRoom} onMade={openRoom} onBoard={openBoard} /> : null}
      {phase === "board" && board ? <TvBoardRoom key={board} board={board} asleep={!pressed} onGone={forgetBoard} onHome={goHome} onUnlink={forgetBoard} /> : null}
      {room && !atHome && phase !== "board" ? <TvRoom key={room} code={room} asleep={!pressed} onPhase={setPhase} onGone={goHome} onMove={openRoom} onBoard={openBoard} /> : null}
      {!atHome && (room || phase === "board") && !pressed ? <TvWake onWake={wake} /> : null}
    </main>
  );
}

function TvStart(props: { onStart: () => void }) {
  return (
    <section class="tv-start-screen">
      <img class="tv-sunburst" src={art("sunburst")} alt="" aria-hidden="true" />
      <div class="tv-brand">
        <img class="tv-logo" src="/play/icons/icon-512.png" alt="" width={512} height={512} />
        <h1 class="tv-wordmark outlined">Pounce</h1>
      </div>
      <Button variant="ok" class="tv-start-btn" data-tv data-tv-default autoFocus onClick={props.onStart}>
        Start
      </Button>
    </section>
  );
}

/** Over a table the TV went straight back to: one press, for sound and full screen. */
function TvWake(props: { onWake: () => void }) {
  return (
    <div class="tv-wake">
      <div class="tv-wake-scrim" aria-hidden="true" />
      <Button variant="ok" class="tv-wake-btn" data-tv data-tv-default autoFocus onClick={props.onWake}>
        <img src={art("icon-sound-off")} alt="" /> Press OK for sound
      </Button>
    </div>
  );
}

type Link = { code: string; url: string };

/**
 * Home: the link a phone scans on the left (a table or a Daily Dish board), the posters on the
 * right. Tonight's board shows only while the server has the Dish on; it opens the kept board, or
 * this same link with the Dish's words.
 */
function TvHome(props: { board: string | null; onLinked: (room: string) => void; onMade: (room: string) => void; onBoard: (token: string) => void }) {
  const [link, setLink] = useState<Link | null>(null);
  const [offline, setOffline] = useState(false);
  const [dish, setDish] = useState(false);
  const [boardLink, setBoardLink] = useState(false);
  const busy = useRef(false);
  const latest = useRef(props);
  latest.current = props;

  useEffect(() => {
    let live = true;
    void dailyOn(tvApi).then((on) => live && setDish(on));
    return () => void (live = false);
  }, []);

  useEffect(() => {
    const screen = new ScreenLink({ api: tvApi });
    const off = screen.on((e) => {
      if (e.kind === "code") {
        setLink({ code: e.code, url: e.url });
        setOffline(false);
      } else if (e.kind === "offline") setOffline(true);
      else if (e.kind === "board") latest.current.onBoard(e.token);
      else latest.current.onLinked(e.room);
    });
    screen.start();
    return () => {
      off();
      screen.stop();
    };
  }, []);

  const make = async (game: GameId, poster: HTMLElement) => {
    if (busy.current) return;
    busy.current = true;
    try {
      props.onMade(await tvApi.createRoom(game, { screen: true }));
    } catch {
      // Not made (offline, most likely): a shake, and the poster can be pressed again.
      play("nope");
      poster.animate(NOPE, { duration: 360, easing: "ease-in-out" });
      busy.current = false;
    }
  };

  // Back closes the board's link panel (home's own Back leaves nothing to close).
  useEffect(() => {
    if (!boardLink) return;
    const onKey = (e: KeyboardEvent) => {
      if (!isBack(e)) return;
      e.preventDefault();
      setBoardLink(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [boardLink]);

  return (
    <section class={`tv-home-screen${dish ? " with-dish" : ""}`}>
      <div class="tv-link" aria-busy={link ? undefined : "true"}>
        <p class="tv-scan outlined">Scan with your phone to put your table here</p>
        <div class="tv-qr-frame">
          <i class="tv-ear left" aria-hidden="true" />
          <i class="tv-ear right" aria-hidden="true" />
          <div class="tv-qr-window">
            {link ? <QrCode url={link.url} label="QR code to put a table on this TV" class="tv-qr" /> : <div class="qr tv-qr" aria-hidden="true" />}
          </div>
        </div>
        <p class="tv-code" aria-label={link ? `Code ${link.code.split("").join(" ")}` : undefined}>
          {link ? link.code : " "}
        </p>
      </div>
      <div class="tv-games">
        {GAME_IDS.map((id, i) => (
          <button
            type="button"
            class={`tv-poster ${id}`}
            data-tv
            data-tv-default={i === 0 ? true : undefined}
            onClick={(e) => {
              play("pop", 0.5);
              void make(id, e.currentTarget);
            }}
          >
            <img class="tv-poster-art" src={art(CATALOG[id].art)} alt="" width={768} height={512} decoding="async" />
            <span class="tv-poster-body">
              <span class="tv-poster-title outlined">{CATALOG[id].title}</span>
              <span class="tv-players">
                <span class="tv-dots" aria-hidden="true">
                  {RINGS.slice(0, CATALOG[id].maxSeats).map((c) => (
                    <i style={{ background: c }} />
                  ))}
                </span>
                {CATALOG[id].minSeats} to {CATALOG[id].maxSeats} players
              </span>
            </span>
          </button>
        ))}
        {dish ? (
          <button
            type="button"
            class="tv-poster board"
            data-tv
            aria-label="Tonight's board"
            onClick={() => {
              play("pop", 0.5);
              if (props.board) props.onBoard(props.board);
              else setBoardLink(true);
            }}
          >
            <span class="tv-poster-art tv-board-poster-art" aria-hidden="true">
              <img class="tv-board-poster-burst" src={art("sunburst")} alt="" />
              <img class="tv-board-poster-trophy" src={art("icon-trophy")} alt="" />
              <Cat cat={3} pose="celebrate" size="calc(var(--u) * 150)" class="tv-board-poster-cat left" />
              <Cat cat={5} pose="leap" size="calc(var(--u) * 150)" class="tv-board-poster-cat right" />
            </span>
            <span class="tv-poster-body">
              <span class="tv-poster-title outlined">Tonight's board</span>
              <span class="tv-players">Daily puzzles</span>
            </span>
          </button>
        ) : null}
      </div>
      {boardLink ? <TvBoardLink link={link} offline={offline} onBack={() => setBoardLink(false)} /> : null}
      {offline ? (
        <div class="tv-note" role="status">
          <span class="dot" /> Reconnecting
        </div>
      ) : null}
    </section>
  );
}

const NO_INSETS = { top: 0, right: 0, bottom: 0, left: 0 };

function useRoom(room: RoomStore): RoomState {
  const [state, setState] = useState(room.state);
  useEffect(() => room.subscribe({ change: setState }), [room]);
  return state;
}

/**
 * The table this TV shows, connected as its screen: the lobby, the table and game over, with the
 * menu over them. It goes home when the table is gone or no longer lists this TV, and moves to
 * another table when a phone links one, Play again deals one, or the TV changes the game.
 */
function TvRoom(props: { code: string; asleep: boolean; onPhase: (p: TvPhase) => void; onGone: () => void; onMove: (code: string) => void; onBoard: (token: string) => void }) {
  const { code } = props;
  const room = useMemo(
    () =>
      new RoomStore({
        code,
        role: "screen",
        token: async () => (await tvApi.credential()).token,
        // A refused token (4401) is forgotten, so the next connect mints a fresh one.
        dropToken: () => tvApi.forget(),
        reducedMotion: () => matchMedia("(prefers-reduced-motion: reduce)").matches,
      }),
    [code],
  );
  const state = useRoom(room);
  const view = state.room;
  const [menu, setMenu] = useState<MenuView>("closed");
  const [frameRef, frame] = useSize<HTMLDivElement>();
  // Whether the table already cheered the game's end, so game over cheers only if it didn't.
  const cheer = useRef(NO_CHEER);
  useEffect(() => room.subscribe({ event: ({ event }) => void (cheer.current = cheerStep(cheer.current, event)) }), [room]);
  const latest = useRef(props);
  latest.current = props;

  // Before the TV moves, the table it leaves lets it go: its socket closes first.
  const moveTo = (next: string) => {
    if (next === code) {
      setMenu("closed");
      return;
    }
    room.stop();
    latest.current.onMove(next);
  };

  useEffect(() => {
    room.start();
    const visible = () => {
      if (document.visibilityState === "visible" && !room.socket.connected) room.socket.reconnectNow();
    };
    const online = () => room.socket.reconnectNow();
    document.addEventListener("visibilitychange", visible);
    window.addEventListener("online", online);
    return () => {
      document.removeEventListener("visibilitychange", visible);
      window.removeEventListener("online", online);
      room.stop();
    };
  }, [room]);

  // A new deploy reloads the TV only between hands, as it does a phone: never mid-hand.
  useEffect(() => setSafeToReload(safeToReload(state.phase)), [state.phase]);
  useEffect(() => () => setSafeToReload(true), []);

  useEffect(() => {
    const shown: Partial<Record<RoomPhase, TvPhase>> = { lobby: "lobby", playing: "table", over: "over" };
    // The table is gone (4404), closed, no longer lists this TV (4403, reported as not found), or
    // this device is locked out of it: forget it and go home. A newer server: reload for it.
    if (state.phase === "notFound" || state.phase === "closed" || state.phase === "locked") latest.current.onGone();
    else if (state.phase === "needsUpdate") reloadForUpdate();
    else if (shown[state.phase]) latest.current.onPhase(shown[state.phase]!);
  }, [state.phase]);

  // Play again: the TV follows to the new table, as its screen there.
  useEffect(() => {
    if (state.rematch && state.rematch !== code) moveTo(state.rematch);
  }, [state.rematch]);

  // A remote's Back opens the menu, and goes back through it.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!isBack(e)) return;
      e.preventDefault();
      setMenu((m) => back(m));
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const busy = useRef(false);
  const changeGame = async (button: HTMLElement) => {
    if (busy.current || !view) return;
    busy.current = true;
    try {
      moveTo(await tvApi.createRoom(otherGame(gameOf(view)), { screen: true }));
    } catch {
      play("nope");
      button.animate(NOPE, { duration: 360, easing: "ease-in-out" });
      busy.current = false;
    }
  };

  const offline = state.everConnected && !state.online;
  // Under the menu, or "Press OK for sound", the table's own buttons are out of the remote's reach.
  const live = menu === "closed" && !props.asleep;
  const openMenu = () => setMenu("items");
  let body;
  if (!view) {
    body = (
      <section class="tv-room-screen">
        <div class="tv-room-card panel">
          <Cat cat={0} pose="awake" size="calc(var(--u) * 220)" class="tv-room-cat" />
          <p class="tv-room-words outlined">{state.everConnected ? "Reconnecting" : "Finding your table"}</p>
        </div>
      </section>
    );
  } else if (view.status === "lobby") {
    body = <TvLobby room={view} live={live} onChangeGame={(b) => void changeGame(b)} />;
  } else {
    body = (
      <>
        <TvTable store={room} state={state} offline={offline && view.status === "playing"} />
        {view.status === "over" ? <TvOver room={view} cheered={cheer.current.cheered} /> : null}
      </>
    );
  }

  return (
    <div class="tv-room" ref={frameRef}>
      {body}
      {view ? <MenuButton rect={tvMenu(frame.width || 1920, frame.height || 1080, NO_INSETS)} live={live} onMenu={openMenu} /> : null}
      {offline && view?.status !== "playing" ? (
        <div class="tv-note" role="status">
          <span class="dot" /> Reconnecting
        </div>
      ) : null}
      {menu !== "closed" ? (
        <TvMenu
          view={menu}
          code={code}
          onView={setMenu}
          onLeave={() => latest.current.onGone()}
          onLinked={moveTo}
          onBoard={(token) => {
            // The board replaces the table: its socket closes first.
            room.stop();
            latest.current.onBoard(token);
          }}
        />
      ) : null}
    </div>
  );
}
