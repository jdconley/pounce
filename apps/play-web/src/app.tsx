import { useEffect, useState } from "preact/hooks";


import { turnOffAlerts, turnOnAlerts, useAlerts } from "./alerts";
import { art } from "./lib/art";
import { currentRoute, navigate, onRoute, type Route } from "./lib/router";
import { onSettings, setSettings, settings } from "./lib/settings";
import { api, ApiError } from "./net/api";
import { RoomSocket } from "./net/socket";
import { installState, promptInstall, useInstall } from "./pwa";
import { app, deleteMyData, finishAge, noteSource, reach, setOwner, syncProfile, useApp } from "./store/app";
import { inviteHost } from "./store/lobby";
import { Button, Cat, Icon, Sheet } from "./ui/common";
import { AgeScreen, NameScreen, type InviteBanner } from "./ui/firstrun";
import { Home, JoinScreen } from "./ui/home";

import type { GameId } from "./lib/catalog";
import type { TableIntent } from "./ui/table-screen";

/** The lobby and the tables load when a table opens, not with the first screen. */
type TableModule = typeof import("./ui/table-screen");
let tableModule: Promise<TableModule> | null = null;
export const loadTables = (): Promise<TableModule> => (tableModule ??= import("./ui/table-screen"));

function LazyTable(props: { code: string; intent: TableIntent }) {
  const [mod, setMod] = useState<TableModule | null>(null);
  useEffect(() => {
    let live = true;
    void loadTables().then((m) => live && setMod(m));
    return () => {
      live = false;
    };
  }, []);
  if (!mod) return <main class="screen violet-bg" aria-busy="true" />;
  return <mod.TableScreen code={props.code} intent={props.intent} />;
}

/** How the next table screen was asked for (a new table, practice, an invite). */
const intents = new Map<string, TableIntent>();

export function openTable(code: string, intent: TableIntent, replace = false): void {
  intents.set(code, intent);
  navigate({ kind: "table", code }, replace);
}

/** A seatless look at an invite's table: who saved a seat (InviteHost.swift). Null after 6 s or on any trouble. */
function peek(code: string): Promise<InviteBanner | null> {
  return new Promise((resolve) => {
    const socket = new RoomSocket({ code, token: async () => (await api.credential()).token, backoff: [] });
    const done = (value: InviteBanner | null) => {
      clearTimeout(timer);
      socket.stop();
      resolve(value);
    };
    const timer = setTimeout(() => done(null), 6000);
    socket.on((e) => {
      if (e.kind === "message" && e.message.t === "snapshot") done(inviteHost(e.message.room));
      else if (e.kind === "notFound" || e.kind === "locked" || e.kind === "closed" || e.kind === "refused" || e.kind === "disconnected") done(null);
    });
    socket.start();
  });
}

function useRoute(): Route {
  const [route, setRoute] = useState(currentRoute);
  useEffect(() => onRoute(setRoute), []);
  return route;
}

export function App() {
  const route = useRoute();
  const { people } = useApp();
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [invite, setInvite] = useState<InviteBanner | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // Once the first screen is up, fetch the tables' code in the background.
  useEffect(() => {
    const t = setTimeout(() => void loadTables(), 1500);
    return () => clearTimeout(t);
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
  }, [route, people.owner]);

  const say = (words: string) => {
    setToast(words);
    setTimeout(() => setToast(null), 2600);
  };

  const newTable = async (game: GameId, practice: boolean) => {
    if (busy) return;
    setBusy(true);
    try {
      const code = await api.createRoom(game);
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
        screen = <LazyTable key={route.code} code={route.code} intent={intents.get(route.code) ?? "open"} />;
        break;
      case "keypad":
        screen = <JoinScreen onJoin={(code) => openTable(code, "guest")} />;
        break;
      case "pounce":
        screen = <PounceScreen token={route.token} />;
        break;
      case "join":
        screen = <main class="screen violet-bg" />;
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
        <div class="banner toast" role="alert">
          {toast}
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
              if (await deleteMyData()) location.replace("/play/");
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
