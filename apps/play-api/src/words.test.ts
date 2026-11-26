import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import { describe, expect, it } from "vitest";

/**
 * Toy Tumble is our own game (spec §3): the names of the classic falling-blocks game and of the
 * online battle game it grew from, and the trade words for their pieces, appear in none of its
 * files. The list is kept in ROT13 so this test never spells them.
 */
const ROT13 = ["Grgevf", "GrgevArg", "grgebzvab", "Grgevzvab"];
const rot13 = (s: string): string => s.replace(/[a-z]/gi, (c) => String.fromCharCode(((c.toLowerCase().charCodeAt(0) - 97 + 13) % 26) + (c <= "Z" ? 65 : 97)));
const BANNED = new RegExp(ROT13.map(rot13).join("|"), "i");

const REPO = join(new URL(".", import.meta.url).pathname, "../../..");
const PATHS = [
  "apps/play-api/src/tumble",
  "apps/play-api/src/games/tumble.ts",
  "apps/play-api/fixtures/tumble",
  "apps/play-api/fixtures/protocol/tumble-client-messages.json",
  "apps/play-api/fixtures/protocol/tumble-server-messages.json",
  "apps/play-api/scripts/tumble-vectors.ts",
  "apps/play-api/scripts/tumble-soak.ts",
  "apps/play-api/scripts/tumble-latency.ts",
  "docs/live-protocol.md",
  "docs/superpowers/specs/2026-11-26-toy-tumble-design.md",
  "docs/superpowers/plans/2026-11-26-toy-tumble-server.md",
  "docs/superpowers/plans/2026-11-26-toy-tumble-web.md",
  "docs/superpowers/plans/2026-11-26-toy-tumble-ios-tv.md",
  "docs/perf/toy-tumble-latency.md",
  "apps/play-web/src/tumble",
  "apps/play-ios/PounceKit/Sources/PounceKit/Tumble",
  "apps/play-ios/Pounce/Tumble",
];
/** Names that hold Toy Tumble files anywhere in the iOS app: every file whose name starts with Tumble. */
const IOS_ROOT = "apps/play-ios";

function files(path: string): string[] {
  const full = join(REPO, path);
  if (!existsSync(full)) return [];
  if (statSync(full).isFile()) return [full];
  return readdirSync(full).flatMap((name) => files(join(path, name)));
}

function tumbleNamed(path: string): string[] {
  const full = join(REPO, path);
  if (!existsSync(full) || !statSync(full).isDirectory()) return [];
  return readdirSync(full).flatMap((name) => {
    if (name === "build" || name.startsWith(".")) return [];
    const child = join(path, name);
    if (statSync(join(REPO, child)).isDirectory()) return tumbleNamed(child);
    return name.startsWith("Tumble") ? [join(REPO, child)] : [];
  });
}

describe("Toy Tumble's words", () => {
  it("decodes the list it guards against", () => {
    expect(ROT13.map(rot13).every((w) => w.length > 5)).toBe(true);
  });

  it("never name the other games or their pieces", () => {
    const all = [...new Set([...PATHS.flatMap(files), ...tumbleNamed(IOS_ROOT)])];
    expect(all.length).toBeGreaterThan(10);
    const hits = all.filter((f) => BANNED.test(readFileSync(f, "utf8"))).map((f) => relative(REPO, f));
    expect(hits).toEqual([]);
  });
});
