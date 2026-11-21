import { randomBytes, randomUUID } from "node:crypto";

import { expect } from "@playwright/test";

import { BASE } from "../playwright.config";

/**
 * A phone playing the Daily Dish, over plain HTTP (docs/daily-protocol.md): a device of its own,
 * one person on it, and the calls a phone makes to show its board on a TV and play the server's
 * test game ("count to 3 + level", `DAILY_TEST=on`). The TV is what the tests look at.
 */
export type DailyPhone = {
  name: string;
  person: string;
  /** `POST /v1/screens/link` with the TV's backup code, for the board. */
  linkBoard(code: string): Promise<number>;
  /** `DELETE /v1/daily/board/tv`: every TV showing this board forgets it. */
  unlink(): Promise<number>;
  /** Starts today's test game: its run and how far it counts. */
  start(): Promise<{ run: string; target: number }>;
  moves(run: string, from: number, to: number): Promise<{ ok: boolean; result: unknown }>;
  showOnTv(run: string, on: boolean): Promise<number>;
};

let address = 0;

export async function dailyPhone(name: string, cat = 3): Promise<DailyPhone> {
  const ip = `10.250.${Math.floor(++address / 250)}.${(address % 250) + 1}`;
  const minted = await fetch(`${BASE}/v1/devices`, { method: "POST", headers: { "cf-connecting-ip": ip } });
  expect(minted.ok).toBe(true);
  const { token } = (await minted.json()) as { token: string };
  const call = (method: string, path: string, body?: unknown) =>
    fetch(`${BASE}${path}`, {
      method,
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json", "cf-connecting-ip": ip },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
  const person = randomUUID();
  const profile = await call("PUT", "/v1/devices/me/profile", {
    timeZone: "America/Los_Angeles",
    ageBand: "adult",
    people: [{ id: person, name, cat, key: randomBytes(32).toString("base64url") }],
  });
  expect(profile.status).toBe(200);
  const q = `?person=${person}`;
  return {
    name,
    person,
    linkBoard: async (code) => (await call("POST", `/v1/screens/link${q}`, { code, board: true })).status,
    unlink: async () => (await call("DELETE", `/v1/daily/board/tv${q}`)).status,
    async start() {
      const res = await call("POST", `/v1/daily/test/start${q}`);
      expect(res.status, "the server's test game (DAILY=on, DAILY_TEST=on)").toBe(200);
      const body = (await res.json()) as { run: string; puzzle: { target: number } };
      return { run: body.run, target: body.puzzle.target };
    },
    async moves(run, from, to) {
      const moves = Array.from({ length: to - from }, (_, i) => ({ k: "step", n: from + i + 1 }));
      const res = await call("POST", `/v1/daily/runs/${run}/moves${q}`, { from, moves });
      expect(res.status).toBe(200);
      return (await res.json()) as { ok: boolean; result: unknown };
    },
    showOnTv: async (run, on) => (await call("PUT", `/v1/daily/runs/${run}/tv${q}`, { on })).status,
  };
}
