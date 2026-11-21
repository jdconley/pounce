import { startRun } from "../src/daily/routes";
import worker from "../src/index";
import { sha256Hex } from "../src/players/ids";
import { Player as RealPlayer } from "../src/players/player";
import { addDays } from "../src/streaks/clock";
import { connect } from "../src/streaks/pairs";

import type { DailyGameId } from "../src/daily/module";
import type { Env } from "../src/env";

export { DeviceIndex } from "../src/room/device-index";
export { GameRoom } from "../src/room/game-room";
export { Identities } from "../src/players/identities";
export { Limiter } from "../src/safety/limiter";
export { Reports } from "../src/safety/reports";
export { Links } from "../src/links/links";
export { Pair } from "../src/streaks/pair";
export { ScreenLinks } from "../src/screens/screen-links";
export { DailyPuzzle } from "../src/daily/puzzle-do";
export { DailyRun } from "../src/daily/run-do";
export { BoardTokens } from "../src/daily/board-tokens";

/** Reports a player refuses before taking them (`/__test/fail-reports?n=`): a Player that is down. */
let failing = 0;

/** The real Player, which can be made to refuse daily reports for a while. */
export class Player extends RealPlayer {
  override recordDaily(...args: Parameters<RealPlayer["recordDaily"]>): void {
    if (failing > 0) {
      failing -= 1;
      throw new Error("player_down");
    }
    super.recordDaily(...args);
  }

  /** Every player id this player keeps Dish data about (tests). */
  dailyHeld(): string[] {
    const sql = this.ctx.storage.sql;
    return sql
      .exec<{ id: string }>("SELECT player_id AS id FROM daily_results UNION SELECT player_id FROM daily_faces UNION SELECT player_id FROM daily_playing")
      .toArray()
      .map((r) => r.id);
  }
}

/**
 * The real worker, plus the daily suites' test hooks: `/__test/puzzle?game=&date=` reads a day's
 * puzzle, whole; `/__test/puzzle-warm?game=&date=` runs that puzzle's warm (its alarm's work) and says whether the
 * next date's puzzle is then made; `/__test/start?player=&game=&now=` starts a run at a made-up
 * time; `/__test/run?id=` reads a run as stored; `/__test/connect?a=&b=` pairs two players, as an
 * accepted invite does; `/__test/board?player=&date=&now=` reads a player's board at a made-up now;
 * `/__test/record?player=` hands a player a counting result for today, as an ended run would;
 * `/__test/remind?player=&now=` runs a player's reminder pass at a made-up time;
 * `/__test/board-token?token=&device=&now=` asks whose board a TV's token shows, at a made-up time.
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
    if (url.pathname === "/__test/board-token") {
      const hash = await sha256Hex(url.searchParams.get("token") ?? "");
      const found = await env.BOARD_TOKENS.get(env.BOARD_TOKENS.idFromName(hash)).resolve(url.searchParams.get("device") ?? "", Number(url.searchParams.get("now")));
      return Response.json({ player: found });
    }
    if (url.pathname === "/__test/daily-held") {
      const stub = env.PLAYERS.get(env.PLAYERS.idFromName(url.searchParams.get("player") ?? "")) as unknown as { dailyHeld(): Promise<string[]> };
      return Response.json(await stub.dailyHeld());
    }
    if (url.pathname === "/__test/fail-reports") {
      failing = Number(url.searchParams.get("n"));
      return new Response(null, { status: 204 });
    }
    if (url.pathname === "/__test/remind") {
      await env.PLAYERS.get(env.PLAYERS.idFromName(url.searchParams.get("player") ?? "")).remind(Number(url.searchParams.get("now")));
      return new Response(null, { status: 204 });
    }
    if (url.pathname === "/__test/record") {
      const now = Date.now();
      const playerId = url.searchParams.get("player") ?? "";
      const stub = env.PLAYERS.get(env.PLAYERS.idFromName(playerId));
      const day = (await stub.dailyDay(now))?.day ?? "";
      const result = { game: "test", date: day, number: 1, outcome: "solved", timeMs: 60_000, hints: 0, tooFast: false, progress: 1 } as const;
      await stub.recordDaily(result, true, now);
      return new Response(null, { status: 204 });
    }
    return worker.fetch(request, env, ctx);
  },
};
