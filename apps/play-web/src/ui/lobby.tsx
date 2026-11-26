import { parseRoomName } from "@pounce/play-api/room/names";
import { useState } from "preact/hooks";


import { art, RINGS } from "../lib/art";
import { titleOf } from "../lib/catalog";
import { buzz } from "../lib/haptics";
import { play } from "../lib/sound";
import { reach } from "../store/app";
import { inviteMessages, mySeats, practiceMessages, rulesMessage, seatToAdd, startClosingOpenSeats, startLit, startWords, swapMessage } from "../store/lobby";
import { BwHowTo } from "../table/bw-help";
import { lobbyRibbons, RULE_COPY, RULES_ORDER } from "../table/bw-model";
import { seatCat, seatName, seatPose } from "../table/seat";

import { Button, Cat, Icon, IconButton, Sheet, Tip } from "./common";
import { NameScreen } from "./firstrun";
import { QrCode } from "./qr";
import { TvIcon } from "./show-on-tv";

import type { RoomStore } from "../store/room";
import type { RoomView } from "@pounce/play-api/protocol";

export const inviteLink = (code: string): string => `${location.origin}/j/${code}`;

/** Seats around the rug: where each sits, as a share of the rug's size. */
const SPOTS: Record<number, [number, number][]> = {
  2: [[0.27, 0.38], [0.73, 0.38]],
  3: [[0.5, 0.2], [0.2, 0.62], [0.8, 0.62]],
  4: [[0.27, 0.24], [0.73, 0.24], [0.27, 0.74], [0.73, 0.74]],
  5: [[0.5, 0.14], [0.16, 0.42], [0.84, 0.42], [0.28, 0.82], [0.72, 0.82]],
  6: [[0.27, 0.15], [0.73, 0.15], [0.12, 0.5], [0.88, 0.5], [0.27, 0.85], [0.73, 0.85]],
};

export function Lobby(props: {
  store: RoomStore;
  room: RoomView;
  kitten: boolean;
  onHome: () => void;
  onAddLocal: (name: string, cat: number) => Promise<void>;
  /** Show on TV: the sheet that types a TV's code (table-screen.tsx owns it). */
  onShowOnTv: () => void;
}) {
  const { store, room } = props;
  const [sheet, setSheet] = useState<null | "add" | "qr" | "local" | "rename" | "howto" | { seat: number }>(null);
  /** Swap seats: the first seat picked, waiting for the second. */
  const [swapFrom, setSwapFrom] = useState<number | null>(null);
  const [copied, setCopied] = useState(false);
  const shown = room.seats.map((s, i) => ({ s, i })).filter(({ s }) => s.kind !== "closed");
  const spots = SPOTS[Math.min(Math.max(shown.length, 2), 6)] ?? SPOTS[2];
  const seated = mySeats(room).length > 0;
  const add = seatToAdd(room);
  const lit = startLit(room);
  const words = startWords(room);
  const game = room.gameId ?? "cat-tower";
  const bird = game === "birdwatch";
  const rules = room.options && "rules" in room.options ? room.options.rules : "official";
  const ribbons = bird ? lobbyRibbons(room) : new Map<number, string>();
  const host = room.youAreHost && seated;

  const send = (messages: Parameters<RoomStore["send"]>[0][] | null) => {
    for (const m of messages ?? []) store.send(m);
  };

  const start = () => {
    if (!lit) {
      play("nope");
      buzz("nope");
      return;
    }
    send(startClosingOpenSeats(room) ?? [{ t: "start" }]);
  };

  const share = async () => {
    send(inviteMessages(room));
    reach("invite_sent");
    const url = inviteLink(room.code);
    const text = `Come play ${titleOf(game)} with me on Pounce.`;
    try {
      if (navigator.share) {
        await navigator.share({ title: "Pounce", text, url });
        return;
      }
    } catch {
      return;
    }
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
    } catch {
      setSheet("qr");
    }
  };

  const houseCat = () => {
    if (add === null) return;
    store.send({ t: "configure", seat: add, kind: "bot" });
    setSheet(null);
  };

  return (
    <main class="screen lobby">
      <div class="room-bg" style={{ backgroundImage: `url(${art("room-bg")})` }} />
      <header class="lobby-top">
        <IconButton icon="icon-back" label="Home" onClick={props.onHome} />
        <button type="button" class="chip table-name" onClick={() => !props.kitten && seated && setSheet("rename")} aria-label={`Table: ${room.name}${props.kitten ? "" : ". Rename"}`}>
          <span>{room.name}</span>
        </button>
        <button type="button" class="chip code-chip outlined" onClick={() => setSheet("qr")} aria-label={`${room.code}: table code. Show QR code`}>
          {room.code}
        </button>
      </header>

      <div class="rug-stage">
        <div class="lobby-rug">
          <img class="rug-art" src={art("rug")} alt="" />
          {shown.map(({ s, i }, k) => {
            const [x, y] = spots[k] ?? [0.5, 0.5];
            const ribbon = ribbons.get(i);
            const label =
              swapFrom !== null && s.kind !== "open"
                ? i === swapFrom
                  ? `${seatName(s)}. Cancel swap`
                  : `Swap with ${seatName(s)}`
                : s.kind === "open"
                  ? "Open seat. Add a player"
                  : `${seatName(s)}${s.kind === "bot" ? "" : s.yours ? ", on this device" : ", on another device"}`;
            return (
              <button
                type="button"
                class={`lobby-seat ${s.kind} ${ribbon ? "ribboned" : ""} ${swapFrom === i ? "swapping" : ""} ${swapFrom !== null && s.kind !== "open" && swapFrom !== i ? "swap-target" : ""}`}
                style={{ left: `${x * 100}%`, top: `${y * 100}%`, ["--ring" as string]: RINGS[i % RINGS.length], ["--ribbon" as string]: ribbon ?? "transparent" }}
                aria-label={label}
                id={s.kind === "open" && i === add ? "open-seat" : undefined}
                onClick={() => {
                  play("pop", 0.5);
                  buzz("tap");
                  if (swapFrom !== null && s.kind !== "open") {
                    if (swapFrom !== i) store.send(swapMessage(swapFrom, i));
                    setSwapFrom(null);
                  } else if (s.kind === "open") setSheet("add");
                  else if (seated && (s.kind === "bot" || s.yours || (bird && host))) setSheet({ seat: i });
                }}
              >
                {s.kind === "open" ? (
                  <span class="cushion open">
                    <Icon name="chip-plus" size={44} />
                  </span>
                ) : (
                  <>
                    <span class="cushion" />
                    <Cat cat={seatCat(s)} pose={seatPose(s, false)} />
                    <span class={`seat-badge ${s.kind === "bot" ? "bot" : s.yours ? "phone" : "remote"}`}>
                      <Icon name={s.kind === "bot" ? "badge-bot" : s.yours ? "badge-phone" : "badge-remote"} size={26} />
                    </span>
                    <span class="name-tag">{seatName(s)}</span>
                  </>
                )}
              </button>
            );
          })}
        </div>
      </div>

      {bird ? (
        <section class="bw-rules panel" aria-label="Rules" id="bw-rules">
          <div class="bw-pills" role="radiogroup" aria-label="Rules">
            {RULES_ORDER.map((r) => (
              <button
                type="button"
                role="radio"
                aria-checked={r === rules}
                class={`bw-pill ${r === rules ? "on" : ""}`}
                disabled={!host && r !== rules}
                onClick={() => {
                  if (!host || r === rules) return;
                  play("pop", 0.5);
                  buzz("tap");
                  store.send(rulesMessage(r));
                }}
              >
                {RULE_COPY[r].name}
              </button>
            ))}
          </div>
          <p class="bw-rules-line">
            <span>{RULE_COPY[rules].line}</span>
            <button type="button" class="link" onClick={() => setSheet("howto")}>
              How to play
            </button>
          </p>
        </section>
      ) : null}

      <section class="add-bar panel" aria-label="Add a player" id="add-bar">
        <h2 class="add-title">Add a player</h2>
        <div class="add-choices">
          <button type="button" class="choice" onClick={() => { send(inviteMessages(room)); reach("invite_sent"); setSheet("qr"); }} disabled={!seated}>
            <Icon name="icon-qr" size={40} />
            <span>Same room</span>
          </button>
          <button type="button" class="choice" onClick={() => void share()} disabled={!seated}>
            <Icon name="icon-share" size={40} />
            {copied ? (
              <span class="flash-life" onAnimationEnd={() => setCopied(false)}>
                Link copied
              </span>
            ) : (
              <span>Far away</span>
            )}
          </button>
          <button type="button" class="choice" onClick={() => setSheet("local")} disabled={!seated || room.seats.every((s) => s.kind === "human")}>
            <Icon name="icon-phone" size={40} />
            <span>This device</span>
          </button>
          <button type="button" class="choice" onClick={houseCat} disabled={!seated || add === null}>
            <Icon name="badge-bot" size={40} />
            <span>House Cat</span>
          </button>
          <button type="button" class="choice tv-choice" id="show-on-tv" onClick={props.onShowOnTv} disabled={!seated}>
            <TvIcon size={40} />
            <span>Show on TV</span>
          </button>
        </div>
      </section>

      <div class="start-row">
        {swapFrom !== null ? (
          <p class="start-words" aria-live="polite">
            Tap a seat to swap
          </p>
        ) : words ? (
          <p class="start-words">{words}</p>
        ) : null}
        <Button size="big" wide id="start" disabled={!lit} onClick={start}>
          <Icon name="icon-play" size={34} /> Start
        </Button>
      </div>

      <Tip id="lobby.add" anchor="add-bar" text="Pick how the next player joins." show={seated && !room.seats.some((s) => s.kind === "human" && !s.yours)} />
      <Tip id="lobby.start" anchor="start" text="Everyone's here? Tap Start." show={lit && room.seats.filter((s) => s.kind === "human").length > 1} />

      {sheet === "qr" ? (
        <Sheet title="Scan to join" onClose={() => setSheet(null)}>
          <QrCard code={room.code} />
          <Button wide variant="teal" onClick={() => void share()}>
            <Icon name="icon-share" size={28} />{" "}
            {copied ? (
              <span class="flash-life" onAnimationEnd={() => setCopied(false)}>
                Link copied
              </span>
            ) : (
              "Send link"
            )}
          </Button>
        </Sheet>
      ) : null}
      {sheet === "add" ? (
        <Sheet title="Add a player" onClose={() => setSheet(null)}>
          <div class="add-choices big">
            <button type="button" class="choice" onClick={() => setSheet("qr")}>
              <Icon name="icon-qr" size={48} />
              <span>Same room</span>
            </button>
            <button type="button" class="choice" onClick={() => void share()}>
              <Icon name="icon-share" size={48} />
              <span>Far away</span>
            </button>
            <button type="button" class="choice" onClick={() => setSheet("local")}>
              <Icon name="icon-phone" size={48} />
              <span>This device</span>
            </button>
            <button type="button" class="choice" onClick={houseCat}>
              <Icon name="badge-bot" size={48} />
              <span>House Cat</span>
            </button>
          </div>
        </Sheet>
      ) : null}
      {sheet === "local" ? (
        <div class="overlay-screen">
          <NameScreen
            kitten={props.kitten}
            invite={null}
            title="Who's playing here?"
            onCancel={() => setSheet(null)}
            onDone={async (name, cat) => {
              await props.onAddLocal(name, cat);
              setSheet(null);
            }}
          />
        </div>
      ) : null}
      {sheet === "howto" ? <BwHowTo rules={rules} onClose={() => setSheet(null)} /> : null}
      {sheet === "rename" ? <RenameSheet current={room.name} onClose={() => setSheet(null)} onRename={(name) => store.send({ t: "rename", name })} /> : null}
      {typeof sheet === "object" && sheet !== null ? (
        <Sheet title={seatName(room.seats[sheet.seat])} onClose={() => setSheet(null)}>
          <div class="sheet-actions">
            {bird && host ? (
              <Button
                wide
                variant="teal"
                id="swap-seats"
                onClick={() => {
                  setSwapFrom(sheet.seat);
                  setSheet(null);
                }}
              >
                <Icon name="icon-swap" size={28} /> Swap seats
              </Button>
            ) : null}
            {room.seats[sheet.seat]?.kind === "human" && !room.seats[sheet.seat]?.yours ? null : room.seats[sheet.seat]?.kind === "bot" ? (
              <Button wide variant="magenta" onClick={() => { store.send({ t: "configure", seat: sheet.seat, kind: "open" }); setSheet(null); }}>
                Remove House Cat
              </Button>
            ) : (
              <Button wide variant="magenta" onClick={() => { store.send({ t: "leave", seat: sheet.seat }); setSheet(null); }}>
                Leave this seat
              </Button>
            )}
          </div>
        </Sheet>
      ) : null}
    </main>
  );
}

function QrCard(props: { code: string }) {
  return (
    <div class="qr-card">
      <QrCode url={inviteLink(props.code)} label="QR code for this table" />
      <p class="qr-code outlined" aria-label={`Code ${props.code.split("").join(" ")}`}>
        {props.code}
      </p>
    </div>
  );
}

function RenameSheet(props: { current: string; onClose: () => void; onRename: (name: string) => void }) {
  const [name, setName] = useState(props.current);
  const clean = parseRoomName(name);
  return (
    <Sheet title="Name this table" onClose={props.onClose}>
      <form
        class="sheet-actions"
        onSubmit={(e) => {
          e.preventDefault();
          if (clean) {
            props.onRename(clean);
            props.onClose();
          }
        }}
      >
        <label class="sr-only" for="table-name">
          Table name
        </label>
        <input id="table-name" class="field" value={name} maxLength={30} onInput={(e) => setName((e.target as HTMLInputElement).value)} />
        <Button type="submit" wide variant="ok" disabled={!clean}>
          Save
        </Button>
      </form>
    </Sheet>
  );
}

/** Starts a practice game once seated: a House Cat, the other seats closed, dealt. */
export function startPractice(store: RoomStore, room: RoomView): boolean {
  const messages = practiceMessages(room);
  if (!messages) return false;
  for (const m of messages) store.send(m);
  return true;
}
