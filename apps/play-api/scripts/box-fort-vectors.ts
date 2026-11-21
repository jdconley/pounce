/**
 * Writes Box Fort's golden vectors to fixtures/daily/box-fort/ from the TS rules.
 * Run: pnpm --filter @pounce/play-api vectors:box-fort
 * src/daily/box-fort/vectors.test.ts fails while the files and the rules disagree.
 */
import { mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { buildVectors, formatVector } from "../src/daily/box-fort/vectors";

// Run from apps/play-api (pnpm --filter does): the bundle itself lives in node_modules/.cache.
const dir = join(process.cwd(), "fixtures/daily/box-fort");
mkdirSync(dir, { recursive: true });
for (const old of readdirSync(dir)) if (old.endsWith(".json")) rmSync(join(dir, old));
for (const file of buildVectors()) {
  writeFileSync(join(dir, `${file.name}.json`), `${formatVector(file)}\n`);
  console.log(`wrote ${file.name}.json (${file.steps.length} steps)`);
}
