import worker from "../src/index";
import { GameRoom as Room } from "../src/room/game-room";

import type { Env } from "../src/env";

export { BoardTokens, Consents, DailyPuzzle, DailyRun, DeviceIndex, Identities, KittenIndex, Limiter, Links, Pair, Player, Reports, ScreenLinks } from "../src/index";

/** Everything a room has written down: its key-value entries, and every row of every table it made. */
export type Stored = { kv: [string, unknown][]; sql: Record<string, Record<string, unknown>[]>; alarm: number | null };

/** The real room, plus a way for a test to read back every byte it stored. */
export class GameRoom extends Room {
  async stored(): Promise<Stored> {
    const kv = [...(await this.ctx.storage.list()).entries()];
    const sql: Stored["sql"] = {};
    const tables = this.ctx.storage.sql
      .exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE '_cf_%' AND name NOT LIKE 'sqlite_%'")
      .toArray();
    for (const { name } of tables) sql[name] = this.ctx.storage.sql.exec(`SELECT * FROM "${name}"`).toArray();
    return { kv, sql, alarm: await this.ctx.storage.getAlarm() };
  }
}

/** The real worker, plus `/__test/room-storage?code=`: what that room has stored. */
export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/__test/room-storage") {
      const room = env.ROOMS.get(env.ROOMS.idFromName(url.searchParams.get("code") ?? "")) as unknown as DurableObjectStub<GameRoom>;
      return Response.json(await room.stored());
    }
    return worker.fetch(request, env, ctx);
  },
};
