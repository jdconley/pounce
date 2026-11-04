import { parseName } from "../protocol";
import { ROOM_CODE } from "../room/codes";

import { PERSON_ID, PERSON_KEY } from "./ids";

export type AgeBand = "kitten" | "teen" | "adult";

export type ProfilePerson = { id: string; name: string; cat: number; key: string; ageBand?: AgeBand; at?: number };

/** What a device uploads on launch: its time zone, its owner's age band and the people on it. */
export type Profile = { timeZone: string; ageBand?: AgeBand; people: ProfilePerson[] };

/** One synced value and when it was last written (client ms). */
export type Entry = { v: unknown; at: number };
export type Section = Record<string, Entry>;
export type StatePatch = { settings?: Section; tutorial?: Section; archive?: Section };

const MAX_PEOPLE = 8;
const MAX_CAT = 7;
const MAX_SECTION_KEYS = 64;
const MAX_VALUE_BYTES = 256;
const STATE_KEY = /^[A-Za-z][A-Za-z0-9_.]{0,31}$/;
const AGE_BANDS: readonly unknown[] = ["kitten", "teen", "adult"];
const SECTIONS = ["settings", "tutorial", "archive"] as const;

type Obj = Record<string, unknown>;

const isObj = (v: unknown): v is Obj => typeof v === "object" && v !== null && !Array.isArray(v);

/** True when `o` has every `required` key and no keys beyond `required` + `optional`. */
function hasKeys(o: Obj, required: string[], optional: string[] = []): boolean {
  const keys = Object.keys(o);
  return required.every((k) => keys.includes(k)) && keys.every((k) => required.includes(k) || optional.includes(k));
}

const isInt = (v: unknown, min: number, max = Number.MAX_SAFE_INTEGER): v is number =>
  typeof v === "number" && Number.isInteger(v) && v >= min && v <= max;

const isAgeBand = (v: unknown): v is AgeBand => AGE_BANDS.includes(v);

function isTimeZone(zone: unknown): zone is string {
  if (typeof zone !== "string" || zone.length > 64) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone });
    return true;
  } catch {
    return false;
  }
}

function parseProfilePerson(p: unknown): ProfilePerson | null {
  if (!isObj(p) || !hasKeys(p, ["id", "name", "cat", "key"], ["ageBand", "at"])) return null;
  const { id, cat, key } = p;
  const name = parseName(p.name);
  if (typeof id !== "string" || !PERSON_ID.test(id) || name === null) return null;
  if (!isInt(cat, 0, MAX_CAT) || typeof key !== "string" || !PERSON_KEY.test(key)) return null;
  if ("ageBand" in p && !isAgeBand(p.ageBand)) return null;
  if ("at" in p && !isInt(p.at, 0)) return null;
  return {
    id,
    name,
    cat,
    key,
    ...(isAgeBand(p.ageBand) ? { ageBand: p.ageBand } : {}),
    ...(isInt(p.at, 0) ? { at: p.at } : {}),
  };
}

export function parseProfile(body: unknown): Profile | null {
  if (!isObj(body) || !hasKeys(body, ["timeZone", "people"], ["ageBand"])) return null;
  const { timeZone, people } = body;
  if (!isTimeZone(timeZone)) return null;
  if ("ageBand" in body && !isAgeBand(body.ageBand)) return null;
  if (!Array.isArray(people) || people.length < 1 || people.length > MAX_PEOPLE) return null;
  const parsed = people.map(parseProfilePerson);
  if (parsed.some((p) => p === null)) return null;
  const valid = parsed as ProfilePerson[];
  if (new Set(valid.map((p) => p.id)).size !== valid.length) return null;
  return { timeZone, ...(isAgeBand(body.ageBand) ? { ageBand: body.ageBand } : {}), people: valid };
}

function parseSection(section: unknown, keyOk: (key: string) => boolean): Section | null {
  if (!isObj(section)) return null;
  const entries = Object.entries(section);
  if (entries.length > MAX_SECTION_KEYS) return null;
  const out: Section = {};
  for (const [key, entry] of entries) {
    if (!keyOk(key) || !isObj(entry) || !hasKeys(entry, ["v", "at"]) || !isInt(entry.at, 0)) return null;
    const json = JSON.stringify(entry.v);
    if (json === undefined || new TextEncoder().encode(json).length > MAX_VALUE_BYTES) return null;
    out[key] = { v: entry.v, at: entry.at };
  }
  return out;
}

export function parseStatePatch(body: unknown): StatePatch | null {
  if (!isObj(body) || !hasKeys(body, [], [...SECTIONS])) return null;
  const out: StatePatch = {};
  for (const name of SECTIONS) {
    if (!(name in body)) continue;
    const section = parseSection(body[name], (key) =>
      name === "archive" ? ROOM_CODE.test(key) : STATE_KEY.test(key),
    );
    if (!section) return null;
    out[name] = section;
  }
  return out;
}

export function parseSignIn(body: unknown): { proof: unknown; person: { id: string; key: string } } | null {
  if (!isObj(body) || !hasKeys(body, ["proof", "person"])) return null;
  const { person } = body;
  if (!isObj(person) || !hasKeys(person, ["id", "key"])) return null;
  const { id, key } = person;
  if (typeof id !== "string" || !PERSON_ID.test(id) || typeof key !== "string" || !PERSON_KEY.test(key)) return null;
  return { proof: body.proof, person: { id, key } };
}

export function parseLink(body: unknown): { proof: unknown; confirmMerge: boolean } | null {
  if (!isObj(body) || !hasKeys(body, ["proof"], ["confirmMerge"])) return null;
  if ("confirmMerge" in body && typeof body.confirmMerge !== "boolean") return null;
  return { proof: body.proof, confirmMerge: body.confirmMerge === true };
}
