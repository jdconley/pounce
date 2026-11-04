import worker from "../src/index";

import type { Env } from "../src/env";
import type { PairState } from "../src/streaks/pair-core";

export { DeviceIndex } from "../src/room/device-index";
export { GameRoom } from "../src/room/game-room";
export { Identities } from "../src/players/identities";
export { Player } from "../src/players/player";
export { Pair } from "../src/streaks/pair";

/**
 * The real worker, plus test hooks on a pair: `/__test/pair` reads its state,
 * `/__test/settle?now=` runs its settlement at a given time, and
 * `/__test/grant?item=` gives it an item with no gift to unwrap.
 */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const stub = () => env.PAIRS.get(env.PAIRS.idFromName(url.searchParams.get("pair") ?? ""));
    if (url.pathname === "/__test/pair") return Response.json(await stub().exportState());
    if (url.pathname === "/__test/settle") {
      await stub().settle(Number(url.searchParams.get("now")));
      return new Response(null, { status: 204 });
    }
    if (url.pathname === "/__test/grant") {
      const state = (await stub().exportState()) as PairState;
      state.owned.push(url.searchParams.get("item") ?? "");
      await stub().replace(state);
      return new Response(null, { status: 204 });
    }
    return worker.fetch(request, env);
  },
};
