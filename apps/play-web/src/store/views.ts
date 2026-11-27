/** Which view a table shows, Cards or Table, remembered per table (the newest 30 tables). */
import { store } from "../lib/kv";

import { mySeats } from "./lobby";

import type { RoomView } from "@pounce/play-api/protocol";

export type View = "cards" | "table";

const KEY = "pounce.views";
const KEEP = 30;

function read(): Record<string, View> {
  const kept = store.json<Record<string, View>>(KEY);
  return kept && typeof kept === "object" && !Array.isArray(kept) ? kept : {};
}

export function viewOf(code: string): View {
  return read()[code] === "table" ? "table" : "cards";
}

export function setView(code: string, view: View): void {
  const all = read();
  // Objects keep insertion order: delete then set puts this table last, the newest.
  delete all[code];
  all[code] = view;
  const keys = Object.keys(all);
  for (const old of keys.slice(0, Math.max(0, keys.length - KEEP))) delete all[old];
  store.set(KEY, JSON.stringify(all));
}

/** Play again: the new table opens on the view the old one was on, when that was ever chosen. */
export function carryView(from: string, to: string): void {
  if (from !== to && read()[from] !== undefined) setView(to, viewOf(from));
}

/** The Cards/Table switch shows while a TV shows the table and this phone holds a seat at it. */
export const showSwitch = (room: RoomView): boolean => room.screen === true && mySeats(room).length > 0;

/**
 * A phone is a controller (just its cards) while a TV shows the table, it holds a seat, and it is
 * on Cards. Otherwise it shows the full table: with no TV every phone does, whatever the switch says.
 */
export const showController = (room: RoomView, view: View): boolean => showSwitch(room) && view === "cards";

/**
 * The view after seat `seat` lays down: a phone on Cards whose own player laid down turns to the
 * Table, to see the groups and hit onto them. Anyone else's lay down, or a phone already on
 * Table, changes nothing. The Table is kept like a press of the switch; only the switch turns it back.
 */
export const viewAfterLayDown = (room: RoomView, view: View, seat: number): View =>
  showController(room, view) && mySeats(room).includes(seat) ? "table" : view;
