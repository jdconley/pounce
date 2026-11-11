import { DurableObject } from "cloudflare:workers";

import { lockedUntil, miss, take, type BackoffRule, type Misses, type Window } from "./backoff";

import type { Env } from "../env";

/** Nothing a limiter keeps matters after this long without a call. */
const IDLE_MS = 2 * 60 * 60 * 1000;

/**
 * One instance per limited key (`ip:<address>`, `device:<id>`, `mint:<address>`, ...): its
 * counters live in the object's storage, so a limit holds across the Worker's isolates and
 * restarts. An idle instance deletes itself.
 */
export class Limiter extends DurableObject<Env> {
  /**
   * A guess at a secret (a room code). Locked out: `retryAt`, and nothing is counted. Otherwise
   * a wrong guess (`failed`) is counted and may start a lockout for the next one.
   */
  async guess(failed: boolean, rule: BackoffRule, now: number): Promise<{ retryAt: number | null }> {
    const prior = (await this.ctx.storage.get<Misses>("misses")) ?? null;
    const retryAt = lockedUntil(prior, now);
    if (retryAt !== null) return { retryAt };
    if (failed) {
      await this.ctx.storage.put("misses", miss(prior, now, rule));
      await this.ctx.storage.setAlarm(now + IDLE_MS);
    }
    return { retryAt: null };
  }

  /** One use of something rationed to `max` per `windowMs` under `name`. False: over the limit. */
  async take(name: string, max: number, windowMs: number, now: number): Promise<boolean> {
    const key = `window:${name}`;
    const { window, ok } = take((await this.ctx.storage.get<Window>(key)) ?? null, now, max, windowMs);
    await this.ctx.storage.put(key, window);
    await this.ctx.storage.setAlarm(now + IDLE_MS);
    return ok;
  }

  async alarm(): Promise<void> {
    await this.ctx.storage.deleteAll();
  }
}
