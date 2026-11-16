/**
 * The app's own state: who is on this device, the profile the server knows, and the first-run
 * steps the funnel hears about. One small store; screens re-render when it changes.
 */
import { useEffect, useState } from "preact/hooks";

import { store } from "../lib/env";
import { api } from "../net/api";

import { addOther, everyone, loadPeople, makePerson, profileBody, savePeople, type AgeBand, type LocalPerson, type People } from "./identity";

export type AppState = {
  people: People;
  /** The profile upload's answer: person id to player id. Empty until it lands. */
  players: Record<string, string>;
  /** Where this device first came from, for the funnel (`source`). */
  source: "organic" | "join_link" | "pounce_link" | "paste" | null;
};

const FUNNEL_KEY = "pounce.funnel";
const SOURCE_KEY = "pounce.source";

let state: AppState = {
  people: loadPeople(),
  players: {},
  source: (store.get(SOURCE_KEY) as AppState["source"]) ?? null,
};
const listeners = new Set<() => void>();

export const app = (): AppState => state;

function set(patch: Partial<AppState>): void {
  state = { ...state, ...patch };
  for (const l of [...listeners]) l();
}

export function useApp(): AppState {
  const [, setN] = useState(0);
  useEffect(() => {
    const l = () => setN((n) => n + 1);
    listeners.add(l);
    return () => void listeners.delete(l);
  }, []);
  return state;
}

function setPeople(people: People): void {
  savePeople(people);
  set({ people });
}

/** The first way in this device saw, kept until a better one (an invite beats organic). */
export function noteSource(source: NonNullable<AppState["source"]>): void {
  if (state.source && state.source !== "organic") return;
  store.set(SOURCE_KEY, source);
  set({ source });
}

export function finishAge(band: AgeBand): void {
  setPeople({ ...state.people, band });
  reach("age_done");
}

/** Sets the owner's name and cat (a new owner the first time). */
export async function setOwner(name: string, cat: number): Promise<LocalPerson> {
  const owner = state.people.owner ? { ...state.people.owner, name: name.trim(), cat } : makePerson(name, cat);
  setPeople({ ...state.people, owner });
  reach("named");
  await syncProfile();
  return owner;
}

/** A person added on this device (pass and play). */
export async function addPerson(name: string, cat: number): Promise<LocalPerson> {
  const person = makePerson(name, cat);
  setPeople(addOther(state.people, person));
  await syncProfile();
  return person;
}

export function personById(id: string | undefined): LocalPerson | undefined {
  return everyone(state.people).find((p) => p.id === id);
}

let syncing: Promise<void> | null = null;

/** Tells the server who is on this device (and their age band). Quiet on failure: tried again later. */
export function syncProfile(): Promise<void> {
  if (!state.people.owner || !state.people.band) return Promise.resolve();
  syncing = (async () => {
    try {
      const answer = await api.uploadProfile(profileBody(state.people));
      set({ players: answer.players });
    } catch {
      // Offline or refused: the next launch tries again.
    }
  })();
  return syncing;
}

// Funnel steps (first-run funnel design, Part 3): kept here with when they happened, and sent
// only once the age check is done (nothing goes to the server before it).

type Steps = Record<string, { at: number; sent?: boolean }>;

export function reach(step: string): void {
  const steps = store.json<Steps>(FUNNEL_KEY) ?? {};
  if (steps[step]) return;
  steps[step] = { at: Date.now() };
  store.set(FUNNEL_KEY, JSON.stringify(steps));
  void flushFunnel();
}

let flushing = false;

export async function flushFunnel(): Promise<void> {
  if (flushing || !state.people.band) return;
  const steps = store.json<Steps>(FUNNEL_KEY) ?? {};
  const unsent = Object.entries(steps).filter(([, s]) => !s.sent);
  if (unsent.length === 0) return;
  flushing = true;
  try {
    const now = Date.now();
    const reached = Object.fromEntries(unsent.map(([k, s]) => [k, Math.max(0, Math.round((now - s.at) / 1000))]));
    const locale = navigator.language && /^[a-z]{2,3}(-[A-Z]{2})?$/.test(navigator.language) ? navigator.language : undefined;
    await api.funnel({ reached, ...(state.source ? { source: state.source } : {}), ...(locale ? { locale } : {}) });
    for (const [k] of unsent) steps[k] = { ...steps[k], sent: true };
    store.set(FUNNEL_KEY, JSON.stringify(steps));
  } finally {
    flushing = false;
  }
}

/**
 * Delete my data: every person on this browser is deleted from the server (as the app's
 * Delete my data does), then everything Pounce keeps in the browser goes. False if the server
 * couldn't be reached; nothing is cleared then, so it can be tried again.
 */
export async function deleteMyData(): Promise<boolean> {
  try {
    for (const person of everyone(state.people)) {
      try {
        await api.call("DELETE", `/v1/me?person=${encodeURIComponent(person.id)}`);
      } catch (error) {
        // A person the server never knew (or already deleted) is fine.
        if (!(error instanceof Error && "status" in error && (error as { status: number }).status === 404)) throw error;
      }
    }
  } catch {
    return false;
  }
  for (const key of ["pounce.device", "pounce.people", "pounce.settings", "pounce.tips", "pounce.tables", FUNNEL_KEY, SOURCE_KEY, "pounce.finished"]) store.remove(key);
  return true;
}

/** Tables this device opened, newest first, for Home when the server's list hasn't come yet. */
const TABLES_KEY = "pounce.tables";

export type KnownTable = { code: string; game: string; name?: string; at: number };

export function rememberTable(t: KnownTable): void {
  const list = (store.json<KnownTable[]>(TABLES_KEY) ?? []).filter((x) => x.code !== t.code);
  store.set(TABLES_KEY, JSON.stringify([t, ...list].slice(0, 30)));
}

export function forgetTable(code: string): void {
  const list = (store.json<KnownTable[]>(TABLES_KEY) ?? []).filter((x) => x.code !== code);
  store.set(TABLES_KEY, JSON.stringify(list));
}

export const knownTables = (): KnownTable[] => store.json<KnownTable[]>(TABLES_KEY) ?? [];
