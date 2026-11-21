import { DurableObject } from "cloudflare:workers";

import type { Env } from "../env";

/** One player's run at one game on one date, named `${playerId}:${game}:${date}` (spec §3, "A run"). */
export class DailyRun extends DurableObject<Env> {}
