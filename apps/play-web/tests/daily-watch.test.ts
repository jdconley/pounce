import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, test } from "vitest";

import { loadWatch } from "../src/daily/watch";

const SRC = resolve(dirname(fileURLToPath(import.meta.url)), "../src");

/** Every file `file` loads statically (not `import()`, not type-only imports, which the build erases). */
function staticGraph(file: string, seen = new Set<string>()): Set<string> {
  if (seen.has(file)) return seen;
  seen.add(file);
  const text = readFileSync(file, "utf8");
  for (const m of text.matchAll(/^\s*(?:import|export)\s(?!type\s)[^;]*?from\s+"(\.[^"]+)"/gm)) {
    const base = resolve(dirname(file), m[1]!);
    const found = [".tsx", ".ts", "/index.ts"].map((ext) => base + ext).find((p) => {
      try {
        readFileSync(p);
        return true;
      } catch {
        return false;
      }
    });
    if (found) staticGraph(found, seen);
  }
  return seen;
}

describe("a TV's watch views", () => {
  test("load by game, with nothing for a game the web doesn't know", async () => {
    const Watch = await loadWatch("test");
    expect(typeof Watch).toBe("function");
    expect(await loadWatch("not-a-game")).toBeNull();
  });

  test("never pull in a play screen, the host or the Dish", () => {
    const graph = [...staticGraph(resolve(SRC, "daily/watch.tsx"))].map((p) => p.slice(SRC.length + 1));
    for (const heavy of ["daily/play.tsx", "daily/dish.tsx", "daily/test-game.tsx", "daily/client.ts", "daily/dish-store.ts"]) expect(graph).not.toContain(heavy);
  });
});
