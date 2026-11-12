import { deviceView } from "../players/accounts";
import { drawable, tablesFor, withoutUndrawable, type TableEntry } from "../room/tables";

import { apnsBody, collapseId } from "./payload";

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
 * A push about a table (`o.code`) of a game other than Cat Tower goes only to the devices whose
 * app has said it can draw that game: an older app could not open the table. `game` is the
 * table's game when the sender knows it (the room itself); otherwise the device's tables list
 * says. Tables an app can't draw never count toward its badge, nor appear in its streak block.
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
  const results = await Promise.all(
    profile.devices.map(async (d) => {
      try {
        const { tables, games } = await deviceView(env, d);
        if (!drawable(game ?? tables.find((t) => t.code === o.code)?.game, games)) return false;
        // The streak block lists tables by code: this device hears only of the ones it can draw.
        const shown = o.streak ? { ...o, streak: withoutUndrawable(o.streak, tables, games) } : o;
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
