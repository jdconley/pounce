import { art, catArt, RINGS, type CatPose } from "../lib/art";

import type { RoomView } from "@pounce/play-api/protocol";


export type SeatInfo = RoomView["seats"][number];

/** A seat's display name: the person's, "House Cat", or nothing for an empty seat. */
export const seatName = (s: SeatInfo | undefined): string => (s?.kind === "bot" ? "House Cat" : (s?.person?.name ?? ""));

/** The House Cat is the gray cat. */
export const seatCat = (s: SeatInfo | undefined): number => (s?.kind === "bot" ? 3 : (s?.person?.cat ?? 0));

export function seatPose(s: SeatInfo | undefined, turn: boolean): CatPose {
  if (s?.presence === "asleep") return "asleep";
  if (s?.presence === "away") return "away";
  return turn ? "awake" : "idle";
}

/**
 * A player at the table: their cat in a ring of their seat's colour, their name, and what is
 * going on with them (cards in hand, laid down, skipped next, on another phone, a House Cat,
 * a weak connection). The ring glows on their turn.
 */
export function SeatAvatar(props: {
  seat: number;
  info: SeatInfo | undefined;
  size: number;
  turn: boolean;
  count?: number;
  laid?: boolean;
  skip?: boolean;
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
    props.turn ? "their turn" : "",
    props.laid ? "laid down" : "",
    props.skip ? "skips next turn" : "",
    props.out ? "out of the game" : "",
    info?.link === "lost" ? "connection lost" : info?.link === "weak" ? "weak connection" : "",
  ].filter(Boolean);
  const Tag = props.onClick ? "button" : "div";
  return (
    <Tag
      type={props.onClick ? "button" : undefined}
      id={props.id}
      class={`seat-avatar ${props.turn ? "turn" : ""} ${props.out ? "out" : ""} ${props.target ? "target" : ""}`}
      style={{ width: `${size}px`, ["--ring" as string]: RINGS[props.seat % RINGS.length] }}
      onClick={props.onClick}
      aria-label={props.label ?? parts.join(", ")}
      role={(props.onClick ? undefined : "img") as "button" | undefined}
    >
      {/* First in the markup, drawn under the ring (CSS order). The space keeps the name and the
          count two words when read together; a flex box draws no space. */}
      {name ? <span class="name-tag">{name}</span> : null}{" "}
      <span class="ring" style={{ width: `${size}px`, height: `${size}px` }}>
        <img src={catArt(seatCat(info), seatPose(info, props.turn))} alt="" width={size} height={size} draggable={false} decoding="async" />
        {badge ? <img class="badge" src={art(badge)} alt="" /> : null}
        {props.count !== undefined ? <span class="count">{props.count}</span> : null}
        {props.skip ? <img class="skip" src={art("badge-skip")} alt="" /> : null}
        {props.laid ? <img class="laid" src={art("badge-laid")} alt="" /> : null}
        {info?.link ? <span class={`link ${info.link}`} /> : null}
      </span>
    </Tag>
  );
}
