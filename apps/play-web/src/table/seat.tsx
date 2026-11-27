import { art, catArt, RINGS, type CatPose } from "../lib/art";

import { seatCat, seatName, type SeatInfo } from "./seat-names";

export { seatCat, seatName, type SeatInfo } from "./seat-names";

export function seatPose(s: SeatInfo | undefined, turn: boolean, pickled = false): CatPose {
  if (s?.presence === "asleep") return "asleep";
  if (s?.presence === "away") return "away";
  if (pickled) return "terrified";
  return turn ? "awake" : "idle";
}

/**
 * A player at the table: their cat in a ring of their seat's colour, their name, and what is
 * going on with them (cards in hand, laid down, pickled, on another phone, a House Cat, a weak
 * connection). The ring glows on their turn. Pickled (a Cucumber skips their turn): the cat is
 * terrified, the ring goes cucumber green, and a tag over it says so (pickled.ts says how long).
 */
export function SeatAvatar(props: {
  seat: number;
  info: SeatInfo | undefined;
  size: number;
  turn: boolean;
  count?: number;
  /** Points so far, under the name (a TV's seats). */
  score?: number;
  laid?: boolean;
  /** A Cucumber skips (or just skipped) their turn. */
  pickled?: boolean;
  out?: boolean;
  /** A drop target is over this seat (a Cucumber aimed at it). */
  target?: boolean;
  onClick?: () => void;
  label?: string;
  id?: string;
}) {
  const { info, size } = props;
  const name = seatName(info);
  const badge = info?.kind === "bot" ? "badge-bot" : info?.yours ? null : info?.kind === "human" ? "badge-remote" : null;
  const parts = [
    // The name and the count first, in the order they're written in the markup: a seat that is a
    // button says its visible text before anything else (WCAG 2.5.3).
    name,
    props.count !== undefined ? `${props.count} ${props.count === 1 ? "card" : "cards"}` : "",
    props.score !== undefined ? `${props.score} ${props.score === 1 ? "point" : "points"}` : "",
    props.turn ? "their turn" : "",
    props.laid ? "laid down" : "",
    props.pickled ? "pickled" : "",
    props.out ? "out of the game" : "",
    info?.link === "lost" ? "connection lost" : info?.link === "weak" ? "weak connection" : "",
  ].filter(Boolean);
  const Tag = props.onClick ? "button" : "div";
  return (
    <Tag
      type={props.onClick ? "button" : undefined}
      id={props.id}
      class={`seat-avatar ${props.turn ? "turn" : ""} ${props.out ? "out" : ""} ${props.target ? "target" : ""} ${props.pickled ? "pickled" : ""}`}
      style={{ width: `${size}px`, ["--ring" as string]: RINGS[props.seat % RINGS.length] }}
      onClick={props.onClick}
      aria-label={props.label ?? parts.join(", ")}
      role={(props.onClick ? undefined : "img") as "button" | undefined}
    >
      {/* First in the markup, drawn under the ring (CSS order). The space keeps the name and the
          count two words when read together; a flex box draws no space. */}
      {name ? <span class="name-tag">{name}</span> : null}{" "}
      {props.score !== undefined ? <span class="score">{props.score}</span> : null}
      <span class="ring" style={{ width: `${size}px`, height: `${size}px` }}>
        <img src={catArt(seatCat(info), seatPose(info, props.turn, props.pickled))} alt="" width={size} height={size} draggable={false} decoding="async" />
        {badge ? <img class="badge" src={art(badge)} alt="" /> : null}
        {props.count !== undefined ? <span class="count">{props.count}</span> : null}
        {props.pickled ? (
          <span class="pickled-tag" aria-hidden="true">
            <img src={art("badge-skip")} alt="" />
            Pickled
          </span>
        ) : null}
        {props.laid ? <img class="laid" src={art("badge-laid")} alt="" /> : null}
        {info?.link ? <span class={`link ${info.link}`} /> : null}
      </span>
    </Tag>
  );
}
