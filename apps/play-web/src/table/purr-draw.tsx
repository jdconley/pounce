/**
 * The drawer's phone (design §11.2): first two word cards, Easy and Tricky; then the word and the
 * clock on top, the easel, the palette, the widths, Undo and Clear, and Got it (a sheet of who
 * guessed) and Give up. The drawer's own lines draw on the frame the finger moves, never waiting
 * for the server; ink goes out in batches beside them (purr-ink.ts). On a shared phone the curtain
 * comes down before the words show.
 */
import { useEffect, useMemo, useRef, useState } from "preact/hooks";

import { buzz } from "../lib/haptics";
import { play } from "../lib/sound";
import { mySeats } from "../store/lobby";
import { Button, Cat, Icon, learnTip, Sheet, Tip, tipLearned, useSize, useTipsVersion } from "../ui/common";
import { replayInk } from "../workers/purr-ink";

import { EaselCanvas } from "./purr-easel-view";
import { COLOURS, EASEL_H, EASEL_W, ERASER, InkWriter, WIDTHS, type Stroke } from "./purr-ink";
import { drawLayout } from "./purr-layout";
import { clock, POINTS, type PurrView } from "./purr-model";
import { useLeft } from "./purr-parts";
import { seatCat, seatName } from "./seat";
import { Curtain, useTextScale } from "./shared";

import type { Easel, EaselSource } from "./purr-easel";
import type { RoomState, RoomStore } from "../store/room";

type Props = { store: RoomStore; state: RoomState; v: PurrView; kitten: boolean };

export function PurrDraw(props: Props) {
  const { state, v } = props;
  const room = state.room!;
  const seat = v.drawer!;
  // A phone more than one person plays on: the drawer takes it before the words show.
  const shared = mySeats(room).length > 1;
  const [revealed, setRevealed] = useState<string | null>(null);
  if (shared && revealed !== v.turn) {
    return <Curtain name={seatName(room.seats[seat])} cat={seatCat(room.seats[seat])} label="Hold to see your word" onReveal={() => setRevealed(v.turn)} />;
  }
  if (v.phase === "choosing" && v.choices) return <WordCards {...props} />;
  return <DrawScreen key={v.turn} {...props} />;
}

/** Two big cards: Easy and Tricky, with their points. With no pick in 10 seconds the Easy word is used. */
function WordCards(props: Props) {
  const { store, state, v } = props;
  const seat = v.drawer!;
  const left = useLeft(v);
  const busy = state.pending !== null;
  const choices = v.choices!;
  const pick = (level: "easy" | "tricky") => {
    if (busy) return;
    play("pop");
    buzz("pick");
    learnTip("purr.pick");
    store.act(seat, { type: "choose", level });
  };
  return (
    <main class="screen purr-screen purr-pick">
      <header class="purr-pick-head">
        <h1 class="outlined">Your turn</h1>
        {left !== null ? <span class="purr-clock-chip">{clock(left)}</span> : null}
      </header>
      <div class="purr-cards" id="purr-cards">
        {(["easy", "tricky"] as const).map((level) => (
          <button type="button" class={`purr-card ${level}`} disabled={busy} onClick={() => pick(level)} id={`pick-${level}`}>
            <span class="purr-card-level">{level === "easy" ? "Easy" : "Tricky"}</span>
            <span class="purr-card-word">{choices[level]}</span>
            <span class="purr-card-points">{props.kitten || level === "easy" ? "1 point" : `${POINTS.tricky} points`}</span>
          </button>
        ))}
      </div>
      <Tip id="purr.pick" anchor="purr-cards" text="Pick one to draw" show place="below" />
    </main>
  );
}

const SWATCHES = [0, 1, 2, 3, 4, 5, 6, 7, ERASER];

function DrawScreen(props: Props) {
  const { store, state, v } = props;
  const room = state.room!;
  const seat = v.drawer!;
  const turn = v.turn;
  const left = useLeft(v);
  const text = useTextScale();
  const [screenRef, screen] = useSize<HTMLElement>();
  const [slotRef, slot] = useSize<HTMLDivElement>();
  const L = drawLayout(screen.width || window.innerWidth, screen.height || window.innerHeight, text);
  // The easel as big as its slot allows, at 3:4.
  const fit = slot.width > 0 ? fitIn(slot.width, slot.height) : L.easel;
  useTipsVersion();

  const writer = useMemo(() => new InkWriter(), [turn]);
  const easel = useRef<Easel | null>(null);
  const [colour, setColour] = useState(0);
  const [width, setWidth] = useState(1);
  const tool = useRef({ colour, width });
  tool.current = { colour, width };
  const [canUndo, setCanUndo] = useState(false);
  const [full, setFull] = useState(false);
  const fullRef = useRef(false);
  fullRef.current = full;
  const [sheet, setSheet] = useState<null | "got" | "giveUp">(null);
  const busy = state.pending !== null;

  // Ink out: a frame loop that runs only while something waits to go.
  const frame = useRef(0);
  const send = (messages: unknown[][]) => {
    for (const ops of messages) store.sendInk(seat, turn, ops);
  };
  const pump = () => {
    frame.current = 0;
    send(writer.flush(performance.now()));
    if (writer.pending) frame.current = requestAnimationFrame(pump);
  };
  const kick = () => {
    if (!frame.current) frame.current = requestAnimationFrame(pump);
  };
  useEffect(() => () => cancelAnimationFrame(frame.current), []);

  const source = (): EaselSource => {
    const live = writer.live;
    const strokes = writer.picture.strokes;
    const finished: Stroke[] = live && strokes.at(-1)?.id === live.id ? strokes.slice(0, -1) : strokes;
    return { finished, live };
  };

  // The finger, on the easel's top layer: every coalesced point, drawn on the next frame.
  const [input, setInput] = useState<HTMLCanvasElement | null>(null);
  useEffect(() => {
    const el = input;
    if (!el) return;
    let active: number | null = null;
    let rect = { left: 0, top: 0, width: 1, height: 1 };
    const at = (e: PointerEvent): [number, number] => [((e.clientX - rect.left) / rect.width) * EASEL_W, ((e.clientY - rect.top) / rect.height) * EASEL_H];
    const down = (e: PointerEvent) => {
      if (active !== null || !e.isPrimary || fullRef.current) return;
      if (e.pointerType === "mouse" && e.button !== 0) return;
      e.preventDefault();
      active = e.pointerId;
      el.setPointerCapture?.(e.pointerId);
      // One layout read, at the start of the stroke.
      const r = el.getBoundingClientRect();
      rect = { left: r.left, top: r.top, width: r.width || 1, height: r.height || 1 };
      const [x, y] = at(e);
      writer.begin(tool.current.colour, tool.current.width, x, y);
      learnTip("purr.easel");
      easel.current?.invalidate();
      kick();
    };
    const move = (e: PointerEvent) => {
      if (e.pointerId !== active) return;
      const events = typeof e.getCoalescedEvents === "function" ? e.getCoalescedEvents() : [];
      let grew = false;
      for (const c of events.length > 0 ? events : [e]) {
        const [x, y] = at(c);
        grew = writer.move(x, y) || grew;
      }
      if (grew) {
        easel.current?.invalidate();
        kick();
      }
    };
    const up = (e: PointerEvent) => {
      if (e.pointerId !== active) return;
      active = null;
      writer.end();
      setCanUndo(writer.canUndo);
      easel.current?.invalidate();
      kick();
    };
    el.addEventListener("pointerdown", down);
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerup", up);
    el.addEventListener("pointercancel", up);
    el.addEventListener("lostpointercapture", up);
    // The phone locked or the tab hidden mid-stroke: the stroke ends cleanly and goes now.
    const hidden = () => {
      if (document.visibilityState !== "hidden") return;
      active = null;
      writer.end();
      send(writer.flush(performance.now(), true));
      setCanUndo(writer.canUndo);
    };
    document.addEventListener("visibilitychange", hidden);
    return () => {
      el.removeEventListener("pointerdown", down);
      el.removeEventListener("pointermove", move);
      el.removeEventListener("pointerup", up);
      el.removeEventListener("pointercancel", up);
      el.removeEventListener("lostpointercapture", up);
      document.removeEventListener("visibilitychange", hidden);
    };
  }, [input, writer]);

  // The room asks for the drawing again (it lost it), or tells this device what it has (a reconnect).
  useEffect(
    () =>
      store.subscribe({
        ink: (m) => {
          if (m.turn !== turn) return;
          if (m.t === "inkResend") {
            send(writer.resend());
            return;
          }
          if (m.t !== "inkSync") return;
          void replayInk(m.ops).then(({ strokes, lastId }) => {
            if (writer.fresh) {
              // A reload mid-turn: the server's drawing is this device's again.
              writer.adoptStrokes(strokes, lastId);
              setCanUndo(writer.canUndo);
              easel.current?.invalidate();
            } else if (!samePicture(strokes, writer.picture.strokes)) {
              // Something this device drew didn't get there: the whole easel again.
              send(writer.resend());
            }
          });
        },
      }),
    [store, writer],
  );

  // The server's easel is full: no more lines until a clear.
  useEffect(() => {
    if (state.error?.code === "easel_full") {
      writer.end();
      setFull(true);
      play("nope");
    }
  }, [state.error?.n]);

  const undo = () => {
    if (!writer.undo()) return;
    play("pop", 0.4);
    buzz("tap");
    setCanUndo(writer.canUndo);
    easel.current?.invalidate();
    kick();
  };
  const clear = () => {
    writer.clear();
    play("whoosh", 0.5);
    buzz("tap");
    setCanUndo(false);
    setFull(false);
    easel.current?.invalidate();
    kick();
  };

  const guessers = v.order.filter((s) => s !== seat && !v.out[s]);
  const low = left !== null && left <= 10_000;
  const easelTipDone = tipLearned("purr.easel");

  return (
    <main
      class={`screen purr-screen purr-draw ${L.side ? "side" : ""}`}
      ref={screenRef}
      style={{ ["--swatch" as string]: `${L.swatch}px`, ["--bar" as string]: `${L.bar}px` }}
    >
      <header class="purr-bar">
        <span class="purr-word outlined" id="purr-word">
          {v.word}
        </span>
        {left !== null ? <span class={`purr-clock-chip ${low ? "low" : ""}`} id="purr-clock">{clock(left)}</span> : null}
      </header>
      <div class="purr-body">
        <div class="purr-slot" ref={slotRef}>
          <div class="purr-frame purr-phone-frame" style={{ width: `${fit.width}px`, height: `${fit.height}px` }}>
            <EaselCanvas
              class="drawable"
              id="purr-easel"
              label="Your easel"
              onEasel={(e, layer) => {
                easel.current = e;
                if (e) e.source = source;
                setInput(layer);
              }}
            >
              {full ? (
                <div class="purr-full" role="alert">
                  <p class="outlined">Easel full</p>
                  <Button variant="ok" onClick={clear} id="purr-full-clear">
                    Clear
                  </Button>
                </div>
              ) : null}
            </EaselCanvas>
          </div>
        </div>
        <div class="purr-tools">
          <div class="purr-palette" role="radiogroup" aria-label="Colour">
            {SWATCHES.map((c) => (
              <button
                type="button"
                role="radio"
                aria-checked={c === colour}
                aria-label={c === ERASER ? "Eraser" : COLOUR_NAMES[c]}
                class={`purr-swatch ${c === colour ? "on" : ""} ${c === ERASER ? "eraser" : ""}`}
                style={{ ["--c" as string]: COLOURS[c] }}
                onClick={() => {
                  buzz("tap");
                  setColour(c);
                }}
              />
            ))}
          </div>
          <div class="purr-row">
            <div class="purr-widths" role="radiogroup" aria-label="Line">
              {WIDTHS.map((w, i) => (
                <button type="button" role="radio" aria-checked={i === width} aria-label={["Thin", "Medium", "Thick"][i]} class={`purr-width ${i === width ? "on" : ""}`} onClick={() => setWidth(i)}>
                  <i style={{ width: `${Math.max(4, w * 0.7)}px`, height: `${Math.max(4, w * 0.7)}px`, background: colour === ERASER ? "#fff" : COLOURS[colour] }} />
                </button>
              ))}
            </div>
            <Button size="small" variant="violet" onClick={undo} disabled={!canUndo} id="purr-undo">
              <Icon name="icon-replay" size={22} /> Undo
            </Button>
            <Button size="small" variant="violet" onClick={clear} id="purr-clear">
              <Icon name="icon-trash" size={22} /> Clear
            </Button>
          </div>
          <div class="purr-actions">
            <Button
              variant="ok"
              id="purr-got-it"
              disabled={busy}
              onClick={() => {
                learnTip("purr.got");
                play("pop", 0.5);
                setSheet("got");
              }}
            >
              <Icon name="icon-check" size={28} /> Got it
            </Button>
            <Button variant="magenta" id="purr-give-up" disabled={busy} onClick={() => setSheet("giveUp")}>
              Give up
            </Button>
          </div>
        </div>
      </div>
      <Tip id="purr.easel" anchor="purr-easel" text="No letters or numbers" show={!easelTipDone} place="below" />
      <Tip id="purr.got" anchor="purr-got-it" text="Tap who said it first" show={easelTipDone && canUndo} />
      {sheet === "got" ? (
        <Sheet title="Who got it?" onClose={() => setSheet(null)}>
          <div class="purr-who" id="purr-who">
            {guessers.map((s) => (
              <button
                type="button"
                class="purr-who-btn"
                style={{ ["--ring" as string]: ringOf(s) }}
                onClick={() => {
                  setSheet(null);
                  writer.end();
                  send(writer.flush(performance.now(), true));
                  buzz("win");
                  store.act(seat, { type: "gotIt", seat: s });
                }}
              >
                <Cat cat={seatCat(room.seats[s])} pose="celebrate" size={72} />
                <span>{seatName(room.seats[s])}</span>
              </button>
            ))}
          </div>
        </Sheet>
      ) : null}
      {sheet === "giveUp" ? (
        <Sheet title="Give up?" onClose={() => setSheet(null)}>
          <div class="sheet-actions">
            <Button
              wide
              variant="magenta"
              id="purr-give-up-yes"
              onClick={() => {
                setSheet(null);
                store.act(seat, { type: "giveUp" });
              }}
            >
              Give up
            </Button>
            <Button wide variant="violet" onClick={() => setSheet(null)}>
              Keep drawing
            </Button>
          </div>
        </Sheet>
      ) : null}
    </main>
  );
}

const COLOUR_NAMES = ["Black", "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Brown"];

const ringOf = (seat: number): string => ["#7B2FFF", "#FF2E9A", "#00D1C1", "#FF8A00", "#2EB8FF", "#9BE22E"][seat % 6]!;

/** The 3:4 easel inside a box, less the frame's border and padding. */
function fitIn(w: number, h: number): { width: number; height: number } {
  const width = Math.floor(Math.min(w, (h * 3) / 4));
  return { width, height: Math.floor((width * 4) / 3) };
}

/** The same strokes, point for point. */
function samePicture(a: readonly Stroke[], b: readonly Stroke[]): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    const x = a[i]!;
    const y = b[i]!;
    if (x.id !== y.id || x.colour !== y.colour || x.width !== y.width || x.points.length !== y.points.length) return false;
    for (let k = 0; k < x.points.length; k++) if (x.points[k] !== y.points[k]) return false;
  }
  return true;
}

