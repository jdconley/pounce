/**
 * Card and piece faces, drawn as iOS draws them (`CardFaceFactory.swift`,
 * `TilePieceFactory.swift`): the face art, the outlined numeral, the coat's glyph and cat, or the
 * Yarn and Cucumber art; a piece is its toy's colour with the number and the toy. Each face is a
 * few CSS background layers on one element, so a card is one thing for the compositor to move.
 */
import { card, type CardId } from "@pounce/play-api/rules/cards";
import { tile, type TileId } from "@pounce/play-api/tiles/pieces";

import { art } from "../lib/art";

let injected = false;

/** The faces' image layers as classes, once: the art's URLs are only known after the build. */
export function injectFaceStyles(): void {
  if (injected || typeof document === "undefined") return;
  injected = true;
  const rules: string[] = [];
  for (const coat of ["tabby", "tuxedo", "calico", "gray"]) {
    rules.push(`.face.coat-${coat}{background-image:url(${art(`glyph-${coat}`)}),url(${art(`coat-${coat}`)}),url(${art("card-face")})}`);
  }
  rules.push(`.face.yarn{background-image:url(${art("card-yarn")}),url(${art("card-face")})}`);
  rules.push(`.face.cucumber{background-image:url(${art("card-cucumber")}),url(${art("card-face")})}`);
  rules.push(`.face.back,.deck-card{background-image:url(${art("card-back")})}`);
  rules.push(`.face.blank{background-image:url(${art("card-face")})}`);
  for (const suit of ["fish", "mouse", "feather", "bell"]) rules.push(`.piece .toy.${suit}{background-image:url(${art(`tile-${suit}`)})}`);
  rules.push(`.piece.yarn .toy{background-image:url(${art("card-yarn")})}`);
  rules.push(`.piece.back .toy{background-image:url(${art("icon-paw-menu")})}`);
  const style = document.createElement("style");
  style.textContent = rules.join("\n");
  document.head.append(style);
}

const COAT_WORD = { tabby: "tabby", tuxedo: "tuxedo", calico: "calico", gray: "gray" } as const;

/** What a screen reader hears for a card. */
export function cardLabel(id: CardId): string {
  const c = card(id);
  if (c.kind === "yarn") return "Yarn, wild";
  if (c.kind === "cucumber") return "Cucumber, skip";
  return `${c.value}, ${COAT_WORD[c.coat]}`;
}

/** A card's face: the classes and the numeral. */
export function CardFace(props: { id: CardId; compact?: boolean }) {
  const c = card(props.id);
  if (c.kind !== "number") return <div class={`face ${c.kind} ${props.compact ? "compact" : ""}`} />;
  return (
    <div class={`face coat-${c.coat} ${props.compact ? "compact" : ""}`}>
      <span class={`num ${c.value > 9 ? "two" : ""} ${c.coat}`}>{c.value}</span>
    </div>
  );
}

export const CardBack = () => <div class="face back" />;

const SUIT_WORD = { fish: "fish", mouse: "mouse", feather: "feather", bell: "bell" } as const;

export function pieceLabel(id: TileId, ghost?: number): string {
  const t = tile(id);
  if (t.kind === "yarn") return ghost ? `Yarn, as ${ghost}` : "Yarn, wild";
  return `${t.value} ${SUIT_WORD[t.suit]}`;
}

/** A piece's face. `ghost` is the number a Yarn stands for where it sits. */
export function PieceFace(props: { id: TileId; ghost?: number | null }) {
  const t = tile(props.id);
  if (t.kind === "yarn") {
    return (
      <div class="piece yarn">
        {props.ghost ? <span class="ghost">{props.ghost}</span> : null}
        <span class="toy" />
      </div>
    );
  }
  return (
    <div class={`piece ${t.suit}`}>
      <span class={`n ${t.value > 9 ? "two" : ""}`}>{t.value}</span>
      <span class={`toy ${t.suit}`} />
    </div>
  );
}

export const PieceBack = () => (
  <div class="piece back">
    <span class="toy" />
  </div>
);
