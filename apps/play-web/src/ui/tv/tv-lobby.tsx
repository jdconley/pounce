/**
 * The table's lobby on the TV: the invite QR big on the left, and on the right the game's rug with
 * a cushion for every seat. Each player's cat walks onto their cushion as their phone sits. Start
 * is a phone's; until anyone sits, the TV may swap the game.
 */
import { useEffect, useRef } from "preact/hooks";

import { art, RINGS } from "../../lib/art";
import { CATALOG } from "../../lib/catalog";
import { play } from "../../lib/sound";
import { lobbyRibbons, RULE_COPY } from "../../table/bw-model";
import { clock, easelLink, isPurr, nearOf, spacedCode, timerOf } from "../../table/purr-model";
import { seatCat, seatName } from "../../table/seat";
import { catsOf, CATS_WORDS } from "../../tumble/store";
import { Cat, Icon } from "../common";
import { inviteLink } from "../lobby";
import { QrCode } from "../qr";

import { anyoneSeated, gameOf, lobbySeats } from "./tv-model";

import type { RoomView } from "@pounce/play-api/protocol";

/** Where each seat sits on the TV's rug stage (wider than tall), as shares of it, by seats shown. */
const SPOTS: Record<number, [number, number][]> = {
  2: [[0.27, 0.5], [0.73, 0.5]],
  3: [[0.2, 0.58], [0.5, 0.36], [0.8, 0.58]],
  4: [[0.27, 0.28], [0.73, 0.28], [0.27, 0.74], [0.73, 0.74]],
  5: [[0.5, 0.22], [0.15, 0.46], [0.85, 0.46], [0.3, 0.8], [0.7, 0.8]],
  6: [[0.17, 0.27], [0.5, 0.22], [0.83, 0.27], [0.17, 0.77], [0.5, 0.8], [0.83, 0.77]],
};

/** Seven to ten seats (Purrtrait): two rows, the bottom one offset. */
export function spotsFor(n: number): [number, number][] {
  if (n <= 6) return SPOTS[Math.max(n, 2)] ?? SPOTS[2]!;
  const top = Math.ceil(n / 2);
  const bottom = n - top;
  const row = (count: number, y: number, inset: number): [number, number][] =>
    Array.from({ length: count }, (_, i) => [inset + ((1 - 2 * inset) * (i + 0.5)) / count, y]);
  return [...row(top, 0.26, 0.02), ...row(bottom, 0.76, bottom < top ? 0.1 : 0.02)];
}

/** A refused press (Juice.swift's nope), as a shake that leaves the focus ring's scale alone. */
export const NOPE: Keyframe[] = [
  { translate: "0" },
  { translate: "-14px 0" },
  { translate: "12px 0" },
  { translate: "-8px 0" },
  { translate: "4px 0" },
  { translate: "0" },
];

export function TvLobby(props: { room: RoomView; live: boolean; onChangeGame: (button: HTMLElement) => void }) {
  const { room } = props;
  const game = gameOf(room);
  const seats = lobbySeats(room);
  const spots = spotsFor(seats.length);
  const filled = seats.filter((s) => s.filled).length;
  const code = room.code;
  // Purrtrait joins only from the TV's own code, which changes every 30 seconds (design §5.2).
  const purr = isPurr(room);
  const near = nearOf(room);
  const url = purr ? (near ? easelLink(location.origin, code, near.key) : null) : inviteLink(code);
  const shown = purr ? (near ? spacedCode(near.code, code) : "") : code;
  const ribbons = game === "birdwatch" ? lobbyRibbons(room) : new Map<number, string>();

  // A pop as each cat arrives.
  const was = useRef(filled);
  useEffect(() => {
    if (filled > was.current) play("pop", 0.6);
    was.current = filled;
  }, [filled]);

  return (
    <section class="tv-lobby">
      <div class="tv-lobby-join">
        <p class="tv-scan outlined">Scan to join</p>
        <div class="tv-qr-frame">
          <i class="tv-ear left" aria-hidden="true" />
          <i class="tv-ear right" aria-hidden="true" />
          <div class="tv-qr-window">
            {url ? <QrCode url={url} label={`QR code to join table ${code}`} class="tv-qr" /> : <div class="qr tv-qr" aria-hidden="true" />}
          </div>
        </div>
        <p class={`tv-code ${purr ? "purr-code" : ""}`} aria-label={shown ? `Table code ${shown.replace(" ", "").split("").join(" ")}` : undefined} id="tv-join-code">
          {shown || " "}
        </p>
      </div>

      <div class={`tv-lobby-table ${seats.length > 6 ? "crowded packed" : seats.length > 4 ? "crowded" : ""}`}>
        <header class={`tv-lobby-head ${game}`}>
          <img class="tv-lobby-art" src={art(CATALOG[game].art)} alt="" width={768} height={512} decoding="async" />
          <h1 class="tv-lobby-title outlined">{CATALOG[game].title}</h1>
          {game === "birdwatch" && room.options && "rules" in room.options ? <p class="tv-lobby-rules outlined">{RULE_COPY[room.options.rules].name}</p> : null}
          {purr ? (
            <p class="tv-lobby-rules outlined" id="tv-purr-timer">
              {clock(timerOf(room) * 1000)} a turn
            </p>
          ) : null}
          {game === "tumble" && room.seats.some((s) => s.kind === "bot") ? <p class="tv-lobby-rules outlined">{CATS_WORDS[catsOf(room)]}</p> : null}
        </header>
        <div class="tv-lobby-rug">
          <img class="tv-lobby-rug-art" src={art("rug")} alt="" />
          {seats.map(({ seat, filled: sat, key }, k) => {
            const [x, y] = spots[k] ?? [0.5, 0.5];
            const info = room.seats[seat];
            const style = { ["--x" as string]: x, ["--y" as string]: y, ["--ring" as string]: RINGS[seat % RINGS.length], ["--from" as string]: x < 0.5 ? -1 : 1 };
            if (!sat) {
              return (
                <div key={key} class="tv-seat open" style={style} role="img" aria-label="Open seat">
                  <span class="tv-open-spot">
                    <img src={art("icon-paw-menu")} alt="" />
                  </span>
                </div>
              );
            }
            return (
              <div key={key} class="tv-seat" style={style} role="img" aria-label={seatName(info)}>
                <span class="tv-cushion" />
                <span class="tv-seat-cat">
                  <Cat cat={seatCat(info)} pose="awake" />
                </span>
                {info?.kind === "bot" ? <img class="tv-seat-badge" src={art("badge-bot")} alt="" /> : null}
                <span class="name-tag" style={ribbons.has(seat) ? { boxShadow: `0 0 0 5px ${ribbons.get(seat)}` } : undefined}>
                  {seatName(info)}
                </span>
              </div>
            );
          })}
        </div>
        <p class="tv-lobby-start tv-label outlined">
          <img src={art("icon-phone")} alt="" />
          Press Start on any phone
        </p>
        {!anyoneSeated(room) ? (
          <button
            type="button"
            class="btn violet tv-change"
            data-tv={props.live ? true : undefined}
            tabIndex={props.live ? 0 : -1}
            onClick={(e) => {
              play("pop", 0.5);
              props.onChangeGame(e.currentTarget);
            }}
          >
            <Icon name="icon-swap" size={64} /> Change game
          </button>
        ) : null}
      </div>

    </section>
  );
}
