# Pounce on the TV, stage 4: Apple TV — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pounce runs as an Apple TV app — the first-class TV. It shows the table for both games at the display's top frame rate, links to a phone's table by QR or backup code, makes tables, and never needs text entry. It ships to TestFlight Family and Friends.

**Architecture:** A tvOS application target `PounceTV` in `apps/play-ios/project.yml` with the iPhone app's bundle id (`com.conleychaos.play`, universal purchase). PounceKit adds `.tvOS(.v26)`. The SpriteKit table code under `Pounce/Table` and `Pounce/Tiles` is compiled into both targets: one copy of the drawing code. Touch input, haptics, edge-pan gestures and the hand stay iOS-only behind `#if os(iOS)`, and a few UIKit calls go through a small seam. The TV builds a seatless *TV arrangement* from PounceKit's layout. The shell is a small SwiftUI app driven by the focus engine.

**Tech Stack:** Swift 6 with strict concurrency, SwiftUI on tvOS 26, SpriteKit, PounceKit, XcodeGen, XCTest and XCUITest on the Apple TV simulator, App Store Connect API (`scripts/distribute.swift`).

**Spec:** `docs/superpowers/specs/2026-11-16-tv-table-design.md` §1–§5, especially §4 "The TV table" and §5 "The Apple TV app". Wire contract: `docs/tv-protocol.md`. Code map: `ios-map.md` in the stage workspace. The web TV page (`apps/play-web/src/ui/tv/`, stage 2) is the reference for TV behaviour and copy.

**Order:** This stage starts after stage 3 (iPhone) has merged, because both touch `TableScene`, `TableLayout`, `RoomStore`, `Messages.swift` and `APIClient`.

## Global Constraints

- **Bundle id and versions.**
  - The bundle id is `com.conleychaos.play`, the same as the iPhone app.
  - Deployment target: tvOS 26.0.
  - Marketing version follows the iPhone app's.
  - Build numbers come from CI, as for iOS.
- **No `PROTOCOL_VERSION` change.** The TV is a screen as defined in `docs/tv-protocol.md`:
  - it connects with `role=screen`;
  - it makes tables with `screen: true`;
  - it links with `/v1/screens`;
  - it closes the waiting socket on `linked` and ignores `expired` after it;
  - it goes home on 403 `not_screen` or 404;
  - it follows `rematch`.
- **The TV never receives or draws a hand or rack.** The scene never builds a face for a hand card. Add an assertion test and keep the property from stage 1.
- **Nothing is typed on the TV.**
  - No `TextField` or keyboard anywhere.
  - The Siri Remote (and a game controller's d-pad) moves focus. Select activates.
  - The Menu or Back button opens the TV menu at the table and goes back elsewhere.
  - Play/Pause does nothing harmful.
- **Copy matches the web TV page exactly:**
  - home: "Scan with your phone to put your table here", "Cat Tower", "Tuna Tiles";
  - lobby: "Scan to join", "Press Start on any phone", "Change game";
  - table: "<Name>'s turn";
  - game over: "Play again on any phone";
  - menu: "Link another table", "Leave table", "Sound on"/"Sound off".
  - No emoji.
- **Sizing for the couch.**
  - Nothing that matters is under 28 pt at 1080p.
  - Lay out for 1920×1080 points. tvOS scales to 4K, and the TV-safe area (`safeAreaInsets`, about 60/80 pt) is respected.
- **Main thread draws, nothing else** (`docs/main-thread.md`).
  - `scripts/main-thread-lint.swift` covers the `PounceTV` folder.
  - The table asks for the display's top rate, with the same idle behaviour as the iPhone tables.
  - The `FrameRateTests` tvOS variant passes on the Apple TV simulator.
- **Storage.** Only the device credential, in the Keychain, through the existing `KeychainCredentialStore`. The kept room code and the sound setting are small values in `UserDefaults`, read and written through the IO layer, not on the main thread.
- **The TV plays the game sounds.** There are no haptics on the TV.
- **Fit.**
  - Apple TV 4K at 1080p and 4K output, and Apple TV HD.
  - Long names (20 characters) and 3-digit scores.
  - 2–6 Cat Tower seats and 2–4 tile seats.
- **Shipping.**
  - The tvOS build uploads to TestFlight and goes to the Family and Friends group, the same as every app change.
  - Adding the tvOS platform to the App Store Connect record is OK'd by JD (2026-11-16, via the manager session) using CI's ASC API key, and no other account change.
  - App Store screenshots and review notes for tvOS are prepared, but nothing is submitted for App Store review without JD.
  - Privacy answers come from the code. The TV collects less than the phone (device identifier only, no name and no age).

## Review Focus

1. **Remote edge cases.**
   - The Menu button at the root of the app must not exit mid-game without the menu.
   - Focus is never lost after a phase change (lobby → table → over → home).
   - A long-press Select does nothing harmful.

   Covered by a Task 6 UI test.
2. **The Apple TV sleeps or the app backgrounds mid-game.**
   - On return it reconnects to the same table as a screen.
   - Phones saw the TV leave after the 10 s grace and come back.

   Covered by a Task 5 test using `RoomStore` with a fake socket.
3. **4K and Apple TV HD.** The same layout scales, with no blurry card faces (texture scale follows `UITraitCollection.displayScale` through the seam) and no clipping. Covered by Task 3 layout tests and Task 7 screenshots.
4. **A phone moves the TV to another table while it shows one.** The old room's screen socket is closed first, and the new room opens. Covered by Task 5.
5. **TestFlight upload of a second platform in the same app record.** `distribute.swift` finds the tvOS build (platform `TV_OS`) and doesn't confuse it with the iOS build of the same number. Covered by Task 8 `--dry-run` output.

---

### Task 1: PounceKit on tvOS, and the TV's own client pieces

**Files:**
- Modify: `PounceKit/Package.swift`: platforms gain `.tvOS(.v26)`.
- Modify: `PounceKit/Sources/PounceKit/Update/AppIdentity.swift`: on tvOS the header says `platform=tvos`. Check the server's `parseApp` accepts it (`apps/play-api/src/app/version.ts`). If it doesn't, add `tvos` there with a test (additive).
- Modify: `PounceKit/Sources/PounceKit/Net/APIConfig.swift`: `socketURL(code:role:)` adds `role=screen`.
- Modify: `PounceKit/Sources/PounceKit/Net/APIClient.swift`:
  - `screens(showing:) async throws -> ScreenLinkOffer`, where `ScreenLinkOffer` is `{token, code, url, expiresIn}`;
  - `createRoom(game:screen:)`.
- Create: `PounceKit/Sources/PounceKit/Net/ScreenLink.swift`:
  - an actor that asks for a link and holds the waiting socket;
  - it renews at 80 % of `expiresIn`, keeping the old socket until the new one opens;
  - it emits `.code(token, code, url)`, `.linked(room)` and `.offline`;
  - it stops after `linked`.
  - Mirror the web `ScreenLink` (`apps/play-web/src/net/screen-link.ts`) and its tests.
- Modify: `PounceKit/Sources/PounceKit/Store/RoomStore.swift`: a `role: .screen` option passed to the socket. 403/4403 `not_screen` and 404 become a terminal `notFound`.
- Test:
  - `ScreenLinkTests.swift`: renewal at 80 %, `linked` arriving on the old socket during renewal, `expired` ignored after `linked`, 4404 → renew.
  - `RoomStoreScreenTests.swift`.
  - Run tvOS PounceKit tests with `xcodebuild test -scheme PounceKit -destination 'platform=tvOS Simulator,name=<own sim>'`, plus the macOS `swift test`.

- [ ] Failing tests → implement → `swift test --package-path PounceKit` and the tvOS `xcodebuild test` both pass → commit "Apple TV: PounceKit runs on tvOS and speaks to TVs".

### Task 2: The table code compiles for tvOS (the seam)

**Files:**
- Modify the files the iOS map lists as UIKit or iOS-only inside `Pounce/Table` and `Pounce/Tiles`:
  - guard touch overrides, edge-pan recognizers, `UIAccessibility.post` (where tvOS lacks it), `Haptics` calls and `UIScreen.topFrameRate` behind `#if os(iOS)`;
  - or route them through `Pounce/Design/Platform.swift`, a new file holding `displayScale`, `topFrameRate(for:)`, `reduceMotion` and `postAnnouncement` with an iOS and a tvOS implementation.
- Modify: `Pounce/Design/Haptics.swift`: `SilentHaptics` on tvOS.
- Modify: `Pounce/Design/Sound.swift`: compiles on tvOS. The ambient session stays iOS-only.
- Modify: `project.yml`:
  - add the `PounceTV` application target (tvOS 26, the same bundle id, its own `PounceTV/Info.plist` and entitlements with Keychain group and associated domains not required);
  - its sources are `PounceTV/**` plus `Pounce/Table/**`, `Pounce/Tiles/**` and the needed `Pounce/Design/*` files, listed explicitly like PounceWidgets;
  - its resources are the shared art catalogs (`Cards`, `Cats`, `FX`, `Table` sprite atlases and the image sets the table uses);
  - add a `PounceTV` scheme.
- Create: `PounceTV/Resources/TVAssets.xcassets` with the tvOS App Icon & Top Shelf brand assets. tvOS requires these:
  - layered app icon (400×240 @1x/@2x, and 1280×768 for the App Store), at least 2 layers;
  - Top Shelf image (1920×720) and Top Shelf wide (2320×720).

  Compose them from the existing art (`home-bg`, the cat and the logo treatment) with a script in `AppStore/` (Swift + CoreGraphics). Commit the outputs. The art should be loud and cartoony, matching the iPhone icon.
- Create: `PounceTV/App/PounceTVApp.swift`, a placeholder root view, so the target builds.

- [ ] `xcodebuild build -scheme PounceTV -destination 'generic/platform=tvOS'` passes, and the iOS `Pounce` scheme still builds and its UI tests still pass. Run `swift scripts/main-thread-lint.swift`, with `PounceTV` added to `checkedRoots`. Commit "Apple TV: the table code builds for tvOS".

### Task 3: The TV arrangement (layout, in PounceKit)

**Files:**
- Modify: `PounceKit/Sources/PounceKit/Layout/TableLayout.swift`: `Arrangement.tv`, seatless:
  - every playing seat around the table;
  - the piles centred and large;
  - laid groups beside their seats;
  - the tower on the left;
  - a banner rect;
  - a menu-hint corner.
- Modify: `PounceKit/Sources/PounceKit/Layout/TilesLayout.swift`: `.tv`, with seats across the top, the board filling the space, the pool and the banner.
- Port the decisions already tested in the web's `ctLayout({tv:true})` and `tilesLayout({tv:true})` (`apps/play-web/src/table/ct-layout.ts`, `tiles-layout.ts`, `tests/layout.test.ts`): same proportions, same worst cases.
- Test: `TableLayoutTVTests.swift` and `TilesLayoutTVTests.swift`.
  - Sizes: 1920×1080 with the TV-safe insets, and 1280×720.
  - Seats: 2–6 Cat Tower seats with 3 groups of 10 each, and 2–4 tile seats with 30 sets of 3.
  - Assert everything is inside the safe frame, there is no overlap, and the card width is at least 112 pt at 1080.

- [ ] Failing tests → implement → pass → commit "Apple TV: a big-screen layout for both games".

### Task 4: The scenes draw the TV table

**Files:**
- Modify: `Pounce/Table/TableScene.swift` and `Pounce/Tiles/TilesScene.swift`.
  - With `.tv`:
    - no hand, trays or input;
    - every seat drawn;
    - the turn banner;
    - celebrations at TV scale;
    - game sounds on;
    - the aim glow on `aims[turn]`;
    - the tile draft shown from `aims[turn].table`, with new pieces marked.
  - With `.phone`, `.tall` and `.wide`, behaviour is unchanged.
- Modify: `Pounce/Table/TableView.swift` / `Pounce/Tiles/TilesTableView.swift`. On tvOS they host the SKView with `runAtTopFrameRate`, using `preferredFramesPerSecond` from the screen's maximum and the same idle pause as the `AnimationDirector`.
- Test:
  - A unit test that a scene in `.tv` with a snapshot from a seated room never creates a hand face node, even when given a view with `hands` (defence in depth).
  - The iOS `FrameRateTests` still pass.

- [ ] Implement → iOS UI tests and frame-rate tests on an iPhone simulator you create yourself → commit "Apple TV: the table draws itself for the TV".

### Task 5: The TV shell

**Files:**
- Create in `PounceTV/Shell/`:
  - `HomeView`: the link QR (reuse the CIFilter QR renderer from `Pounce/Shell/ShareRoom.swift`, moved to a shared file), the backup code, and the two game posters.
  - `LobbyView`: the invite QR and code, cats walking on, "Press Start on any phone", and "Change game" only while nobody is seated.
  - `TableHost`: the SKView with the scene in `.tv`, the banner, and the "Reconnecting" note.
  - `GameOverView`: ranked, "Play again on any phone", following rematch.
  - `TVMenu`: Menu button, with "Link another table", "Leave table" and "Sound on"/"Sound off".
- Create: `PounceTV/App/TVModel.swift`.
  - Phases: home, lobby, table, over.
  - Keeps the room code. Rejoins it on launch.
  - The link move closes the old room's screen socket first.
  - Handles `not_screen`/404 by going home.
  - Handles the scene phase: background closes sockets, active reconnects.
- Use the focus engine: `.focusable()`, `focusSection()`, `@FocusState` defaults, `.onExitCommand` for Menu.
- Test: `PounceTVTests` (unit) for `TVModel` with a fake socket and API:
  - link → room;
  - move;
  - not_screen → home;
  - rematch follow;
  - background/active rejoin;
  - Change game shown only while nobody is seated.

- [ ] Failing tests → implement → screenshots on an Apple TV simulator you create (Apple TV 4K at 1080p, and Apple TV HD) of every phase for both games, against your own dev server (port 8800). Phones are browser phones (stage 2's web) or `pounce-e2e`. Look at each screenshot → commit "Apple TV: home, lobby, table and game over on the TV".

### Task 6: Frame-rate gates and remote UI tests on the Apple TV simulator

**Files:**
- Create: the `PounceTVUITests` target in `project.yml`, with `FrameRateTVTests.swift`:
  - the tvOS variant of `PounceUITests/FrameRateTests.swift`;
  - a DEBUG `-demo tv-hit` and `-demo tv-tiles` driving a fake socket, like the iOS demos;
  - the same pass/fail rules (top rate asked; no main-thread hang over 100 ms; app work ≤ 8.3 ms per frame where the display runs 120 Hz, otherwise ≤ 16.7 ms).
- Create: `RemoteTests.swift`. Driving with `XCUIRemote.shared.press(.right/.select/.menu)`, it covers:
  - home → a game → lobby → Menu → Leave;
  - focus never lost.
- Modify: `apps/play-ios/scripts/frame-rate.sh` takes `PLATFORM=tvOS`.
- Modify: `.github/workflows/ios.yml`:
  - the `build` job also builds `PounceTV` for `generic/platform=tvOS` and runs the PounceKit tvOS tests;
  - an optional `TV smooth play gates (Apple TV simulator)` job, a sibling of the iOS one;
  - the distribute path filter adds `PounceTV`.

- [ ] Run locally on your own Apple TV simulator and record the frame numbers → commit "Apple TV: smooth-play and remote checks on the Apple TV simulator".

### Task 7: Store assets, privacy and review notes

**Files:**
- `PounceTV/Resources/PrivacyInfo.xcprivacy` (the TV's own: device ID for app functionality; nothing else).
- `docs/privacy/app-store-label.md`: a tvOS note.
- `docs/app-review-notes.md`: a tvOS section saying how to test without an iPhone (the TV makes a table and a browser at play.conleychaos.com/play joins it). Keep it under the character limit.
- `AppStore/`: a tvOS capture path, with 1920×1080 screenshots from the simulator (home, lobby, both tables, game over).

- [ ] Commit "Apple TV: store screenshots, privacy and review notes".

### Task 8: TestFlight, cross-platform matrix, and the PR

- [ ] `scripts/testflight.sh` takes `PLATFORM=tvOS` (scheme `PounceTV`, `generic/platform=tvOS`, its own archive path), and `distribute.swift` takes `--platform TV_OS`, filtering builds by platform. Run `--dry-run` locally.
- [ ] CI (`ios.yml` testflight job) archives and uploads both iOS and tvOS on merge, and distributes both to Family and Friends.
- [ ] Add the tvOS platform to the ASC app record. JD OK'd this. Use a one-off `workflow_dispatch` input `add_tvos_platform` that runs a small script with CI's ASC key (`POST /v1/appStoreVersions` with `platform: TV_OS` and the current version string, if the record has no tvOS version yet). Run it once via `gh workflow run`, and confirm with its log. Do nothing else in ASC.
- [ ] Cross-platform matrix on our own dev server:
  - Apple TV simulator as the screen, with the iPhone simulator app (stage 3) and a browser phone at one table, for both games, played to the end;
  - an older iPhone build at the Apple TV table;
  - the Apple TV moved between tables by a phone.
- [ ] Message the manager session with what JD needs to do for the real Apple TV test (pair it in Xcode › Devices, keep it awake, the TestFlight app on the TV). Use the device when JD has it ready. Otherwise record the simulator results.
- [ ] PR "Pounce on Apple TV" with before/after (new: the TV screens), frame numbers and the matrix. Merge when `check`, `build` and `e2e-web` are green (and the TV gates, if they ran). Confirm the TestFlight tvOS build reaches Family and Friends.
- [ ] Delete every simulator this stage made.
