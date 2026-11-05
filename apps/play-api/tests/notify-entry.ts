import worker from "../src/index";

import type { Env } from "../src/env";

export { DeviceIndex } from "../src/room/device-index";
export { GameRoom } from "../src/room/game-room";
export { Identities } from "../src/players/identities";
export { Player } from "../src/players/player";
export { Pair } from "../src/streaks/pair";

/**
 * The real worker, plus test hooks: `/__test/remind?player=&now=` runs a
 * player's reminder pass at a given time, `/__test/settle?pair=&now=` a
 * pair's settlement, `/__test/notify?player=` reads its reminder state.
 */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const q = (k: string) => url.searchParams.get(k) ?? "";
    const player = () => env.PLAYERS.get(env.PLAYERS.idFromName(q("player")));
    if (url.pathname === "/__test/remind") {
      await player().remind(Number(q("now")));
      return new Response(null, { status: 204 });
    }
    if (url.pathname === "/__test/notify") return Response.json(await player().notifyState());
    if (url.pathname === "/__test/settle") {
      await env.PAIRS.get(env.PAIRS.idFromName(q("pair"))).settle(Number(q("now")));
      return new Response(null, { status: 204 });
    }
    return worker.fetch(request, env);
  },
};
