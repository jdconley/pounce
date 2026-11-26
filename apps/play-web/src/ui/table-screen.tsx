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
import { carryView, setView, showController, showSwitch, viewOf, type View } from "../store/views";
import { BirdwatchTable } from "../table/birdwatch";
import { BwHowTo } from "../table/bw-help";
import { bwOverTitle, bwStandings, RULE_COPY } from "../table/bw-model";
import { ScoreSheet } from "../table/bw-panels";
import { CatTowerTable } from "../table/cattower";
import { CtController } from "../table/ct-controller";
import { seatCat, seatName } from "../table/seat";
import { SwitchView } from "../table/shared";
import { TilesTable } from "../table/tiles";
import { TilesController } from "../table/tiles-controller";

import { Button, Cat, Icon, IconButton, Sheet } from "./common";
import { Lobby } from "./lobby";
import { ShowOnTvSheet, TvIcon } from "./show-on-tv";

import type { RoomView } from "@pounce/play-api/protocol";

export type TableIntent = "host" | "practice" | "guest" | "open";

function useRoom(store: RoomStore): RoomState {
  const [state, setState] = useState(store.state);
  useEffect(() => store.subscribe({ change: setState }), [store]);
  return state;
}

/** `say`: a toast over every screen (app.tsx's), as "On the TV" outlives the sheet that linked it. */
export function TableScreen(props: { code: string; intent: TableIntent; say?: (words: string) => void }) {
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

  // Play again: the new table, on the view (Cards or Table) this one was on.
  const playAgain = (code: string) => {
    carryView(props.code, code);
    navigate({ kind: "table", code });
  };
  useEffect(() => {
    if (state.rematch && state.phase === "over" && wantRematch.current) playAgain(state.rematch);
  }, [state.rematch]);
  const wantRematch = useRef(false);

  // Cards (just this phone's hand, the controller) or Table, while a TV shows the table.
  const [view, setViewNow] = useState<View>(() => viewOf(props.code));
  useEffect(() => setViewNow(viewOf(props.code)), [props.code]);
  const changeView = (next: View) => {
    setView(props.code, next);
    setViewNow(next);
  };

  const home = () => navigate({ kind: "home" });
  const [menu, setMenu] = useState<null | "menu" | "scores" | "forfeit" | "howto">(null);
  const [showOnTv, setShowOnTv] = useState(false);
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
        onShowOnTv={() => setShowOnTv(true)}
        onAddLocal={async (name, cat) => {
          const person = await addPerson(name, cat);
          // An open seat, else a House Cat's (a person takes it over), else a closed one, opened.
          const truth = store.state.truth ?? room;
          let seat = truth.seats.findIndex((s) => s.kind === "open");
          if (seat < 0) seat = truth.seats.findIndex((s) => s.kind === "bot");
          if (seat < 0) {
            seat = truth.seats.findIndex((s) => s.kind === "closed");
            if (seat < 0) return;
            store.send({ t: "configure", seat, kind: "open" });
          }
          store.send({ t: "claim", seat, person: { id: person.id, name: person.name, cat: person.cat } });
        }}
      />
    );
  } else {
    const isTiles = room.gameId === "tiles";
    const isBird = room.gameId === "birdwatch";
    const tvSwitch = (isBird ? Boolean(room.birdwatch) : isTiles ? Boolean(room.tiles) : room.game !== null) && showSwitch(room);
    const cards = tvSwitch && showController(room, view);
    // Tuna Tiles on Cards: the rack off turn; on your turn the full table, as rearranging it needs
    // it (the same element as on Table, so a draft survives the switch).
    const t = room.tiles;
    const tilesTurn = t !== undefined && t.status === "playing" && mySeats(room).some((s) => s === t.turn && !t.forfeited[s]);
    const controller = cards && (!isTiles || !tilesTurn);
    body = (
      <main class="screen table-screen">
        <div class="room-bg" style={{ backgroundImage: `url(${art("room-bg")})` }} />
        {isBird ? (
          room.birdwatch ? <BirdwatchTable store={store} state={state} sounds={!cards} cards={cards} topInset={tvSwitch && !cards ? SWITCH_STRIP : 0} /> : null
        ) : isTiles && room.tiles ? (
          controller ? (
            <TilesController store={store} state={state} onView={changeView} />
          ) : (
            <TilesTable store={store} state={state} sounds={!cards} topInset={tvSwitch ? SWITCH_STRIP : 0} />
          )
        ) : room.game ? (
          controller ? (
            <CtController store={store} state={state} onView={changeView} />
          ) : (
            <CatTowerTable store={store} state={state} topInset={tvSwitch ? SWITCH_STRIP : 0} />
          )
        ) : null}
        {tvSwitch && (!controller || isBird) ? (
          <div class="view-bar">
            <SwitchView view={view} onChange={changeView} />
          </div>
        ) : null}
        <div class="table-menu">
          <IconButton icon="icon-paw-menu" label="Menu" plain onClick={() => setMenu("menu")} id="table-menu" />
        </div>
        {menu === "menu" ? (
          <Sheet title={room.name} onClose={() => setMenu(null)}>
            <div class="settings">
              <button type="button" class="row" onClick={() => setMenu("scores")}>
                <Icon name="icon-trophy" size={32} />
                <span class="grow">Scores</span>
              </button>
              {mySeats(room).length > 0 ? (
                <button
                  type="button"
                  class="row"
                  id="menu-show-on-tv"
                  onClick={() => {
                    setMenu(null);
                    setShowOnTv(true);
                  }}
                >
                  <TvIcon size={32} />
                  <span class="grow">Show on TV</span>
                </button>
              ) : null}
              {isBird && room.options ? (
                <button type="button" class="row" onClick={() => setMenu("howto")}>
                  <Icon name="icon-play" size={32} />
                  <span class="grow">How to play</span>
                  <span class="fine">{RULE_COPY[room.options.rules].name}</span>
                </button>
              ) : (
                <a class="row" href="/support" target="_blank" rel="noopener">
                  <Icon name="icon-play" size={32} />
                  <span class="grow">How to play</span>
                </a>
              )}
              <button type="button" class="row" onClick={home}>
                <Icon name="icon-home" size={32} />
                <span class="grow">Home</span>
              </button>
              {room.status === "playing" && liveSeats(room).length > 0 ? (
                <button type="button" class="row danger" onClick={() => setMenu("forfeit")}>
                  <Icon name="icon-leave" size={32} />
                  <span class="grow">Forfeit</span>
                </button>
              ) : null}
            </div>
          </Sheet>
        ) : null}
        {menu === "scores" ? isBird && room.birdwatch ? <ScoreSheet room={room} onClose={() => setMenu(null)} /> : <ScoresSheet room={room} onClose={() => setMenu(null)} /> : null}
        {menu === "howto" && room.options ? <BwHowTo rules={room.options.rules} onClose={() => setMenu(null)} /> : null}
        {menu === "forfeit" ? (
          <Sheet title="Forfeit this game?" onClose={() => setMenu(null)}>
            <div class="sheet-actions">
              <p class="fine">{forfeitWords(room)}</p>
              <Button
                wide
                variant="magenta"
                id="forfeit"
                onClick={() => {
                  for (const seat of liveSeats(room)) store.forfeit(seat);
                  setMenu(null);
                }}
              >
                Forfeit
              </Button>
              <Button wide variant="violet" onClick={() => setMenu(null)}>
                Keep playing
              </Button>
            </div>
          </Sheet>
        ) : null}
        {room.status === "over" && isBird ? (
          <BwGameOver
            room={room}
            quiet={cards}
            onHome={home}
            onAgain={() => {
              wantRematch.current = true;
              if (state.rematch) playAgain(state.rematch);
              else store.send({ t: "rematch" });
            }}
          />
        ) : room.status === "over" ? (
          <GameOver
            room={room}
            quiet={cards}
            onHome={home}
            onAgain={() => {
              wantRematch.current = true;
              if (state.rematch) playAgain(state.rematch);
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
      {showOnTv && room ? (
        <ShowOnTvSheet
          room={room.code}
          onClose={() => setShowOnTv(false)}
          onShown={() => {
            setShowOnTv(false);
            props.say?.("On the TV");
          }}
        />
      ) : null}
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

/** The strip along the top of the full table the Cards/Table switch takes: the switch and its margin. */
const SWITCH_STRIP = 52;

/** Who won, everyone's place, and Play again (GameOverView.swift). */
/** `quiet`: no fanfare, as the TV cheers (a phone on Cards); the buzz stays. */
function GameOver(props: { room: RoomView; onHome: () => void; onAgain: () => void; quiet?: boolean }) {
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
    if (!props.quiet) play(won ? "fanfare" : "leap");
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

/** Birdwatch's game over: the winning side, every side's score, and Play again. */
function BwGameOver(props: { room: RoomView; onHome: () => void; onAgain: () => void; quiet?: boolean }) {
  const { room } = props;
  const rows = bwStandings(room);
  const winners = room.birdwatch?.winners ?? [];
  const won = winners.some((w) => mySeats(room).includes(w));
  useEffect(() => {
    if (!props.quiet) play(won ? "fanfare" : "leap");
    buzz("win");
  }, []);
  const title = bwOverTitle(room);
  return (
    <div class="game-over" role="dialog" aria-label={title}>
      <img class="sunburst" src={art("sunburst")} alt="" />
      <div class="panel over-card">
        <div class="winners">
          {winners.map((w) => (
            <Cat cat={seatCat(room.seats[w])} pose="celebrate" size={winners.length > 1 ? 96 : 120} />
          ))}
        </div>
        <h2 class="title outlined">{title}</h2>
        <ol class="ranks">
          {rows.map((r) => (
            <li class={r.won ? "won" : ""}>
              <span class="bw-cats">
                {r.seats.map((s) => (
                  <Cat cat={seatCat(room.seats[s])} pose={r.won ? "celebrate" : "idle"} size={36} />
                ))}
              </span>
              <span class="who">{r.name}</span>
              <span class="detail">{r.score}</span>
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

/** This device's seats still in the game. */
function liveSeats(room: RoomView): number[] {
  // Birdwatch: a seat that leaves goes to a House Cat, so every seat still this device's is live.
  if (room.gameId === "birdwatch") return mySeats(room);
  const out = room.game?.forfeited ?? room.tiles?.forfeited ?? [];
  return mySeats(room).filter((s) => !out[s]);
}

/** What a forfeit means here, in the words iOS uses (TableMenuSheet.swift). */
function forfeitWords(room: RoomView): string {
  if (room.gameId === "birdwatch") return "A House Cat takes your seat.";
  const out = room.game?.forfeited ?? room.tiles?.forfeited ?? [];
  const mine = new Set(liveSeats(room));
  const rest = room.seats.flatMap((s, i) => ((s.kind === "human" || s.kind === "bot") && !out[i] && !mine.has(i) ? [i] : []));
  if (rest.length === 1) return `${seatName(room.seats[rest[0]!])} wins.`;
  return "You finish last. The rest play on.";
}

/** Everyone's standing (Scores in the iOS table menu). */
function ScoresSheet(props: { room: RoomView; onClose: () => void }) {
  const { room } = props;
  const g = room.game;
  const t = room.tiles;
  const seats = room.seats.flatMap((s, i) => (s.kind === "human" || s.kind === "bot" ? [i] : []));
  return (
    <Sheet title="Scores" onClose={props.onClose}>
      <ol class="ranks">
        {seats.map((s) => (
          <li>
            <Cat cat={seatCat(room.seats[s])} size={40} />
            <span class="who">{seatName(room.seats[s])}</span>
            <span class="detail">
              {g ? `Level ${Math.min((g.phase[s] ?? 0) + 1, 10)} · ${g.scores[s] ?? 0}` : `${t?.rackCounts[s] ?? 0} pieces`}
            </span>
          </li>
        ))}
      </ol>
    </Sheet>
  );
}
