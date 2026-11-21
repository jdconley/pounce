#!/usr/bin/env node
/**
 * Builds Sniff's word lists from SCOWL (see SOURCE.md for the source, its version, checksum and
 * licence). Run it from anywhere:
 *
 *   node apps/play-api/src/daily/sniff/words/build-words.mjs [path/to/scowl/final]
 *
 * With no path it downloads SCOWL 2020.12.07, checks its sha256 and reads it from a temp folder.
 *
 * It writes, next to itself:
 * - allowed.txt and allowed.ts: every five-letter word a player may guess (about eleven thousand).
 *   allowed.ts holds them sorted and joined with no separator, so a client checks a word by binary
 *   search without parsing anything.
 * - answers.txt and answers.ts: the words Sniff may pick as a day's answer (about two thousand),
 *   each with its commonness tier: 1 from SCOWL's level 10, 2 from 20, 3 from 35. Server only.
 * and the app's copy of allowed.txt, apps/play-ios/Pounce/Daily/Sniff/sniff-allowed.txt.
 *
 * Both lists drop offensive and adult words: the server's name filter (src/names/filter.ts) and
 * blocked.rot13.txt (words that filter lets through, written in ROT13 so the repo doesn't spell
 * them out). Answers also drop plurals and verb forms made by adding s or es, past tenses made by
 * adding d or ed, and the hand pass in answers-cut.txt and answers-cut.rot13.txt:
 * words a parent would wince at, or that make a dull or unfair answer.
 */
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { nameAllowed } from "../../../names/filter.ts";

const HERE = dirname(fileURLToPath(import.meta.url));
const IOS_COPY = join(HERE, "../../../../../play-ios/Pounce/Daily/Sniff/sniff-allowed.txt");

const SCOWL_URL = "https://downloads.sourceforge.net/project/wordlist/SCOWL/2020.12.07/scowl-2020.12.07.tar.gz";
const SCOWL_SHA256 = "5587667caa20c4891390c2d42dbb4d5c4c3f41bee77af1457ece3ba23fb859cc";

/** Guesses: every English spelling SCOWL has, up to its level 80 (its "large" size). */
const ALLOWED_LISTS = ["english", "american", "british", "canadian", "australian", "variant_1"];
const ALLOWED_MAX_LEVEL = 80;
/** Answers: American and common spellings at SCOWL's three commonest levels, by tier. */
const ANSWER_LISTS = ["english", "american"];
const ANSWER_TIERS = new Map([
  [10, 1],
  [20, 2],
  [35, 3],
]);
/** A base word for the plural and past-tense rules must be at least this common. */
const BASE_MAX_LEVEL = 50;

async function scowlFinal() {
  if (process.argv[2]) return process.argv[2];
  const dir = mkdtempSync(join(tmpdir(), "scowl-"));
  const res = await fetch(SCOWL_URL);
  if (!res.ok) throw new Error(`download failed: ${res.status}`);
  const bytes = Buffer.from(await res.arrayBuffer());
  const sum = createHash("sha256").update(bytes).digest("hex");
  if (sum !== SCOWL_SHA256) throw new Error(`sha256 mismatch: ${sum}`);
  const tarball = join(dir, "scowl.tar.gz");
  writeFileSync(tarball, bytes);
  execFileSync("tar", ["-xzf", tarball, "-C", dir]);
  return join(dir, "scowl-2020.12.07", "final");
}

/** Words from the given lists at levels up to `max`, each with the lowest level it appears at. */
function read(final, lists, max) {
  const level = new Map();
  for (const file of readdirSync(final)) {
    const m = /^(.+)-words\.(\d+)$/.exec(file);
    if (!m || !lists.includes(m[1]) || Number(m[2]) > max) continue;
    const n = Number(m[2]);
    for (const word of readFileSync(join(final, file), "latin1").split("\n")) {
      const w = word.trim();
      if (!/^[a-z]+$/.test(w)) continue;
      if (!level.has(w) || level.get(w) > n) level.set(w, n);
    }
  }
  return level;
}

const rot13 = (s) => s.replace(/[a-z]/g, (c) => String.fromCharCode(((c.charCodeAt(0) - 97 + 13) % 26) + 97));
const lines = (file) =>
  readFileSync(join(HERE, file), "utf8")
    .split("\n")
    .map((l) => l.replace(/#.*/, "").trim())
    .filter(Boolean);

/** True when `w` is `base` plus s, es, d or ed (or y to ies, ied), for a common enough base. */
function inflected(w, common) {
  const has = (b) => b.length >= 2 && common.has(b);
  if (w.endsWith("ies") && has(w.slice(0, -3) + "y")) return true;
  if (w.endsWith("ied") && has(w.slice(0, -3) + "y")) return true;
  if (w.endsWith("es") && has(w.slice(0, -2))) return true;
  if (w.endsWith("s") && !w.endsWith("ss") && has(w.slice(0, -1))) return true;
  if (w.endsWith("ed") && has(w.slice(0, -2))) return true;
  if (w.endsWith("d") && has(w.slice(0, -1))) return true;
  return false;
}

const final = await scowlFinal();
const blocked = new Set(lines("blocked.rot13.txt").map(rot13));
const cut = new Set([...lines("answers-cut.txt"), ...lines("answers-cut.rot13.txt").map(rot13)]);
const clean = (w) => w.length === 5 && nameAllowed(w) && !blocked.has(w);

const all = read(final, ALLOWED_LISTS, ALLOWED_MAX_LEVEL);
const common = new Set([...read(final, ALLOWED_LISTS, BASE_MAX_LEVEL).keys()]);
const allowed = [...all.keys()].filter(clean).sort();
const allowedSet = new Set(allowed);

const answerLevels = read(final, ANSWER_LISTS, 35);
const answers = [...answerLevels]
  .filter(([w]) => allowedSet.has(w) && !inflected(w, common) && !cut.has(w))
  .map(([w, level]) => [w, ANSWER_TIERS.get(level)])
  .sort(([a], [b]) => (a < b ? -1 : 1));

const header = (what) => `// Generated by build-words.mjs from SCOWL 2020.12.07 (SOURCE.md). Don't edit: ${what}\n`;

writeFileSync(join(HERE, "allowed.txt"), allowed.join("\n") + "\n");
mkdirSync(dirname(IOS_COPY), { recursive: true });
writeFileSync(IOS_COPY, allowed.join("\n") + "\n");
writeFileSync(
  join(HERE, "allowed.ts"),
  header("change the script or its lists and run it again.") +
    "/** Every five-letter word a player may guess, sorted and joined with no separator. Ships to clients. */\n" +
    `export const ALLOWED =\n  ${JSON.stringify(allowed.join(""))};\n`,
);
writeFileSync(join(HERE, "answers.txt"), answers.map(([w, t]) => `${w} ${t}`).join("\n") + "\n");
writeFileSync(
  join(HERE, "answers.ts"),
  header("change the script or its lists and run it again.") +
    "/** Sniff's possible answers with their commonness tier (1 commonest). Server only: never import it from a client. */\n" +
    "export const ANSWERS: readonly (readonly [string, 1 | 2 | 3])[] = [\n" +
    answers.map(([w, t]) => `  ["${w}", ${t}],`).join("\n") +
    "\n];\n",
);

const tiers = [1, 2, 3].map((t) => answers.filter(([, x]) => x === t).length);
console.log(`allowed ${allowed.length}, answers ${answers.length} (tiers ${tiers.join(" / ")})`);
