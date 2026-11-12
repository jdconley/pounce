import type { NotifyKind } from "./policy";
import type { Json } from "../players/parse";

/** The pair's state in a push (§12.7), for the Notification Service Extension and widgets. */
export type StreakBlock = {
  pair: string;
  count: number;
  me: boolean;
  them: boolean;
  naps: number;
  myMove: string[];
  theirMove: string[];
};

/** One push, before it's addressed to a device: the copy, grouping and data. */
export type Outgoing = {
  kind: NotifyKind;
  title: string;
  body: string;
  /** The room the push opens. */
  code?: string;
  thread: string;
  /** `<kind>:<id>`; the payload builder keeps it within 64 bytes. */
  collapse: string;
  from?: { name: string; cat: number };
  streak?: StreakBlock;
  data?: Record<string, Json>;
  /**
   * The same push for a device whose app can't open `code`'s table (a game it doesn't draw): the
   * copy, and a table it can open instead when there is one. Only on a push that isn't solely
   * about that table (a streak reminder). Without it, such a device isn't sent the push at all.
   * Never part of the payload (`forDevice` applies it).
   */
  otherwise?: { body: string; code?: string };
};
