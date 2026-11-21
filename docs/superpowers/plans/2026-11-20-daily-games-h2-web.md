# H2: the Daily Dish in the web player — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the Daily Dish at `play.conleychaos.com/play`: Home redesigned around it, the Dish screen
(cards, board, stats, Show board on TV), the puzzle host every game plugs into, the share card, a
first-visit tip, all hidden while the server's `DAILY` flag is off.

**Architecture:** one IO layer per concern in `src/daily/` (the run session, the board socket, the
Dish store), screens that only read memory and hand changes to that layer, and the share card drawn
in a Web Worker on `OffscreenCanvas`. Games plug in through `host.tsx` and a one-line registry; the
server's test game (`DAILY_TEST=on`) plays the host end to end in Playwright.

**Tech Stack:** Preact 11, Vite 8, Vitest + happy-dom, Playwright against `wrangler dev` on :8807.

**Spec:** `docs/superpowers/specs/2026-11-20-daily-games-design.md` (§6, §7, §8 phone side, §9,
§10), map `docs/superpowers/plans/2026-11-20-daily-games.md`, wire `docs/daily-protocol.md` with
fixtures in `apps/play-api/fixtures/daily/protocol/`.

## Global Constraints

- `PROTOCOL_VERSION` stays 1. The Dish is hidden while `GET /v1/daily/board` answers 404.
- Main thread draws only (`docs/main-thread.md`): no timers in screen code (`src/ui`, and the
  Dish's screens), no storage outside `lib/kv.ts`, image encode in a worker; frame gates hold at
  phone (4x slower, 16.7 ms p95) and laptop (8.3 ms p95).
- UI words: buttons one to three words, messages one short sentence, no emoji, plain words.
- Kittens (`people.band === "kitten"`) get no share.
- Redesign Home as a whole screen; screenshots of every changed screen on iPhone SE, a large
  phone, iPad portrait and landscape, and the largest text size.
- Never ports 8787 or 4343; my dev server is 8807. Own only H2's files (map plan row H2), plus
  the one-line hook-ups in `app.tsx`, `lib/router.ts`, `ui/tv-link.tsx`, `playwright.config.ts`,
  `eslint.main-thread.mjs` and `e2e/main-thread.spec.ts`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A dropped connection mid-run:** the batch in flight is resent with the same `from`; nothing is
   lost or applied twice; the clock keeps counting. (Task 1 test "resends the same from".)
2. **A run resumed on another device or after a reload:** start returns the state and `seq`; the
   next batch starts at that `seq`; an ended run opens straight to the end screen. (Task 1, Task 5.)
3. **The Dish turned off (404) or the network down at Home:** Home shows no Dish and no error; it
   reappears when the board loads. (Task 3 test "off on 404".)
4. **Long names and big numbers** on the board and the cards (12-character names, 59:59 times,
   9,999 points): no clipping at iPhone SE and largest text. (Task 4/6 screenshots, CSS ellipsis.)
5. **Double taps:** Give up, Hint and Show board on TV fire once while their call is out. (Task 5
   e2e taps Give up twice; Task 4 sheet uses a `working` ref like `show-on-tv.tsx`.)

## File structure (all under `apps/play-web/`)

| File | Responsibility |
|---|---|
| `src/daily/host.tsx` | The contract (done, dfd9955). |
| `src/daily/client.ts` | `RunSession` (done) + `Run` implementation, `startRun`, and the Dish's HTTP calls. |
| `src/daily/board-socket.ts` | The board socket: subprotocols, ping, backoff, unknown kinds skipped. |
| `src/daily/dish-store.ts` | Availability, board, stats, tvs; one socket while any Dish screen is up. |
| `src/daily/format.ts` | Result words, clock text, share text. Pure. |
| `src/daily/registry.ts` | One line per game (done). |
| `src/daily/test-game.tsx` | The server's test game screen (done). |
| `src/daily/dish.tsx` | The Dish screen: cards, board, stats, Show board on TV. |
| `src/daily/board.tsx` | The board view: overall and a tab per game. |
| `src/daily/stats.tsx` | One game's stats sheet. |
| `src/daily/play.tsx` | The puzzle host screen: bar, clock, Show on TV, give up, end screen. |
| `src/daily/share.ts` + `src/workers/share-card.worker.ts` | The share card (worker) and Web Share / copy. |
| `src/daily/dish-home.tsx` | Home's Today strip. |
| `src/daily/daily.css` | The Dish's styles. |
| `src/ui/home.tsx` | Home redesigned with the Today strip. |
| `tests/daily-*.test.ts` | Unit tests. |
| `e2e/daily.spec.ts` | The test game end to end; board, stats, share, TV link. |

---

### Task 1: The run session

**Files:** Modify `src/daily/client.ts`; Test `tests/daily-client.test.ts`.

**Interfaces:**
- Produces: `class Run<P,S,M,R> implements RunSession<P,S,M,R>` with
  `constructor(start: StartAnswer<P,S>, deps: RunDeps)`;
  `type RunDeps = { call: (method: string, path: string, body?: unknown) => Promise<Response>; person: string; now?: () => number; setTimer?; clearTimer?; batchMs?: number }`;
  `startRun(game: DailyGameId, person: string, call = api.call): Promise<Run | null>` (null on 404);
  `dailyPath(path: string, person: string): string` (adds `?person=`).

- [ ] **Step 1: failing tests**, driven by a fake `call` answering from `fixtures/daily/protocol/http.json`:
  - "batches moves at most once a second": two `send`s, then advance 999 ms → no call; 1000 ms → one
    POST `/v1/daily/runs/<run>/moves?person=` with `{ from: 0, moves: [m1, m2] }`.
  - "urgent sends at once and resolves with the batch's last reveal".
  - "one batch in flight: moves sent meanwhile go next with from = the answer's seq".
  - "resends the same from after a dropped connection" (call throws `ApiError(0,"offline")` once →
    the same body is sent again after backoff; a `link` event says "retrying" then "ok").
  - "too_soon waits and resends from seq"; "illegal resends the legal prefix, then resyncs from start";
    "stale and over resync from start" (emits `resync`, and `result` when start's result is set).
  - "hint flushes first, then emits hint and counts it"; "giveUp flushes, then emits result".
  - "elapsedMs counts from startedAt on the server clock plus 30 s a hint".
  - "chunks batches over 100 moves".
- [ ] **Step 2:** run `pnpm --filter @pounce/play-web exec vitest run tests/daily-client.test.ts` → FAIL.
- [ ] **Step 3:** implement. Timers live here (net code). Backoff `[250, 500, 1000, 2000, 4000]`, then 4000.
  `online` event retries at once. 429 waits 1000 ms.
- [ ] **Step 4:** tests pass. **Step 5:** commit "feat(daily-web): the run session batches, resends and resyncs".

### Task 2: The board socket

**Files:** Create `src/daily/board-socket.ts`; Test `tests/daily-board-socket.test.ts` (reuses `tests/fake-socket.ts`).

**Interfaces:**
- Produces: `type BoardEvent = { kind: "board"; board: BoardAnswer } | { kind: "result"; player: string; result: DailyResult } | { kind: "progress"; player: string; game: string; progress: number } | { kind: "tvs"; count: number } | { kind: "gone" }`;
  `class BoardSocket { constructor(opts: { person: string; token: () => Promise<string>; factory?; origin?; setTimer?; clearTimer? }); start(on: (e: BoardEvent) => void): void; stop(): void }`.

- [ ] **Step 1: failing tests:** URL is `ws(s)://<origin>/v1/daily/board/ws?person=…&games=…&app=…`
  with subprotocols `["pounce", "pounce.token.<token>"]`; each `socket.json` sample decodes to its
  event; `watch`, `watchOffer`, `watchEnd`, an unknown `t` and bad JSON are skipped; pings every 3 s
  and reconnects with `BACKOFF` after a close; a close before open with 404 semantics (code 4404) →
  `gone`.
- [ ] **Steps 2–5:** run, implement, pass, commit "feat(daily-web): the board socket".

### Task 3: The Dish store and the words

**Files:** Create `src/daily/dish-store.ts`, `src/daily/format.ts`; Test `tests/daily-store.test.ts`, `tests/daily-format.test.ts`.

**Interfaces:**
- Produces: `type DishState = { status: "unknown" | "off" | "on"; board: BoardAnswer | null; stats: Record<string, Stats> | null; tvs: number }`;
  `useDish(person: string | undefined): DishState` (fetches board, opens the socket while mounted, refcounted);
  `refreshDish(): Promise<void>`; `myRow(board, game)`; `bestRow(board, game)`.
  `format.ts`: `clock(ms): string` ("0:07", "1:42", "59:59", "1:02:03"),
  `resultWords(r: DailyResult): string` ("4 of 6", "Missed", "1,240 points", "1:42", "Gave up 1:42"),
  `shareText(title, r): string` ("Sniff 12: 4 of 6", "Nine Lives 3: 4:05, 1 hint"),
  `SHARE_URL = "https://play.conleychaos.com/daily"`, `games(board)`: the board's games that the registry has, in the board's order.
- [ ] **Step 1: failing tests:** "off on 404", "on with the board", "a result event updates the
  row then the next board replaces it", "tvs updates from the socket", the format cases above.
- [ ] **Steps 2–5:** run, implement, pass, commit "feat(daily-web): the Dish store and its words".

### Task 4: The Dish screen, board, stats and Show board on TV

**Files:** Create `src/daily/dish.tsx`, `board.tsx`, `stats.tsx`, `daily.css`; Modify `src/lib/router.ts`
(`{ kind: "dish" }` at `/play/daily`, `{ kind: "daily"; game }` at `/play/daily/<game>`), `src/app.tsx`
(lazy routes), `src/ui/tv-link.tsx` ("Tonight's board" card when the Dish is on); Test `tests/router.test.ts`.

- Cards: one per game in `games(board)`: the game's title, number, your result or Play, the best on
  your board (cat + name + result). Played cards open the end screen; unplayed open the host.
- Board: tabs "Dish" then each game; rows show rank, cat, name (ellipsis), result and marks
  (crown per game won; "Hint" mark; a "playing" dot with progress). Nobody who hasn't played.
- Stats button per game opens a sheet: played, solve rate, streak, best, best time/points,
  Sniff's 1–6 bars or a 30-day strip.
- "Show board on TV": sheet with the TV's backup code (`linkBoard({ code, board: true })`), and
  "Unlink" (`DELETE /v1/daily/board/tv`). `tv-link.tsx` adds a "Tonight's board" choice that links
  with `{ token, board: true }`.
- Tip `dish.first` on the first card: "New puzzles every day."
- [ ] Router tests first; then the screen; commit "feat(daily-web): the Dish screen".

### Task 5: The puzzle host and the end screen

**Files:** Create `src/daily/play.tsx`; Test `e2e/daily.spec.ts`.

- Top bar: back, "<Title> <number>", the clock (rAF, writes text only when the second changes),
  "Show on TV" switch only while `tvs > 0` (`PUT /v1/daily/runs/{run}/tv`), Give up (a sheet:
  "Give up?" Give up / Keep playing).
- The game's `Screen` fills the rest; `playing` false once a result arrives.
- End screen (over the dimmed board, after 900 ms so the finish shows): result words, place on
  today's board ("1st of 3"), Share (not for kittens), Stats, "Next puzzle" for an unplayed game, Dish.
- e2e: Home → Dish → test game → Step until done → end screen shows "Solved" and "1st"; give up
  on a second person; reload mid-run resumes; the Dish board lists the result.

### Task 6: Share card

**Files:** Create `src/daily/share.ts`, `src/workers/share-card.worker.ts`; Test `tests/daily-share.test.ts`.

- `renderCard(req: CardRequest): Promise<Blob>` posts to the worker; the worker draws on an
  `OffscreenCanvas(1080, 1080)`: the game's color, title + number, result words, the share grid
  (filled, outlined, plain paws), "play.conleychaos.com/daily", then `convertToBlob({ type: "image/png" })`.
- `share(...)`: `navigator.canShare({ files })` → `navigator.share({ files, text, url })`; else
  `navigator.share({ text, url })`; else `navigator.clipboard.writeText(text + " " + url)` → "Copied".
- Unit-test `shareText`, the grid layout math (`cardLayout(rows)`), and the fallback order with stubs.

### Task 7: Home redesigned with the Dish

**Files:** Create `src/daily/dish-home.tsx`; Modify `src/ui/home.tsx`, `src/ui/screens.css`.

- Home order: header; **Today** (the Dish: four treats, done or not, your result once done, "Open"
  to the Dish) when the Dish is on; Your tables; New game; dock. Posters shrink to a row on phones
  so Today sits above the fold. Before/after screenshots at every size.

### Task 8: Gates and screenshots

**Files:** Modify `playwright.config.ts` (port 8807 via `E2E_PORT`, `--var DAILY:on --var DAILY_TEST:on`),
`e2e/main-thread.spec.ts` (a `playDish` step after Tuna Tiles: Home → Dish → board tabs → test game →
end screen → Share), `eslint.main-thread.mjs` (the Dish's screens join `UI_CODE`).

- [ ] Run `E2E_PORT=8807 pnpm --filter @pounce/play-web e2e --project laptop-chrome --project android-chrome`.
- [ ] Screenshots to the notes folder; PR "Daily puzzles get a home in the browser (switched off until launch)".
