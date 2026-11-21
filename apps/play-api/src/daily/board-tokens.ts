import { DurableObject } from "cloudflare:workers";

import type { Env } from "../env";

/** One TV board token, named by the token's SHA-256: whose board it shows, until when (spec §8). */
export class BoardTokens extends DurableObject<Env> {}
