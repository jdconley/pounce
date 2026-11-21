/**
 * Watching a puzzle on the TV (daily games design §8): the card that offers it, and the host that
 * draws the run from the server's frames. Each game brings its own read-only view
 * (`DailyWatchView`); until a game's lands, a placeholder stands in.
 */
import { useEffect, useRef } from "preact/hooks";

import { art } from "../../lib/art";
import { play } from "../../lib/sound";
import { Cat } from "../common";

import { gameTitle, offerWords, resultWords, type Frame, type Offer, type Watching } from "./tv-board-model";

import type { DailyResult } from "@pounce/play-api/daily/module";
import type { JSX } from "preact";

/** A game's read-only view of a run, drawn from its public puzzle and public state. */
export type DailyWatchView = (props: { puzzle: unknown; state: unknown }) => JSX.Element;

/** The games' watch views, by game id. Each game adds its own line here as it lands. */
const WATCH_VIEWS: Partial<Record<string, DailyWatchView>> = {};

/** The test game ("count to N"): the number reached, big. */
function TestWatch(props: { puzzle: unknown; state: unknown }) {
  const n = (props.state as { n?: unknown } | null)?.n;
  return <p class="tv-watch-count outlined">{typeof n === "number" ? n : 0}</p>;
}

/** A game whose view hasn't landed yet: its name, and that someone is at it. */
function Placeholder(props: { game: string }) {
  return (
    <div class="tv-watch-placeholder">
      <p class="tv-watch-placeholder-title outlined">{gameTitle(props.game)}</p>
      <img class="tv-watch-placeholder-art" src={art("icon-hourglass")} alt="" />
    </div>
  );
}

/** The view for `game`: its own, the test game's count, or the placeholder. */
export function watchViewFor(game: string): DailyWatchView {
  const own = WATCH_VIEWS[game];
  if (own) return own;
  if (game === "test") return TestWatch;
  return () => <Placeholder game={game} />;
}

/** The card: "Mom is playing Sniff. Spoilers." Not now has the remote's focus. */
export function TvWatchCard(props: { offer: Offer; onWatch: () => void; onNotNow: () => void }) {
  const { offer } = props;
  // Not now takes the remote's focus when the card comes up, wherever it was (the paw, say):
  // watching is a choice, never an accident.
  const notNow = useRef<HTMLButtonElement>(null);
  useEffect(() => notNow.current?.focus({ preventScroll: true }), []);
  return (
    <div class="tv-watch-card" role="alertdialog" aria-label={offerWords(offer)}>
      <Cat cat={offer.cat} pose="awake" size="calc(var(--u) * 150)" class="tv-watch-card-cat" />
      <p class="tv-watch-card-words outlined">{offerWords(offer)}</p>
      <div class="tv-watch-card-buttons">
        <button
          type="button"
          class="tv-menu-item violet"
          data-tv
          onClick={() => {
            play("pop", 0.5);
            props.onWatch();
          }}
        >
          <img src={art("icon-play")} alt="" />
          <span>Watch</span>
        </button>
        <button
          type="button"
          class="tv-menu-item magenta"
          data-tv
          data-tv-default
          ref={notNow}
          onClick={() => {
            play("pop", 0.5);
            props.onNotNow();
          }}
        >
          <img src={art("icon-back")} alt="" />
          <span>Not now</span>
        </button>
      </div>
    </div>
  );
}

const ENDED_WORDS: Record<DailyResult["outcome"], string> = { solved: "Solved", done: "Done", missed: "Missed", gaveUp: "Gave up", closed: "Closed" };

/** A run, live: who and which game on top, the game's own view below, its result once it ends. */
export function TvWatch(props: { watching: Watching; frame: Frame | undefined; ended: { result: DailyResult; name: string } | null; onBack: () => void }) {
  const { watching, ended } = props;
  const View = watchViewFor(watching.game);
  return (
    <section class="tv-watch" data-game={watching.game} aria-label={`${watching.name}, ${gameTitle(watching.game)}`}>
      <header class="tv-watch-top">
        <Cat cat={watching.cat} pose="idle" size="calc(var(--u) * 110)" />
        <p class="tv-watch-who outlined">{watching.name}</p>
        <span class="tv-watch-game">{gameTitle(watching.game)}</span>
        <span class="tv-watch-gap" />
        <button
          type="button"
          class="tv-menu-item violet tv-watch-back"
          data-tv
          data-tv-default={ended ? undefined : true}
          onClick={() => {
            play("pop", 0.5);
            props.onBack();
          }}
        >
          <img src={art("icon-back")} alt="" />
          <span>Board</span>
        </button>
      </header>
      <div class="tv-watch-stage">{props.frame === undefined ? <Placeholder game={watching.game} /> : <View puzzle={props.frame.puzzle} state={props.frame.state} />}</div>
      {ended ? (
        <div class="tv-watch-ended" role="status">
          <img class="tv-watch-ended-burst" src={art("sunburst")} alt="" aria-hidden="true" />
          <Cat cat={watching.cat} pose={ended.result.outcome === "solved" || ended.result.outcome === "done" ? "celebrate" : "idle"} size="calc(var(--u) * 260)" />
          <p class="tv-watch-ended-title outlined">{ENDED_WORDS[ended.result.outcome]}</p>
          {ended.result.outcome === "solved" || ended.result.outcome === "done" ? <p class="tv-watch-ended-result">{resultWords(ended.result)}</p> : null}
        </div>
      ) : null}
    </section>
  );
}
