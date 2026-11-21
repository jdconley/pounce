import worker from "../src/index";

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

/** The real worker, plus the daily suites' test hooks. */
export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return worker.fetch(request, env, ctx);
  },
};
