# T1: Tonight's board on the TV, implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the TV (Apple TV app and the browser TV page) links to a person's Daily Dish board from
a phone, keeps it for 30 days, shows it live with a celebration per result, offers to watch a run
when a player turns on Show on TV, and unlinks from its menu, all behind the server's `DAILY` flag.

**Architecture:** each platform gets the same three layers. A pure board state (a reducer over the
board socket's messages, tested on the protocol fixtures), a board socket client (connect, ping,
reconnect, "gone" on 404 or a revoke), and screens: a third home poster, the board, the watch card
and the watch host. The TV's model owns the board as it owns a table: one phase more (`board`),
one kept value more (the board token).

**Tech Stack:** Preact + TypeScript + Vitest + Playwright (`apps/play-web`); Swift 6, SwiftUI,
XCTest/XCUITest on tvOS (`apps/play-ios/PounceTV`, PounceKit).

**Spec:** `docs/superpowers/specs/2026-11-20-daily-games-design.md` §6 and §8; wire contract
`docs/daily-protocol.md` ("The board socket", "A board on the TV"); TV design
`docs/superpowers/specs/2026-11-16-tv-table-design.md` and `docs/tv-protocol.md`; map
`docs/superpowers/plans/2026-11-20-daily-games.md` (T1 row).

## Global Constraints

- `PROTOCOL_VERSION` stays 1. T1 changes no server file.
- `DAILY` stays off in production. The TV hides "Tonight's board" unless the server says the Dish
  is on: `GET /v1/daily/board/ws` without an upgrade answers 426 when on, 404 when off.
- Test only against T1's own dev server on port **8808** with `DAILY=on`, `DAILY_TEST=on`,
  `TV=on`. Never 8787 or 4343.
- The main thread draws, nothing else. Keychain only through PounceKit's IO layer; the browser's
  storage only through `src/lib/kv.ts`. Decoding a board message is small (under 1 ms); anything
  bigger goes off the main thread.
- Readable from about 3 meters: nothing that matters under 28 pt at 1080p (web: 28 px at
  1920x1080).
- Copy: buttons one to three words, messages one short sentence, no emoji, no "you can".
  Fixed strings: "Tonight's board", "Unlink", "Watch", "Not now",
  "<Name> is playing <Game>. Spoilers.", "Scan from the Dish on your phone".
- Watch card: Not now has the default focus, and the card goes after 20 seconds.
- No text entry anywhere on the TV.
- Translucent groups fade as one layer (`.compositingGroup()`, CSS on the group).
- Own only T1 files: `PounceTV/` (Shell and App), `PounceTVTests/`, `PounceTVUITests/`,
  `apps/play-web/src/ui/tv/`, the TV e2e files. Shared files touched, additively: PounceKit
  `Net/ScreenLink.swift` (a `.board` event), PounceKit `IO/BoardKeep.swift` (new),
  `apps/play-web/src/net/screen-link.ts` (a `board` event), `apps/play-web/playwright.config.ts`
  (DAILY vars, the TV project's test match), `e2e/main-thread.spec.ts` (a board step).
- Phase A uses TV-local wire types (`TVBoardWire.swift`, the server's own TS types on the web).
  H1's `DailyWire`/`DailyBoardSocket` and H2's board socket are for phones (`?person=`); when they
  merge, Phase B may switch the TV to them.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Decisions

- **Where the board lives on the TV.** A new phase, `board`, beside `home`, `lobby`, `table`,
  `over`. The TV opens to: a kept table, else a kept board token (not expired), else home (web:
  Start first, as today).
- **Home.** Three posters on the right: Cat Tower, Tuna Tiles, Tonight's board (the last only
  while the Dish is on). The link on the left now reads "Scan with your phone" and takes both a
  table link and a board link (same socket). The board poster opens the board when a token is
  kept; otherwise it opens a board link panel: QR, code, "Scan from the Dish on your phone", Back.
- **Any link socket** (home, the board panel, the table menu's "Link another table") that hears
  `{ "t": "board", "token" }` keeps the token and shows the board. A board replaces a table: the
  table is let go and forgotten.
- **Kept token.** `{ token, until }` with `until = now + 30 days`. Apple TV: Keychain item
  (service `com.conleychaos.play.tv`, account `board`) through `KeychainBoardKeep`. Browser:
  `pounce.tv.board` in `kv`. Forgotten on a 404 at connect, a close with reason `revoked` or
  `expired`, Unlink, or `until` passed at launch. Forgetting goes home.
- **The board screen (1920x1080).** Left column 600 wide: "Tonight's board" and the date, then the
  Dish: rank, cat, name, crowns, points. Right: one card per game the board lists (1 to 4, in the
  board's order, a 2x2 grid; one or two games fill a column). A game card: title and number, then
  up to 4 rows (rank, cat, name, result), then "+N more". People playing now follow, with a
  progress bar and "Playing". Sizes: names 40 pt, results 40 pt, card titles 48 pt, ranks 36 pt,
  "+N more" 30 pt. Empty board: a sleeping cat and "Nobody has played yet".
- **Result words.** solved: time `m:ss` (Sniff: "4 of 6"; Box Fort: points with a thousands
  separator); missed: "Missed"; gaveUp: "Gave up"; done (Box Fort): points; closed: "Closed".
  Hints: a small hint mark and "+1 hint" for VoiceOver. Ranks: "1st" style is not used; the
  number alone in a coloured disc (gold, silver, bronze, then violet).
- **Celebration.** On `result`, the row for `player` in that game (once the following `board`
  lands) gets a cheer for 2.4 s: the row slides in from the right (spring), the cat swaps to its
  `leap` pose and jumps, and `sfx-fanfare` plays (`sfx-sparkle` when the result wasn't solved).
  The Dish row of that player pulses once. Only one cheer at a time; a newer one replaces it.
- **Watch.** `watchOffer` shows the card for 20 s (bottom centre, over the board, not over a
  table: offers that land while a table is shown are dropped). Watch opens the watch view for that
  player and game, drawn from the latest `watch` frame kept for them (frames are kept per player
  from the offer on, even after Not now). `watchEnd` with a result shows the result over the watch
  view for 6 s, then the board; with null, the board at once. A `watchEnd` for someone not being
  watched clears their offer and frames. Back from the watch view goes to the board.
- **Watch host.** `watchViewFor(game)` returns the game's `DailyWatchView` when one is registered
  (Phase B), else the placeholder: the game's title, the player's cat in its `awake` pose,
  "Watching", and for the test game the number counted so far ("3") drawn large.
- **Menu on the board.** Back (web) / Menu (Apple TV) opens the menu: "Play a game" (home, board
  kept), "Sound on/off", "Unlink" (forget the token, home). Menu at home still leaves the app.
- **Dish on probe.** Once per launch and each time home shows: `GET /v1/daily/board/ws` with the
  TV's device token; 426 means on. Any error means off (the poster hides; links still work).

## Review Focus

1. A board token revoked from the phone while the TV is asleep or backgrounded: on return the
   TV's connect gets 404 and must go home, not spin reconnecting. (Tasks 2, 7)
2. A `board` link arriving while the TV shows a table: the table socket closes first, then the
   board shows; the kept room is cleared so a relaunch opens the board. (Tasks 4, 8)
3. Long names and many rows: a 20-character name and 9 people on one game must not overflow the
   card ("+N more", truncation with ellipsis). (Tasks 4, 9)
4. A `result` for yesterday (closed at 04:00) arriving after midnight: the board shows the next
   `board` snapshot's date; the cheer only fires for a row on the board shown. (Tasks 1, 6)
5. The watch card's 20 s timer while the remote is idle, and an offer replaced by a newer offer
   from another player: the newer card shows and gets its own 20 s. (Tasks 1, 6)

---

## Web

### Task 1: The board state, pure (web)

**Files:**
- Create: `apps/play-web/src/ui/tv/tv-board-model.ts`
- Test: `apps/play-web/src/ui/tv/tv-board-model.test.ts`

**Interfaces:**
- Consumes: `BoardMessage`, `BoardAnswer` from `@pounce/play-api/daily/messages`; `DailyResult`,
  `DailyGameId` from `@pounce/play-api/daily/module`; `DAILY_TITLES` from
  `@pounce/play-api/daily/games` (types and a constant only, no game engine).
- Produces:
  - `type Offer = { player: string; name: string; cat: number; game: string; until: number }`
  - `type Cheer = { player: string; game: string; solved: boolean; until: number }`
  - `type BoardScreen = { board: BoardAnswer | null; offer: Offer | null; frames: Record<string, { game: string; state: unknown }>; watching: { player: string; name: string; cat: number; game: string } | null; ended: { result: DailyResult; name: string; until: number } | null; cheer: Cheer | null }`
  - `EMPTY_SCREEN: BoardScreen`
  - `boardStep(s: BoardScreen, m: BoardMessage, now: number): BoardScreen`
  - `watch(s: BoardScreen, now: number): BoardScreen` (Watch pressed), `notNow(s): BoardScreen`,
    `tick(s, now): BoardScreen` (expires offer, ended, cheer), `stopWatching(s): BoardScreen`
  - `resultWords(r: DailyResult): string`, `gameTitle(game: string): string`,
    `offerWords(o: Offer): string` → `"Mom is playing Sniff. Spoilers."`
  - `visibleRows(g: GameBoard, max = 4): { rows: BoardRow[]; more: number }` (ranked rows first,
    then playing rows, `more` counts the rest)
  - `OFFER_MS = 20_000`, `ENDED_MS = 6_000`, `CHEER_MS = 2_400`, `BOARD_DAYS = 30`
  - `keptBoard(raw: string | null, now: number): string | null`, `boardToKeep(token: string, now: number): string`

- [ ] **Step 1: Write the failing tests** against `fixtures/daily/protocol/socket.json`:
  `board` sets `board`; `result` then `board` sets `cheer` for that player and game with
  `until = now + 2400` and `solved` from the outcome; `progress` updates that row's
  `playing.progress` in place; `watchOffer` sets `offer.until = now + 20000`; `watch` keeps
  `frames[player]`; `watch()` moves the offer into `watching`; `watchEnd` with a result for the
  watched player sets `ended` (6 s) and clears `frames[player]`; with null clears `watching`;
  `tick(now + 20001)` clears the offer; a second `watchOffer` from another player replaces the
  first with its own 20 s; `tvs`, `pong`, unknown kinds leave the state unchanged;
  `resultWords` for each outcome (`125000` → `"2:05"`, Sniff `guesses: 4` → `"4 of 6"`, Box Fort
  `points: 1240` → `"1,240"`, missed → `"Missed"`, gaveUp → `"Gave up"`);
  `offerWords` → `"Kid is playing Test. Spoilers."`; `visibleRows` on 9 rows → 4 and `more: 5`;
  `keptBoard` round trip, null after 30 days, null on garbage.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-web exec vitest run src/ui/tv/tv-board-model.test.ts` → FAIL (module missing).
- [ ] **Step 3: Implement** the module (pure functions, no DOM).
- [ ] **Step 4: Run** the same command → PASS.
- [ ] **Step 5: Commit** `feat(tv): the board's state, from the board socket's messages`.

### Task 2: The board socket and the link's board event (web)

**Files:**
- Create: `apps/play-web/src/ui/tv/tv-board-socket.ts`, test `tv-board-socket.test.ts`
- Modify: `apps/play-web/src/net/screen-link.ts` (event `{ kind: "board"; token: string }` on
  `{ t: "board", token }`, then stop), its test file

**Interfaces:**
- Produces:
  - `type BoardSocketEvent = { kind: "message"; message: BoardMessage } | { kind: "offline" } | { kind: "online" } | { kind: "gone" }`
  - `class BoardSocket { constructor(o: { api: Api; board: string; origin?: string; factory?: SocketFactory; setTimer?; clearTimer?; backoff?: number[] }); on(l): () => void; start(): void; stop(): void; reconnectNow(): void }`
    URL `wsUrl(origin, "/v1/daily/board/ws?board=<token>")`, subprotocols
    `["pounce", "pounce.token.<device token>"]`. Pings `{ "t": "ping" }` every 25 s. A close with
    code 4404, or code 1000 with reason `revoked` or `expired`, emits `gone` and stops; 4401
    forgets the device credential and reconnects; anything else emits `offline` and reconnects
    with `BACKOFF`.
  - `dailyOn(api: Api, origin?: string): Promise<boolean>`: `fetch` GET `/v1/daily/board/ws` with
    `authorization: Bearer <device token>`; true only for 426.
- [ ] **Step 1: Write failing tests** with a fake socket factory: URL and protocols; messages
  parsed and emitted; non-JSON dropped; 4404 → `gone` and no reconnect; 1000 `revoked` → `gone`;
  1006 → `offline` then a reconnect after the first backoff; `stop()` closes and emits nothing.
  `screen-link.test.ts`: `{ t: "board", token }` emits `board` and stops.
  `dailyOn`: 426 → true, 404 → false, a throw → false.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-web exec vitest run src/ui/tv src/net/screen-link.test.ts` → FAIL.
- [ ] **Step 3: Implement** both.
- [ ] **Step 4: Run** → PASS. Update `TvHome`/`TvMenu` listeners so the new event kind compiles
  (handled in Task 3).
- [ ] **Step 5: Commit** `feat(tv): the board socket, and a link that brings a board`.

### Task 3: The TV page shows the board (web)

**Files:**
- Create: `apps/play-web/src/ui/tv/tv-board.tsx` (`TvBoard`, the board screen and its
  celebration), `tv-watch.tsx` (`TvWatchCard`, `TvWatch`, `watchViewFor`, placeholders),
  `tv-board-link.tsx` (`TvBoardLink`, the poster's link panel), `tv-board.css`
- Modify: `tv-app.tsx` (phase `board`, home's third poster, kept board, board menu),
  `tv-menu.tsx` (board items: "Play a game", sound, "Unlink"), `tv-model.ts` (`bootPhase(kept,
  board)` → `"lobby" | "board" | "start"`), `tv-model.test.ts` if present

**Interfaces:**
- Consumes: Task 1's state functions, Task 2's `BoardSocket`, `dailyOn`, ScreenLink's `board`.
- Produces: DOM hooks the e2e uses: `.tv-poster.board` ("Tonight's board"), `.tv-board`,
  `.tv-board-game[data-game]`, `.tv-board-row[data-player]` with `.cheer` while cheering,
  `.tv-dish-row`, `.tv-watch-card` (buttons "Watch", "Not now"), `.tv-watch[data-game]`,
  `.tv-watch-ended`, menu button "Unlink"; board link panel `.tv-board-link` with `.tv-code`.
- [ ] **Step 1: Write failing unit tests** in `tv-model.test.ts` for `bootPhase`: kept room →
  `"lobby"`, else kept board → `"board"`, else `"start"`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** `bootPhase` and the screens per Decisions;
  sizes in CSS with `--u` so 1 u = 1 px at 1080p and nothing that matters is under `28 * --u`.
  The board's state lives in `useReducer`-style local state fed by `BoardSocket`; `tick` runs on a
  1 s timer only while an offer, an end or a cheer is up. The cheer animation is CSS (transform
  and opacity). Sounds via `play("fanfare")` / `play("sparkle")`; offers play `pop`.
- [ ] **Step 4: Run** `pnpm --filter @pounce/play-web typecheck && pnpm --filter @pounce/play-web exec vitest run src/ui/tv && pnpm lint` → PASS.
- [ ] **Step 5: Commit** `feat(tv): Tonight's board on the browser TV`.

### Task 4: Browser TV end to end, gate and shots (web)

**Files:**
- Create: `apps/play-web/e2e/tv-board.spec.ts`, `apps/play-web/e2e/daily-phone.ts` (a phone over
  plain HTTP: `POST /v1/devices`, `PUT /v1/devices/me/profile` with one person, then
  `start(game)`, `moves(run, from, moves)`, `showOnTv(run, on)`, `linkBoard({ code })`,
  `unlink()`)
- Modify: `apps/play-web/playwright.config.ts` (`--var DAILY:on --var DAILY_TEST:on`; `tv-chrome`
  matches `tv-board.spec` too, and the other projects ignore it), `e2e/main-thread.spec.ts` (a
  `tv-board` step: link a board, then 6 results and 6 progress messages arrive while measured)

**Tests (each a Playwright test on `tv-chrome`, server on `E2E_PORT=8808`):**
- [ ] **links a board from a phone by code, and keeps it across a reload**: the poster opens the
  panel; the phone links with the panel's code; `.tv-board` shows; reload → straight to the board.
- [ ] **a result arrives live**: the phone plays the test game to the end (`start`, then one batch
  `1..target`); the row for "Mom" shows a time and gets `.cheer`; the Dish row shows 4 points.
- [ ] **long names fit**: a 20-character name (Review Focus 3) doesn't overflow its card
  (`scrollWidth <= clientWidth`).
- [ ] **the watch card**: the phone starts a run and turns Show on TV on; the card reads
  "Mom is playing Test. Spoilers.", "Not now" is focused; Watch shows `.tv-watch` with the count;
  a move updates it; the run's end shows `.tv-watch-ended`, then the board. A second offer left
  alone is gone after 20 s.
- [ ] **Unlink from the TV's menu** goes home and a reload stays home; **a revoke from the phone**
  (`DELETE /v1/daily/board/tv`) sends the TV home (Review Focus 1).
- [ ] **screenshots** at 1920x1080 of home, the board link panel, the board, the cheer, the watch
  card and the watch view, to `docs/screenshots/tv-board/web-*.png`.
- [ ] Run `E2E_PORT=8808 pnpm --filter @pounce/play-web exec playwright test --project tv-chrome tv-board main-thread` after `pnpm --filter @pounce/play-web build` → PASS, gate lines printed.
- [ ] Commit `test(tv): the browser TV's board end to end, with its frame gate`.

## Apple TV

### Task 5: PounceKit: the link's board event and the kept board token

**Files:**
- Modify: `PounceKit/Sources/PounceKit/Net/ScreenLink.swift` (`case board(token: String)`; the
  frame's `token`; on `t == "board"` finish with it), `Tests/PounceKitTests/ScreenLinkTests.swift`
- Create: `PounceKit/Sources/PounceKit/IO/BoardKeep.swift`, `Tests/PounceKitTests/BoardKeepTests.swift`

**Interfaces:**
- Produces:
  - `ScreenLinkEvent.board(token: String)` (the link is spent, events end).
  - `public struct KeptBoard: Codable, Equatable, Sendable { public let token: String; public let until: Date }`
    with `static func fresh(_ token: String, now: Date) -> KeptBoard` (30 days) and
    `func live(at now: Date) -> Bool`.
  - `public protocol BoardKeeping: Sendable { func load() async -> KeptBoard?; func keep(_ board: KeptBoard?) async }`
  - `public actor KeychainBoardKeep: BoardKeeping` (`KeychainItem(service: "com.conleychaos.play.tv", account: "board")`, JSON) and `public actor MemoryBoardKeep: BoardKeeping`.
- [ ] **Step 1: Failing tests**: a socket frame `{"t":"board","token":"…"}` yields `.board` and
  the stream finishes; `KeptBoard.fresh` lasts 30 days (`live` true at 29 d, false at 31 d);
  `MemoryBoardKeep` round trip and `keep(nil)` forgets.
- [ ] **Step 2:** `cd apps/play-ios/PounceKit && swift test --filter 'ScreenLinkTests|BoardKeepTests'` → FAIL.
- [ ] **Step 3: Implement.** Keychain calls stay inside `KeychainItem`.
- [ ] **Step 4:** same command → PASS; `swift apps/play-ios/scripts/main-thread-lint.swift` → clean.
- [ ] **Step 5: Commit** `feat(tv): a TV link can bring a board, and the TV keeps its token`.

### Task 6: The board's wire, state and socket (Apple TV)

**Files:**
- Create: `PounceTV/App/TVBoardWire.swift` (Decodable `BoardAnswer`, `GameBoard`, `BoardRow`,
  `DishRow`, `DailyResult`, `BoardMessage` enum with `.board/.result/.progress/.watchOffer/.watch/.watchEnd/.other`,
  `state` kept as raw JSON `Data`), `PounceTV/App/TVBoardState.swift` (the same reducer as Task 1:
  `TVBoardState` struct with `apply(_:now:)`, `watch(now:)`, `notNow()`, `tick(now:)`,
  `stopWatching()`; `resultWords`, `gameTitle`, `offerWords`, `visibleRows`),
  `PounceTV/App/TVBoardSocket.swift` (protocol `BoardSocketing: Sendable { var events: AsyncStream<BoardSocketEvent> { get }; func start() async; func stop() async }`,
  `enum BoardSocketEvent { case message(BoardMessage), offline, online, gone }`, actor
  `TVBoardSocket` over `WebSocketConnector`: URL from `config.endpoint("/v1/daily/board/ws",
  query: [board])` with the scheme swapped to ws/wss; `SocketConnectError.notFound` → `.gone`;
  unauthorized → retry with a fresh credential; drop → `.offline`, backoff, reconnect; ping every
  25 s; a received close reason can't be read from URLSession, so a drop that then connects to a
  404 is how a revoke shows)
- Test: `PounceTVTests/TVBoardStateTests.swift`, `PounceTVTests/TVBoardSocketTests.swift`

- [ ] **Step 1: Failing tests**: decode every message in `fixtures/daily/protocol/socket.json`
  (read by path as `PounceKitTests/Fixtures.swift` does); the same reducer cases as Task 1, with
  the same values; the socket over a fake connector: messages decoded in order, `notFound` → one
  `.gone` and no retry, a dropped receive → `.offline` then a reconnect.
- [ ] **Step 2:** `xcodebuild test -scheme PounceTV -destination 'platform=tvOS Simulator,name=<T1 sim>' -only-testing:PounceTVTests` → FAIL.
- [ ] **Step 3: Implement.** Game titles: `["sniff": "Sniff", "nine-lives": "Nine Lives",
  "cat-nap": "Cat Nap", "box-fort": "Box Fort", "test": "Test"]`.
- [ ] **Step 4:** same → PASS. **Step 5: Commit** `feat(tv): the Apple TV reads the board socket`.

### Task 7: The TV model shows a board (Apple TV)

**Files:**
- Modify: `PounceTV/App/TVModel.swift` (phase `.board`; `board: TVBoardState`; `boardOn: Bool`;
  `boardLinkShown`; `openBoard()`, `showBoardLink()`, `unlink()`, `playAGame()`, `watch()`,
  `notNow()`, `stopWatching()`; link handlers for `.board(token)`; launch order: room, board,
  home; background closes the board socket, return reopens it; `.gone` forgets and goes home),
  `PounceTV/App/TVServices.swift` (`boardSocket: @Sendable (String) -> any BoardSocketing`,
  `boards: any BoardKeeping`, `dailyOn: @Sendable () async -> Bool`, `now: @Sendable () -> Date`),
  `PounceTV/App/TVDemo.swift` (demo services get the new fields)
- Test: `PounceTVTests/TVModelTests.swift` (new cases)

- [ ] **Step 1: Failing tests**: a kept live board opens `.board` at launch; an expired one goes
  home and is forgotten; home's link `.board(token)` keeps `KeptBoard.fresh` and opens `.board`;
  the menu's link `.board` at a table closes the table socket, forgets the room, opens `.board`
  (Review Focus 2); `.gone` forgets the token and goes home; `unlink()` forgets and goes home;
  `playAGame()` goes home with the token kept; the poster shows only when `dailyOn` is true; an
  offer expires after 20 s of the injected clock; background then return reconnects the board.
- [ ] **Step 2–4:** run `PounceTVTests` → FAIL, implement, → PASS.
- [ ] **Step 5: Commit** `feat(tv): the Apple TV opens to its board`.

### Task 8: The board, watch and menu screens (Apple TV)

**Files:**
- Create: `PounceTV/Shell/BoardView.swift` (the board and its cheer), `PounceTV/Shell/BoardWatch.swift`
  (`WatchCard`, `WatchHost`, `DailyWatchViews` registry with placeholders),
  `PounceTV/Shell/BoardLinkView.swift` (the poster's link panel)
- Modify: `PounceTV/Shell/HomeView.swift` (three posters, the board poster, "Scan with your
  phone"), `TVRoot.swift` (`.board` phase, the card over it, Menu on the board), `TVMenu.swift`
  (board items: "Play a game", sound, "Unlink"), `TVStyle.swift` (shared row styles if needed)

**Accessibility identifiers** (the UI tests use them): `tv.poster.board`, `tv.boardLink.code`,
`tv.board`, `tv.board.game.<game>`, `tv.board.row.<game>.<player>` (value `"cheer"` while
cheering), `tv.board.dish.<player>`, `tv.watch.card`, `tv.watch.watch`, `tv.watch.notNow`,
`tv.watch.view.<game>`, `tv.watch.ended`, `tv.menu.playAGame`, `tv.menu.unlink`.

- [ ] Build the screens per Decisions: fonts at least 28 pt, names truncate, the watch card's
  default focus `tv.watch.notNow`; the cheer is a SwiftUI spring (row offset from 400 to 0), the
  cat's `leap` pose with a jump, `Sound.shared.play(ArtName.Sound.sfxFanfare)`.
- [ ] Previews and DEBUG shots: `TVShots` gains `-tv-board-shot <home|link|board|cheer|card|watch>`
  on the `tv-board` demo.
- [ ] `xcodebuild build -scheme PounceTV` and the lint → clean. Commit `feat(tv): Tonight's board on Apple TV`.

### Task 9: Apple TV demo, frame gate, UI tests against 8808, shots

**Files:**
- Modify: `PounceTV/App/TVDemo.swift` (`-demo tv-board`: a kept board token, a fake board socket
  that sends the fixture board, then every 1.5 s at the app's pace a progress, a result and a
  fresh board for a six-person, four-game board, an offer and frames on the test signal),
  `PounceTVUITests/FrameRateTVTests.swift` (`testBoardPlaysAtTheTopFrameRate`: measures 20 s of
  the board demo; table-frame checks skipped for a screen with no SpriteKit table, the
  main-thread budget, hangs and link frames enforced as for the others)
- Create: `PounceTVUITests/BoardLiveTests.swift` (the TV app with
  `POUNCE_API_BASE_URL=http://localhost:8808`; the test runner is the phone over `URLSession`,
  same calls as the web's `daily-phone.ts`): link a board by the code the TV shows (read from
  `tv.boardLink.code`'s label), a result arrives live (`tv.board.row.test.me` value `cheer`), the
  watch card with `tv.watch.notNow` focused, Watch shows `tv.watch.view.test`, Unlink from the
  menu goes home. Skipped with a clear message when 8808 isn't answering.
- Create: `PounceTVUITests/BoardShotTests.swift` (1080p screenshots as attachments, exported to
  `docs/screenshots/tv-board/appletv-*.png`)
- [ ] Run `PLATFORM=tvOS scripts/frame-rate.sh "<T1 sim>"` for the board variant → FRAMES line,
  no failures; `xcodebuild test … -only-testing:PounceTVUITests/BoardLiveTests` with the dev
  server up → PASS; `RemoteTests` → no new failures (the known one stays as on main).
- [ ] Commit `test(tv): the Apple TV board live, its frame gate and shots`.

### Task 10: Report Phase A

- [ ] Note in the shared notes folder (`t1-tv.md`): what's built, the shots, the gate numbers,
  the open questions (TV-local wire types vs H1/H2's, the playwright config lines).
- [ ] Message the lead with a short summary and stop.

## Phase B (on the lead's word)

- For each game: register its `DailyWatchView` in `DailyWatchViews` (Swift) and `watchViewFor`
  (web), add a watch test per game (e2e and `BoardLiveTests`), shots.
- Rebase onto main (`git rebase --onto origin/main claude/daily-server-391b57`), switch to H1/H2's
  shared wire types if they fit, open the PR "Tonight's board on the TV (switched off until
  launch)".
