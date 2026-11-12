import { drawable, withoutUndrawable, type TableEntry } from "../room/tables";

import type { Outgoing } from "./types";

/**
 * A push as one device should get it, or null when it shouldn't get it at all.
 *
 * `tables` are the device's tables (its own and its players'), `games` the games its app can
 * draw beyond Cat Tower, and `game` the game of the push's table when the sender knows it (a
 * room does); otherwise the tables say. For a device that can open every table it has, the push
 * is the one it was given: this changes nothing for anyone with no table of another game.
 *
 * For a device that can't open the push's table:
 * - a push that is only about that table ("your move", a nudge, play again) is not for it;
 * - one that says what such a device gets instead (`otherwise`: a streak reminder) is sent with
 *   that copy, pointing at the table it names, or at none.
 * Either way its streak block lists only tables it can open.
 */
export function forDevice(o: Outgoing, tables: readonly TableEntry[], games: readonly string[], game?: string): Outgoing | null {
  const { otherwise, ...push } = o.streak ? { ...o, streak: withoutUndrawable(o.streak, tables, games) } : o;
  if (o.code === undefined || drawable(game ?? tables.find((t) => t.code === o.code)?.game, games)) return push;
  if (!otherwise) return null;
  const instead: Outgoing = { ...push, body: otherwise.body };
  if (otherwise.code === undefined) delete instead.code;
  else instead.code = otherwise.code;
  return instead;
}
