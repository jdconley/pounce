import worker from "../src/index";

import type { Env } from "../src/env";

export { DeviceIndex } from "../src/room/device-index";
export { GameRoom } from "../src/room/game-room";
export { Identities } from "../src/players/identities";
export { Player } from "../src/players/player";

/** Rooms whose `adopt` fails, to cut a merge short. */
function failingAdopts(rooms: Env["ROOMS"]): Env["ROOMS"] {
  return {
    idFromName: (name: string) => rooms.idFromName(name),
    get: (id: DurableObjectId) => {
      const stub = rooms.get(id);
      return new Proxy(stub, {
        get: (target, key) => (key === "adopt" ? () => Promise.reject(new Error("injected")) : Reflect.get(target, key)),
      });
    },
  } as unknown as Env["ROOMS"];
}

/**
 * The real worker, plus test hooks: `x-test-fail-adopt` makes room adopts
 * fail for that request, and `/__test/expire` runs a guest's retention now.
 */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/__test/expire") {
      const id = url.searchParams.get("player") ?? "";
      await env.PLAYERS.get(env.PLAYERS.idFromName(id)).expire();
      return new Response(null, { status: 204 });
    }
    if (request.headers.has("x-test-fail-adopt")) return worker.fetch(request, { ...env, ROOMS: failingAdopts(env.ROOMS) });
    return worker.fetch(request, env);
  },
};
