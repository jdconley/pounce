/**
 * The puzzle host (map plan "The contracts" §2): any daily game, full screen. The host draws the
 * bar (back, the game and its number, the clock), Show on TV (only while a TV shows a board you're
 * on), Give up, and the end: the result, your place on today's board, share, stats and the next
 * puzzle. The game draws its board and controls in the stage, and talks to the server only
 * through its `RunSession`.
 */
import { useEffect, useRef, useState } from "preact/hooks";

import { buzz } from "../lib/haptics";
import { navigate } from "../lib/router";
import { play } from "../lib/sound";
import { api } from "../net/api";
import { useApp } from "../store/app";
import { Button, IconButton, Sheet } from "../ui/common";
import { TvIcon } from "../ui/show-on-tv";

import { dailyPath, startRun, type Run } from "./client";
import { dishGames } from "./dish-home";
import { dishStore, myRow, useDish } from "./dish-store";
import { clock, placeWords, puzzleNumber, resultWords } from "./format";
import { DAILY_WEB_GAMES } from "./registry";
import { renderCard, shareResult } from "./share";
import { StatsSheet } from "./stats";
import { lookOf, Treat } from "./treats";

import type { DailyGame } from "./host";
import type { DailyGameId, DailyResult } from "@pounce/play-api/daily/module";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnyGame = DailyGame<any, any, any, any>;

/** The clock: the server's time for this run, redrawn only when its second changes. */
function Clock(props: { run: Run }) {
  const ref = useRef<HTMLSpanElement>(null);
  useEffect(() => {
    let frame = 0;
    let shown = "";
    const tick = () => {
      const text = clock(props.run.elapsedMs());
      if (text !== shown && ref.current) ref.current.textContent = shown = text;
      if (!props.run.result) frame = requestAnimationFrame(tick);
    };
    tick();
    return () => cancelAnimationFrame(frame);
  }, [props.run, props.run.result]);
  return <span class="dd-clock" ref={ref} role="timer" aria-label="Time" />;
}

const OUTCOME: Record<string, string> = { solved: "Solved", missed: "Missed", gaveUp: "Gave up", closed: "Time's up", done: "Fort done" };

function EndPanel(props: {
  game: DailyGameId;
  result: DailyResult;
  rank: number | null;
  of: number;
  next: DailyGameId | null;
  canShare: boolean;
  sharing: boolean;
  onShare: () => void;
  onStats: () => void;
}) {
  const { result } = props;
  const look = lookOf(props.game);
  return (
    <div class="dd-end-scrim">
      <section class={`dd-end ${result.outcome}`} aria-labelledby="end-h" style={{ "--c": look.color, "--d": look.deep }}>
        <Treat game={props.game} size={84} />
        <h2 class="outlined" id="end-h">
          {OUTCOME[result.outcome] ?? "Done"}
        </h2>
        <p class="dd-end-result outlined">{resultWords(result)}</p>
        <p class="dd-end-place">
          {result.tooFast ? "Too fast for the board" : props.rank ? `${placeWords(props.rank, props.of)} today` : "On today's board"}
          {result.hints > 0 ? ` · ${result.hints === 1 ? "1 hint" : `${result.hints} hints`}` : ""}
        </p>
        <div class="dd-end-actions">
          {props.canShare ? (
            <Button variant="magenta" disabled={props.sharing} onClick={props.onShare}>
              Share
            </Button>
          ) : null}
          <Button variant="violet" onClick={props.onStats}>
            Stats
          </Button>
          {props.next ? (
            <Button variant="ok" onClick={() => navigate({ kind: "daily", game: props.next! })}>
              Next puzzle
            </Button>
          ) : null}
          <Button variant="teal" onClick={() => navigate({ kind: "dish" })}>
            Dish
          </Button>
        </div>
      </section>
    </div>
  );
}

export function PuzzleHost(props: { game: DailyGameId; say: (words: string) => void }) {
  const { game } = props;
  const { people } = useApp();
  const person = people.owner?.id;
  const dish = useDish(person);
  const [mod, setMod] = useState<AnyGame | null>(null);
  const [run, setRun] = useState<Run | null>(null);
  const [result, setResult] = useState<DailyResult | null>(null);
  const [quitting, setQuitting] = useState(false);
  const [tvOn, setTvOn] = useState(false);
  const [stats, setStats] = useState(false);
  const [sharing, setSharing] = useState(false);
  const [late, setLate] = useState(false);
  const working = useRef(false);
  const look = lookOf(game);

  useEffect(() => {
    const load = DAILY_WEB_GAMES[game];
    if (!load || !person) return navigate({ kind: "dish" }, true);
    let live = true;
    Promise.all([load.play(), startRun(game, person)])
      .then(([m, r]) => {
        if (!live) return;
        if (!r) return navigate({ kind: "dish" }, true);
        setMod(m.default as AnyGame);
        setRun(r as Run);
        setResult(r.result);
        setLate(!r.result && r.start.closesAt - r.serverNow() < 15 * 60_000);
      })
      .catch(() => {
        if (!live) return;
        props.say("Couldn't reach Pounce.");
        navigate({ kind: "dish" }, true);
      });
    return () => {
      live = false;
    };
  }, [game, person]);

  useEffect(() => {
    if (!run) return;
    const off = run.subscribe((e) => {
      if (e.kind !== "result") return;
      setResult(e.result);
      setQuitting(false);
      play(e.result.outcome === "solved" || e.result.outcome === "done" ? "fanfare" : "flip", 0.7);
      buzz(e.result.outcome === "solved" ? "win" : "drop");
      void dishStore.refresh();
    });
    return () => {
      off();
      // Whatever the game queued goes before the screen does.
      void run.flush();
    };
  }, [run]);

  const giveUp = async () => {
    if (!run || working.current) return;
    working.current = true;
    try {
      const r = await run.giveUp();
      if (!r) props.say("Couldn't reach Pounce.");
    } finally {
      working.current = false;
      setQuitting(false);
    }
  };

  const toggleTv = async () => {
    if (!run || !person) return;
    const on = !tvOn;
    setTvOn(on);
    try {
      await api.call("PUT", dailyPath(`/v1/daily/runs/${run.start.run}/tv`, person), { on });
    } catch {
      setTvOn(!on);
      props.say("Couldn't reach Pounce.");
    }
  };

  const share = async () => {
    if (!run || !result || !mod || !person || sharing) return;
    setSharing(true);
    try {
      // The final public state, for the card's grid (only games whose card has one).
      let grid = null;
      if (mod.share) {
        const fresh = await startRun(game, person).catch(() => null);
        grid = fresh ? mod.share(fresh.start.state, result) : null;
      }
      const png = await renderCard({ title: look.title, number: result.number, words: resultWords(result), hints: result.hints, color: look.color, deep: look.deep, grid });
      const out = await shareResult(look.title, result, png);
      if (out === "copied") props.say("Copied");
      else if (out === "failed") props.say("Couldn't share.");
    } finally {
      setSharing(false);
    }
  };

  const board = dish.board;
  const games = dishGames(board);
  const next = games.find((g) => g !== game && !myRow(board, g)?.result) ?? null;
  const gameRows = board?.games.find((g) => g.game === game)?.rows.filter((r) => r.result) ?? [];
  const mine = myRow(board, game);
  const Screen = mod?.Screen;

  return (
    <main class="screen dd-play" style={{ "--c": look.color, "--d": look.deep }}>
      <header class="dd-play-bar">
        <IconButton icon="icon-back" label="Dish" onClick={() => navigate({ kind: "dish" })} />
        <div class="dd-play-title">
          <h1 class="outlined">
            {look.title} {run && puzzleNumber(run.start.number) ? <span class="dd-num">{puzzleNumber(run.start.number)}</span> : null}
          </h1>
          {run ? <Clock run={run} /> : null}
        </div>
        <div class="dd-play-actions">
          {run && !result && dish.tvs > 0 ? (
            <button type="button" class={`dd-tv-switch ${tvOn ? "on" : ""}`} role="switch" aria-checked={tvOn} aria-label="Show on TV" onClick={() => void toggleTv()}>
              <TvIcon size={30} />
            </button>
          ) : null}
          {run && !result ? (
            <Button size="small" variant="violet" class="dd-give-up" onClick={() => setQuitting(true)}>
              Give up
            </Button>
          ) : null}
        </div>
      </header>
      {late ? (
        <p class="dd-late" role="status">
          The Dish turns over at 4:00
        </p>
      ) : null}
      <div class={`dd-stage ${result ? "over" : ""}`}>{Screen && run ? <Screen session={run} playing={!result} /> : null}</div>
      {result ? (
        <EndPanel
          game={game}
          result={result}
          rank={mine?.result ? mine.rank : null}
          of={gameRows.length}
          next={next}
          canShare={people.band !== "kitten"}
          sharing={sharing}
          onShare={() => void share()}
          onStats={() => setStats(true)}
        />
      ) : null}
      {quitting ? (
        <Sheet title="Give up?" onClose={() => setQuitting(false)}>
          <div class="sheet-actions">
            <Button wide variant="magenta" id="give-up-yes" onClick={() => void giveUp()}>
              Give up
            </Button>
            <Button wide variant="violet" onClick={() => setQuitting(false)}>
              Keep playing
            </Button>
          </div>
        </Sheet>
      ) : null}
      {stats && board ? <StatsSheet game={game} stats={dish.stats?.[game] ?? null} today={board.date} onClose={() => setStats(false)} /> : null}
    </main>
  );
}
