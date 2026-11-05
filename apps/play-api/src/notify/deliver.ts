import { deviceTables } from "../players/accounts";

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
 * tables list counts them. `also` counts a table whose index may not have
 * caught up with the move yet.
 */
export async function badgeFor(env: Env, deviceId: string, also?: string): Promise<number> {
  const tables = await deviceTables(env, deviceId);
  const mine = new Set(tables.filter((t) => t.yourTurn && t.status === "playing").map((t) => t.code));
  if (also) mine.add(also);
  return mine.size;
}

/** Sends one push to every device of a player, each with its own badge. True if any device got it. */
export async function deliverToPlayer(env: Env, profile: PushProfile, o: Outgoing, level: Level, also?: string): Promise<boolean> {
  const results = await Promise.all(
    profile.devices.map(async (d) => {
      try {
        const body = apnsBody(o, level, await badgeFor(env, d, also));
        return (await device(env, d).pushAlert(body, collapseId(o.collapse), level)).sent;
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
