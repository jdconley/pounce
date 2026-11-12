import worker from "../src/index";

import type { Env } from "../src/env";

export { DeviceIndex } from "../src/room/device-index";
export { GameRoom } from "../src/room/game-room";
export { Identities } from "../src/players/identities";
export { Limiter } from "../src/safety/limiter";
export { Reports } from "../src/safety/reports";
export { Player } from "../src/players/player";
export { Pair } from "../src/streaks/pair";

/** Every call the Worker itself made to a device's index since the log was last read: the method and its arguments. */
let calls: { method: string; args: unknown[] }[] = [];

/** `DEVICES`, with each method the Worker calls on a device's index written down first. */
function watched(devices: Env["DEVICES"]): Env["DEVICES"] {
  return new Proxy(devices, {
    get(target, prop) {
      if (prop !== "get") {
        const value = Reflect.get(target, prop) as unknown;
        return typeof value === "function" ? (value.bind(target) as unknown) : value;
      }
      return (id: DurableObjectId) => {
        const stub = target.get(id) as unknown as Record<string, (...args: unknown[]) => unknown>;
        return new Proxy(stub, {
          get(_, method) {
            if (typeof method !== "string") return undefined;
            return (...args: unknown[]) => {
              calls.push({ method, args });
              return (stub[method] as (...a: unknown[]) => unknown)(...args);
            };
          },
        });
      };
    },
  });
}

/**
 * The real worker, with the Worker's own calls to `DEVICES` counted: `/__test/device-calls` hands
 * the log over and empties it. Calls made from inside a Durable Object are not the Worker's and
 * are not counted. Also `/__test/remind?player=&now=`, as in the notification suites.
 */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/__test/device-calls") {
      const log = calls;
      calls = [];
      return Response.json(log);
    }
    if (url.pathname === "/__test/remind") {
      await env.PLAYERS.get(env.PLAYERS.idFromName(url.searchParams.get("player") ?? "")).remind(Number(url.searchParams.get("now")));
      return new Response(null, { status: 204 });
    }
    return worker.fetch(request, { ...env, DEVICES: watched(env.DEVICES) });
  },
};
