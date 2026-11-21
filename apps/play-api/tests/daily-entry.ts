import { startRun } from "../src/daily/routes";
import worker from "../src/index";
import { addDays } from "../src/streaks/clock";
import { connect } from "../src/streaks/pairs";

import type { DailyGameId } from "../src/daily/module";
import type { Env } from "../src/env";

export { DeviceIndex } from "../src/room/device-index";
export { GameRoom } from "../src/room/game-room";
export { Identities } from "../src/players/identities";
export { Limiter } from "../src/safety/limiter";
export { Reports } from "../src/safety/reports";
export { Player } from "../src/players/player";
export { Links } from "../src/links/links";
export { Pair } from "../src/streaks/pair";
export { ScreenLinks } from "../src/screens/screen-links";
export { DailyPuzzle } from "../src/daily/puzzle-do";
export { DailyRun } from "../src/daily/run-do";
export { BoardTokens } from "../src/daily/board-tokens";

/**
 * The real worker, plus the daily suites' test hooks: `/__test/puzzle?game=&date=` reads a day's
 * puzzle, whole; `/__test/puzzle-warm?game=&date=` runs that puzzle's warm (its alarm's work) and says whether the
 * next date's puzzle is then made; `/__test/start?player=&game=&now=` starts a run at a made-up
 * time; `/__test/run?id=` reads a run as stored; `/__test/connect?a=&b=` pairs two players, as an
 * accepted invite does; `/__test/board?player=&date=&now=` reads a player's board at a made-up now.
 */
export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const game = (url.searchParams.get("game") ?? "") as DailyGameId;
    const date = url.searchParams.get("date") ?? "";
    const puzzle = (d: string) => env.DAILY_PUZZLES.get(env.DAILY_PUZZLES.idFromName(`${game}:${d}`));
    if (url.pathname === "/__test/puzzle") return Response.json(await puzzle(date).get(game, date));
    if (url.pathname === "/__test/puzzle-warm") {
      await puzzle(date).get(game, date);
      await puzzle(date).warm();
      return Response.json({ next: await puzzle(addDays(date, 1)).made() });
    }
    if (url.pathname === "/__test/start") {
      return startRun(env, "test-device", url.searchParams.get("player") ?? "", game, Number(url.searchParams.get("now")));
    }
    if (url.pathname === "/__test/run") {
      return Response.json(await env.DAILY_RUNS.get(env.DAILY_RUNS.idFromName(url.searchParams.get("id") ?? "")).exportState());
    }
    if (url.pathname === "/__test/connect") {
      await connect(env, url.searchParams.get("a") ?? "", url.searchParams.get("b") ?? "", Date.now());
      return new Response(null, { status: 204 });
    }
    if (url.pathname === "/__test/board") {
      const playerId = url.searchParams.get("player") ?? "";
      return Response.json(await env.PLAYERS.get(env.PLAYERS.idFromName(playerId)).board(date, Number(url.searchParams.get("now"))));
    }
    return worker.fetch(request, env, ctx);
  },
};
