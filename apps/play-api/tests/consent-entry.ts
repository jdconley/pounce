import worker from "../src/index";
import { appStoreNotification } from "../src/kittens/kittens";

import type { Env } from "../src/env";

export { Consents } from "../src/kittens/consents";
export { KittenIndex } from "../src/kittens/kitten-index";
export { DeviceIndex } from "../src/room/device-index";
export { GameRoom } from "../src/room/game-room";
export { Identities } from "../src/players/identities";
export { Links } from "../src/links/links";
export { Player } from "../src/players/player";
export { Pair } from "../src/streaks/pair";

/**
 * The real worker, plus test hooks: `/__test/consent?player=` reads a
 * kitten's record, `/__test/consent-tick?player=&now=` runs its alarm pass at
 * a chosen time, `/__test/consent-resend?player=&parent=&now=` asks for
 * another code at a chosen time (past the 30 s wait), `/__test/tokens?device=` says which push tokens a device
 * holds, `/__test/expire?player=` runs a guest's retention now, and
 * `/__test/appstore` reaches the App Store handler with the fixture root the
 * test sends (production pins only Apple's).
 */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const q = (k: string) => url.searchParams.get(k) ?? "";
    const consents = () => env.CONSENTS.get(env.CONSENTS.idFromName(q("player")));
    if (url.pathname === "/__test/consent") return Response.json(await consents().record());
    if (url.pathname === "/__test/consent-alarm") return Response.json(await consents().alarmAt());
    if (url.pathname === "/__test/consent-tick") {
      await consents().tick(Number(q("now")));
      return new Response(null, { status: 204 });
    }
    if (url.pathname === "/__test/consent-resend") {
      const out = await consents().resendCode(q("parent"), Number(q("now")));
      return Response.json("ok" in out ? { state: out.ok.state } : out);
    }
    if (url.pathname === "/__test/tokens") return Response.json(await env.DEVICES.get(env.DEVICES.idFromName(q("device"))).tokens());
    if (url.pathname === "/__test/expire") {
      await env.PLAYERS.get(env.PLAYERS.idFromName(q("player"))).expire();
      return new Response(null, { status: 204 });
    }
    if (url.pathname === "/__test/appstore") {
      const { roots, body } = (await request.json()) as { roots: string[]; body: unknown };
      return appStoreNotification(env, body, roots, Date.now());
    }
    return worker.fetch(request, env);
  },
};
