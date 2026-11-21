import type { Env } from "../env";

/** Hands work to the request's `waitUntil`, as `src/index.ts` does. */
export type Later = (work: Promise<unknown>) => void;

/** An authenticated route, the same shape as `src/index.ts`'s. */
export type Route = (request: Request, env: Env, deviceId: string, later: Later) => Promise<Response> | Response;

/** The Daily Dish's authenticated route for this request, or null (a 404). Only while `DAILY` is on. */
export function dailyRoute(method: string, pathname: string): Route | null {
  if (!pathname.startsWith("/v1/daily/")) return null;
  // Each route lands with its handler (server plan Tasks 6, 7 and 10).
  return method === "" ? null : null;
}
