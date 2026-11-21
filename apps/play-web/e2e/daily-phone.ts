import { randomBytes, randomUUID } from "node:crypto";

import { expect } from "@playwright/test";
import { greedyMove } from "@pounce/play-api/daily/box-fort/greedy";

import { BASE } from "../playwright.config";

import type { BoxFortPublicState } from "@pounce/play-api/daily/box-fort/module";
import type { BoardAnswer } from "@pounce/play-api/daily/messages";
import type { DailyResult } from "@pounce/play-api/daily/module";

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
  /** Starts today's `game`: its run, public puzzle and public state. */
  begin(game: string): Promise<Begun>;
  /** One batch of the game's own moves from `from`, as the server answers it. */
  send(run: string, from: number, moves: unknown[]): Promise<{ ok: boolean; seq: number; result: DailyResult | null }>;
  giveUp(run: string): Promise<number>;
  /** `GET /v1/daily/board`: tonight's board as this person sees it, `tvs` included. */
  board(): Promise<BoardAnswer>;
};

export type Begun = { run: string; puzzle: unknown; state: unknown; seq: number };

/**
 * A first move each daily game accepts, from its start: Sniff's guess, a digit in Nine Lives' first
 * open cell (a clash is legal), an x on Cat Nap's first cell, and Box Fort's greedy placement.
 */
export function firstMove(game: string, begun: Begun): unknown {
  switch (game) {
    case "sniff":
      return { k: "guess", word: "large" };
    case "nine-lives": {
      const givens = (begun.puzzle as { givens: number[] }).givens;
      return { k: "set", i: givens.indexOf(0), d: 1 };
    }
    case "cat-nap":
      return { k: "mark", cells: [0], to: "x" };
    case "box-fort": {
      const s = begun.state as BoxFortPublicState;
      const move = greedyMove(s.rug, s.pieces, s.placed);
      if (!move) throw new Error("no Box Fort placement");
      return move;
    }
    default:
      throw new Error(`no first move for ${game}`);
  }
}

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
    async begin(game) {
      const res = await call("POST", `/v1/daily/${game}/start${q}`);
      expect(res.status, `${game} is on the server`).toBe(200);
      return (await res.json()) as Begun;
    },
    async send(run, from, moves) {
      const res = await call("POST", `/v1/daily/runs/${run}/moves${q}`, { from, moves });
      expect(res.status).toBe(200);
      return (await res.json()) as { ok: boolean; seq: number; result: DailyResult | null };
    },
    giveUp: async (run) => (await call("POST", `/v1/daily/runs/${run}/giveup${q}`)).status,
    async board() {
      const res = await call("GET", `/v1/daily/board${q}`);
      expect(res.status).toBe(200);
      return (await res.json()) as BoardAnswer;
    },
  };
}
