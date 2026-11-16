# Pounce on the TV, stage 3: iPhone — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a TV shows the table, the iPhone app shows only your own cards with a Cards/Table switch. "Show on TV" scans the TV's QR (or takes its backup code) to put the table there. `/tv/<token>` universal links open the app. The app sends live `aim`, and it keeps game sounds quiet on Cards.

**Architecture:** PounceKit learns the wire additions from `docs/tv-protocol.md`: `RoomView.screen`, the `aim` message both ways, and `POST /v1/screens/link`. The controller is not a second table. It is the same `TableScene`/`TilesScene` in a new *controller arrangement* from PounceKit's layout code. The opponents bar, tower and laid zone are hidden, and the hand, trays and piles fill the phone. Hit targets come from a short SwiftUI list built on the existing `HitAims`. All new IO (camera, network, the view preference) goes through the existing off-main layers.

**Tech Stack:** Swift 6, SwiftUI, SpriteKit, PounceKit (Swift package), VisionKit `DataScannerViewController` for the QR, XCTest/XCUITest.

**Spec:** `docs/superpowers/specs/2026-11-16-tv-table-design.md` §2 (Show on TV, camera), §3. Wire contract: `docs/tv-protocol.md`. Code map: `ios-map.md` in the stage workspace.

## Global Constraints

- No `PROTOCOL_VERSION` change. Every decode stays tolerant: an app built from this stage still plays at a table with no TV, and still plays against a server with `TV` off.
- The main thread draws, and does nothing else (`docs/main-thread.md`):
  - no disk, Keychain, network waits, sleeps or locks on main;
  - `scripts/main-thread-lint.swift` must pass;
  - `FrameRateTests` must still pass at the top frame rate;
  - the camera session runs off main (VisionKit manages its own queue).
- Controller default:
  - When `room.screen == true` and the phone holds a seat, the phone shows Cards.
  - The switch is on the controller screen, always visible, one tap: "Cards" | "Table".
  - The choice is per phone, per table, and is kept (newest 30 tables).
  - When `screen` is absent, the phone shows the full table whatever the switch says.
  - When `screen` returns, a phone on "Table" stays on "Table".
- Sound:
  - On Cards, no game-event sounds; button taps stay.
  - On Table, game-event sounds play as today.
  - Haptics stay on, and `turn` buzzes on your turn in both views.
- Copy, exact:
  - "Cards", "Table", "Show on TV", "Type the TV's code", "TV code", "Show", "On the TV".
  - "Move the TV to this table?", with "Move" / "Cancel".
  - "No TV with that code.", "Too many wrong codes. Try again later."
  - Tip on the switch: "Your cards are here. The table is on the TV."
  - The camera purpose string: "Scan the code on your TV. The picture stays on your phone."
  - No emoji.
- Privacy:
  - The scanner reads only the QR's text. Frames never leave the phone and are never stored.
  - `PrivacyInfo.xcprivacy` gains nothing.
  - `docs/privacy/app-store-label.md` stays "not collected" for photos and video, with a line saying why.
- Fit: iPhone SE (3rd gen) 375×667, iPhone 17 Pro, Pro Max, iPad portrait and landscape, and the largest accessibility text size. Nothing clips or collides with the cat, the bars or the safe areas. Long names (20 characters) and 3-digit scores included.
- `/tv/*` joins the site association in this stage, not before. Universal links open this app, and a shipped 1.1 app that receives one simply opens. Record that in `docs/tv-protocol.md`.
- Every merge that touches `apps/play-ios` goes to TestFlight and the Family and Friends group (CI does this). The PR title is family-readable.

## Review Focus

1. **A phone with an old server or the TV flag off.** No `screen` key and no `/v1/screens`. Show on TV says "No TV with that code." and nothing else breaks. (Task 1 tests.)
2. **Scanning a QR that isn't Pounce's.** Any URL other than `https://play.conleychaos.com/tv/<22 chars>` is ignored, and the scanner keeps looking. (Task 4 unit test for the parser.)
3. **Camera permission denied.** The sheet shows "Type the TV's code" without crashing, and offers Settings only through the system's own control. (Task 4 UI test with the permission reset.)
4. **Pass and play on a controller.** The curtain still covers the hand between players, and the TV shows normal turns. (Task 3 UI test.)
5. **Rotation on iPad and Dynamic Type at the largest size, on the controller.** (Task 2 layout tests, Task 3 screenshots.)

---

### Task 1: PounceKit speaks TV

**Files:**
- Modify: `PounceKit/Sources/PounceKit/Protocol/Messages.swift`, which gains the `ServerMessage.aim(seat:aim:)` case, the `ClientMessage.aim(seat:aim:)` case and its encode branch, and the `GameAim` enum (`.target(seat:group:)`, `.table([[TileID]])`).
- Modify: `RoomView`, adding `screen: Bool?`. Find the file in `Protocol/`.
- Modify: `PounceKit/Sources/PounceKit/Store/RoomStore.swift`. It gains `aims: [Int: GameAim]`, cleared when a snapshot changes the turn or status, and `func aim(seat: Int, _ aim: GameAim?)`, throttled to one send per 120 ms with the latest value trailing. A nil clears at once.
- Modify: `PounceKit/Sources/PounceKit/Net/APIClient.swift`, adding `func linkScreen(_ by: ScreenKey, room: String, move: Bool) async throws -> ScreenLinkResult`. `ScreenKey` is `.token(String)` or `.code(String)`. `ScreenLinkResult` is `.linked` or `.showing`.
- Modify: `PounceKit/Sources/PounceKit/Protocol/DeepLink.swift`, adding `.tv(token:)`. It parses `https://play.conleychaos.com/tv/<22 base64url>` and `pounce-dev://tv/<token>` (dev only).
- Create: `PounceKit/Sources/PounceKit/Store/TableViews.swift`, the per-table Cards/Table preference store, persisted through the IO layer.
- Test:
  - `PounceKit/Tests/PounceKitTests/ScreenProtocolTests.swift` (extends the stage 1 file: the fixtures now decode into `.aim` and `screen == true`).
  - `RoomStoreAimTests.swift`, `InviteLinkTests.swift` (`/tv/`), `TableViewsTests.swift`.

- [ ] Write failing tests:
  - decode `fixtures/protocol/screen-server-messages.json`;
  - encode `aim` with and without a value (`{"t":"aim","seat":1,"aim":{"target":{"seat":0,"group":1}}}` / `{"t":"aim","seat":1}`);
  - throttle timing with an injected clock;
  - clear on turn change;
  - `DeepLink.parse`: `/tv/<token>` → `.tv`, a 21-char token → nil, another host → nil;
  - the preference store's default, set and cap of 30.
- [ ] Implement. Run `swift test --package-path PounceKit` → PASS. Commit "iPhone: PounceKit learns the TV's messages".

### Task 2: The controller arrangement (layout, in PounceKit)

**Files:**
- Modify: `PounceKit/Sources/PounceKit/Layout/TableLayout.swift`, adding `Arrangement.controller`.
- Modify: `PounceKit/Sources/PounceKit/Layout/TilesLayout.swift`, adding a rack-only arrangement for off turn.
- Test: `TableLayoutControllerTests.swift`, `TilesLayoutControllerTests.swift`.

**Interfaces:**
- `.controller` layout:
  - piles at the top under a status line;
  - the hand large at the bottom (card width ≥ 64 pt on SE);
  - trays above the hand;
  - room for the switch at the top and the action row;
  - no opponents bar, tower or laid zone frames.
- Tiles rack-only: the rack large and centred, and a status line.

- [ ] Write failing tests at 375×667, 402×874, 440×956, 820×1180 and 1180×820, with 11 cards and 3 trays (and 14 tiles plus a stash): every frame is inside the safe area, nothing overlaps, and the minimum sizes hold.
- [ ] Implement, test and commit "iPhone: a layout for just your cards".

### Task 3: Cards/Table on the table screen

**Files:**
- Modify: `Pounce/Table/TableScene.swift`, `Pounce/Table/TableInput.swift` and `Pounce/Tiles/TilesScene.swift`, so they honour the controller arrangement (hide opponents, tower and laid zone; keep hand, trays, piles and the curtain).
- Modify: `Pounce/Shell/TableScreen.swift`, which chooses the arrangement from `screen`, the seat and the preference, and shows the switch.
- Create: `Pounce/Shell/ViewSwitch.swift` (the "Cards"/"Table" pill, `.tipTarget("table.view")`) and `Pounce/Shell/HitList.swift` (the targets for a picked card, labelled "Mom's 3s", "Your run", "Ava's run of 7s").
- Modify:
  - `Pounce/Design/Sound.swift`: `play(_:volume:kind:)` with `.game` or `.ui`, and `gameMuted`.
  - The scene's sound calls, which become `.game`.
  - `PounceKit/Tutorial/UITips.swift` and `Pounce/Shell/Tips.swift`, adding `UITip.tableView`.
- Behaviour:
  - Picking a hit target sends `store.aim(seat, .target(...))`.
  - Confirm plays the hit.
  - Cancel, a turn end or playing it clears the aim.
  - On Tuna Tiles, every draft change on your turn sends `.table(draft)`, and submit or reset clears it.
- Test:
  - A UI test in `PounceUITests/ControllerTests.swift`, using a DEBUG `-demo controller` that feeds a fake socket with `screen: true`. It checks that the switch exists, that tapping Table shows the opponents bar, and that a hit through the list lands.
  - The frame-rate gate still passes.

- [ ] Implement.
- [ ] Take screenshots on SE, 17 Pro Max, iPad portrait and landscape, and at the largest text size. Cover both games, off turn, on turn, the hit list and pass and play.
- [ ] Run `scripts/ui-tests.sh` (own dev server port 8794) and `scripts/frame-rate.sh` on a simulator this stage creates. Commit "iPhone: your phone shows just your cards when the table is on the TV".

### Task 4: Show on TV

**Files:**
- Create: `Pounce/Shell/ShowOnTVSheet.swift`, which holds the scanner, the code entry and the confirm.
- Create: `Pounce/Shell/QRScanner.swift`, a `DataScannerViewController` wrapped in `UIViewControllerRepresentable`, recognising QR only.
- Create: `PounceKit/Sources/PounceKit/Protocol/TVCode.swift`, which normalises a typed code and parses a scanned URL.
- Modify:
  - `Pounce/Shell/TableMenuSheet.swift` and `Pounce/Shell/AddPlayerTray.swift` (the "Show on TV" item);
  - `Pounce/Shell/CodeKeypad.swift` (a 6-character mode);
  - `Pounce/Info.plist` (`NSCameraUsageDescription`);
  - `Pounce/App/AppModel.swift` (`handle(.tv(token))`).
- `handle(.tv(token))` works like this:
  - After onboarding, if a table is open, it links that table.
  - Otherwise it shows "Your tables" plus the game picker, and links whatever is picked or made.
- Modify: `apps/play-api/src/http/links.ts`, so `/tv/*` joins `components`. Also update `apps/play-api/tests/worker.test.ts`.
- Modify: `docs/privacy/app-store-label.md`, adding the camera line.
- Test:
  - `TVCodeTests.swift`: only Pounce TV URLs parse, and a typed code is normalised.
  - `ShowOnTVTests.swift` (UI test): type a code against the dev server with a scripted screen link, then see "On the TV". With permission denied, the code entry still works.

- [ ] Implement, test and screenshot. Commit "iPhone: Show on TV scans the TV's code".

### Task 5: Cross-platform check and the PR

- [ ] Matrix on our own dev server (port 8794) with `TV:on`:
  - the iPhone simulator as a controller with a browser TV page (stage 2) and a browser phone, playing both games;
  - an older app build (`git worktree` of `origin/main` before stage 3, built to its own simulator) at a TV table, playing the full table with no errors;
  - `pounce-e2e full` with a screen attached.
- [ ] Before and after screenshots in the PR.
- [ ] Open the PR "Your iPhone shows just your cards when the table is on the TV; Show on TV". Merge it when `check`, `build` and `e2e-web` pass and the smooth play gates are green. Confirm the TestFlight build reaches Family and Friends.
- [ ] Delete the simulators this stage made.
