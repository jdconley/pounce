/**
 * Birdwatch's card faces (design §3.3): Cat Tower's chunky style in Tuna Tiles' toy suits. A
 * suit's body colour, a big white outlined numeral in the corner and the suit's silhouette, so the
 * corner alone reads in a tight fan and colour is never the only cue; a seed badge with its value
 * on a card worth points. The Bird has its own white face. Each face is one element with a few
 * spans and CSS image layers, so a card is one thing for the compositor to move.
 */
import { art } from "../lib/art";


import bird from "./bw-art/bird.svg?url";
import { cardFacts, cardLabel, type CardId, type RuleSetId } from "./bw-model";

let injected = false;

/** The suits' and the Bird's image layers as classes, once: the art's URLs are only known after the build. */
export function injectBirdStyles(): void {
  if (injected || typeof document === "undefined") return;
  injected = true;
  const rules = ["fish", "mouse", "feather", "bell"].map((suit) => `.bface .pip.${suit},.bw-suit-icon.${suit}{background-image:url(${art(`tile-${suit}`)})}`);
  rules.push(`.bface.bird .art,.bface.bird .pip,.bw-bird-icon{background-image:url(${bird})}`);
  rules.push(`.bface.back{background-image:url(${art("card-back")})}`);
  const style = document.createElement("style");
  style.textContent = rules.join("\n");
  document.head.append(style);
}

export const birdArt = bird;

export { cardLabel };

/** A card's face. `points` shows its seed badge (every card worth points has one). */
export function BirdFace(props: { id: CardId; rules: RuleSetId }) {
  injectBirdStyles();
  const f = cardFacts(props.id, props.rules);
  if (f.bird) {
    return (
      <div class="bface bird">
        <span class="pip" />
        <span class="art" />
        <span class="seed">{f.points}</span>
      </div>
    );
  }
  return (
    <div class={`bface ${f.suit}`}>
      <span class={`n ${f.rank! > 9 ? "two" : ""}`}>{f.rank}</span>
      <span class={`pip ${f.suit}`} />
      <span class={`art pip ${f.suit}`} />
      {f.points ? <span class="seed">{f.points}</span> : null}
    </div>
  );
}

export function BirdBack() {
  injectBirdStyles();
  return <div class="bface back" />;
}

/** A suit's silhouette, for buttons and the trump badge. */
export const SuitIcon = (props: { suit: string; size?: number }) => {
  injectBirdStyles();
  return <span class={`bw-suit-icon ${props.suit}`} style={props.size ? { width: `${props.size}px`, height: `${props.size}px` } : undefined} aria-hidden="true" />;
};
