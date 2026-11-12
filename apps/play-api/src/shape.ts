/** Small checks on untyped JSON, shared by the protocol parser and each game's action parser. */

export type Obj = Record<string, unknown>;

export const isObj = (v: unknown): v is Obj =>
  typeof v === "object" && v !== null && !Array.isArray(v);

/** True when `o` has every `required` key and no keys beyond `required` + `optional`. */
export function hasKeys(o: Obj, required: string[], optional: string[] = []): boolean {
  const keys = Object.keys(o);
  return (
    required.every((k) => keys.includes(k)) &&
    keys.every((k) => required.includes(k) || optional.includes(k))
  );
}

export const isInt = (v: unknown, min: number, max = Number.MAX_SAFE_INTEGER): v is number =>
  typeof v === "number" && Number.isInteger(v) && v >= min && v <= max;
