/**
 * The page a phone's camera opens from a TV's QR (`/play/tv-link/<token>`, after first run when
 * it hasn't run): pick one of your tables, or start a new game, and it goes on that TV.
 */
import { useEffect, useRef, useState } from "preact/hooks";

import { art } from "../lib/art";
import { buzz } from "../lib/haptics";
import { navigate } from "../lib/router";
import { play } from "../lib/sound";
import { linkExpired, linkFailedWords, linkWords } from "../lib/tv-code";
import { api, type TableEntry } from "../net/api";
import { knownTables } from "../store/app";

import { Button, Icon, IconButton, Sheet } from "./common";
import { Posters, TableCard } from "./home";

import type { TableIntent } from "./table-screen";
import type { GameId } from "../lib/catalog";

/** Tables a TV can take: the ones still waiting or playing, newest first. */
function liveTables(list: TableEntry[]): TableEntry[] {
  return list.filter((t) => t.status === "lobby" || t.status === "playing").sort((a, b) => b.updatedAt - a.updatedAt);
}

/**
 * `say`: "On the TV". `warn`: why a table made here opened without the TV (the link failed after
 * the table was made, which still opens rather than being left behind).
 */
export function TvLinkPage(props: {
  token: string;
  say: (words: string) => void;
  warn: (words: string) => void;
  onOpen: (code: string, intent: TableIntent) => void;
}) {
  const [tables, setTables] = useState<TableEntry[] | null>(null);
  const [busy, setBusy] = useState(false);
  // A second tap before the re-render that disables the buttons is still one tap.
  const working = useRef(false);
  const [error, setError] = useState<string | null>(null);
  const [expired, setExpired] = useState(false);
  const [moving, setMoving] = useState<{ code: string; intent: TableIntent } | null>(null);

  useEffect(() => {
    let live = true;
    api
      .listTables()
      .then((list) => live && setTables(liveTables(list)))
      .catch(() => {
        // Offline: the tables this device opened before.
        if (live) setTables(knownTables().map((k) => ({ code: k.code, name: k.name, game: k.game, status: "playing", yourTurn: false, updatedAt: k.at })));
      });
    return () => {
      live = false;
    };
  }, []);

  /** Sends `code` to the TV, then opens it here; a TV showing another table asks first. */
  const link = async (code: string, intent: TableIntent, move = false) => {
    const answer = await api.linkScreen({ token: props.token }, code, move);
    if (answer === "showing") {
      setMoving({ code, intent });
      return;
    }
    props.say("On the TV");
    props.onOpen(code, intent);
  };

  /** Links a table just made here; when the link fails the table opens anyway, with a note. */
  const linkNew = async (code: string, move = false) => {
    try {
      await link(code, "host", move);
    } catch (failure) {
      setMoving(null);
      props.warn(linkFailedWords(failure));
      props.onOpen(code, "host");
    }
  };

  const run = async (work: () => Promise<void>) => {
    if (working.current) return;
    working.current = true;
    setBusy(true);
    setError(null);
    try {
      await work();
    } catch (failure) {
      setMoving(null);
      if (linkExpired(failure)) setExpired(true);
      else {
        setError(linkWords(failure));
        play("nope");
        buzz("nope");
      }
    } finally {
      working.current = false;
      setBusy(false);
    }
  };

  const home = () => navigate({ kind: "home" });

  if (expired) {
    return (
      <main class="screen violet-bg">
        <div class="state">
          <img src={art("state-closed")} alt="" />
          <p>This TV link has expired.</p>
          <Button onClick={home}>
            <Icon name="icon-home" size={28} /> Home
          </Button>
        </div>
      </main>
    );
  }

  const newGame = (game: GameId) =>
    void run(async () => {
      const code = await api.createRoom(game);
      await linkNew(code);
    });

  return (
    <main class="screen home tv-link" aria-busy={busy ? "true" : undefined}>
      <div class="room-bg" style={{ backgroundImage: `url(${art("home-bg")})` }} />
      <header class="tv-link-top">
        <IconButton icon="icon-back" label="Home" onClick={home} />
        <h1 class="title outlined">Put a table on the TV</h1>
      </header>

      {error ? (
        <p class="link-error tv-link-error" role="alert">
          {error}
        </p>
      ) : null}

      {tables && tables.length > 0 ? (
        <section class="home-section" aria-labelledby="tv-tables-h">
          <h2 class="outlined section-h" id="tv-tables-h">
            Your tables
          </h2>
          <div class="table-strip">
            {tables.map((t) => (
              <TableCard t={t} disabled={busy} onOpen={(code) => void run(() => link(code, "open"))} />
            ))}
          </div>
        </section>
      ) : null}

      <section class="home-section posters" aria-labelledby="tv-new-h">
        <h2 class="outlined section-h" id="tv-new-h">
          New game
        </h2>
        <Posters onPlay={newGame} disabled={busy} />
      </section>

      {moving ? (
        <Sheet title="Move the TV to this table?" onClose={() => (moving.intent === "host" ? props.onOpen(moving.code, "host") : setMoving(null))}>
          <div class="sheet-actions">
            <Button
              wide
              variant="ok"
              disabled={busy}
              onClick={() => void run(() => (moving.intent === "host" ? linkNew(moving.code, true) : link(moving.code, moving.intent, true)))}
            >
              Move
            </Button>
            {/* A table made here opens even when the TV stays where it is. */}
            <Button wide variant="violet" onClick={() => (moving.intent === "host" ? props.onOpen(moving.code, "host") : setMoving(null))}>
              Cancel
            </Button>
          </div>
        </Sheet>
      ) : null}
    </main>
  );
}
