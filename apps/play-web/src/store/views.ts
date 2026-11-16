/** Which view a table shows, Cards or Table, remembered per table (the newest 30 tables). */
import { store } from "../lib/kv";

export type View = "cards" | "table";

const KEY = "pounce.views";
const KEEP = 30;

function read(): Record<string, View> {
  const kept = store.json<Record<string, View>>(KEY);
  return kept && typeof kept === "object" && !Array.isArray(kept) ? kept : {};
}

export function viewOf(code: string): View {
  return read()[code] === "table" ? "table" : "cards";
}

export function setView(code: string, view: View): void {
  const all = read();
  // Objects keep insertion order: delete then set puts this table last, the newest.
  delete all[code];
  all[code] = view;
  const keys = Object.keys(all);
  for (const old of keys.slice(0, Math.max(0, keys.length - KEEP))) delete all[old];
  store.set(KEY, JSON.stringify(all));
}
