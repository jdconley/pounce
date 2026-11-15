/**
 * One table, from the moment its link opens to the end of the game: connecting, the lobby, the
 * game, game over and Play again. It seats this device as the way in asks (a new table, a
 * practice game, a guest's invite), and keeps the socket alive through sleep and lost networks.
 */
import { useEffect, useMemo, useRef, useState } from "preact/hooks";


import { art } from "../lib/art";
import { buzz } from "../lib/haptics";
import { navigate } from "../lib/router";
import { play } from "../lib/sound";
import { api } from "../net/api";
import { noteGameFinished, reloadForUpdate, setSafeToReload } from "../pwa";
import { addPerson, forgetTable, rememberTable, useApp } from "../store/app";
import { autoClaimSeat, firstTableMessages, mySeats, practiceMessages } from "../store/lobby";
import { RoomStore, type RoomState } from "../store/room";
import { CatTowerTable } from "../table/cattower";
import { seatCat, seatName } from "../table/seat";
import { TilesTable } from "../table/tiles";

import { Button, Cat, Icon, IconButton } from "./common";
import { Lobby } from "./lobby";

import type { RoomView } from "@pounce/play-api/protocol";

export type TableIntent = "host" | "practice" | "guest" | "open";

function useRoom(store: RoomStore): RoomState {
  const [state, setState] = useState(store.state);
  useEffect(() => store.subscribe({ change: setState }), [store]);
  return state;
}

export function TableScreen(props: { code: string; intent: TableIntent }) {
  const { people } = useApp();
  const store = useMemo(
    () =>
      new RoomStore({
        code: props.code,
        token: async () => (await api.credential()).token,
        dropToken: () => undefined,
        reducedMotion: () => matchMedia("(prefers-reduced-motion: reduce)").matches,
      }),
    [props.code],
  );
  const state = useRoom(store);
  const room = state.room;

  useEffect(() => {
    store.start();
    const visible = () => {
      const active = document.visibilityState === "visible";
      store.send({ t: "presence", state: active ? "active" : "background" });
      if (active && !store.socket.connected) store.socket.reconnectNow();
    };
    const online = () => store.socket.reconnectNow();
    const shown = (e: PageTransitionEvent) => {
      if (e.persisted) store.socket.reconnectNow();
    };
    document.addEventListener("visibilitychange", visible);
    window.addEventListener("online", online);
    window.addEventListener("pageshow", shown);
    return () => {
      document.removeEventListener("visibilitychange", visible);
      window.removeEventListener("online", online);
      window.removeEventListener("pageshow", shown);
      store.stop();
    };
  }, [store]);

  // Seat this device as the way in asks, once.
  const seatedOnce = useRef(false);
  const setupDone = useRef(false);
  useEffect(() => {
    const truth = state.truth;
    const owner = people.owner;
    if (!truth || !owner) return;
    const seated = mySeats(truth).length > 0;
    if (!seated && !seatedOnce.current && truth.status === "lobby") {
      const seat = props.intent === "host" || props.intent === "practice" ? (truth.seats.findIndex((s) => s.kind === "open") >= 0 ? truth.seats.findIndex((s) => s.kind === "open") : autoClaimSeat(truth)) : autoClaimSeat(truth);
      if (seat !== null && seat >= 0) {
        seatedOnce.current = true;
        store.send({ t: "claim", seat, person: { id: owner.id, name: owner.name, cat: owner.cat } });
      }
      return;
    }
    if (seated && !setupDone.current) {
      setupDone.current = true;
      if (props.intent === "practice") for (const m of practiceMessages(truth) ?? []) store.send(m);
      else if (props.intent === "host") for (const m of firstTableMessages(truth) ?? []) store.send(m);
    }
  }, [state.truth, people.owner]);

  // A refused claim (someone took the seat first): try once more on the next snapshot.
  useEffect(() => {
    if (state.error?.code === "seat_taken" && mySeats(state.truth ?? ({ seats: [] } as unknown as RoomView)).length === 0) seatedOnce.current = false;
  }, [state.error?.n]);

  useEffect(() => {
    if (room) rememberTable({ code: room.code, game: room.gameId ?? "cat-tower", name: room.name, at: Date.now() });
  }, [room?.name, room?.code]);

  // New deploys wait for a safe moment: never mid-hand.
  useEffect(() => {
    setSafeToReload(state.phase !== "playing");
    if (state.phase === "needsUpdate") reloadForUpdate();
    if (state.phase === "over") {
      noteGameFinished();
    }
    if (state.phase === "notFound" || state.phase === "closed") forgetTable(props.code);
  }, [state.phase]);
  useEffect(() => () => setSafeToReload(true), []);

  // Play again: the new table.
  useEffect(() => {
    if (state.rematch && state.phase === "over" && wantRematch.current) navigate({ kind: "table", code: state.rematch });
  }, [state.rematch]);
  const wantRematch = useRef(false);

  const home = () => navigate({ kind: "home" });
  const offline = state.everConnected && !state.online && ["lobby", "playing", "over", "connecting"].includes(state.phase);

  let body;
  if (state.phase === "notFound" || state.phase === "closed" || state.phase === "locked") {
    const words =
      state.phase === "locked" ? "Too many wrong codes. Try again later." : state.phase === "closed" ? "This table has closed." : "No table with that code.";
    body = (
      <main class="screen violet-bg">
        <div class="state">
          <img src={art(state.phase === "locked" ? "state-stalled" : "state-closed")} alt="" />
          <p>{words}</p>
          <Button onClick={home}>
            <Icon name="icon-home" size={28} /> Home
          </Button>
        </div>
      </main>
    );
  } else if (!room) {
    body = (
      <main class="screen violet-bg">
        <div class="state">
          <img class="bob" src={art("state-offline")} alt="" />
          <p>{state.everConnected ? "Reconnecting" : "Finding your table"}</p>
          <Button variant="violet" size="small" onClick={home}>
            Home
          </Button>
        </div>
      </main>
    );
  } else if (room.status === "lobby") {
    body = (
      <Lobby
        store={store}
        room={room}
        kitten={people.band === "kitten"}
        onHome={home}
        onAddLocal={async (name, cat, seat) => {
          const person = await addPerson(name, cat);
          store.send({ t: "claim", seat, person: { id: person.id, name: person.name, cat: person.cat } });
        }}
      />
    );
  } else {
    const isTiles = room.gameId === "tiles";
    body = (
      <main class="screen table-screen">
        <div class="room-bg" style={{ backgroundImage: `url(${art("room-bg")})` }} />
        {isTiles && room.tiles ? <TilesTable store={store} state={state} /> : room.game ? <CatTowerTable store={store} state={state} /> : null}
        <div class="table-menu">
          <IconButton icon="icon-home" label="Home" plain onClick={home} />
        </div>
        {room.status === "over" ? (
          <GameOver
            room={room}
            onHome={home}
            onAgain={() => {
              wantRematch.current = true;
              if (state.rematch) navigate({ kind: "table", code: state.rematch });
              else store.send({ t: "rematch" });
            }}
          />
        ) : null}
      </main>
    );
  }

  return (
    <>
      {body}
      {offline ? (
        <div class="banner offline" role="status">
          <span class="dot" /> {navigator.onLine ? "Reconnecting" : "Offline"}
        </div>
      ) : state.online && state.link === "weak" && state.phase === "playing" ? (
        <div class="banner" role="status">
          <span class="dot" /> Slow connection
        </div>
      ) : null}
    </>
  );
}

/** Who won, everyone's place, and Play again (GameOverView.swift). */
function GameOver(props: { room: RoomView; onHome: () => void; onAgain: () => void }) {
  const { room } = props;
  const g = room.game;
  const t = room.tiles;
  const winners = g?.winners ?? t?.winners ?? [];
  const forfeited = g?.forfeited ?? t?.forfeited ?? [];
  const seats = room.seats.flatMap((s, i) => (s.kind === "human" || s.kind === "bot" ? [i] : []));
  const rank = [...seats].sort((a, b) => {
    const w = Number(winners.includes(b)) - Number(winners.includes(a));
    if (w) return w;
    const f = Number(forfeited[a] ?? false) - Number(forfeited[b] ?? false);
    if (f) return f;
    if (g) return (g.phase[b] ?? 0) - (g.phase[a] ?? 0) || (g.scores[a] ?? 0) - (g.scores[b] ?? 0);
    return (t?.scores[b] ?? 0) - (t?.scores[a] ?? 0);
  });
  const mine = mySeats(room);
  const won = winners.some((w) => mine.includes(w));
  useEffect(() => {
    play(won ? "fanfare" : "leap");
    buzz("win");
  }, []);
  const title = winners.length === 1 ? `${seatName(room.seats[winners[0]!])} wins` : winners.length > 1 ? "A tie" : "Game over";
  return (
    <div class="game-over" role="dialog" aria-label={title}>
      <img class="sunburst" src={art("sunburst")} alt="" />
      <div class="panel over-card">
        <div class="winners">
          {winners.map((w) => (
            <Cat cat={seatCat(room.seats[w])} pose="celebrate" size={120} />
          ))}
        </div>
        <h2 class="title outlined">{title}</h2>
        <ol class="ranks">
          {rank.map((s) => (
            <li class={winners.includes(s) ? "won" : ""}>
              <Cat cat={seatCat(room.seats[s])} pose={winners.includes(s) ? "celebrate" : "idle"} size={40} />
              <span class="who">{seatName(room.seats[s])}</span>
              <span class="detail">
                {forfeited[s] ? "Left" : g ? `Level ${Math.min((g.phase[s] ?? 0) + 1, 10)} · ${g.scores[s] ?? 0}` : `${(t?.scores[s] ?? 0) > 0 ? "+" : ""}${t?.scores[s] ?? 0}`}
              </span>
            </li>
          ))}
        </ol>
        <div class="over-actions">
          <Button variant="ok" onClick={props.onAgain} id="again">
            <Icon name="icon-replay" size={28} /> Play again
          </Button>
          <Button variant="violet" onClick={props.onHome}>
            <Icon name="icon-home" size={28} /> Home
          </Button>
        </div>
      </div>
    </div>
  );
}
