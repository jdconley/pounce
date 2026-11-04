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
};
