import { useEffect, useState } from "preact/hooks";


import { turnOffAlerts, turnOnAlerts, useAlerts } from "./alerts";
import { art } from "./lib/art";
import { flushNow } from "./lib/kv";
import { currentRoute, navigate, onRoute, type Route } from "./lib/router";
import { keepTvSettings, onSettings, setSettings, settings } from "./lib/settings";
import { api, ApiError } from "./net/api";
import { installState, promptInstall, useInstall } from "./pwa";
import { app, deleteMyData, finishAge, noteSource, reach, rememberTable, setOwner, syncProfile, useApp } from "./store/app";
import { peekInvite as peek } from "./store/peek";
import { Button, Cat, Icon, Sheet } from "./ui/common";
import { AgeScreen, NameScreen, type InviteBanner } from "./ui/firstrun";
import { Home, JoinScreen } from "./ui/home";
import { TvLinkPage } from "./ui/tv-link";

import type { GameId } from "./lib/catalog";
import type { TableIntent } from "./ui/table-screen";

/** The lobby and the tables load when a table opens, not with the first screen. */
type TableModule = typeof import("./ui/table-screen");
let tableModule: Promise<TableModule> | null = null;
export const loadTables = (): Promise<TableModule> => (tableModule ??= import("./ui/table-screen"));

function LazyTable(props: { code: string; intent: TableIntent; say: (words: string) => void; near?: string }) {
  const [mod, setMod] = useState<TableModule | null>(null);
  useEffect(() => {
    let live = true;
    void loadTables().then((m) => live && setMod(m));
    return () => {
      live = false;
    };
  }, []);
  if (!mod) return <main class="screen violet-bg" aria-busy="true" />;
  return <mod.TableScreen code={props.code} intent={props.intent} say={props.say} near={props.near} />;
}

/** How the next table screen was asked for (a new table, practice, an invite), and a Purrtrait table's join key. */
const intents = new Map<string, { intent: TableIntent; near?: string }>();

export function openTable(code: string, intent: TableIntent, replace = false, near?: string): void {
  intents.set(code, { intent, near });
  navigate({ kind: "table", code }, replace);
}

/** The Daily Dish loads when it opens: Home shows only its Today row. */
type DailyModule = typeof import("./daily/screens");
let dailyModule: Promise<DailyModule> | null = null;
const loadDaily = (): Promise<DailyModule> => (dailyModule ??= import("./daily/screens"));

function LazyDaily(props: { route: Extract<Route, { kind: "dish" | "daily" }>; say: (words: string) => void }) {
  const [mod, setMod] = useState<DailyModule | null>(null);
  useEffect(() => {
    let live = true;
    void loadDaily().then((m) => live && setMod(m));
    return () => {
      live = false;
    };
  }, []);
  if (!mod) return <main class="screen violet-bg" aria-busy="true" />;
  return props.route.kind === "dish" ? <mod.DishScreen say={props.say} /> : <mod.PuzzleHost key={props.route.game} game={props.route.game} say={props.say} />;
}

/** The TV page loads only on a TV: phones never download it. */
type TvModule = typeof import("./ui/tv/tv-app");

function LazyTv() {
  const [mod, setMod] = useState<TvModule | null>(null);
  useEffect(() => {
    let live = true;
    // This page is a TV: its sound is its own, not the phone's in the same browser.
    keepTvSettings();
    void import("./ui/tv/tv-app").then((m) => live && setMod(m));
    return () => {
      live = false;
    };
  }, []);
  if (!mod) return <main class="screen violet-bg" aria-busy="true" />;
  return <mod.TvApp />;
}

function useRoute(): Route {
  const [route, setRoute] = useState(currentRoute);
  useEffect(() => {
    // A child's first effects run before this one: a route it moved to then (an invite link opened
    // by someone who already has a name goes straight to the table) is read here, not missed.
    setRoute(currentRoute());
    return onRoute(setRoute);
  }, []);
  return route;
}

export function App() {
  const route = useRoute();
  // A TV is no one's device: no first run, no profile, no funnel.
  if (route.kind === "tv") return <LazyTv />;
  return <PlayerApp route={route} />;
}

function PlayerApp(props: { route: Route }) {
  const { route } = props;
  const { people } = useApp();
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [invite, setInvite] = useState<InviteBanner | null>(null);
  const [toast, setToast] = useState<{ words: string; good: boolean; top: boolean } | null>(null);
  const [busy, setBusy] = useState(false);

  // Once the first screen is up, fetch the tables' code in the background.
  useEffect(() => {
    const idle = (globalThis as { requestIdleCallback?: (fn: () => void, o?: { timeout: number }) => number }).requestIdleCallback;
    if (idle) idle(() => void loadTables(), { timeout: 4000 });
    else void loadTables();
  }, []);

  // Where this device came from, the first time.
  useEffect(() => {
    if (route.kind === "join") noteSource("join_link");
    else if (route.kind === "pounce") noteSource("pounce_link");
    else noteSource("organic");
    void syncProfile();
  }, []);

  // A guest who hasn't named themselves yet sees who invited them.
  useEffect(() => {
    if (route.kind === "join" && people.band && !people.owner) void peek(route.code).then(setInvite);
  }, [route.kind === "join" ? route.code : "", Boolean(people.band)]);

  // A guest with a name goes straight to the seat.
  useEffect(() => {
    if (route.kind === "join" && people.owner) {
      reach("link_opened");
      openTable(route.code, "guest", true);
    }
    // The TV's QR at a Purrtrait table: in with its key (the address bar drops it).
    if (route.kind === "easel" && people.owner) openTable(route.code, "guest", true, route.near);
  }, [route, people.owner]);

  const say = (words: string) => setToast({ words, good: false, top: false });
  /** Something that worked ("On the TV"): under the header, not in the refusal's red. */
  const cheer = (words: string) => setToast({ words, good: true, top: true });
  /** A refusal on a screen with bars along the bottom (a lobby): under the header too. */
  const warn = (words: string) => setToast({ words, good: false, top: true });

  const newTable = async (game: GameId, practice: boolean) => {
    if (busy) return;
    setBusy(true);
    try {
      const code = await api.createRoom(game);
      // Known here at once: the TV-link page offers it even before the table has loaded.
      rememberTable({ code, game, at: Date.now() });
      openTable(code, practice ? "practice" : "host");
    } catch (error) {
      say(error instanceof ApiError && error.status === 0 ? "You're offline." : "Couldn't make a table. Try again.");
    } finally {
      setBusy(false);
    }
  };

  let screen;
  if (!people.band) {
    screen = <AgeScreen onDone={(band) => finishAge(band)} />;
  } else if (!people.owner) {
    screen = (
      <NameScreen
        kitten={people.band === "kitten"}
        invite={invite}
        onDone={async (name, cat) => {
          await setOwner(name, cat);
        }}
      />
    );
  } else {
    switch (route.kind) {
      case "table":
        screen = <LazyTable key={route.code} code={route.code} intent={intents.get(route.code)?.intent ?? "open"} near={intents.get(route.code)?.near} say={cheer} />;
        break;
      case "keypad":
        screen = <JoinScreen onJoin={(code, near) => openTable(code, "guest", false, near)} />;
        break;
      case "pounce":
        screen = <PounceScreen token={route.token} />;
        break;
      case "join":
      case "easel":
        screen = <main class="screen violet-bg" />;
        break;
      case "dish":
      case "daily":
        screen = <LazyDaily route={route} say={cheer} />;
        break;
      // A TV's QR: first run (above) keeps this route, then the page puts a table on that TV.
      case "tvLink":
        screen = <TvLinkPage token={route.token} say={cheer} warn={warn} onOpen={(code, intent) => openTable(code, intent, true)} />;
        break;
      default:
        screen = <Home onSettings={() => setSettingsOpen(true)} onNew={(g) => void newTable(g, false)} onPractice={(g) => void newTable(g, true)} />;
    }
  }

  return (
    <>
      {screen}
      {settingsOpen ? <SettingsSheet onClose={() => setSettingsOpen(false)} /> : null}
      {toast ? (
        <div class={`banner toast ${toast.good ? "good" : ""} ${toast.top ? "top" : ""}`} role={toast.good ? "status" : "alert"} key={toast.words} onAnimationEnd={() => setToast(null)}>
          {toast.good ? <Icon name="icon-check" size={26} /> : null}
          {toast.words}
        </div>
      ) : null}
    </>
  );
}

/** A request to play (`/p/<token>`): who asked, and Play deals the table (§12.4). */
function PounceScreen(props: { token: string }) {
  const [from, setFrom] = useState<{ id: string; from: { name: string; cat: number } } | null | undefined>(undefined);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    reach("link_opened");
    api
      .pounceLink(props.token)
      .then(setFrom)
      .catch(() => setFrom(null));
  }, [props.token]);
  if (from === undefined) return <main class="screen violet-bg" />;
  if (from === null) {
    return (
      <main class="screen violet-bg">
        <div class="state">
          <img src={art("state-closed")} alt="" />
          <p>This invite has expired.</p>
          <Button onClick={() => navigate({ kind: "home" })}>Home</Button>
        </div>
      </main>
    );
  }
  return (
    <main class="screen violet-bg">
      <div class="state">
        <Cat cat={from.from.cat} pose="awake" size={180} />
        <h1 class="title outlined">{from.from.name} wants to play</h1>
        <Button
          size="big"
          variant="ok"
          disabled={busy}
          onClick={async () => {
            setBusy(true);
            try {
              await syncProfile();
              const owner = app().people.owner;
              const code = owner ? await api.answerPounce(from.id, props.token, owner.id) : null;
              if (code) openTable(code, "open", true);
              else setFrom(null);
            } catch {
              setFrom(null);
            } finally {
              setBusy(false);
            }
          }}
        >
          <Icon name="icon-play" size={34} /> Play
        </Button>
      </div>
    </main>
  );
}

function SettingsSheet(props: { onClose: () => void }) {
  const { people } = useApp();
  const [s, setS] = useState(settings());
  const [editing, setEditing] = useState(false);
  const [confirm, setConfirm] = useState(false);
  const [failed, setFailed] = useState(false);
  const [store, setStore] = useState<string | null>(null);
  const install = useInstall();
  const alerts = useAlerts();
  useEffect(() => onSettings(setS), []);
  useEffect(() => {
    fetch("/v1/app", { cache: "no-store" })
      .then((r) => r.json())
      .then((b: { storeUrl?: string }) => setStore(b.storeUrl ?? null))
      .catch(() => undefined);
  }, []);
  if (editing && people.owner) {
    return (
      <div class="overlay-screen">
        <NameScreen
          kitten={people.band === "kitten"}
          invite={null}
          initial={{ name: people.owner.name, cat: people.owner.cat }}
          title="You"
          onCancel={() => setEditing(false)}
          onDone={async (name, cat) => {
            await setOwner(name, cat);
            setEditing(false);
          }}
        />
      </div>
    );
  }
  if (confirm) {
    return (
      <Sheet title="Delete my data?" onClose={() => setConfirm(false)}>
        <div class="sheet-actions">
          <p class="fine">Your names, cats, tables and progress go for good, here and on our server.</p>
          {failed ? <p class="fine">Couldn't reach Pounce. Try again.</p> : null}
          <Button
            wide
            variant="magenta"
            onClick={async () => {
              setFailed(false);
              await turnOffAlerts();
              if (await deleteMyData()) {
                flushNow();
                location.replace("/play/");
              }
              else setFailed(true);
            }}
          >
            <Icon name="icon-trash" size={28} /> Delete
          </Button>
          <Button wide variant="violet" onClick={() => setConfirm(false)}>
            Keep
          </Button>
        </div>
      </Sheet>
    );
  }
  const iphone = /iPhone|iPad/.test(navigator.userAgent);
  return (
    <Sheet title="Settings" onClose={props.onClose}>
      <div class="settings">
        {people.owner ? (
          <button type="button" class="row me-row" onClick={() => setEditing(true)}>
            <Cat cat={people.owner.cat} size={48} />
            <span class="grow">{people.owner.name}</span>
            <span class="edit">Edit</span>
          </button>
        ) : null}
        <Toggle label="Sound" icon={s.sound ? "icon-sound-on" : "icon-sound-off"} on={s.sound} onChange={(v) => setSettings({ sound: v })} />
        {typeof navigator.vibrate === "function" ? (
          <Toggle label="Vibration" icon={s.haptics ? "icon-haptics-on" : "icon-haptics-off"} on={s.haptics} onChange={(v) => setSettings({ haptics: v })} />
        ) : null}
        {people.band !== "kitten" && (alerts === "on" || alerts === "off") ? (
          <Toggle label="Turn alerts" icon={alerts === "on" ? "icon-bell" : "icon-bell-off"} on={alerts === "on"} onChange={(v) => void (v ? turnOnAlerts() : turnOffAlerts())} />
        ) : null}
        {install === "available" ? (
          <button type="button" class="row" onClick={() => void promptInstall()}>
            <Icon name="icon-plus" size={32} />
            <span class="grow">Install Pounce</span>
          </button>
        ) : null}
        {iphone && store ? (
          <a class="row" href={store}>
            <Icon name="icon-phone" size={32} />
            <span class="grow">Get the iPhone app</span>
          </a>
        ) : null}
        <a class="row" href="/support" target="_blank" rel="noopener">
          <Icon name="icon-play" size={32} />
          <span class="grow">How to play</span>
        </a>
        <a class="row" href="/privacy" target="_blank" rel="noopener">
          <Icon name="icon-padlock" size={32} />
          <span class="grow">Privacy</span>
        </a>
        <button type="button" class="row" onClick={() => setConfirm(true)}>
          <Icon name="icon-trash" size={32} />
          <span class="grow">Delete my data</span>
        </button>
        <p class="fine">{installState() === "installed" ? "Installed. " : ""}Family game night, every night.</p>
      </div>
    </Sheet>
  );
}

function Toggle(props: { label: string; icon: string; on: boolean; onChange: (v: boolean) => void }) {
  return (
    <button type="button" class="row" role="switch" aria-checked={props.on} onClick={() => props.onChange(!props.on)}>
      <Icon name={props.icon} size={32} />
      <span class="grow">{props.label}</span>
      <span class={`switch ${props.on ? "on" : ""}`} aria-hidden="true">
        <i />
      </span>
    </button>
  );
}
