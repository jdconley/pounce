/**
 * Everyone else's phone (design §11.3): "Look at the TV", whose turn it is, this player's score,
 * and "You draw next" on the turn before theirs. No drawing, no word, nothing to type. After a
 * turn, the word and who got it.
 */
import { useEffect, useRef, useState } from "preact/hooks";

import { RINGS } from "../lib/art";
import { buzz } from "../lib/haptics";
import { play } from "../lib/sound";
import { Cat, Tip } from "../ui/common";

import { PurrDraw } from "./purr-draw";
import { mineIn, nextDrawer, purrOf, revealLine, roleOf, turnLine, type PurrEvent, type PurrView } from "./purr-model";
import { seatCat, seatName } from "./seat";

import type { RoomState, RoomStore } from "../store/room";
import type { RoomView } from "@pounce/play-api/protocol";
import "./purrtrait.css";

/** A Purrtrait table on a phone: the drawer's screen on the drawer's device, this one on every other. */
export function PurrPhone(props: { store: RoomStore; state: RoomState; kitten: boolean }) {
  const room = props.state.room!;
  const v = purrOf(room);
  if (!v) return null;
  if (roleOf(room, v) === "drawer" && v.phase !== "reveal" && v.phase !== "over") return <PurrDraw store={props.store} state={props.state} v={v} kitten={props.kitten} />;
  return <PurrWatch store={props.store} room={room} v={v} />;
}

function PurrWatch(props: { store: RoomStore; room: RoomView; v: PurrView }) {
  const { room, v } = props;
  const mine = mineIn(room, v);
  const next = nextDrawer(v);
  const drawsNext = next !== null && mine.includes(next) && v.drawer !== next;
  const [reason, setReason] = useState<"time" | "gaveUp" | "left" | null>(null);
  useEffect(
    () =>
      props.store.subscribe({
        event: ({ event }) => {
          if ((event.kind as string) !== "purrtrait") return;
          const e = (event as unknown as { event: PurrEvent }).event;
          if (e.type === "missed") setReason(e.reason);
          if (e.type === "turn") setReason(null);
          if (e.type === "guessed" && mine.includes(e.guesser)) {
            play("sparkle");
            buzz("win");
          }
        },
      }),
    [props.store, mine.join()],
  );
  // A buzz when this phone's turn to draw is next.
  const told = useRef("");
  useEffect(() => {
    if (drawsNext && told.current !== v.turn) {
      told.current = v.turn;
      buzz("tap");
    }
  }, [drawsNext, v.turn]);

  const drawer = v.drawer;
  const reveal = v.phase === "reveal" && v.last;
  return (
    <main class="screen purr-screen purr-watch">
      <div class="purr-watch-card panel">
        {drawer !== null && v.phase !== "over" ? (
          <div class="purr-watch-drawer" style={{ ["--ring" as string]: RINGS[drawer % RINGS.length] }}>
            <Cat cat={seatCat(room.seats[drawer])} pose={reveal ? (v.last?.guesser !== null ? "celebrate" : "terrified") : "awake"} size={96} />
            <span class="purr-watch-line">{reveal ? revealLine(room, v, reason) : turnLine(room, v)}</span>
          </div>
        ) : null}
        {reveal ? (
          <p class="purr-watch-word outlined" id="purr-watch-word">
            {v.last!.word}
          </p>
        ) : (
          <h1 class="purr-look outlined" id="purr-look">
            {v.paused ? "Waiting for the TV" : "Look at the TV"}
          </h1>
        )}
        {drawsNext ? (
          <p class="purr-next" id="purr-next">
            You draw next
          </p>
        ) : null}
      </div>
      <ul class="purr-mine" aria-label="Your score">
        {mine.map((s) => (
          <li style={{ ["--ring" as string]: RINGS[s % RINGS.length] }}>
            <Cat cat={seatCat(room.seats[s])} size={48} />
            <span class="who">{seatName(room.seats[s])}</span>
            <span class="pts">{v.scores[s] ?? 0}</span>
          </li>
        ))}
      </ul>
      <Tip id="purr.guess" anchor="purr-look" text="Guess out loud" show={!reveal && v.phase === "drawing" && mine.length > 0} place="below" />
    </main>
  );
}
