/**
 * The first-run funnel's milestones (first-run funnel design, Part 3): the first time a device
 * reached each step, kept in the `FUNNEL` D1 database. The app's `Funnel.Milestone`
 * (PounceKit/Funnel) spells the app's own the same way; a test holds the two lists together.
 */

/** Steps only the server can vouch for: it records them itself, and an app can't send them. */
export const SERVER_MILESTONES = [
  /** `POST /v1/devices` minted the device: the app's first launch. */
  "device_created",
  /** The device created a table (`POST /v1/rooms`). */
  "table_created",
  /** The device holds a person's seat at a table, its own or someone else's. */
  "seat_taken",
  /** The device holds a seat at a table another device created. */
  "joined_table",
  /** The device's first move the room accepted. */
  "first_move",
  /** A game the device had a seat in reached its end. */
  "game_finished",
  /** A finished game with at least two people seated (pass and play counts). */
  "game_with_human",
  /** A finished game with someone seated from another device. */
  "game_with_device",
] as const;

/** Steps the app reports (`POST /v1/funnel`), all after the age check. */
export const APP_MILESTONES = [
  /** The age check finished. */
  "age_done",
  /** The owner's name and cat were picked. */
  "named",
  /** Home showed. */
  "home_seen",
  /** An invite to a table went out: the share sheet sent it, or its QR code showed. */
  "invite_sent",
  /** The app opened a `/j` or `/p` link. */
  "link_opened",
  /** The app opened a pasted invite. */
  "invite_pasted",
  /** The notifications prompt was answered, either way. */
  "push_answered",
  /** The notifications prompt was answered yes. */
  "push_allowed",
] as const;

export type ServerMilestone = (typeof SERVER_MILESTONES)[number];
export type AppMilestone = (typeof APP_MILESTONES)[number];
export type Milestone = ServerMilestone | AppMilestone;

/**
 * How a device first came to Pounce, as the app saw it until it first opened a table: on its
 * own, from a `/j` (table) link, a `/p` (request to play) link, or an invite it pasted. The app
 * says "organic" until it knows better; an invite before the first table replaces it, and after
 * that the app sends the same source for good.
 */
export const SOURCES = ["organic", "join_link", "pounce_link", "paste"] as const;
export type Source = (typeof SOURCES)[number];

export const isAppMilestone = (value: unknown): value is AppMilestone =>
  typeof value === "string" && (APP_MILESTONES as readonly string[]).includes(value);

export const isSource = (value: unknown): value is Source =>
  typeof value === "string" && (SOURCES as readonly string[]).includes(value);
