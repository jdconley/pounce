import { ROOM_CODE } from "../room/codes";
import { PAIR_ID } from "../streaks/pairs";

import type { Answer, Target } from "./limits";

/** `pc_` + 16 random bytes, base64url. */
export const POUNCE_ID = /^pc_[A-Za-z0-9_-]{22}$/;
/** A Messages link token: 16 random bytes, base64url (§12.4). */
export const LINK_TOKEN = /^[A-Za-z0-9_-]{22}$/;

const ANSWERS: readonly unknown[] = ["play", "later", "no"];

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => typeof v === "object" && v !== null && !Array.isArray(v);
const only = (o: Obj, allowed: string[]) => Object.keys(o).every((k) => allowed.includes(k));

function parseTarget(t: unknown): Target | null {
  if (t === "new" || t === "pick") return t;
  if (!isObj(t) || !only(t, ["table"]) || typeof t.table !== "string" || !ROOM_CODE.test(t.table)) return null;
  return { table: t.table };
}

/** `POST /v1/pounces`: `{to?: pairId, target}`. Without `to`, it's a Messages link. */
export function parsePounce(body: unknown): { to: string | null; target: Target } | null {
  if (!isObj(body) || !only(body, ["to", "target"])) return null;
  const target = parseTarget(body.target);
  if (!target) return null;
  if (!("to" in body)) return { to: null, target };
  return typeof body.to === "string" && PAIR_ID.test(body.to) ? { to: body.to, target } : null;
}

/** `POST /v1/pounces/{id}/answer`: `{answer, choice?, link?}`; a choice ("new" or a code) only with "play". */
export function parseAnswer(body: unknown): { answer: Answer; choice: string | null; link: string | null } | null {
  if (!isObj(body) || !only(body, ["answer", "choice", "link"]) || !ANSWERS.includes(body.answer)) return null;
  const answer = body.answer as Answer;
  const { choice, link } = body;
  if (choice !== undefined && (answer !== "play" || typeof choice !== "string" || (choice !== "new" && !ROOM_CODE.test(choice)))) return null;
  if (link !== undefined && (typeof link !== "string" || !LINK_TOKEN.test(link))) return null;
  return { answer, choice: (choice as string | undefined) ?? null, link: (link as string | undefined) ?? null };
}
