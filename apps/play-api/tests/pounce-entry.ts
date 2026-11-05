import worker from "../src/index";

import type { Env } from "../src/env";

export { DeviceIndex } from "../src/room/device-index";
export { GameRoom } from "../src/room/game-room";
export { Identities } from "../src/players/identities";
export { Links } from "../src/links/links";
export { Player } from "../src/players/player";
export { Pair } from "../src/streaks/pair";

/**
 * The real worker, plus test hooks: `/__test/pounces?player=` lists a
 * player's pounces, `/__test/remind?player=&now=` runs its alarm pass (which
 * prunes old pounces), `/__test/link?key=&now=` reads the links index and
 * `/__test/links-prune?now=` prunes it.
 */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const q = (k: string) => url.searchParams.get(k) ?? "";
    const player = () => env.PLAYERS.get(env.PLAYERS.idFromName(q("player")));
    const links = () => env.LINKS.get(env.LINKS.idFromName("links"));
    if (url.pathname === "/__test/pounces") return Response.json(await player().pounceRows());
    if (url.pathname === "/__test/remind") {
      await player().remind(Number(q("now")));
      return new Response(null, { status: 204 });
    }
    if (url.pathname === "/__test/link") return Response.json(await links().get(q("key"), Number(q("now")) || Date.now()));
    if (url.pathname === "/__test/links-prune") {
      await links().prune(Number(q("now")));
      return new Response(null, { status: 204 });
    }
    return worker.fetch(request, env);
  },
};
