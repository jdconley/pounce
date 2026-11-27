/**
 * Purrtrait on the TV (design §11.1): the easel in the middle at full height, showing the drawer's
 * lines as they come; everyone's cat, name and score on the left; who is drawing, the clock and
 * the word's group on the right. When the turn ends the word shows big across the easel.
 */
import { useEffect, useRef, useState } from "preact/hooks";

import { art, RINGS } from "../../lib/art";
import { play } from "../../lib/sound";
import { EaselCanvas } from "../../table/purr-easel-view";
import { clock, GROUP_WORDS, purrOf, revealLine, type PurrEvent, type PurrView } from "../../table/purr-model";
import { useInkPicture, useLeft } from "../../table/purr-parts";
import { seatCat, seatName } from "../../table/seat";
import { Cat } from "../common";

import type { RoomState, RoomStore } from "../../store/room";
import type { RoomView } from "@pounce/play-api/protocol";
import "../../table/purrtrait.css";

type Props = { store: RoomStore; state: RoomState; offline: boolean };

export function PurrTvTable(props: Props) {
  const { store, state } = props;
  const room = state.room!;
  const v = purrOf(room)!;
  const ink = useInkPicture(store, v.turn);
  const left = useLeft(v);
  const [reason, setReason] = useState<"time" | "gaveUp" | "left" | null>(null);
  const [cheer, setCheer] = useState<{ seat: number; n: number } | null>(null);

  // Sounds and the guesser's leap, as the events play.
  useEffect(
    () =>
      store.subscribe({
        event: ({ event }) => {
          if ((event.kind as string) !== "purrtrait") return;
          const e = (event as unknown as { event: PurrEvent }).event;
          if (e.type === "turn") {
            setReason(null);
            play("whoosh", 0.6);
          } else if (e.type === "chosen") play("pop", 0.6);
          else if (e.type === "guessed") {
            setReason(null);
            setCheer((c) => ({ seat: e.guesser, n: (c?.n ?? 0) + 1 }));
            play("fanfare");
          } else if (e.type === "missed") {
            setReason(e.reason);
            play("thud");
          }
        },
      }),
    [store],
  );

  // The last five seconds tick.
  const second = left === null ? null : Math.ceil(left / 1000);
  const ticked = useRef<number | null>(null);
  useEffect(() => {
    if (v.phase !== "drawing" || second === null || second > 5 || second < 1 || ticked.current === second) return;
    ticked.current = second;
    play("tick", 0.5);
  }, [second, v.phase]);

  // The easel reads the phase each frame: while drawing the newest stroke is live, after it every stroke is done.
  const phase = useRef(v.phase);
  phase.current = v.phase;
  useEffect(() => ink.easel?.invalidate(), [v.phase]);

  const showing = v.phase === "drawing" || v.phase === "reveal";
  return (
    <section class={`purr-tv phase-${v.phase}`} aria-label="Purrtrait">
      <PlayerList room={room} v={v} cheer={cheer} />
      <div class="purr-tv-stand">
        <div class="purr-frame">
          <i class="purr-clip" aria-hidden="true" />
          <EaselCanvas
            class="purr-tv-easel"
            id="tv-easel"
            label={v.drawer !== null ? `${seatName(room.seats[v.drawer])}'s drawing` : "Easel"}
            onEasel={(e) => {
              ink.easel = e;
              if (e) e.source = () => (phase.current === "drawing" ? ink.source() : ink.done());
            }}
          >
            {!showing ? <div class="purr-blank" aria-hidden="true" /> : null}
            {v.phase === "reveal" && v.last ? (
              <div class="purr-reveal" role="status" key={v.turn}>
                <p class="purr-reveal-word outlined" style={{ ["--len" as string]: longestWord(v.last.word) }}>
                  {v.last.word}
                </p>
                <p class="purr-reveal-line outlined">
                  {revealLine(room, v, reason)}
                  {v.last.points > 0 ? <span class="purr-points">+{v.last.points}</span> : null}
                </p>
              </div>
            ) : null}
          </EaselCanvas>
        </div>
      </div>
      <TurnPanel room={room} v={v} left={left} />
      {props.offline ? (
        <div class="tv-note" role="status">
          <span class="dot" /> Reconnecting
        </div>
      ) : null}
    </section>
  );
}

/** Everyone's cat, name and score, the drawer's lit. */
function PlayerList(props: { room: RoomView; v: PurrView; cheer: { seat: number; n: number } | null }) {
  const { room, v } = props;
  const seats = room.seats.flatMap((s, i) => (i < v.seats && (s.kind === "human" || s.kind === "bot") ? [i] : []));
  return (
    <ol class={`purr-tv-players ${seats.length > 7 ? "many" : ""}`} aria-label="Scores">
      {seats.map((seat) => {
        const drawing = v.drawer === seat && v.phase !== "over";
        const guessed = v.phase === "reveal" && v.last !== null && v.last.guesser !== null;
        const got = guessed && (v.last?.guesser === seat || v.drawer === seat);
        return (
          <li class={`${drawing ? "drawing" : ""} ${v.out[seat] ? "out" : ""} ${got ? "scored" : ""}`} style={{ ["--ring" as string]: RINGS[seat % RINGS.length] }}>
            <span class="purr-tv-cat" key={props.cheer?.seat === seat ? `c${props.cheer.n}` : "c"}>
              <Cat cat={seatCat(room.seats[seat])} pose={got ? "leap" : drawing ? "awake" : "idle"} />
            </span>
            <span class={`purr-tv-name ${seatName(room.seats[seat]).length > 9 ? "long" : ""}`}>{seatName(room.seats[seat])}</span>
            {drawing ? <Brush /> : null}
            <span class="purr-tv-score" key={`${seat}:${v.scores[seat] ?? 0}`}>
              {v.scores[seat] ?? 0}
            </span>
          </li>
        );
      })}
    </ol>
  );
}

/** Who is drawing, the clock and the group. */
function TurnPanel(props: { room: RoomView; v: PurrView; left: number | null }) {
  const { room, v, left } = props;
  if (v.drawer === null || v.phase === "over") return <aside class="purr-tv-turn" />;
  const who = seatName(room.seats[v.drawer]);
  const low = left !== null && left <= 10_000 && v.phase === "drawing";
  return (
    <aside class="purr-tv-turn" aria-live="polite">
      <div class="purr-tv-drawer" style={{ ["--ring" as string]: RINGS[v.drawer % RINGS.length] }}>
        <span class="purr-tv-drawer-cat">
          <Cat cat={seatCat(room.seats[v.drawer])} pose={v.phase === "reveal" && v.last?.guesser === null ? "terrified" : "celebrate"} />
        </span>
        <span class="name-tag">{who}</span>
        <span class="purr-tv-doing outlined">{v.phase === "choosing" ? "is picking" : v.phase === "drawing" ? "is drawing" : ""}</span>
      </div>
      {v.phase === "drawing" && left !== null ? (
        <p class={`purr-tv-clock outlined ${low ? "low" : ""} ${v.paused ? "paused" : ""}`} id="tv-clock" aria-label={`${Math.ceil(left / 1000)} seconds left`}>
          <img src={art("icon-hourglass")} alt="" />
          {clock(left)}
        </p>
      ) : null}
      {v.group && v.phase !== "choosing" ? (
        <p class="purr-tv-group" id="tv-group">
          {GROUP_WORDS[v.group]}
        </p>
      ) : null}
      <p class="purr-tv-round outlined">
        Round {v.round} of {v.rounds}
      </p>
    </aside>
  );
}

/** The longest word of a phrase, in letters: the reveal is sized so it never breaks inside one. */
const longestWord = (phrase: string): number => Math.max(4, ...phrase.split(" ").map((w) => w.length));

/** The drawer's mark: a brush. */
export function Brush(props: { size?: string }) {
  return (
    <svg class="purr-brush" viewBox="0 0 48 48" aria-hidden="true" style={props.size ? { width: props.size, height: props.size } : undefined}>
      <g transform="rotate(40 24 24)" stroke="#1b0b3a" stroke-width="3.5" stroke-linejoin="round">
        <rect x="20" y="20" width="8" height="26" rx="4" fill="#ffd21f" />
        <rect x="18.5" y="13" width="11" height="9" rx="2" fill="#c9d2e8" />
        <path d="M18.5 13 Q17 4 24 1 Q31 4 29.5 13 Z" fill="#ff3b4a" />
      </g>
    </svg>
  );
}
