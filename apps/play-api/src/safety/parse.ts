import { isGeneratedName, nameAllowed } from "../names/filter";
import { PERSON_ID, sha256Hex } from "../players/ids";
import { parseName } from "../protocol";
import { parseRoomName } from "../room/names";

/** Why a player was reported: what the app's picker offers. */
export const REPORT_REASONS = ["name", "bothering", "other"] as const;
export type ReportReason = (typeof REPORT_REASONS)[number];

type Obj = Record<string, unknown>;

const hasOnly = (o: Obj, keys: string[]) => keys.every((k) => k in o) && Object.keys(o).length === keys.length;

/** A report's body: the person (as the table shows them) and one of the picker's reasons. */
export function parseReport(body: Obj | null): { person: string; reason: ReportReason } | null {
  if (!body || !hasOnly(body, ["person", "reason"])) return null;
  const { person, reason } = body;
  if (typeof person !== "string" || !PERSON_ID.test(person)) return null;
  const known = REPORT_REASONS.find((r) => r === reason);
  return known ? { person: person.toLowerCase(), reason: known } : null;
}

/** A block's body: the person, as the table shows them. */
export function parseBlock(body: Obj | null): { person: string } | null {
  if (!body || !hasOnly(body, ["person"])) return null;
  const { person } = body;
  return typeof person === "string" && PERSON_ID.test(person) ? { person: person.toLowerCase() } : null;
}

/** A name check's body, and the verdict: `bad_name`, or for a kitten `not_allowed`. */
export function checkName(body: Obj | null, kitten: boolean): { ok: true } | { ok: false; reason: "bad_name" | "not_allowed" } | null {
  if (!body || !hasOnly(body, ["kind", "name"])) return null;
  const { kind } = body;
  if (kind !== "person" && kind !== "table") return null;
  const name = kind === "person" ? parseName(body.name) : parseRoomName(body.name);
  if (name === null) return null;
  if (!nameAllowed(name)) return { ok: false, reason: "bad_name" };
  // A kitten types no names (spec §14.1): a person's comes from the dice, a table keeps its own.
  if (kitten && (kind === "table" || !isGeneratedName(name))) return { ok: false, reason: "not_allowed" };
  return { ok: true };
}

/** `Authorization: Bearer <REPORTS_KEY>`, compared by digest so timing tells nothing. */
export async function ownerAsks(header: string | null, key: string | undefined): Promise<boolean> {
  if (!key || !header?.startsWith("Bearer ")) return false;
  const [a, b] = await Promise.all([sha256Hex(header.slice("Bearer ".length).trim()), sha256Hex(key)]);
  return a === b;
}

/** `?after=` for the owner's list: a report id, 0 when absent; null when malformed. */
export function parseAfter(value: string | null): number | null {
  if (value === null) return 0;
  return /^\d{1,15}$/.test(value) ? Number(value) : null;
}
