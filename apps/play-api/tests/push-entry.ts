import worker from "../src/index";

import type { Env } from "../src/env";
import type { YourTurnIntent } from "../src/room/core";

export { DeviceIndex } from "../src/room/device-index";
export { GameRoom } from "../src/room/game-room";

/**
 * The real worker, plus one test-only route that calls DeviceIndex over RPC
 * (Miniflare's Node-side namespace handles speak fetch, not RPC).
 */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/__test/")) {
      const stub = env.DEVICES.get(env.DEVICES.idFromName(url.searchParams.get("device") ?? ""));
      if (url.pathname === "/__test/token") {
        await stub.setApnsToken(url.searchParams.get("token") ?? "");
        return new Response(null, { status: 204 });
      }
      const intent = (await request.json()) as YourTurnIntent;
      return Response.json(await stub.push(intent));
    }
    return worker.fetch(request, env);
  },
};
