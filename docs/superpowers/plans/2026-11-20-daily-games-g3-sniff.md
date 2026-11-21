# Daily Dish, G3: Sniff, the five-letter word puzzle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sniff, the Daily Dish's word puzzle: our own word lists, the server's marking rule and
daily answer, its `DailyModule`, golden vectors, the Swift guess check and keyboard state, and the
play and watch views on iOS and the web. Phase A ends with the views driven by local state; phase B
plugs them into the H1 and H2 hosts.

**Architecture:**
- **Words** are built once by a committed Node script from SCOWL (MIT-style licence, public-domain
  sources) and committed as text and TS. The answer list lives only in `apps/play-api`. The allowed
  list ships to clients as one sorted string, checked by binary search, so nothing is parsed.
- **Marks are worked out only on the server** (`marks.ts`). Clients get them as `reveal`s and only
  derive the keyboard's state from them.
- **The daily answer** comes from one of three pools (by commonness and repeated letters), picked by
  the weekday. Each pool is shuffled per cycle with a secret key that doesn't change by date, so no
  word repeats until its pool is used up.
- **Views** draw from one value, the board (guesses with marks, the draft row, a pending guess).
  The play view adds its own keyboard; the watch view draws the same trail read-only.

**Tech Stack:** TypeScript (Worker, vitest), Node ESM script, Swift 6 (PounceKit, SwiftUI),
Preact (play-web), Playwright and XCUITest in phase B.

**Spec:** `docs/superpowers/specs/2026-11-20-daily-games-design.md` (§1 Sniff, §2 levels, §3
seeds and Sniff's answer, §4 words, §6 progress, §8 watch, §12). Map:
`docs/superpowers/plans/2026-11-20-daily-games.md`. Contract: server plan Task 3 (`DailyModule`).

## Global Constraints

- Own only: `apps/play-api/src/daily/sniff/` (with `words/`), `apps/play-api/fixtures/daily/sniff/`,
  `PounceKit/Sources/PounceKit/Daily/Sniff/` and its tests (`PounceKitTests/Daily/Sniff*`),
  `Pounce/Daily/Sniff/`, `apps/play-web/src/daily/sniff/` and `apps/play-web/tests/daily-sniff*`.
  Phase B adds one line to each registry.
- Until S1 merges, the contract types live in `apps/play-api/src/daily/sniff/contract.ts`, copied
  exactly from Task 3; phase B deletes it and imports `../module` and `../days`.
- Nothing taken from Wordle, the NYT or any other game: no word lists, colors, sounds or layouts.
  Marks are a filled paw (right spot), an outlined paw (elsewhere) and plain (not in the word), in
  Pounce's palette: magenta `#FF2E9A` with a filled paw, sky `#2EB8FF` with an outlined paw, and a
  plain panel `#3B1580`. Never green, yellow or gray.
- The answer list never ships to a client: no client-facing module may import `words/answers.ts`
  or `module.ts`.
- Guesses: at most 6, at least 500 ms apart, each in the allowed list. An unknown word shakes, isn't
  counted and isn't sent.
- The main thread draws only: on iOS the allowed list is read with `Disk.resource` (async, IO
  layer); on the web it is a lazily imported module. Checking a word is a binary search, under
  0.1 ms.
- UI copy: one to three words on buttons, no emoji, plain words. Teach with tips, not text.
- Ports: local dev server 8804 only. Own simulator, shut down after.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Repeated letters.** A guess with a letter twice against an answer with it once (and the
   reverse), with the right spot later in the word than the elsewhere copy. Pinned in Task 3's
   hand-written vectors.
2. **A resent or late guess.** A seventh guess, a guess after a solve, and a guess under 500 ms
   after the last all answer without changing the state (Task 4).
3. **Case and junk in a move.** `"PLANT"`, `"plan"`, `"pl@nt"`, extra keys: refused as
   `parseMove` null, never a crash (Task 4).
4. **The answer leaking.** `publicPuzzle`, `publicState` before the end, `progress` and the reveal
   of a non-final guess never carry the answer (Task 4); no client file imports the answer list
   (Task 2).
5. **Largest text and iPhone SE.** Six rows, the draft and a three-row keyboard fit without
   clipping at AX5 on an SE; tags shrink, keys never go under 44 pt tall (Task 7).

---

### Task 1: Word lists and their build script

**Files:**
- Create: `apps/play-api/src/daily/sniff/words/build-words.mjs`
- Create: `apps/play-api/src/daily/sniff/words/SOURCE.md` (source, version, sha256, licence text)
- Create: `apps/play-api/src/daily/sniff/words/blocked.rot13.txt` (offensive and adult words, ROT13 so
  the repo doesn't spell them out), `answers-cut.txt` (the hand pass: words left out of answers)
- Generated: `words/allowed.txt` (one word a line), `words/allowed.ts` (`export const ALLOWED: string`,
  the sorted words joined with no separator), `words/answers.txt` (`word tier` a line),
  `words/answers.ts` (`export const ANSWERS: readonly (readonly [string, 1 | 2 | 3])[]`), and the iOS
  copy `apps/play-ios/Pounce/Daily/Sniff/sniff-allowed.txt` (same bytes as `allowed.txt`)
- Test: `apps/play-api/src/daily/sniff/words/words.test.ts`

**Interfaces:**
- Produces: `ALLOWED` and `ANSWERS` as above.
- The script: `node build-words.mjs <scowl-final-dir>`. With no argument it downloads
  `scowl-2020.12.07.tar.gz` into a temp directory, checks sha256
  `5587667caa20c4891390c2d42dbb4d5c4c3f41bee77af1457ece3ba23fb859cc` and extracts it.
- Rules:
  - **Allowed:** every `^[a-z]{5}$` line in `{english,american,british,canadian,australian}` and
    `variant_1` `-words.{10..80}` (ISO-8859-1), minus `blocked`.
  - **Answers:** the same from levels 10, 20 and 35, tier 1, 2 and 3 by level, minus:
    - plurals and verb forms made by adding s or es to a word in the allowed list;
    - past tenses made by adding d or ed to a word in the allowed list;
    - `blocked` and `answers-cut.txt`.

- [ ] **Step 1: Write the failing tests** in `words.test.ts`:
  - `"allowed is about ten thousand sorted five-letter words"`: 9000 to 12000, `/^[a-z]{5}$/`,
    strictly ascending, and `ALLOWED === allowed.txt` joined.
  - `"answers are about two thousand, all allowed, all tiers present"`: 1800 to 2600.
  - `"no answer is a plural made by adding s"`: for each answer ending in `s`, `answer.slice(0, 4)`
    is not allowed.
  - `"no blocked word anywhere"`: decode `blocked.rot13.txt`, none in allowed or answers.
  - `"the iOS copy matches"`: `sniff-allowed.txt` equals `allowed.txt`.
  - `"client files never import the answers"`: `allowed.ts`, `keyboard.ts` and `types.ts` import no
    `answers` or `module`.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run src/daily/sniff/words`.
  Expected: FAIL (no files).
- [ ] **Step 3: Write the script, the blocklist and SOURCE.md; run it; do the hand pass** over the
  answers (adds to `answers-cut.txt` until nothing a parent would wince at is left), rerun.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(sniff): our own word lists, built from SCOWL`.

### Task 2: Types, the allowed check and the keyboard state (client-safe)

**Files:**
- Create: `apps/play-api/src/daily/sniff/types.ts`, `allowed-check.ts`, `keyboard.ts`
- Test: `apps/play-api/src/daily/sniff/keyboard.test.ts`, `allowed-check.test.ts`

**Interfaces:**
- `type Mark = "spot" | "near" | "none"`; `type Guess = { word: string; marks: Mark[] }`;
  `type SniffMove = { k: "guess"; word: string }`; `type SniffPublic = { letters: 5; tries: 6 }`;
  `type SniffView = { guesses: Guess[]; answer?: string }` (the answer only once the run ended).
- `isAllowed(word: string, allowed?: string): boolean`: binary search at stride 5 over `ALLOWED`.
- `keyboardMarks(guesses: readonly Guess[]): Partial<Record<string, Mark>>`: best mark per letter,
  `spot` over `near` over `none`.

- [ ] **Step 1: Failing tests:** `"every allowed word passes and its neighbours don't"` (for 200
  words: the word passes, the word with its last letter bumped passes only if listed),
  `"uppercase and wrong length fail"`, `"keyboard keeps the best mark"` (`a` near then spot is spot;
  spot then none stays spot).
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run src/daily/sniff`. FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** PASS, 100% coverage of the three files.
- [ ] **Step 5: Commit** `feat(sniff): allowed check and keyboard state`.

### Task 3: The marking rule and its golden vectors

**Files:**
- Create: `apps/play-api/src/daily/sniff/marks.ts`
- Create: `apps/play-api/fixtures/daily/sniff/marks.json`, hand-written:
  `[{ "name", "answer", "guess", "marks": ["spot"|"near"|"none" x5] }]`
- Test: `apps/play-api/src/daily/sniff/marks.test.ts`

**Interfaces:** `markGuess(answer: string, guess: string): Mark[]`. Spots first; then left to right,
a letter is `near` while the answer still has unmatched copies of it, else `none`.

- [ ] **Step 1: Write `marks.json` by hand** with at least these: all spot; all none; a guess with
  a letter twice and the answer once, elsewhere then right spot (`"spool"` vs `"polka"`... chosen so
  the right-spot copy is the later one, and the earlier copy must be `none`); the answer twice and
  the guess once; both twice in swapped spots; three of a letter in the guess against two; a letter
  right-spot plus an extra elsewhere copy. Each derived by hand, with the reasoning in `name`.
- [ ] **Step 2: Failing test:** `"every vector marks as written"` reads the JSON by path.
- [ ] **Step 3: Run** `pnpm --filter @pounce/play-api exec vitest run src/daily/sniff/marks`. FAIL.
- [ ] **Step 4: Implement `markGuess`.** Run: PASS, 100% coverage.
- [ ] **Step 5: Commit** `feat(sniff): the marking rule, pinned by hand-written vectors`.

### Task 4: The daily answer and the module

**Files:**
- Create: `apps/play-api/src/daily/sniff/contract.ts` (Task 3's types, `DayLevel`, `Day`, plus the
  approved `make(rng, level, day: { date: Day; key: Seed })`)
- Create: `apps/play-api/src/daily/sniff/answer.ts`, `module.ts`
- Create: `apps/play-api/fixtures/daily/sniff/runs.json` (written by the test with
  `UPDATE_SNIFF_VECTORS=1`, then checked)
- Test: `answer.test.ts`, `module.test.ts`

**Interfaces:**
- `type Pool = "easy" | "mid" | "hard"`; `poolFor(level: DayLevel): Pool`: levels 1 and 2 easy,
  3, 4 and 7 mid, 5 and 6 hard. `POOLS: Record<Pool, readonly string[]>`: easy is tier 1 with no
  repeated letter, mid is tier 2 with none, hard is tier 3 and every word with a repeated letter.
- `poolDay(date: Day, pool: Pool): number`: how many dates from `SNIFF_EPOCH = "2026-01-05"` (a
  Monday) up to, not including, `date` use `pool`.
- `answerFor(key: Seed, date: Day): string`: pool `p` of the date's level; `i = poolDay`;
  `cycle = floor(i / n)`; the word at `i mod n` of `shuffle(POOLS[p], createRng(cycleSeed(key, p,
  cycle)))`, where `cycleSeed` mixes the key words with the pool and cycle through a 32-bit finaliser
  and is never all zero.
- `pickAnswer(rng: Rng, level: DayLevel): string`: the fallback when no `day` is given.
- `SniffPuzzle = { answer: string; level: DayLevel }`; `SniffState = { guesses: Guess[]; lastMs:
  number | null }`.
- `sniff: DailyModule<SniffPuzzle, SniffState, SniffMove>`:
  - `publicPuzzle` → `{ letters: 5, tries: 6 }`; `init` → no guesses.
  - `parseMove`: exactly `{ k: "guess", word }`, word `^[a-z]{5}$`, else null.
  - `apply`: over (6 used or solved) → `over`; under 500 ms since `lastMs` → `too_soon`; not
    allowed → `illegal`; else marks, `reveal: { word, marks }` plus `answer` when it ends, `end`
    `solved` (all spot) or `missed` (sixth).
  - `hint` → null; `progress` → guesses used / 6; `publicState` → `SniffView`, with the answer
    only once solved or missed.
  - `result`: `guesses` used, `progress` 1 when solved, else the best guess's spots / 5.
  - `compare`: solved before not; then fewer guesses; then progress (higher first); then time.
  - `floorMs`: 5000 for every level; `minMoveGapMs`: 500.

- [ ] **Step 1: Failing tests** (`answer.test.ts`):
  - `"the same key and date give the same answer"`; `"no word repeats within a pool's cycle"`
    (walk every easy date of one cycle: all distinct, and together exactly the easy pool);
  - `"each weekday uses its pool"` (2026-11-23 to 29); `"poolDay counts across weeks"`;
  - `"different keys give different orders"`; `"pickAnswer stays in the level's pool"`;
  - `"a year of dates: every answer allowed and in its pool"`.
- [ ] **Step 2: Failing tests** (`module.test.ts`), with a fixed answer `"plant"`:
  - `"a solve in three"`: reveals, `end: "solved"`, result `guesses: 3`;
  - `"six misses end missed and reveal the answer only then"`;
  - `"a seventh guess and a guess after a solve are over"`;
  - `"a guess 499 ms after the last is too_soon, 500 is fine"`;
  - `"an unknown word is illegal and changes nothing"`;
  - `"parseMove refuses uppercase, short, junk and extra keys"`;
  - `"publicPuzzle and publicState before the end hold no answer"` (deep search for `"plant"`);
  - `"compare: solved in 3 beats solved in 4 beats missed; time breaks ties"`;
  - `"make uses the day when given, the rng when not"`;
  - `"runs.json replays"`: each vector's moves through `apply` give its recorded answers.
- [ ] **Step 3: Run** `pnpm --filter @pounce/play-api exec vitest run src/daily/sniff`. FAIL.
- [ ] **Step 4: Implement `answer.ts`, `module.ts`; write `runs.json` once with the update flag.**
- [ ] **Step 5: Run** the folder, then `pnpm --filter @pounce/play-api typecheck` and `lint`. PASS,
  100% coverage of `src/daily/sniff/*.ts`.
- [ ] **Step 6: Commit** `feat(sniff): daily answer and the server module`.

### Task 5: Swift: the allowed check, the board model and keyboard state

**Files:**
- Create: `PounceKit/Sources/PounceKit/Daily/Sniff/SniffWords.swift`, `SniffBoard.swift`,
  `SniffDemo.swift`
- Test: `PounceKit/Tests/PounceKitTests/Daily/SniffTests.swift`

**Interfaces:**
- `public struct SniffWords: Sendable { init(data: Data); func allows(_ word: String) -> Bool;
  static func load(bundle: Bundle) async -> SniffWords? }` (stride-6 binary search over the
  newline-separated bytes; `load` uses `Disk.resource("sniff-allowed", ofType: "txt")`).
- `public enum SniffMark: String, Codable, Sendable { case spot, near, none }`;
  `public struct SniffGuess: Codable, Sendable, Equatable { word: String; marks: [SniffMark] }`.
- `public struct SniffBoard: Sendable, Equatable`: `guesses`, `draft: String`, `pending: String?`,
  `answer: String?`; `type(_ letter: Character)`, `delete()`, `submit(words:) -> SniffSubmit`
  (`.send(String)`, `.short`, `.unknown`, `.busy`, `.over`), `apply(_ reveal: SniffGuess, answer:
  String?)`, `keyboard: [Character: SniffMark]`, `isOver`.
- `SniffDemo.reveals: [String: SniffGuess]`: the demo referee's canned reveals, the words of
  `runs.json`'s first vector.

- [ ] **Step 1: Failing tests:** `"every allowed word passes"` (reads `allowed.txt` by path),
  `"the app's copy is the server's"` (`sniff-allowed.txt` bytes equal), `"non-words and caps fail"`,
  `"keyboard keeps the best mark"` (from `marks.json`), `"typing stops at five, delete stops at
  zero"`, `"submit: short, unknown, send; busy while pending; over after six"`, `"demo reveals match
  runs.json"`.
- [ ] **Step 2: Run** `cd apps/play-ios/PounceKit && swift test --filter Sniff`. FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** PASS; `swift apps/play-ios/scripts/main-thread-lint.swift` passes.
- [ ] **Step 5: Commit** `feat(sniff): allowed check and board model in PounceKit`.

### Task 6: Web views

**Files:**
- Create: `apps/play-web/src/daily/sniff/board.ts` (the same board model as Swift, over the TS
  `isAllowed` and `keyboardMarks`), `trail.tsx` (the six rows of scent tags, shared),
  `sniff.tsx` (`SniffPlay`: trail, draft, keyboard, hardware keys), `watch.tsx` (`SniffWatch`),
  `keys.tsx`, `sniff.css`, `demo.html` + `demo.tsx` (a dev page on the demo referee)
- Test: `apps/play-web/tests/daily-sniff.test.ts`

**Interfaces:** `SniffPlay({ view: SniffView, onGuess: (word) => Promise<{ reveal: Guess; answer?: string } | { refused: string }> })`;
`SniffWatch({ view: SniffView })`. Phase B wraps these in H2's `DailyGameScreen` / `DailyWatchView`.

- [ ] **Step 1: Failing tests:** the board model's typing, submit and keyboard cases (as Task 5);
  `"the trail renders marks as shapes"` (happy-dom: a spot tag has `data-mark="spot"` and a filled
  paw, a near tag an outlined paw, a none tag no paw); `"no import of answers"`.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-web exec vitest run tests/daily-sniff.test.ts`. FAIL.
- [ ] **Step 3: Implement.** Shake with `element.animate`, no timers; the allowed list by
  `import()`.
- [ ] **Step 4: Run tests, typecheck and lint.** PASS. Screenshot `demo.html` at 375 and 1280 wide.
- [ ] **Step 5: Commit** `feat(sniff): web play and watch views`.

### Task 7: iOS views

**Files:**
- Create: `Pounce/Daily/Sniff/SniffTrail.swift` (shared drawing: `ScentTag`, `PawMark`, rows),
  `SniffPlayView.swift` (trail, draft, `SniffKeyboard`), `SniffWatchView.swift`,
  `SniffDemoView.swift` (DEBUG, `-demo sniff`, local state and `SniffDemo` referee)

- [ ] **Step 1:** Build and run `-demo sniff` on an iPhone SE and a Pro Max simulator of my own,
  iPad both ways, AX5. Fix every clip and collision.
- [ ] **Step 2:** Screenshots into the notes folder; main-thread lint passes.
- [ ] **Step 3: Commit** `feat(sniff): iOS play and watch views`.

### Task 8: Report phase A and wait

- [ ] Send the lead what's done, the contract question's state, and the give-up gap (below).

### Phase B (after the lead's message)

- Rebase on `origin/main`; delete `contract.ts` and import `../module`, `../days`; add the line to
  `src/daily/games.ts`, Swift `DailyCatalog`, the web registry.
- Wrap the views in `DailyGameView` / `DailyWatchView` and `DailyGameScreen` / `DailyWatchView`.
- iPhone UI test and Playwright test that play to the end against `wrangler dev --port 8804` with
  `DAILY=on`; frame gates; screenshots on every size; the PR "Sniff: the daily word puzzle".

## Open with the lead

- Settled 2026-11-20: `make(rng, level, day: { date, key })`, `day` required, `key` from S1's
  `cycleKey(secret, game)`. `pickAnswer` (the no-day fallback) is gone.
- `publicState(p, s)` can't tell a run ended by give up or 04:00, so it can't show the answer then.
  The host may need the answer on those ends.
