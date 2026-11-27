/**
 * Watching a puzzle on the TV (daily games design §8): the card that offers it, and the host that
 * draws the run from the server's frames. Each game's own read-only view comes from the web
 * registry (`DailyWatch`, in its own chunk); a game the registry doesn't list yet gets a placeholder.
 */
import { useEffect, useLayoutEffect, useRef } from "preact/hooks";

import { DAILY_WEB_GAMES } from "../../daily/registry";
import { DailyWatch, loadWatch } from "../../daily/watch";
import { art } from "../../lib/art";
import { play } from "../../lib/sound";
import { Cat } from "../common";

import { endedWords, gameTitle, offerWords, resultWords, type Frame, type Offer, type Watching } from "./tv-board-model";

import type { DailyResult } from "@pounce/play-api/daily/module";

/** A game whose view hasn't landed yet: its name, and that someone is at it. */
function Placeholder(props: { game: string }) {
  return (
    <div class="tv-watch-placeholder">
      <p class="tv-watch-placeholder-title outlined">{gameTitle(props.game)}</p>
      <img class="tv-watch-placeholder-art" src={art("icon-hourglass")} alt="" />
    </div>
  );
}

/** Whether this build has `game`'s own watch view (the web registry lists it). */
export function hasWatchView(game: string): boolean {
  return Object.hasOwn(DAILY_WEB_GAMES, game);
}

/** The card: "Mom is playing Sniff. Spoilers." Not now has the remote's focus. */
export function TvWatchCard(props: { offer: Offer; onWatch: () => void; onNotNow: () => void }) {
  const { offer } = props;
  // Not now takes the remote's focus when the card comes up, wherever it was (the paw, say):
  // watching is a choice, never an accident.
  const notNow = useRef<HTMLButtonElement>(null);
  useLayoutEffect(() => notNow.current?.focus({ preventScroll: true }), []);
  // Fetch the game's watch view while the card is up, so Watch draws the run at once.
  useEffect(() => {
    if (hasWatchView(offer.game)) void loadWatch(offer.game);
  }, [offer.game]);
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

/** A run, live: who and which game on top, the game's own view below, its result once it ends. */
export function TvWatch(props: { watching: Watching; frame: Frame | undefined; ended: { result: DailyResult; name: string } | null; onBack: () => void }) {
  const { watching, ended, frame } = props;
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
      <div class="tv-watch-stage">
        {frame === undefined || !hasWatchView(watching.game) ? (
          <Placeholder game={watching.game} />
        ) : (
          <DailyWatch game={watching.game} puzzle={frame.puzzle} state={frame.state} />
        )}
      </div>
      {ended ? (
        <div class="tv-watch-ended" role="status">
          <img class="tv-watch-ended-burst" src={art("sunburst")} alt="" aria-hidden="true" />
          <Cat cat={watching.cat} pose={ended.result.outcome === "solved" || ended.result.outcome === "done" ? "celebrate" : "idle"} size="calc(var(--u) * 260)" />
          <p class="tv-watch-ended-title outlined">{endedWords(ended.result)}</p>
          {/* The time or points, or how far it got ("62%"). */}
          <p class="tv-watch-ended-result">{resultWords(ended.result)}</p>
        </div>
      ) : null}
    </section>
  );
}
