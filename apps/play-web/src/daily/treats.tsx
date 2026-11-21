/**
 * Each daily game's look in the Dish: its name, its colors and its treat, drawn like the other
 * choice icons (ink outline, bright fill, a shine). Original shapes: a scent tag, a paw grid, a
 * moon with a sleeping tail, a cardboard box. The names match the server's `DAILY_TITLES`, kept here
 * so the page never loads the server's game list (it imports every puzzle maker).
 */
import { useId } from "preact/hooks";

import type { DailyGameId } from "@pounce/play-api/daily/module";

export type Look = { title: string; color: string; deep: string };

export const LOOKS: Record<DailyGameId, Look> = {
  sniff: { title: "Sniff", color: "#ff2e9a", deep: "#c4006c" },
  "nine-lives": { title: "Nine Lives", color: "#2eb8ff", deep: "#0a6fc2" },
  "cat-nap": { title: "Cat Nap", color: "#9d63ff", deep: "#5a1fd6" },
  "box-fort": { title: "Box Fort", color: "#ff8a00", deep: "#c25200" },
  test: { title: "Test", color: "#00d1c1", deep: "#008a80" },
};

export const lookOf = (game: string): Look => LOOKS[game as DailyGameId] ?? LOOKS.test;

const INK = "#1b0b3a";

function Glyph(props: { game: string; shine: string }) {
  switch (props.game) {
    case "sniff":
      // A scent tag on a string, with a paw.
      return (
        <>
          <path d="M14 22 L32 10 L50 22 L50 52 Q50 56 46 56 L18 56 Q14 56 14 52 Z" fill="#fff" stroke={INK} stroke-width="3.5" stroke-linejoin="round" />
          <circle cx="32" cy="20" r="3.5" fill={INK} />
          <ellipse cx="32" cy="42" rx="7" ry="6" fill={props.shine} stroke={INK} stroke-width="2.5" />
          <circle cx="24" cy="32" r="3" fill={props.shine} stroke={INK} stroke-width="2" />
          <circle cx="32" cy="29" r="3" fill={props.shine} stroke={INK} stroke-width="2" />
          <circle cx="40" cy="32" r="3" fill={props.shine} stroke={INK} stroke-width="2" />
        </>
      );
    case "nine-lives":
      // Nine paw tiles, one lit.
      return (
        <>
          <rect x="10" y="10" width="44" height="44" rx="8" fill="#fff" stroke={INK} stroke-width="3.5" />
          {[0, 1, 2].flatMap((r) =>
            [0, 1, 2].map((c) => <rect key={`${r}${c}`} x={15 + c * 12.5} y={15 + r * 12.5} width="9.5" height="9.5" rx="2.5" fill={r === 1 && c === 1 ? props.shine : "#d9ccff"} stroke={INK} stroke-width="1.8" />),
          )}
        </>
      );
    case "cat-nap":
      // A moon with a curled tail and a Z.
      return (
        <>
          <path d="M40 10 A22 22 0 1 0 54 42 A17 17 0 1 1 40 10 Z" fill="#ffd21f" stroke={INK} stroke-width="3.5" stroke-linejoin="round" />
          <path d="M14 50 Q26 58 38 50" fill="none" stroke={INK} stroke-width="3.5" stroke-linecap="round" />
          <path d="M42 14 h9 l-9 10 h9" fill="none" stroke="#fff" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round" />
        </>
      );
    case "box-fort":
      // A cardboard box with its flaps up.
      return (
        <>
          <path d="M10 22 L22 14 L32 22 L42 14 L54 22 L32 30 Z" fill="#ffc77a" stroke={INK} stroke-width="3" stroke-linejoin="round" />
          <path d="M12 26 L32 32 L52 26 L52 50 L32 58 L12 50 Z" fill="#e8a250" stroke={INK} stroke-width="3.5" stroke-linejoin="round" />
          <path d="M32 32 V58" stroke={INK} stroke-width="3" />
          <rect x="18" y="38" width="8" height="5" rx="1.5" fill="#fff" opacity="0.7" />
        </>
      );
    default:
      // The test game: three steps.
      return (
        <>
          <rect x="10" y="38" width="14" height="16" rx="3" fill="#fff" stroke={INK} stroke-width="3" />
          <rect x="25" y="26" width="14" height="28" rx="3" fill="#fff" stroke={INK} stroke-width="3" />
          <rect x="40" y="14" width="14" height="40" rx="3" fill={props.shine} stroke={INK} stroke-width="3" />
        </>
      );
  }
}

/** The game's treat on its colored dish. Decorative. */
export function Treat(props: { game: string; size?: number }) {
  const id = useId();
  const look = lookOf(props.game);
  const size = props.size ?? 56;
  return (
    <svg class="dd-treat" width={size} height={size} viewBox="0 0 64 64" aria-hidden="true" focusable="false">
      <defs>
        <linearGradient id={`${id}d`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color={look.color} />
          <stop offset="1" stop-color={look.deep} />
        </linearGradient>
      </defs>
      <circle cx="32" cy="32" r="29" fill={`url(#${id}d)`} stroke={INK} stroke-width="3.5" />
      <path d="M12 24 Q16 10 30 7" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" opacity="0.55" />
      <g transform="translate(9.6 9.6) scale(0.7)">
        <Glyph game={props.game} shine={look.color} />
      </g>
    </svg>
  );
}

/** A small crown, for a game won on the Dish board. */
export function CrownMark(props: { game: string }) {
  const look = lookOf(props.game);
  return (
    <svg class="dd-crown" width="22" height="18" viewBox="0 0 22 18" role="img" aria-label={`Won ${look.title}`}>
      <path d="M2 15 L3 4 L8 9 L11 2 L14 9 L19 4 L20 15 Z" fill={look.color} stroke={INK} stroke-width="2" stroke-linejoin="round" />
    </svg>
  );
}
