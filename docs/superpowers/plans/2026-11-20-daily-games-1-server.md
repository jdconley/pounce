# Daily Dish, part 1: the server core — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The server referees daily puzzle runs, keeps results and boards, counts daily runs toward streaks, and links a TV to a board. All of it sits behind a `DAILY` flag and uses a test-only game, so the four real games can be built in parallel afterwards.

**Architecture:**
- Pure cores carry the logic, each fully unit-tested:
  - `src/daily/*.ts`: seeds, days, the run referee, the board and stats;
  - the streak changes in `src/streaks/`.
- Thin Durable Objects hold the state:
  - `DailyPuzzle`, one per game and date;
  - `DailyRun`, one per player, game and date;
  - `BoardTokens`, one per TV board token.
- The existing `Player` gains the day's results and the board's sockets.
- Routes live under `/v1/daily/...` in `src/index.ts`'s router.
- **Interface:** a game is a `DailyModule` (Task 3). The game sessions plug theirs into `src/daily/games.ts`.

**Tech Stack:**
- TypeScript on a Cloudflare Worker with SQLite-backed Durable Objects;
- vitest, with Miniflare for the integration tests;
- WebCrypto (HMAC, HKDF);
- xoshiro128** (`src/rules/rng.ts`).

**Spec:** `docs/superpowers/specs/2026-11-20-daily-games-design.md` (read §2, §3, §5, §6, §8 and §11 first).

## Global Constraints

- **`PROTOCOL_VERSION` stays 1.** Everything is additive: new routes, new socket kinds, and new optional fields.
- **The `DAILY` flag.**
  - `dailyOn(env)` is true for "on", "1" or "true", like `tvOn`.
  - While it's off, every `/v1/daily/*` route is a 404. Streaks ignore daily runs, and nothing else changes.
  - It stays **off** in `wrangler.jsonc` (spec §11: "all four at once"). Miniflare tests set it themselves.
- **No route accepts a score, a time, an outcome or a "solved" flag from a client.**
- **The day:** 04:00 to 04:00 in the player's zone (`streaks/clock.ts` `dayKey`).
  - A run closes at the end of its date.
  - A zone change applies to daily puzzles only from the player's next 04:00.
- **The weekday levels:** Mon 1, Tue 2, Wed 3, Thu 4, Fri 5, Sat 6, Sun "7", meaning level 4 but bigger.
- **Seeds:**
  - `HMAC-SHA256(dailyKey, "daily.v1|" + game + "|" + date)`, where `dailyKey` is HKDF-SHA256 over `TOKEN_SECRET`, with an empty salt and info `"pounce daily v1"`.
  - The first 16 bytes become four uint32 words for `createRng`. An all-zero result is replaced by `[1, 0, 0, 0]`.
  - No new secret.
- **Limits:**
  - starts: 30 per device per hour;
  - moves: 20 per second per run, and at most 100 moves per batch;
  - Sniff guesses: at least 500 ms apart (enforced by the game module).
- **Results are kept 120 days.**
- **Coverage:** new `src/daily/**` and the touched `src/streaks/**` and `src/notify/**` hold 100% (`vitest.config.ts` thresholds). The DO glue files are excluded like the existing ones.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. The PR body ends with the Claude Code line.

## Review Focus

1. **A day with only table turns must settle exactly as before.** Run the whole existing `src/streaks` suite unchanged, plus one test per existing day state with no daily runs involved.
2. **A run that is open across 04:00.** It closes as `closed`, never counts toward a streak, and still shows on the board as unsolved (Task 5, `run-core.close`).
3. **A move batch resent after a dropped connection** (the same `from` seq). It must be accepted once and answered with the same state, not refused or applied twice (Task 5).
4. **Two devices of one player starting the same run at once.** They get one run, and the later start returns the earlier start time (Task 6).
5. **A player with no time zone yet.** Days use `FALLBACK_ZONE`, as streaks do (Task 2).

---

### Task 1: The `DAILY` flag, bindings and route skeleton

**Files:**
- Modify: `src/env.ts` (adds `DAILY?: string`, `DAILY_TEST?: string` (Miniflare only), `DAILY_PUZZLES`, `DAILY_RUNS`, `BOARD_TOKENS` and `dailyOn`)
- Modify: `wrangler.jsonc`
  - adds `"DAILY": "off"` with a comment like its neighbors';
  - adds the three bindings;
  - adds migration `{ "tag": "v8", "new_sqlite_classes": ["DailyPuzzle", "DailyRun", "BoardTokens"] }`.
- Modify: `src/index.ts` (exports the new classes; `route(...)` takes `daily: boolean` and tries `dailyRoute(method, pathname)` first when on)
- Create: `src/daily/routes.ts` (`dailyRoute(method, pathname): Route | null`; it returns `null` for everything until Task 6)
- Test: `src/env.test.ts`, `tests/daily.test.ts` (new), `tests/daily-entry.ts` (new; exports the real worker plus DO classes and test hooks, like `tests/streaks-entry.ts`)

**Interfaces:**
- Produces:
  - `dailyOn(env: Pick<Env, "DAILY">): boolean`;
  - `Env.DAILY_PUZZLES: DurableObjectNamespace<DailyPuzzle>`, `Env.DAILY_RUNS: DurableObjectNamespace<DailyRun>` and `Env.BOARD_TOKENS: DurableObjectNamespace<BoardTokens>`;
  - `tests/play-helpers.ts` `worker(script, { daily?: boolean })`.

- [ ] **Step 1: Write the failing tests**
  - `env.test.ts`: `"DAILY is off in wrangler.jsonc"`, which expects `dailyOn({ DAILY: read("DAILY") })` to be `false`.
  - `daily.test.ts`: `"every /v1/daily route is a 404 with DAILY off"` covers `POST /v1/daily/sniff/start`, `POST /v1/daily/runs/x/moves`, `GET /v1/daily/board` and `GET /v1/daily/board/ws`.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run src/env.test.ts tests/daily.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement the flag, the bindings, the migration, and empty DO classes** in `src/daily/puzzle-do.ts`, `src/daily/run-do.ts` and `src/daily/board-tokens.ts`. Wire `route`.
- [ ] **Step 4: Run the same command, then `pnpm --filter @pounce/play-api typecheck`.** Expected: PASS.
- [ ] **Step 5: Commit** with `feat(daily): DAILY flag, bindings and route skeleton`.

### Task 2: Seeds, days, levels and numbers

**Files:**
- Create: `src/daily/seed.ts`, `src/daily/days.ts`
- Test: `src/daily/seed.test.ts`, `src/daily/days.test.ts`

**Interfaces:**
- Consumes: `Seed` and `createRng` from `src/rules/rng.ts`; `dayKey`, `addDays`, `dayEnd`, `dayStart`, `FALLBACK_ZONE` and `Day` from `src/streaks/clock.ts`.
- Produces:
  - `dailySeed(secret: string, game: DailyGameId, date: Day): Promise<Seed>`;
  - `type DayLevel = 1 | 2 | 3 | 4 | 5 | 6 | 7`;
  - `levelFor(date: Day): DayLevel`;
  - `LAUNCH: Day`, a constant that starts as `"2099-01-01"` and is set by the launch PR;
  - `puzzleNumber(date: Day): number`, which is `daysBetween(LAUNCH, date) + 1`;
  - `type DailyZone = { zone: string; since: Day }`;
  - `dailyDay(now: number, zone: DailyZone | null, reported: string | null): { day: Day; zone: DailyZone }`. It returns the day in the locked zone. When `reported` differs, the new zone applies from the next 04:00 of the old zone.
  - `closesAt(date: Day, zone: string): number`, which is `dayEnd(date, zone)`.

- [ ] **Step 1: Write the failing tests**
  - `"seed is stable"`: a fixed secret and `("sniff", "2026-11-23")` give exactly one pinned 4-word array. Write it on the first green run and keep it.
  - `"seeds differ by game and by date"`.
  - `"seeds never repeat over 400 dates × 4 games"`.
  - `"levelFor maps Mon..Sun to 1..7"`, using 2026-11-23 to 2026-11-29.
  - `"puzzleNumber is 1 on LAUNCH"`.
  - `"dailyDay rolls at 04:00 local, DST included"`: America/Los_Angeles on 2026-03-08 and 2026-11-01.
  - `"a zone hop east doesn't open tomorrow early"`: locked LA, reported Pacific/Kiritimati at 20:00 LA, still the LA day.
  - `"the new zone applies after the next 04:00"`.
  - `"no zone uses FALLBACK_ZONE"`.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run src/daily/seed.test.ts src/daily/days.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement both files** (WebCrypto `importKey` / `deriveBits` with HKDF, then `sign` with HMAC).
- [ ] **Step 4: Run the same command.** Expected: PASS, with 100% coverage of both files.
- [ ] **Step 5: Commit** with `feat(daily): seeds, days, levels`.

### Task 3: The game module interface, the registry and a test game

**Files:**
- Create: `src/daily/module.ts`, `src/daily/games.ts`, `src/daily/test-game.ts`
- Test: `src/daily/test-game.test.ts`, `src/daily/games.test.ts`

**Interfaces:**
- Produces the contract every game session implements. It is exact, because four sessions depend on it:

```ts
export type DailyGameId = "nine-lives" | "box-fort" | "sniff" | "cat-nap" | "test";
export type Outcome = "solved" | "missed" | "gaveUp" | "closed" | "done"; // "done": Box Fort's ending
export type DailyResult = {
  game: DailyGameId; date: Day; number: number; outcome: Outcome;
  timeMs: number; hints: number; tooFast: boolean;
  guesses?: number;   // Sniff
  points?: number;    // Box Fort
  progress: number;   // 0..1, how far an unsolved run got
};
export type Applied<S> =
  | { ok: true; state: S; reveal?: unknown; end?: "solved" | "missed" | "done" }
  | { ok: false; reason: "illegal" | "too_soon" | "over" };
export interface DailyModule<P = unknown, S = unknown, M = unknown> {
  id: DailyGameId;
  make(rng: Rng, level: DayLevel): P;            // server only: the whole puzzle, solution included
  publicPuzzle(p: P): unknown;                  // what start returns: never the solution, answer or future sets
  init(p: P): S;
  parseMove(raw: unknown): M | null;            // exact shape or null
  apply(p: P, s: S, m: M, msSinceStart: number): Applied<S>;
  hint(p: P, s: S): Applied<S> | null;          // null: this game has no hints
  progress(p: P, s: S): number;                 // 0..1, spoiler-free
  publicState(p: P, s: S): unknown;             // what a resuming client and a watching TV get
  result(p: P, s: S, outcome: Outcome, timeMs: number, hints: number): Omit<DailyResult, "game" | "date" | "number" | "tooFast">;
  compare(a: DailyResult, b: DailyResult): number; // < 0: a ranks above b
  floorMs: Record<DayLevel, number>;            // faster than this: tooFast
  minMoveGapMs: number;                         // moves closer than this are "too_soon"
}
```

- `games.ts`:
  - `DAILY_GAMES: Partial<Record<DailyGameId, DailyModule>>` holds only `test` here. Each game session adds its own line.
  - `dailyModule(id: string, env: { DAILY_TEST?: string }): DailyModule | null` returns `test` only when `env.DAILY_TEST === "on"`, which only Miniflare sets.
- The test game, "count to N":
  - The puzzle is `{ target: 3 + level }`.
  - A move is `{ k: "step", n }`, where `n` must equal the next number.
  - It ends `solved` at the target.
  - A hint takes one step.
  - `floorMs` is all 0, and `minMoveGapMs` is 0.

- [ ] **Step 1: Write the failing tests**
  - `"test game solves at target"`.
  - `"parseMove rejects extra keys and wrong types"`.
  - `"apply refuses the wrong number as illegal"`.
  - `"dailyModule hides test unless DAILY_TEST"`.
  - `"publicPuzzle carries nothing apply doesn't need"`. It checks the keys are only `target` for the test game, and is the pattern each game copies for its own secret fields.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run src/daily/test-game.test.ts src/daily/games.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement the three files.**
- [ ] **Step 4: Run the same command.** Expected: PASS, with 100% coverage.
- [ ] **Step 5: Commit** with `feat(daily): game module contract and test game`.

### Task 4: `DailyPuzzle`, one puzzle per game and date

**Files:**
- Modify: `src/daily/puzzle-do.ts`
- Test: `tests/daily.test.ts`

**Interfaces:**
- Consumes: `dailySeed`, `levelFor` and `dailyModule`.
- Produces: the `DailyPuzzle` DO, named `${game}:${date}`, with `get(game: DailyGameId, date: Day): Promise<unknown>`. It returns the stored full puzzle `P`, made once with `module.make(createRng(seed), levelFor(date))` and kept in SQLite.
- An alarm at 03:00 UTC makes tomorrow's puzzle in the `DailyPuzzle` for the next date. That's a cache warm only: `get` always makes the puzzle on a miss.

- [ ] **Step 1: Write the failing tests**
  - `"the same game and date give the same puzzle from two isolates"`. Use the hook `/__test/puzzle?game=&date=` in `daily-entry.ts`.
  - `"different dates give different puzzles"`.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run tests/daily.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement the DO** (`blockConcurrencyWhile` on make, like `Pair`).
- [ ] **Step 4: Run the same command.** Expected: PASS.
- [ ] **Step 5: Commit** with `feat(daily): DailyPuzzle`.

### Task 5: The run referee (pure core)

**Files:**
- Create: `src/daily/run-core.ts`
- Test: `src/daily/run-core.test.ts`

**Interfaces:**
- Consumes: `DailyModule`, `DailyResult`, `Outcome` and `closesAt`.
- Produces:

```ts
export type RunState = {
  id: string; playerId: string; game: DailyGameId; date: Day; zone: string;
  startedAt: number; seq: number; state: unknown; hints: number;
  lastMoveAt: number; ended: { outcome: Outcome; at: number } | null;
  result: DailyResult | null; tv: boolean;
  answers: Record<number, Answer>; // the answer for each batch's `from`, so a resend gets the same reply
};
export type Answer =
  | { ok: true; seq: number; reveals: unknown[]; progress: number; result: DailyResult | null }
  | { ok: false; error: "illegal" | "too_soon" | "over" | "stale" | "bad_message"; at: number; seq: number };
export function newRun(m: DailyModule, p: unknown, a: { id: string; playerId: string; game: DailyGameId; date: Day; zone: string; now: number }): RunState;
export function moves(m: DailyModule, p: unknown, r: RunState, from: number, raw: unknown[], now: number): Answer;
export function useHint(m: DailyModule, p: unknown, r: RunState, now: number): Answer;
export function giveUp(m: DailyModule, p: unknown, r: RunState, now: number): Answer;
export function close(m: DailyModule, p: unknown, r: RunState, now: number): DailyResult | null; // at closesAt: outcome "closed"
export function countsForStreak(r: RunState): boolean;
export const HINT_PENALTY_MS = 30_000;
export const MAX_BATCH = 100;
```

- Rules the tests pin:
  - `from` below `seq` returns the stored answer for that `from` when it exists. Otherwise it returns `stale`.
  - `from` above `seq` returns `stale`.
  - A batch is all or nothing: the first illegal move refuses it, and `seq` is unchanged.
  - `timeMs` is `ended.at - startedAt + HINT_PENALTY_MS * hints`.
  - `tooFast` is `timeMs < floorMs[levelFor(date)]`.
  - After `ended`, every call answers `over`.
  - A move at or after `closesAt` closes the run first.
  - A batch over `MAX_BATCH`, or a non-array, is `bad_message`.
  - `giveUp` with no moves ends `gaveUp`, but `countsForStreak(r)` is false.

- [ ] **Step 1: Write the failing tests** (using the test game):
  - `"a full solve gives solved with the server's time"`;
  - `"a resent batch gets the same answer once"`;
  - `"an illegal move refuses the whole batch"`;
  - `"stale from is refused"`;
  - `"a hint adds 30 s and counts"`;
  - `"too fast is kept and marked"`;
  - `"moves after the end answer over"`;
  - `"a move after closesAt closes as closed"`;
  - `"close at day end gives closed with progress"`;
  - `"over 100 moves is bad_message"`;
  - `"countsForStreak: solved, missed, done, gaveUp-with-moves yes; closed and gaveUp-without-moves no"`.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run src/daily/run-core.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement `run-core.ts`.**
- [ ] **Step 4: Run the same command.** Expected: PASS, with 100% coverage.
- [ ] **Step 5: Commit** with `feat(daily): run referee core`.

### Task 6: `DailyRun` and the start, move, hint, give-up and TV routes

**Files:**
- Modify: `src/daily/run-do.ts`, `src/daily/routes.ts`
- Test: `tests/daily.test.ts`

**Interfaces:**
- Consumes: `run-core`, `DailyPuzzle.get`, `dailyDay`, `resolveMe` (`players/accounts.ts`), `Limiter` (`safety/limiter.ts`) and the `Player` zone.
- Produces: the routes. Each takes `?person=` like `/v1/me` routes. A device that doesn't speak for the person gets a 403.

| Route | Body | Answer |
|---|---|---|
| `POST /v1/daily/{game}/start` | none | 200 `{ run, game, date, number, level, startedAt, now, puzzle, state, seq, result, closesAt }`. The same run if it exists (`state` is `publicState`). 404 for an unknown or unlisted game. 429 over the limit. |
| `POST /v1/daily/runs/{run}/moves` | `{ from, moves: [] }` | 200 `Answer`. 404 for someone else's run (never 403, so ids reveal nothing). |
| `POST /v1/daily/runs/{run}/hint` | none | 200 `Answer` |
| `POST /v1/daily/runs/{run}/giveup` | none | 200 `Answer` |
| `PUT /v1/daily/runs/{run}/tv` | `{ on: boolean }` | 204 (watching: Task 10) |

- The `DailyRun` DO:
  - It is named `${playerId}:${game}:${date}`. The run id is that name, HMAC'd with `dailyKey` and base64url-encoded, so ids can't be guessed.
  - An alarm at `closesAt` calls `close`.
  - When a run ends, it calls `Player.recordDaily(result, countsForStreak, endedAt)` (Task 7) with `waitUntil` and one retry, never fatal.
- A 2 KB body cap.
- Moves are limited by `Limiter.take("daily-moves:" + run, 20, 1000)`. Starts are limited by `"daily-start:" + deviceId` (30 per hour).

- [ ] **Step 1: Write the failing tests** (with `DAILY` and `DAILY_TEST` on):
  - `"start then solve, the result is the server's"`;
  - `"a second start returns the same run and startedAt"`;
  - `"two devices of one player get one run"`;
  - `"someone else's run is a 404"`;
  - `"a posted result field is ignored and the run is unchanged"`, which sends `{ from: 0, moves: [], result: {...}, timeMs: 1 }` and expects state unchanged and no result;
  - `"tomorrow can't be started"`, which fakes now as 03:59 local and checks the date is still today;
  - `"a run closes at 04:00 by alarm"`;
  - `"the start limit answers 429"`.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run tests/daily.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement the DO and the routes.**
- [ ] **Step 4: Run the same command.** Expected: PASS.
- [ ] **Step 5: Commit** with `feat(daily): runs and routes`.

### Task 7: Results, the board and stats

**Files:**
- Create: `src/daily/board.ts` (pure)
- Modify: `src/players/player.ts`, which adds a table `daily_results(date TEXT, game TEXT, player_id TEXT, result TEXT, PRIMARY KEY (date, game, player_id))` and `daily_stats(game TEXT PRIMARY KEY, stats TEXT)`, deleted past 120 days by the existing alarm, plus the RPCs below
- Modify: `src/daily/routes.ts`
- Test: `src/daily/board.test.ts`, `tests/daily.test.ts`

**Interfaces:**
- Produces:

```ts
export type BoardRow = { player: string; name: string; cat: number; result: DailyResult | null; playing: { progress: number } | null };
export type GameBoard = { game: DailyGameId; number: number; rows: BoardRow[] }; // played rows only, ranked by module.compare
export type Dish = { rows: { player: string; name: string; cat: number; points: number; crowns: DailyGameId[]; ended: number }[] };
export function rankGame(m: DailyModule, rows: BoardRow[]): BoardRow[];
export function dish(boards: GameBoard[]): Dish; // 3/2/1 per game by rank among played rows, +1 per ended run (outcome != "closed"); ties share; crowns for first; tooFast rows excluded everywhere
export type Stats = { played: number; solved: number; streak: number; best: number; bestTimeMs: number | null; bestPoints: number | null; guesses: number[]; last30: { date: Day; result: DailyResult | null }[] };
export function addToStats(s: Stats | null, r: DailyResult): Stats;
```

- `Player` RPCs:
  - `recordDaily(result, counts, endedAt)` stores its own row, updates stats, and fans the row out to each pair's partner with `receiveDaily(playerId, face, result)`. If `counts`, it also does the streak reporting in Task 8.
  - `receiveDaily(...)` stores the partner's row.
  - `board(date)` returns `{ date, games: GameBoard[], dish: Dish }`.
- Routes:
  - `GET /v1/daily/board?person=&date=`, where the date defaults to the player's day, and only today or the past 120 days are allowed;
  - `GET /v1/daily/stats?person=`.
- Who's on the board: the player plus the people in `pairs`. A pair that is left drops off from the next read.

- [ ] **Step 1: Write the failing tests**
  - Unit:
    - `"rankGame orders by compare and drops tooFast"`;
    - `"dish gives 3/2/1 plus 1 per ended run, shared ties, crowns"`;
    - `"closed runs earn no ended point"`;
    - `"stats streak counts consecutive dates with an ended run"`.
  - Integration:
    - `"a connection's result appears on my board"`;
    - `"someone I'm not paired with never appears"`;
    - `"nobody who hasn't played appears"`;
    - `"results past 120 days are gone"`.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run src/daily/board.test.ts tests/daily.test.ts`. Expected: FAIL.
- [ ] **Step 3: Implement it.**
- [ ] **Step 4: Run the same command.** Expected: PASS.
- [ ] **Step 5: Commit** with `feat(daily): results, board, stats`.

### Task 8: Streaks count daily runs (the reversal)

**Files:**
- Modify: `src/streaks/pair-core.ts`
  - `DayRow` gains `daily: Record<string, number>`;
  - adds `reportDaily(s, playerId, at, now)`;
  - `bothIn` gains the second branch.
- Modify: `src/streaks/pair.ts` (adds `reportDaily(playerId, at, now)` and pushes the views like `report`)
- Modify: `src/streaks/personal.ts` (`recordTurn` is reused; a daily run calls it)
- Modify: `src/players/player.ts` (`recordDaily`, when `counts` and `dailyOn` and `trophyOn`, calls `recordPersonalTurn(endedAt, now)` and each pair's `reportDaily`)
- Test: `src/streaks/pair-core.daily.test.ts` (new), `src/streaks/personal.test.ts`, `tests/daily.test.ts`

**Interfaces:**
- Produces: `reportDaily(s: PairState, playerId: string, at: number, now: number): void`.
  - It credits the streak day of `at` in that person's zone, and only if that day hasn't settled.
  - It increments `turns[playerId]` and `daily[playerId]`.
- The `bothIn` rule (spec §5, "The rule, exactly"):

```text
tableTurns = Σ turns − Σ daily
if tableTurns > 0: today's rule, unchanged (some turn, and every person isIn)
else: every person has daily[p] > 0
```

- [ ] **Step 1: Write the failing tests**
  - `"both play only daily runs: kept"`.
  - `"one plays a daily run, the other nothing: missed (nap used)"`.
  - `"a table turn by Mom, JD never held the move, JD plays Sniff: kept"`.
  - `"a table turn by Mom, no daily runs: identical to before"`, run for each existing day state.
  - `"A holds the move all day and plays Sniff, B nothing: not kept"`.
  - `"a daily run reported after settlement is ignored"`.
  - `"your own streak counts a daily run"`.
  - `"DAILY off: reportDaily is never called"` (integration).
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run src/streaks tests/daily.test.ts`. Expected: the new tests FAIL, and every existing test PASSES.
- [ ] **Step 3: Implement it.** Old saved `DayRow`s have no `daily`; treat a missing one as `{}`.
- [ ] **Step 4: Run** `pnpm --filter @pounce/play-api exec vitest run src/streaks tests/streaks.test.ts tests/daily.test.ts`. Expected: PASS, with `src/streaks/**` at 100%.
- [ ] **Step 5: Commit** with `feat(streaks): a daily run counts as playing today`.

### Task 9: The reminder's Dish case

**Files:**
- Modify: `src/notify/reminders.ts`. `ReminderInput` gains `dishOpen: boolean` (DAILY on, and the player has ended no daily run today). The daily slot may fire when not in today and (`myMove` or `dishOpen`). Backoff counts a day with a daily run as played.
- Modify: the copy table where reminder copy lives (same folder). Adds "Today's Dish is out. {Game} {number} is waiting." with the game name from the first of today's unplayed games in the order Sniff, Nine Lives, Cat Nap, Box Fort.
- Modify: `src/players/player.ts` (fills `dishOpen`)
- Test: `src/notify/reminders.test.ts`

- [ ] **Step 1: Write the failing tests**
  - `"no move waiting but the Dish is open: the daily reminder fires with the Dish copy"`.
  - `"kittens still get nothing"`.
  - `"teens: off by default, nothing 00:00 to 06:00"`.
  - `"a daily run resets backoff"`.
  - `"dishOpen false: exactly today's behavior"`.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run src/notify`. Expected: FAIL.
- [ ] **Step 3: Implement it.**
- [ ] **Step 4: Run the same command.** Expected: PASS, with 100% coverage.
- [ ] **Step 5: Commit** with `feat(notify): the daily reminder knows the Dish`.

### Task 10: The board socket, TV board links and watching

**Files:**
- Modify: `src/screens/screens.ts` and `src/screens/screen-links.ts`. `POST /v1/screens/link` accepts `{ token | code, board: true }` in place of `room`, with `?person=`. The waiting TV is told `{ t: "board", token }`.
- Modify: `src/daily/board-tokens.ts`
  - One instance per `sha256(token)`, holding `{ playerId, expires }` with a 30-day expiry.
  - `resolve(): Promise<string | null>` and `revoke()`.
- Modify: `src/players/player.ts`
  - Hibernatable board sockets, tagged `phone` or `tv`.
  - `pushBoard(kind, payload)` on every result, progress (at most one a second per player) and watch frame.
  - Relays a partner's watch offer to its own `tv` sockets.
- Modify: `src/daily/routes.ts`
  - `GET /v1/daily/board/ws`: a phone with the device token and `?person=`. A TV with `?board=<token>` (browsers use subprotocols, as in `docs/tv-protocol.md`).
  - `DELETE /v1/daily/board/tv?person=` revokes all of that player's board tokens.
- Modify: `src/daily/run-do.ts`. While `tv` is on, each accepted batch sends `watch` frames (`publicState`) to the runner's `Player`, which relays them to its partners' TV sockets and its own. On the end, it sends `watchEnd`.
- Test: `tests/daily-board.test.ts`

**Interfaces:**
- Produces these socket messages from server to client. The exact JSON is written in Task 11's doc.
  - `{ t: "board", board }`
  - `{ t: "result", player, result }`
  - `{ t: "progress", player, game, progress }`
  - `{ t: "watchOffer", player, name, cat, game }`
  - `{ t: "watch", player, game, state }`
  - `{ t: "watchEnd", player, game, result }`
- A TV socket sends only `{ t: "ping" }`. Anything else is `not_allowed`.

- [ ] **Step 1: Write the failing tests**
  - `"a phone links a TV to its board by token and by code"`.
  - `"the TV gets the board snapshot, then live results"`.
  - `"a TV board token lasts 30 days and dies on revoke"`.
  - `"progress messages never carry state"`: deep-check for no `state` and no puzzle keys.
  - `"watch frames go out only after tv: on, and only to TVs whose board includes the player"`.
  - `"a TV socket's other messages are not_allowed"`.
  - `"room links still work unchanged"`: run the existing `tests/screens.test.ts`.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run tests/daily-board.test.ts tests/screens.test.ts`. Expected: the new tests FAIL, and `screens` PASSES.
- [ ] **Step 3: Implement it.**
- [ ] **Step 4: Run the same command.** Expected: PASS.
- [ ] **Step 5: Commit** with `feat(daily): live board, TV board links, watching`.

### Task 11: The wire doc, pinned fixtures, privacy text, and the PR

**Files:**
- Create: `docs/daily-protocol.md`, in the style of `docs/tv-protocol.md`. It covers every route and socket message, with exact JSON, the errors and the limits.
- Create: `apps/play-api/fixtures/daily/protocol/*.json`, samples of each answer and message. The client sessions decode these.
- Modify: `tests/fixtures-pinned.test.ts`, which pins the new files by hash.
- Modify: `apps/play-api/src/http/privacy.ts` and `docs/privacy/retention-policy.md`. They say daily results go only to your connections and a TV linked to your board, and are kept 120 days. `docs/privacy/app-store-label.md` gets one line under Gameplay Content: "daily puzzle runs and results". The data types don't change, so the label test still passes.

- [ ] **Step 1: Write the fixtures from real answers** (a Miniflare test that writes them, then is turned into a test that checks them).
- [ ] **Step 2: Run** `pnpm check` from the repo root. Expected: PASS: lint, typecheck, all tests and coverage.
- [ ] **Step 3: Commit** with `docs(daily): protocol, fixtures, privacy text`.
- [ ] **Step 4: Open the PR** with the title `Daily puzzles: the server side (off until launch)`.
  - The body says what's in it, that `DAILY` is off in production, and the test results.
  - There are no UI changes, so no screenshots.
  - The body ends with the Claude Code line.
