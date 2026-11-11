import worker from "../src/index";

import type { Env } from "../src/env";

export { DeviceIndex } from "../src/room/device-index";
export { GameRoom } from "../src/room/game-room";
export { Identities } from "../src/players/identities";
export { Limiter } from "../src/safety/limiter";
export { Reports } from "../src/safety/reports";
export { Player } from "../src/players/player";
export { Pair } from "../src/streaks/pair";

/**
 * The real worker, plus test hooks: `/__test/live?code=&now=` ends the
 * room's live tables whose limits have passed by `now` (the alarm's job, on a
 * later clock), and `/__test/running?device=&code=&now=` asks a device whether it holds "your move" back.
 */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const q = (k: string) => url.searchParams.get(k) ?? "";
    const room = () => env.ROOMS.get(env.ROOMS.idFromName(q("code")));
    if (url.pathname === "/__test/live") {
      await room().checkLive(Number(q("now")));
      return new Response(null, { status: 204 });
    }
    if (url.pathname === "/__test/running") {
      const device = env.DEVICES.get(env.DEVICES.idFromName(q("device")));
      return Response.json(await device.liveRunning(q("code"), Number(q("now"))));
    }
    return worker.fetch(request, env);
  },
};
