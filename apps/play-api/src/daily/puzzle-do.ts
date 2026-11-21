import { DurableObject } from "cloudflare:workers";

import type { Env } from "../env";

/** One day's puzzle for one game, named `${game}:${date}` (spec §3, "Puzzles"). */
export class DailyPuzzle extends DurableObject<Env> {}
