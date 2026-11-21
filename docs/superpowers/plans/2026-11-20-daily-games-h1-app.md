# H1: the Daily Dish in the iOS and iPad app — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Daily Dish in the iPhone and iPad app: Home redesigned around it, the Dish screen
(cards, board, stats, Show board on TV), the puzzle host that runs any daily game, the share card,
the first-visit tip. All of it is hidden while the server has `DAILY` off.

**Architecture:** PounceKit holds everything that talks to the server or decodes: the wire types,
the run session actor, the board socket actor, the catalog, the store the screens read, and the
share card renderer. All of it runs off the main actor. The app's `Pounce/Daily/` holds the
screens. Games plug in through `DailyGameView` and `DailyWatchView` (task 1, already pushed). Each
game adds one line to `DailyGames.swift` and one to `DailyWatchGames.swift`.

**Tech stack:** Swift 6 (strict concurrency), SwiftUI, Swift Testing (PounceKit), XCTest UI tests,
CoreGraphics and ImageIO for the share card. No new packages.

**Spec:** `docs/superpowers/specs/2026-11-20-daily-games-design.md` §6, §7, §8 (linking a board,
phone side), §9, §10. Wire: `docs/daily-protocol.md`, fixtures in
`apps/play-api/fixtures/daily/protocol/`. Map: `docs/superpowers/plans/2026-11-20-daily-games.md`.

## Global constraints

- `PROTOCOL_VERSION` stays 1. The Dish hides on a 404 from `GET /v1/daily/board` (spec §11).
- The main thread draws, nothing else (`docs/main-thread.md`). Network, decoding and the share
  render are off the main actor. `swift scripts/main-thread-lint.swift` reports 0 violations.
- UI copy: buttons and labels are one to three words, messages one short sentence. No emoji. No
  "last place", and nothing about who didn't play.
- Kittens get no share (spec §7, §10).
- Share text is exactly `"<Title> <number>: <summary>"` plus `https://play.conleychaos.com/daily`.
- Loud, cartoony Palette colors only. Fade groups with `.compositingGroup()`.
- Test only against your own `wrangler dev` on port 8806 with `DAILY=on DAILY_TEST=on`. Never
  use :8787 or :4343, and never JD's phone. Use simulators "H1 SE", "H1 ProMax" and "H1 iPad",
  and shut them down when done.
- Own only H1's files (map plan, "Who owns which files"). `ShowOnTVSheet.swift` gets a board
  target added; nobody else owns it.

## Review focus

1. **The flag goes off, or comes back, mid-session.** A board 404 hides the Dish on Home with no
   leftover gap, and an error screen never shows. Test: `DailyStoreTests.boardNotFoundHides`.
2. **A run ends on another device while this one shows it.** Resume shows the end screen, not the
   board. Test: `DailyRunSessionTests.anEndedRunTellsANewListenerAtOnce` (done).
3. **Long names and big numbers on the board and the treats** ("Grandpa Bartholomew",
   "12,480 points", a 1:02:09 time). Rows truncate the name, never the result. Covered by the
   screenshot pass at AX5 on iPhone SE, using the `-demo-dish long` board.
4. **No connection.** The board keeps what it last showed, the host shows "Reconnecting" from
   `.link(.retrying)`, and moves are not lost. Test: `DailyRunSessionTests.aNetworkFailureResendsTheSameFrom`
   (done), plus `DailyBoardSocketTests.reconnectsAfterADrop`.
5. **A result for yesterday arrives on the socket** (a run closed at 04:00). It never lands on
   today's board. Test: `DailyWireTests.aResultForAnotherDateLeavesTheBoard`.

---

### Task 1: The host contract (done, 3a56912)

`DailyRunSession`, `DailyClock`, `DailyService` on `APIClient`, `DailyJSON`, `DailyWire`,
`DailyCatalog`, `DailyGameView` / `DailyWatchView`, the registries and the test game.
Tests: `DailyRunSessionTests` (13).

### Task 2: Every protocol fixture decodes

**Files:**
- Test: `PounceKit/Tests/PounceKitTests/DailyWireTests.swift`
- Modify: `PounceKit/Sources/PounceKit/Daily/DailyWire.swift` if a fixture doesn't decode

**Interfaces:** Produces `Fixtures.daily(_ name: String) throws -> [String: Data]`, which reads
`daily/protocol/<name>.json` keyed by sample name.

- [ ] Write tests:
  - `everyHTTPSampleDecodes`: start and resumed decode as `DailyStart`. movesOk, movesSolved,
    movesIllegal, movesStale, movesOver, hint and gaveUp decode as `DailyMovesAnswer`. board
    decodes as `DailyBoard` with `tvs == 1`, three test rows, Grandpa playing at 0.5, and the
    dish's first row with points 4 and `crowns == ["test"]`. stats decodes as `DailyStatsList`.
  - `everySocketSampleDecodes`: each sample is a known case except `linkBoard`, which is the
    screen socket's message and decodes as `.unknown("board")`, because it has no `board` object.
  - `unknownKindsAreSkipped`: `{"t":"later","x":1}` decodes as `.unknown("later")`.
  - `clientBodiesEncode`: `DailyMovesBody(from: 0, moves: [step1, step2])` encodes equal to
    client.json's `moves`.
  - `aResultForAnotherDateLeavesTheBoard`.
  - `addingAResultFillsTheRow`.
- [ ] Run `swift test --package-path PounceKit --filter DailyWireTests`. Expected: pass, or fix
  the decoders.
- [ ] Commit.

### Task 3: The board socket

**Files:**
- Create: `PounceKit/Sources/PounceKit/Daily/DailyBoardSocket.swift`
- Test: `PounceKit/Tests/PounceKitTests/DailyBoardSocketTests.swift`

**Interfaces:** Produces
`actor DailyBoardSocket { init(config: APIConfig, person: String?, connector: any WebSocketConnector, credential: @Sendable () async throws -> DeviceCredential, retry: Duration = .seconds(1), ping: Duration = .seconds(25)); func messages() -> AsyncStream<DailyBoardMessage>; func start(); func stop() }`
and `APIConfig.dailyBoardSocketURL(person: String?) -> URL`
(`ws(s)://host/v1/daily/board/ws?person=`).

- [ ] Write tests with a fake connector:
  - `decodesAndSkipsUnknown`: frames are board, `{"t":"later"}` and tvs; the stream yields board
    then `.tvs(1)`.
  - `reconnectsAfterADrop`: the first connection's receive throws. The socket connects again, and
    the second connection's board arrives.
  - `notFoundStops`: connect throws `.notFound`. The stream finishes and no retry follows.
  - `urlCarriesPerson`: the URL is `ws://h:1/v1/daily/board/ws?person=p1`.
- [ ] Implement. It reads frames in a loop, decodes them on the actor, and drops `.unknown`,
  `.pong` and `.error`. After a drop it backs off: retry, doubling, up to 30 s. A ping goes out
  every `ping`.
- [ ] Run the tests until they pass, then commit.

### Task 4: The Dish store

**Files:**
- Create: `PounceKit/Sources/PounceKit/Daily/DailyStore.swift`
- Test: `PounceKit/Tests/PounceKitTests/DailyStoreTests.swift`

**Interfaces:**
- Produces `@MainActor @Observable final class DailyStore`:
  - `init(service: any DailyService, socket: (@Sendable (String?) -> DailyBoardSocket)?)`
  - `var person: String?`
  - `private(set) var enabled: Bool?` (nil until it knows; false after a 404)
  - `private(set) var board: DailyBoard?`
  - `private(set) var stats: [String: DailyStats]`
  - `func refresh() async`, `func refreshStats() async`, `func listen() async` (runs the socket
    until cancelled)
  - `var tvs: Int`
  - `func mine(_ game: String) -> DailyResult?`
  - `func playing(_ game: String) -> Bool`
- The store holds no IO. It applies socket messages in memory: `board` replaces, `result` goes
  through `DailyBoard.adding`, `progress` through `moving`, and `tvs` through `with(tvs:)`.
- [ ] Write tests:
  - `boardNotFoundHides`: the service throws `APIError.notFound`, so `enabled == false` and
    `board == nil`.
  - `aBoardShows`: `enabled == true`.
  - `offlineKeepsTheBoard`: a transport error after a board keeps it.
  - `socketMessagesApply`: `result`, `progress` and `tvs` each change the board.
  - `personChangeClears`.
- [ ] Implement, test and commit.

### Task 5: The share card

**Files:**
- Create: `PounceKit/Sources/PounceKit/Daily/DailyShare.swift`
- Test: `PounceKit/Tests/PounceKitTests/DailyShareTests.swift`

**Interfaces:**
- Produces `public enum DailyShareMark: Sendable { case hit, near, miss, empty }`.
- Produces `public struct DailyShare: Sendable`:
  - `init(game: DailyGameInfo, result: DailyResult, marks: [[DailyShareMark]]?)`
  - `var text: String`: the line plus "\n" plus the link
  - `static let link = URL(string: "https://play.conleychaos.com/daily")!`
  - `@concurrent func png(scale: CGFloat = 2) async -> Data?`: a 600 by 600 pt card, drawn with
    CoreGraphics and CoreText, off the main actor.
- Produces `DailyGameView.shareMarks(state:) -> [[DailyShareMark]]?` (default nil), which Sniff
  implements.
- [ ] Write tests:
  - `textIsTheLineAndLink`: Sniff solved in 4 gives `"Sniff 12: 4 of 6\nhttps://play.conleychaos.com/daily"`.
  - `nineLivesShowsTimeOnly`: "Nine Lives 12: 4:07".
  - `pngRenders`: the data starts with the PNG signature, and the image is 1200 px wide.
  - `noLettersEver`: the share holds no field that takes letters (no API for them).
- [ ] Implement, test and commit.

### Task 6: The app model and the Dish route

**Files:**
- Modify: `Pounce/App/Route.swift`: add `case dish` and `case daily(game: String)`.
- Modify: `Pounce/App/RootView.swift`: route keys and screens.
- Modify: `Pounce/App/AppModel.swift`: `let daily: DailyStore`, with person following the owner
  like `trophies`, and `func openDish()`, `func openDaily(_ game: String)`.
- Create: `Pounce/Daily/DailyDemo.swift` (DEBUG): `-demo-dish [fresh|done|long]`, a
  `DailyService` in memory with a board for screenshots and UI tests with no server.

### Task 7: Home, redesigned

**Files:** Modify `Pounce/Shell/HomeView.swift`. Create `Pounce/Daily/DishBand.swift`.

The column becomes: notices, then the Dish band (while `daily.enabled == true`), then what
leads. The Dish band is a candy panel titled "Daily Dish" with the day's number and four treats
in one row. Each treat has the game's color disc and glyph, a check once done, your short result
or "Play", and a small "playing" dot. Tapping the title opens the Dish, and tapping a treat opens
that puzzle (or its end screen, once done). On a phone, when the Dish shows and there are no
tables, the shelf drops its posters for tickets, so the Dish and a game both fit above the dock.
On an iPad the band spans the column above the tables and shelf, side by side in landscape. At
accessibility sizes the treats go two by two.

- [ ] Shots before and after: SE, Pro Max, iPad portrait and landscape, AX5.

### Task 8: The Dish screen

**Files:** Create `Pounce/Daily/DishScreen.swift`, `Pounce/Daily/DailyBoardView.swift`,
`Pounce/Daily/DailyStatsView.swift`, and `Pounce/Daily/DailyArt.swift` (each game's color and
glyph).

- The bar has Back and the title "Daily Dish".
- The four cards, two by two on a phone and four across on an iPad. Each shows the number, your
  result and the best on the board.
- The board: a segmented row (Dish, then one tab per game). Rows show rank, cat, name and the
  result with its mark (solved, missed or hinted). Playing rows show a progress ring. There is no
  "last".
- Stats per game for the selected tab: played, solve rate, current and best streak, best, a
  small chart (Sniff's guesses 1 to 6, or the last 30 days' times or points), and a 30-day strip.
- "Show board on TV" opens `ShowOnTVSheet(target: .board)`. "Unlink" calls
  `unlinkBoard` and shows only after a link this session or while `tvs > 0`.
- The tip `UITip.dishFirst` (`ui.dish.first`, screen `.dish`, anchor `dish.cards`): "Four new
  puzzles every day."

### Task 9: The puzzle host

**Files:** Create `Pounce/Daily/DailyPuzzleScreen.swift` and `Pounce/Daily/DailyEndView.swift`.

- It begins the run through `DailyRunSession.begin`, off the main actor, then
  `DailyHost.prepare`. It shows a spinner meanwhile, and "Puzzle not found" on a 404.
- The top bar: Back, the title and number, the clock (a `TimelineView` once a second, from
  `session.clock.elapsedMs(at:hints:)`), the Show on TV switch (only while `daily.tvs > 0`; it
  calls `showOnTV`), and Give up (with a confirmation).
- "Reconnecting" shows while `.link(.retrying)`.
- In the last 15 minutes: "The Dish turns over at 4:00".
- The end view: the result, your place on today's board, Share (hidden for kittens), Stats, and
  "Next puzzle" (the first game you haven't played).

### Task 10: The local server and the UI tests

**Files:** Create `PounceUITests/DailyTests.swift` and `PounceUITests/DailyShotTests.swift`.

- `testTheTestGamePlaysToTheEnd`, against `wrangler dev --port 8806` with
  `--var DAILY:on --var DAILY_TEST:on`: Home, then the Dish, then Count, then Step until solved,
  then the end view (result and place), then Share appears, then the board lists Me.
- `testGiveUp`, and `testDishHiddenWhenOff` (a server without DAILY).
- Frame gate: `FrameRateTests.testDishBoardUpdatesAtTheTopFrameRate` (the `-demo-dish` board
  with live progress ticks).
- Shots: Home before and after, the Dish, the host, and the end, on SE, Pro Max, iPad portrait
  and landscape, and AX5.

### Task 11: Rebase and the PR

Once S1 has merged: `git rebase --onto origin/main 8395901`. Then build, run the tests and the
lint, and open the PR "Daily puzzles get a home in the app (switched off until launch)" with the
shots. Don't merge.
