# Toy Tumble on iPhone, iPad and Apple TV Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Toy Tumble plays on iPhone and iPad, and the Apple TV table shows every box live. It is hidden in Release builds below 1.4.

**Architecture:**
- A Swift port of the box engine in PounceKit passes every shared fixture cell for cell.
- A SpriteKit scene runs the local box on the frame clock at the screen's maximum rate. It replays other boxes from the relayed stream.
- The Apple TV app uses the same board nodes at TV scale.
- Networking stays in PounceKit's IO layer (`RoomSocket`), off the main thread.

**Tech Stack:** Swift, SpriteKit, SwiftUI, XCTest, xcodegen (`project.yml`).

**Spec:** `docs/superpowers/specs/2026-11-26-toy-tumble-design.md`. The wire is `docs/live-protocol.md`. The engine contract is the server plan's Tasks 1 to 3 and `apps/play-api/fixtures/tumble/*.json`.

**Precedent:** the Birdwatch iOS and TV PR, commit `a15a31ca` (`git show --stat a15a31ca`). Follow its layout: `Pounce/Birdwatch/*` (Scene, Stage, Input, Panels, TableView, Demo, Autoplay), `HowToGuide`, `Tips`, `LobbyView`, `ArtName`, `Art/manifest.json`, the `PounceTV` model and table preview, UI tests, TV scene tests and `dev-server.sh`.

## Global Constraints

- The other games' names and the trade words for their pieces appear nowhere. Code says toy, box, row, junk and trick. The words test scans `apps/play-ios/**/Tumble*`.
- UI words are exactly those in the web plan's Global Constraints (shared copy).
- The constants match the web plan:
  - batches;
  - the junk wait;
  - gravity, the Zoomies and Catnip;
  - the set-down wait.
- **Gates (§10.4):**
  - `GameCatalog`'s Toy Tumble entry, and `tumble` in `x-pounce-games`, exist only when `#if DEBUG`, or when the bundle's short version is 1.4 or later. Release 1.3 builds never show or request it.
  - The server refuses older apps itself.
- **Main thread:** SpriteKit's update, the engine step (< 0.5 ms) and drawing only. Socket, decode and storage stay in PounceKit's IO layer. `main-thread-lint.swift` must pass. 8.3 ms per frame.
- `preferredFramesPerSecond` is the screen's maximum. Gravity comes from the frame clock and is independent of frame rate.
- **Simulators:** your own, named "Toy Tumble <device>". Mute each after boot and before launch with `xcrun simctl spawn <udid> defaults write com.conleychaos.play settings.soundOn -bool NO`, and on Apple TV also `tv.soundOn`. UI tests pass `-settings.soundOn` `<false/>`. Delete your simulators and build output when done.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Going to the background mid-round** (a call, the home screen, Control Center). The socket drops. On return within 15 s the box syncs and play goes on. Later, the player watches until the next round. Pinned in Task 2.
2. **The system edge gestures.** A drag near the left edge must not trigger back navigation, and a flick down near the top must not pull Notification Center into the toy's path. Pinned in Task 3.
3. **iPhone SE with 6 players at the largest text size.** The board cells stay ≥ 20 pt, the minis and tray fit, and the text-bearing chrome scales without collisions. Pinned in Task 4.
4. **ProMotion.** At 120 Hz, gravity and the set-down wait take the same wall time as at 60 Hz. Pinned in Task 2.
5. **Apple TV with 6 boxes and constant hits.** No dropped frames, and toys glide between updates. Pinned in Task 5.

---

### Task 1: The Swift engine passes every fixture

**Files:**
- Create: `apps/play-ios/PounceKit/Sources/PounceKit/Tumble/TumbleRng.swift`, `TumbleToys.swift`, `TumbleQueue.swift`, `TumbleBox.swift`, `TumbleCodec.swift`, `TumbleWire.swift`
- Create: `apps/play-ios/PounceKit/Tests/PounceKitTests/TumbleFixtureTests.swift` (or the package's existing test target)
- Modify: the package resources, so the tests read `apps/play-api/fixtures/tumble/*.json` the way other protocol fixtures are read (see how `Rules/*-messages.json` are shared)

**Interfaces:**
- Produces Swift mirrors of the server plan's Task 1 to 4 names:
  - `TumbleRng.next(_ s: [UInt32]) -> (UInt32, [UInt32])`;
  - `ToyId`, `toyCells`, `spawn`, `toyAt`;
  - `struct Box: Codable, Equatable`;
  - `setDown`, `receiveJunk`, `applyHit`, `useTrick`, `turn`, `fits`;
  - the wire types, `Codable`, decoding exactly `docs/live-protocol.md`.
- Use `Int` for cells, `UInt32` arithmetic with wrapping operators (`&*`, `&<<`) for xoshiro, and the same float `Double(u) / 4294967296`.

- [ ] **Step 1: Write the failing test.** For every fixture file and every step, run the op and assert the box text, `held`, `waiting`, `next`, `rng`, `out` and `rows`, and every expected field, are equal. Also assert `queue[i] == toyAt(roundSeed, i)`.
- [ ] **Step 2: Run, expect FAIL.** Run `swift test --package-path apps/play-ios/PounceKit --filter TumbleFixtureTests`, or the package's test command from `apps/play-ios/README.md`.
- [ ] **Step 3: Implement, porting line for line from `apps/play-api/src/tumble/*.ts`.**
- [ ] **Step 4: Run, expect PASS on all fixtures.**
- [ ] **Step 5: Commit.**

### Task 2: The local box, replay and the socket

**Files:**
- Create: `PounceKit/Sources/PounceKit/Tumble/TumbleLocal.swift` and `TumbleReplay.swift` (mirrors of the web plan's Task 1), plus tests
- Modify: `PounceKit/Sources/PounceKit/Net/RoomSocket.swift` (send `tumble` batches, and decode `tumble`, `tumbleHit`, `tumbleSync` and `tumbleSeat` off the main thread), and `Protocol/*` (the message enum)

- [ ] **Step 1: Write the failing tests.**
  - Gravity by wall time: steps at 8.33 ms and at 16.67 ms reach the same row at 1000 ms (Review Focus 4).
  - The junk wait and landing.
  - Batching at 50 ms with a flush on set-down.
  - Replay of the fixture streams.
  - A `q` gap gives a sync request.
  - A return from the background gives a sync request before any step (Review Focus 1).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit.**

### Task 3: The SpriteKit scene and touch controls

**Files:**
- Create: `apps/play-ios/Pounce/Tumble/TumbleScene.swift`, `TumbleBoxNode.swift` (one box at any cell size, with settled cells rendered to one texture, re-made only on a set-down or hit), `TumbleInput.swift`, `TumbleStage.swift` (layout), `TumbleTableView.swift`, `TumbleDemo.swift` and `TumbleAutoplay.swift` (for UI tests and DemoMode, as Birdwatch has)
- Modify: `Pounce/Shell/TableScreen.swift` (route the game), `Pounce/App/DemoMode.swift`

- [ ] **Step 1: Write the failing UI test** `PounceUITests/ToyTumbleTests.swift`, as `BirdwatchTests.swift` does.
  - In a demo round against House Cats:
    - a drag moves the toy;
    - a tap turns it;
    - a flick drops it;
    - a trick dragged onto a mini is used.
  - A drag starting 4 pt from the left edge moves the toy and doesn't navigate back (Review Focus 2).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement spec §5.2 and §5.3.**
  - Input is handled in `touchesBegan`, `touchesMoved` and `touchesEnded`, applied at once.
  - Swipe-back is off, and `preferredScreenEdgesDeferringSystemGestures` is all edges while playing.
  - Haptics: light on set-down, medium on a clear, strong on a hit.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit.**

### Task 4: Art, lobby, shelf, tips, How to play

**Files:**
- Modify:
  - `Art/manifest.json` and `Art/prompts/tumble/*`: the toy cushions in 4 toy colors with stitched silhouettes, hairball rows, trick badges, the box and rim cat moods, and the cover `game-tumble`.
  - `Pounce/Design/ArtName.swift`
  - `GameCatalog.swift`: the gated entry, 2 to 6 players, tint `lime`.
  - `Pounce/Shell/LobbyView.swift`: the Cats pills, one seat per device, "Waiting for Sam" and "Play without Sam".
  - `Pounce/Shell/Tips.swift` and `CoachMark.swift`: the five tips.
  - `Pounce/Shell/HowToGuide.swift`: the Toy Tumble page with the tricks table.
  - `apps/play-ios/README.md`
- [ ] **Step 1: Hold the style checkpoint.** Render the 9 toys, hairball rows and badges at mini size and at full size, next to the spec §3 table. Check each row's difference, and redraw anything close before production art. Put the images in the PR.
- [ ] **Step 2: Write snapshot and layout tests** for iPhone SE, iPhone 17 Pro Max, and iPad portrait and landscape, at 2 and 6 players and the largest accessibility text size (Review Focus 3). Write a `GameCatalog` test: the entry exists in Debug and is gated by version in Release.
- [ ] **Step 3: Run, expect FAIL, then implement, then PASS.**
- [ ] **Step 4: Commit.**

### Task 5: Apple TV table and frame gates

**Files:**
- Modify: `PounceTV/App/TVModel.swift`, `TVRoom.swift`, `TVStandings.swift`, `TVTablePreview.swift`, `PounceTV/Shell/TableHost.swift`, `HomeView.swift`, `LobbyView.swift`
- Create: `PounceTV/.../TumbleTVScene.swift` (reusing `TumbleBoxNode`), `PounceTVTests/TumbleSceneTVTests.swift`
- Modify: the iOS frame-rate UI test and its TV counterpart, adding Toy Tumble cases

- [ ] **Step 1: Write the failing tests.**
  - A `tumbleSync` of 6 boxes lays out 6 in a row, filling the safe area.
  - Glide interpolation between `m` updates.
- [ ] **Step 2: Implement spec §5.6.**
- [ ] **Step 3: Add the frame gates.**
  - 60 s of scripted play on iPhone against 5 House Cats with hits, at 120 Hz where the simulator allows.
  - The Apple TV showing 6 boxes for 60 s (Review Focus 5).
  - No frame over budget, and no hang.
- [ ] **Step 4: Run the touched tests, expect PASS.** Run `xcodebuild test` with the schemes and test plans named in `apps/play-ios/README.md`, filtered to the Toy Tumble tests and the frame gates, on your own muted simulators.
- [ ] **Step 5: Cross-play check.** Against your local server, with `GAMES` including `tumble` on a free port, play one table with this app on an iPhone simulator, the web player in muted Chromium, and the Apple TV simulator as the screen. Capture screenshots or a short recording for the PR.
- [ ] **Step 6: Commit, push and open the PR "Toy Tumble on iPhone, iPad and the TV: falling toys, tricks and hairballs"**, with screenshots of every screen touched. Delete your simulators and build output.
