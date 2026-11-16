/**
 * Who plays on this device: the owner, the people added for pass and play, and the owner's age
 * band. Kept in local storage, as iOS keeps them on the phone (`PeopleStore`). Every person has
 * a random key that proves to the server it is the same person next time.
 */
import { GENERATED_NAMES } from "@pounce/play-api/names/filter";

import { store } from "../lib/env";

export type AgeBand = "kitten" | "teen" | "adult";

export type LocalPerson = { id: string; name: string; cat: number; key: string };

export type People = {
  owner: LocalPerson | null;
  /** People added on this device for pass and play. */
  others: LocalPerson[];
  band: AgeBand | null;
};

const PEOPLE_KEY = "pounce.people";
const MAX_OTHERS = 7;

function base64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export const newKey = (): string => base64url(crypto.getRandomValues(new Uint8Array(32)));

export function newPersonId(): string {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

/** A cat-ish name from the app's own list (all a kitten's name may be). */
export function randomName(not?: string): string {
  const pool = GENERATED_NAMES.filter((n) => n !== not);
  return pool[Math.floor(Math.random() * pool.length)] ?? "Mochi";
}

export const randomCat = (): number => Math.floor(Math.random() * 8);

/** The band for a year of birth, as iOS's age check decides it. */
export function bandFor(year: number, now = new Date()): AgeBand {
  // Without a birthday, the younger reading: born this year minus 13 might still be 12.
  const age = now.getFullYear() - year - 1;
  if (age < 13) return "kitten";
  if (age < 18) return "teen";
  return "adult";
}

export function loadPeople(): People {
  const kept = store.json<People>(PEOPLE_KEY);
  if (!kept || typeof kept !== "object") return { owner: null, others: [], band: null };
  return { owner: kept.owner ?? null, others: Array.isArray(kept.others) ? kept.others : [], band: kept.band ?? null };
}

export function savePeople(people: People): void {
  store.set(PEOPLE_KEY, JSON.stringify(people));
}

/** Everyone on this device, owner first. */
export const everyone = (people: People): LocalPerson[] => (people.owner ? [people.owner, ...people.others] : [...people.others]);

export function makePerson(name: string, cat: number): LocalPerson {
  return { id: newPersonId(), name: name.trim(), cat, key: newKey() };
}

export function addOther(people: People, person: LocalPerson): People {
  const others = [...people.others.filter((p) => p.id !== person.id), person].slice(-MAX_OTHERS);
  return { ...people, others };
}

/** The profile the server keeps (`PUT /v1/devices/me/profile`). */
export function profileBody(people: People) {
  const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  return {
    timeZone,
    ...(people.band ? { ageBand: people.band } : {}),
    people: everyone(people).map((p) => ({ id: p.id, name: p.name, cat: p.cat, key: p.key })),
  };
}
