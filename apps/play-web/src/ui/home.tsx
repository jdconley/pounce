import { useEffect, useState } from "preact/hooks";

import { alertsCardDismissed, dismissAlertsCard, turnOnAlerts, useAlerts } from "../alerts";
import { TodayDish, useDishOn } from "../daily/dish-home";
import { art, RINGS } from "../lib/art";
import { CATALOG, GAME_IDS, titleOf, type GameId } from "../lib/catalog";
import { isRoomCode, navigate } from "../lib/router";
import { api, type TableEntry } from "../net/api";
import { promptInstall, useInstall } from "../pwa";
import { knownTables, reach, useApp } from "../store/app";

import { Button, Cat, CloseMark, Icon, IconButton, Tip } from "./common";


function Dots(props: { n: number }) {
  return (
    <span class="dots" aria-hidden="true">
      {RINGS.slice(0, props.n).map((c) => (
        <i style={{ background: c }} />
      ))}
    </span>
  );
}

/** A table on Home's strip (and the TV-link page's): `onOpen` instead of opening it. */
export function TableCard(props: { t: TableEntry; onOpen?: (code: string) => void; disabled?: boolean }) {
  const { t } = props;
  const people = (t.seats ?? []).filter((s) => s.kind === "human" && s.person);
  const first = people[0]?.person;
  const status = t.status === "lobby" ? "Waiting" : t.status === "over" ? "Game over" : t.yourTurn ? "Your turn" : "Playing";
  return (
    <button
      type="button"
      class={`table-card ${t.yourTurn && t.status === "playing" ? "turn" : ""}`}
      disabled={props.disabled}
      onClick={() => (props.onOpen ? props.onOpen(t.code) : navigate({ kind: "table", code: t.code }))}
    >
      {t.yourTurn && t.status === "playing" ? <span class="turn-badge" aria-hidden="true"><Icon name="icon-paw-menu" size={26} /></span> : null}
      <Cat cat={first?.cat ?? 0} pose={t.status === "playing" ? "awake" : "idle"} size={64} />
      <strong class="outlined">{t.name ?? t.code}</strong>
      <span class="sub">{status}</span>
      <span class="code">{t.code}</span>
      {/* Named by what it shows, then its game: a voice command can say what the eye reads. */}
      <span class="sr-only">, {titleOf(t.game ?? "cat-tower")}</span>
    </button>
  );
}

export function Home(props: { onSettings: () => void; onPractice: (game: GameId) => void; onNew: (game: GameId) => void }) {
  const { people } = useApp();
  const install = useInstall();
  const [tables, setTables] = useState<TableEntry[] | null>(null);

  useEffect(() => {
    reach("home_seen");
    let live = true;
    api
      .listTables()
      .then((list) => live && setTables(list))
      .catch(() => {
        // Offline: the tables this device opened before.
        if (live) setTables(knownTables().map((k) => ({ code: k.code, name: k.name, game: k.game, status: "playing", yourTurn: false, updatedAt: k.at })));
      });
    return () => {
      live = false;
    };
  }, []);

  const open = (tables ?? []).filter((t) => t.status !== "over").sort((a, b) => Number(b.yourTurn) - Number(a.yourTurn) || b.updatedAt - a.updatedAt);
  const turns = open.filter((t) => t.yourTurn && t.status === "playing").length;
  const alerts = useAlerts();
  const askAlerts = alerts === "off" && open.length > 0 && people.band !== "kitten" && !alertsCardDismissed();
  const owner = people.owner;
  // With the Dish on, Home makes room for it: the game posters fold into a compact row.
  const dishOn = useDishOn();

  return (
    <main class="screen home">
      <div class="room-bg" style={{ backgroundImage: `url(${art("home-bg")})` }} />
      <header class="home-top">
        <button type="button" class="me" onClick={props.onSettings} aria-label={`You: ${owner?.name ?? ""}. Settings`}>
          {owner ? <Cat cat={owner.cat} pose="idle" size={44} /> : null}
          <span class="outlined">{owner?.name}</span>
        </button>
        <div class="top-actions">
          {install === "available" ? (
            <Button variant="teal" size="small" onClick={() => void promptInstall()} id="install">
              Install
            </Button>
          ) : null}
          <IconButton icon="icon-gear" label="Settings" onClick={props.onSettings} id="gear" />
        </div>
      </header>

      <TodayDish />

      {open.length > 0 ? (
        <section class="home-section" aria-labelledby="tables-h">
          <h2 class="outlined section-h" id="tables-h">
            Your tables {turns > 0 ? <span class="chip turns">{turns === 1 ? "1 turn" : `${turns} turns`}</span> : null}
          </h2>
          {askAlerts ? (
            <div class="alerts-card panel" role="group" aria-label="Turn alerts">
              <Icon name="icon-bell" size={36} />
              <span class="grow">A ping when it's your move.</span>
              <Button size="small" variant="ok" onClick={() => void turnOnAlerts().then(() => dismissAlertsCard())}>
                Turn on
              </Button>
              <button type="button" class="icon-btn plain small-x" aria-label="Not now" onClick={dismissAlertsCard}>
                <CloseMark />
              </button>
            </div>
          ) : null}
          <div class="table-strip" id="tables">
            {open.map((t) => (
              <TableCard t={t} />
            ))}
          </div>
        </section>
      ) : null}

      <section class="home-section posters" aria-labelledby="new-h">
        <h2 class="outlined section-h" id="new-h">
          New game
        </h2>
        <Posters onPlay={props.onNew} firstId="play-first" compact={dishOn} />
      </section>

      <nav class="home-start" aria-label="Start">
        <Button variant="violet" onClick={() => props.onPractice("cat-tower")} id="practice">
          <Icon name="badge-bot" size={30} /> Practice
        </Button>
        <Button variant="teal" onClick={() => navigate({ kind: "keypad" })} id="join">
          <Icon name="icon-keypad" size={30} /> Join
        </Button>
      </nav>
      <Tip id="home.play" anchor="play-first" text="Tap Play to start a game." show={open.length === 0} place="below" />
    </main>
  );
}

/** The games' posters, each with Play (Home's New game, and the TV-link page's). */
export function Posters(props: { onPlay: (game: GameId) => void; firstId?: string; disabled?: boolean; compact?: boolean }) {
  return (
    <div class={`poster-grid ${props.compact ? "compact" : ""}`}>
      {GAME_IDS.map((id, i) => (
        <article class={`poster ${id}`}>
          <img class="poster-art" src={art(CATALOG[id].art)} alt="" width={768} height={512} decoding="async" />
          <div class="poster-body">
            <h3 class="outlined">{CATALOG[id].title}</h3>
            <p>{CATALOG[id].tagline}</p>
            <div class="poster-foot">
              <span class="players">
                <Dots n={CATALOG[id].maxSeats} /> {CATALOG[id].minSeats} to {CATALOG[id].maxSeats} players
              </span>
              <Button
                size="small"
                class="poster-play"
                id={i === 0 ? props.firstId : undefined}
                disabled={props.disabled}
                onClick={() => props.onPlay(id)}
                aria-label={`Play ${CATALOG[id].title}`}
              >
                <Icon name="icon-play" size={26} /> Play
              </Button>
            </div>
          </div>
        </article>
      ))}
    </div>
  );
}

/** Join by code: five letters, typed or pasted (a whole invite link works too). */
export function JoinScreen(props: { onJoin: (code: string) => void }) {
  const [value, setValue] = useState("");
  const [shake, setShake] = useState(0);
  const code = value.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 5);
  const ok = isRoomCode(code);
  const submit = () => {
    if (ok) props.onJoin(code);
    else setShake((n) => n + 1);
  };
  const paste = async () => {
    try {
      const text = await navigator.clipboard.readText();
      const found = /\/j\/([A-Za-z0-9]{5})/.exec(text)?.[1] ?? /\b([A-Za-z0-9]{5})\b/.exec(text)?.[1];
      if (found) {
        setValue(found.toUpperCase());
        if (isRoomCode(found.toUpperCase())) props.onJoin(found.toUpperCase());
      }
    } catch {
      // No clipboard access: typing works.
    }
  };
  return (
    <main class="screen violet-bg join">
      <button type="button" class="icon-btn back-btn" aria-label="Back" onClick={() => navigate({ kind: "home" })}>
        <Icon name="icon-back" />
      </button>
      <form
        class="join-form"
        onSubmit={(e) => {
          e.preventDefault();
          submit();
        }}
      >
        <h1 class="title outlined">Join a table</h1>
        <label class="sr-only" for="code">
          Table code
        </label>
        <input
          id="code"
          class={`field code-field ${shake ? "nope" : ""}`}
          key={shake}
          value={code}
          placeholder="CODE"
          autoComplete="off"
          autoCapitalize="characters"
          spellcheck={false}
          inputMode="text"
          enterKeyHint="go"
          maxLength={40}
          autoFocus
          onInput={(e) => setValue((e.target as HTMLInputElement).value)}
        />
        <div class="join-actions">
          {"clipboard" in navigator && typeof navigator.clipboard.readText === "function" ? (
            <Button variant="violet" onClick={() => void paste()}>
              Paste
            </Button>
          ) : null}
          <Button type="submit" variant="ok" disabled={!ok}>
            Join
          </Button>
        </div>
      </form>
    </main>
  );
}
