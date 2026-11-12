import { storeKnown } from "../app/live";
import { gameTitle } from "../games";
import { deviceView } from "../players/accounts";
import { tablesFor, type TableEntry } from "../room/tables";

import { forDevice } from "./audience";
import { apnsBody, collapseId } from "./payload";
import { updateFor } from "./update";

import type { Level } from "./policy";
import type { NotifySettings } from "./settings";
import type { Outgoing } from "./types";
import type { Env } from "../env";
import type { AgeBand } from "../players/parse";

/** What sending to a player needs: who they are, their settings, and their devices. */
export type PushProfile = {
  id: string;
  name: string;
  band: AgeBand | null;
  zone: string | null;
  settings: NotifySettings;
  devices: string[];
};

const device = (env: Env, id: string) => env.DEVICES.get(env.DEVICES.idFromName(id));

/**
 * The badge (§12.5): tables where it's this device's move, as the app's own
 * tables list counts them (`tables`: the ones its app is shown). `also` counts
 * a table whose index may not have caught up with the move yet: only for "your
 * move", whose table it is.
 */
function badge(tables: readonly TableEntry[], also?: string): number {
  const mine = new Set(tables.filter((t) => t.yourTurn && t.status === "playing").map((t) => t.code));
  if (also) mine.add(also);
  return mine.size;
}

/**
 * Sends one push to every device of a player, each with its own badge. True if any device got it.
 * `senders` are the people behind it, which a consented kitten's device checks (parent consent,
 * plan decision 16); without them a kitten's device refuses it.
 *
 * Each device gets the push as `forDevice` says: one about a table of a game its app can't draw
 * is not sent to it, unless the push says what such a device gets instead (a streak reminder).
 * `game` is the table's game when the sender knows it (the room itself). Tables an app can't
 * draw never count toward its badge, nor appear in its streak block.
 *
 * A device not sent a push a person made about such a table gets the update push in its place
 * (`DeviceIndex.pushUpdate`: once per table, only when the App Store has a newer version than
 * its app, never a kitten's device). It doesn't count as this push having been delivered.
 */
export async function deliverToPlayer(
  env: Env,
  profile: PushProfile,
  o: Outgoing,
  level: Level,
  also?: string,
  senders?: (string | null)[],
  game?: string,
): Promise<boolean> {
  const gate = senders ? { recipient: profile.id, senders } : undefined;
  // Read at most once, and only if some device is held back from a push a person sent. What is
  // known is all it reads (what Apple itself last said): no push waits on Apple.
  let live: Promise<string | null> | undefined;
  const latest = () => (live ??= storeKnown(env).then((k) => k.store));
  const results = await Promise.all(
    profile.devices.map(async (d) => {
      try {
        const { tables, games } = await deviceView(env, d);
        const shown = forDevice(o, tables, games, game);
        if (shown === null) {
          const held = game ?? tables.find((t) => t.code === o.code)?.game;
          const update = held === undefined ? null : updateFor(o, held, gameTitle(held));
          if (update) await device(env, d).pushUpdate(update, level, await latest());
          return false;
        }
        const body = apnsBody(shown, level, badge(tablesFor(tables, games).slice(0, 50), also));
        return (await device(env, d).pushAlert(body, collapseId(o.collapse), level, gate)).sent;
      } catch {
        return false;
      }
    }),
  );
  return results.some(Boolean);
}

/** Asks a player's widgets to reload (§11.2); each device throttles itself. */
export async function pokeWidgets(env: Env, playerId: string, now: number): Promise<void> {
  const ids = await env.PLAYERS.get(env.PLAYERS.idFromName(playerId)).deviceIds();
  await Promise.all(ids.map((d) => device(env, d).pokeWidget(now).catch(() => undefined)));
}
