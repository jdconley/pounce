/**
 * Pounce on the TV (`/play/tv`). A TV is no one's seat: it shows a link (a QR and a backup code)
 * that a phone scans to put its table here, or makes a table itself from one of the two game
 * posters. It runs on its own device credential (`tvApi`), never runs first run, and is driven by
 * a remote: arrow keys, Enter and Back, with the mouse as well.
 */
import { useEffect, useRef, useState } from "preact/hooks";

import { art, RINGS } from "../../lib/art";
import { CATALOG, GAME_IDS, type GameId } from "../../lib/catalog";
import { store } from "../../lib/kv";
import { isRoomCode } from "../../lib/router";
import { play, unlockAudio } from "../../lib/sound";
import { tvApi } from "../../net/api";
import { ScreenLink } from "../../net/screen-link";
import { RoomStore, type RoomPhase } from "../../store/room";
import { Button, Cat } from "../common";
import { QrCode } from "../qr";

import { isBack, useDpad } from "./focus";
import "./tv.css";

/** The table this TV shows, so a reload goes back to it. */
const ROOM_KEY = "pounce.tv.room";

export type TvPhase = "start" | "home" | "lobby" | "table" | "over";

const keptRoom = (): string | null => {
  const code = store.get(ROOM_KEY);
  return code && isRoomCode(code) ? code : null;
};

const keepRoom = (code: string | null): void => {
  if (code) store.set(ROOM_KEY, code);
  else store.remove(ROOM_KEY);
};

/** Keeps the screen on while the TV page shows, taken again whenever the page comes back. */
function useWakeLock(on: boolean): void {
  useEffect(() => {
    if (!on || !("wakeLock" in navigator)) return;
    let live = true;
    let held: WakeLockSentinel | null = null;
    const take = () => {
      if (document.visibilityState !== "visible" || (held && !held.released)) return;
      navigator.wakeLock
        .request("screen")
        .then((sentinel) => {
          if (live) held = sentinel;
          else void sentinel.release();
        })
        .catch(() => undefined);
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

export function TvApp() {
  const root = useRef<HTMLElement>(null);
  const [phase, setPhase] = useState<TvPhase>("start");
  const [room, setRoom] = useState<string | null>(null);
  useDpad(root);
  useWakeLock(phase !== "start");

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

  const start = () => {
    unlockAudio();
    try {
      void document.documentElement.requestFullscreen?.().catch(() => undefined);
    } catch {
      // No full screen here (an iframe, an old TV browser): the page still plays.
    }
    const kept = keptRoom();
    if (kept) openRoom(kept);
    else setPhase("home");
  };

  // Back leaves a table for the home screen.
  useEffect(() => {
    if (phase === "start" || phase === "home") return;
    const onKey = (e: KeyboardEvent) => {
      if (!isBack(e)) return;
      e.preventDefault();
      goHome();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [phase]);

  return (
    <main class={`tv tv-${phase}`} ref={root}>
      <div class="tv-bg" style={{ backgroundImage: `url(${art("home-bg")})` }} aria-hidden="true" />
      {phase === "start" ? <TvStart onStart={start} /> : null}
      {phase === "home" ? <TvHome onLinked={openRoom} onMade={openRoom} /> : null}
      {room && phase !== "start" && phase !== "home" ? <TvRoom key={room} code={room} phase={phase} onPhase={setPhase} onGone={goHome} /> : null}
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

type Link = { code: string; url: string };

/** A refused press (Juice.swift's nope), as a shake that leaves the focus ring's scale alone. */
const NOPE: Keyframe[] = [
  { translate: "0" },
  { translate: "-14px 0" },
  { translate: "12px 0" },
  { translate: "-8px 0" },
  { translate: "4px 0" },
  { translate: "0" },
];

function TvHome(props: { onLinked: (room: string) => void; onMade: (room: string) => void }) {
  const [link, setLink] = useState<Link | null>(null);
  const [offline, setOffline] = useState(false);
  const busy = useRef(false);
  const linked = useRef(props.onLinked);
  linked.current = props.onLinked;

  useEffect(() => {
    const screen = new ScreenLink({ api: tvApi });
    const off = screen.on((e) => {
      if (e.kind === "code") {
        setLink({ code: e.code, url: e.url });
        setOffline(false);
      } else if (e.kind === "offline") setOffline(true);
      else linked.current(e.room);
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

  return (
    <section class="tv-home-screen">
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
            aria-label={CATALOG[id].title}
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
      </div>
      {offline ? (
        <div class="tv-note" role="status">
          <span class="dot" /> Reconnecting
        </div>
      ) : null}
    </section>
  );
}

/**
 * The table this TV shows, connected as its screen. For now a card with the table's code: the
 * lobby, the table and game over come later (stage 2, tasks 5 and 6).
 */
function TvRoom(props: { code: string; phase: TvPhase; onPhase: (p: TvPhase) => void; onGone: () => void }) {
  const [lost, setLost] = useState(false);
  const gone = useRef(props.onGone);
  gone.current = props.onGone;
  const onPhase = useRef(props.onPhase);
  onPhase.current = props.onPhase;

  useEffect(() => {
    const room = new RoomStore({
      code: props.code,
      role: "screen",
      token: async () => (await tvApi.credential()).token,
      dropToken: () => undefined,
      reducedMotion: () => matchMedia("(prefers-reduced-motion: reduce)").matches,
    });
    const shown: Partial<Record<RoomPhase, TvPhase>> = { lobby: "lobby", playing: "table", over: "over" };
    const off = room.subscribe({
      change: (s) => {
        setLost(s.everConnected && !s.online);
        // The room is gone (4404), closed, or no longer lists this TV (4403, which the socket
        // reports as not found): forget it and go home.
        if (s.phase === "notFound" || s.phase === "closed") gone.current();
        else if (shown[s.phase]) onPhase.current(shown[s.phase]!);
      },
    });
    room.start();
    return () => {
      off();
      room.stop();
    };
  }, [props.code]);

  return (
    <section class="tv-room-screen">
      <div class="tv-room-card panel">
        <Cat cat={0} pose={props.phase === "over" ? "celebrate" : "awake"} size="calc(var(--u) * 220)" class="tv-room-cat" />
        <span class="tv-room-label outlined">Table</span>
        <strong class="tv-room-code outlined" aria-label={`Table ${props.code.split("").join(" ")}`}>
          {props.code}
        </strong>
        {props.phase === "lobby" ? <p class="tv-room-words outlined">Press Start on any phone</p> : null}
      </div>
      {lost ? (
        <div class="tv-note" role="status">
          <span class="dot" /> Reconnecting
        </div>
      ) : null}
    </section>
  );
}
