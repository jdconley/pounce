# Pounce iOS App (play-ios) Implementation Plan — Plan 2 of 3

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native iPhone app JD can install from Xcode and play a full game of Cat Tower in against `wrangler dev` — real Codex-generated art in style D, juicy low-CPU SpriteKit animation, mixed own-phone / pass-and-play / bot seats — plus the two small `play-api` changes it needs and a TestFlight script ready for when JD's Apple setup is done.

**Architecture:** A local Swift package `PounceKit` holds every rule, protocol type, network client and state reducer (tested with `swift test`, no simulator). A thin XcodeGen-generated app target `Pounce` adds the SwiftUI shell and one SpriteKit `TableScene` that animates `TableIntent`s from the `RoomStore` and then reconciles to the latest server truth. Art comes from Codex CLI image generation through a small cutout/atlas pipeline, with named placeholders first so code never waits on art.

**Tech Stack:** Swift 6.4 (Swift 6 language mode, strict concurrency), Xcode 27, iOS 26 SDK, SwiftUI, SpriteKit, Core Haptics, AVFoundation, LinkPresentation, CoreImage, Network, Security, UserNotifications, Vision (art tool only), Swift Testing + XCTest/XCUITest, XcodeGen, Codex CLI (`codex exec`, `image_generation`), ImageMagick (`magick`). Server side: TypeScript, vitest, wrangler (all from the pnpm catalog).

**Spec:** `docs/superpowers/specs/2026-10-31-pounce-ios-design.md` (iOS design, approved) and its parent `docs/superpowers/specs/2026-10-31-pounce-cat-tower-design.md`. Server contract: `apps/play-api/src/protocol.ts`, `src/index.ts`, `src/rules/view.ts`, `src/rules/engine.ts`, `src/room/core.ts`, `src/push/apns.ts`, and `docs/superpowers/plans/notes/2026-10-31-play-api-followups.md`.

**Plan series:** 1 = server (done). 2 = this iOS app (M1). 3 = M2 social (Sign in with Apple, groups, push invites, Nearby, nudges, reactions, Kitten/Alley Cat, rematch).

## Global Constraints

- iOS 26.0 minimum, iPhone only, portrait only. Swift 6 language mode with complete strict concurrency. Bundle ID `com.conleychaos.play`, team `B222J9J7B8`, display name `Pounce`.
- **No third-party Swift packages.** Apple frameworks only. No new npm packages in `apps/play-api`.
- **No emoji anywhere** (UI, art, code strings shown to users). **No visible English text** except player names, the room code, move codes and card/score numerals. VoiceOver labels (spoken, String Catalog) are allowed and required.
- Art style D "Loud Toy": glossy 3D cartoon, very thick dark outlines, saturated violet / hot magenta / electric teal / sunny orange / sky blue. Never beige, cream, pastel, or the red/blue/green/yellow four-color set (including avatar rings). Reference: `apps/play-ios/Art/style-samples/chosen-d-loud-toy.png`.
- Coats: `tabby`, `tuxedo`, `calico`, `gray` — told apart by cat pattern + glyph (stripe / bow tie / three patches / paw), never color alone. Card ids: 0–95 numbers (`coat = id / 24`, `value = id % 12 + 1`), 96–103 Yarn, 104–107 Cucumber. Points: 1–9 = 5, 10–12 = 10, Cucumber = 15, Yarn = 25.
- Server is the authority; client validation only drives glows. Never render another seat's hand.
- Server contract: apply every `snapshot` even when `seq == lastSeq`; `room_closed` is terminal (socket may stay open); `hands` keys are strings; upload the APNs token every launch; reject snapshots whose `protocol != 1`.
- Room code alphabet `BCDFGHJKLMNPQRTVWXZ2346789`, 5 characters; move codes 6 characters, same alphabet, valid 10 minutes. Share link `https://play.conleychaos.com/j/<CODE>`; move link `https://play.conleychaos.com/j/<CODE>?move=<MOVECODE>`.
- Server constants the client relies on: 6 lobby seats (0–1 open, 2–5 closed), 2–6 players, bot delay 1.2 s, next round auto-starts 6 s after round over, away → asleep after 5 min.
- Base URL: Debug `http://localhost:8787`, Release `https://play.conleychaos.com`; env var `POUNCE_API_BASE_URL` overrides at launch.
- Render on demand: the `SKView` is paused whenever nothing animates; 60 fps cap; no `SKShapeNode`, `SKEffectNode` or Core Image filters at runtime.
- `apps/play-api`: keep `pnpm lint`, `pnpm typecheck`, `pnpm test` green, including 100 % coverage on `src/rules/**` and `src/room/core.ts`. Never commit `.dev.vars` or any secret; the repo is public.
- Commit after every task on the current branch, message ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

## Review Focus

1. **Socket drops mid-turn, then reconnects** — the reconnect snapshot (same `seq` as the last event) must be applied, the drawn card is in hand, and the player can discard without a stuck in-flight lock. (Task 8 test `inFlightClearsOnReconnectSnapshot`.)
2. **A known table that expired while the app was closed** — connecting returns 404; the app must show "room closed" and drop it from Home, not shake the join tiles. (Task 7 + Task 14 tests `knownCode404IsClosed`.)
3. **Turn moves between two seats on the same phone** — the curtain must cover the table and no hand nodes for the new seat may exist until the hold completes; a remote/bot turn in between hides any revealed hand. (Task 9 tests `curtainBetweenLocalSeats`, `remoteTurnHidesHand`.)
4. **Cucumber discard with no legal target** (every other seat already pending a skip) — the client must send `discard` without `skipTarget` instead of waiting for a target that can't be chosen. (Task 9 test `cucumberWithNoTargetsDiscardsPlain`.)
5. **Double-tap / two quick drags** — only one `act` may be in flight; the second gesture is ignored until the first resolves, so a stray `not_your_turn`/`bad_step` can never be blamed on the wrong action. (Task 8 test `secondActWhileInFlightIsRefused`.)

---

## File Structure

```
apps/play-api/                         (Plan 1 package; two small additions)
  assets/og-room.jpg                   1200×630 share image (already generated)
  scripts/embed-og.mjs                 writes src/http/og-image.ts from the jpg
  src/http/og-image.ts                 generated: base64 of og-room.jpg
  src/http/links.ts                    + Open Graph tags, ogImage() response
  src/index.ts                         + GET /og/room.jpg route, origin passed to sharePage
  tests/protocol-fixtures.test.ts      writes/verifies fixtures/protocol/*.json
  fixtures/protocol/server-messages.json, client-messages.json
  .dev.vars.example

apps/play-ios/
  project.yml                          XcodeGen spec (source of truth)
  .gitignore                           Pounce.xcodeproj/, Art/raw/, Art/cut/, build/
  README.md                            bootstrap, run, test, e2e, TestFlight, JD prerequisites
  scripts/bootstrap.sh                 xcodegen generate (installs via brew if missing)
  scripts/dev-server.sh                ensures apps/play-api/.dev.vars, runs wrangler dev on :8787
  scripts/e2e.sh                       dev server + `swift run pounce-e2e`
  scripts/screenshots.sh               demo-mode screenshots via simctl
  scripts/testflight.sh                archive + export + upload (not run in this plan)
  Pounce/
    Info.plist, Pounce.entitlements
    App/        PounceApp.swift, AppDelegate.swift, AppModel.swift, AppConfig.swift, Route.swift,
                PushCoordinator.swift, DemoMode.swift (DEBUG)
    Design/     Palette.swift, OutlinedText.swift, PillButton.swift, Juice.swift, Haptics.swift,
                Sound.swift, Settings.swift, ArtName.swift
    Shell/      PickCatView.swift, HomeView.swift, TableCard.swift, PeopleSheet.swift, JoinView.swift,
                CodeKeypad.swift, LobbyView.swift, SeatMenu.swift, ShareRoom.swift, TableScreen.swift,
                PassCurtainView.swift, TableMenuSheet.swift, MoveSeatSheet.swift, StateCard.swift,
                PushPrimingView.swift, GameOverView.swift
    Table/      TableView.swift, TableScene.swift, AnimationDirector.swift, CardFaceFactory.swift,
                CardNode.swift, CatNode.swift, HandNode.swift, PileNode.swift, TowerNode.swift,
                LaidZoneNode.swift, TrayNode.swift, OpponentsNode.swift, TableInput.swift,
                Effects.swift, IntentAnimations.swift, Celebrations.swift, TableAccessibility.swift
    Resources/  Assets.xcassets (AppIcon, imagesets, Cats/Cards/Table/FX .spriteatlas), Sounds/*.caf,
                Localizable.xcstrings
  PounceKit/
    Package.swift                      library PounceKit + executable pounce-e2e; iOS 26 / macOS 26
    Sources/PounceKit/
      Rules/       Card.swift, Group.swift, Phases.swift, Solver.swift
      Protocol/    Models.swift, GameEvent.swift, Messages.swift, Codec.swift, RoomCode.swift, DeepLink.swift
      Net/         APIConfig.swift, Credentials.swift, APIClient.swift, WebSocket.swift, RoomSocket.swift
      Store/       RoomStore.swift, TableIntent.swift, TableModel.swift, PassAndPlay.swift
      Layout/      TableLayout.swift
      Identity/    PeopleStore.swift, TableCache.swift, NameGenerator.swift
      Demo/        DemoFixtures.swift
    Sources/pounce-e2e/main.swift
    Tests/PounceKitTests/  Fixtures.swift + one test file per source area
  PounceUITests/  SmokeTests.swift, IdleRenderTests.swift
  Art/
    style-samples/, mockups/          (committed in the design step)
    manifest.json                      every asset: name, destination, point size, prompt
    prompts/*.txt                      Codex prompts (committed)
    tools/gen.sh, cutout.swift, build-assets.sh, placeholders.sh, sfx.swift
```

---

### Task 1: Share page Open Graph tags and image (`apps/play-api`)

The Messages bubble on the invitee's phone is built by Messages fetching `/j/<CODE>`; it needs Open Graph tags and an image.

**Files:**
- Create: `apps/play-api/scripts/embed-og.mjs`, `apps/play-api/src/http/og-image.ts` (generated, committed)
- Modify: `apps/play-api/src/http/links.ts`, `apps/play-api/src/http/links.test.ts`, `apps/play-api/src/index.ts`, `apps/play-api/tests/worker.test.ts`

**Interfaces:**
- Produces: `sharePage(code: string, testflightUrl: string | undefined, origin: string): Response`; `ogImage(): Response`; route `GET /og/room.jpg`.

- [ ] **Step 1: Write the failing tests** in `src/http/links.test.ts`:

```ts
test("share page carries Open Graph tags pointing at the origin's image", async () => {
  const html = await sharePage("BCDFG", undefined, "https://play.conleychaos.com").text();
  expect(html).toContain('<meta property="og:title" content="Cat Tower">');
  expect(html).toContain('<meta property="og:image" content="https://play.conleychaos.com/og/room.jpg">');
  expect(html).toContain('<meta property="og:image:width" content="1200">');
  expect(html).toContain('<meta property="og:image:height" content="630">');
  expect(html).toContain('<meta name="twitter:card" content="summary_large_image">');
  expect(html).toContain('<meta property="og:description" content="BCDFG">');
});
test("og image is a cacheable jpeg", async () => {
  const res = ogImage();
  expect(res.headers.get("content-type")).toBe("image/jpeg");
  expect(res.headers.get("cache-control")).toBe("public, max-age=86400");
  const bytes = new Uint8Array(await res.arrayBuffer());
  expect([bytes[0], bytes[1]]).toEqual([0xff, 0xd8]);
});
```
Update existing `sharePage(...)` calls in tests to pass an origin. In `tests/worker.test.ts` add: `GET https://play.conleychaos.com/og/room.jpg` → 200 `image/jpeg`; `GET /j/BCDFG` HTML contains `og:image` with `https://play.conleychaos.com/og/room.jpg`.

- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api test` — expect the new tests to FAIL.
- [ ] **Step 3: Write `scripts/embed-og.mjs`** (node, no deps): reads `assets/og-room.jpg`, writes `src/http/og-image.ts` as `/** Generated by scripts/embed-og.mjs from assets/og-room.jpg. Do not edit. */\nexport const OG_IMAGE_BASE64 = "<base64>";\n`. Run it once.
- [ ] **Step 4: Implement** in `links.ts`: add the six meta tags (plus `og:type` `website`, `og:url` `${origin}/j/${code}`) inside `<head>`, all values escaped; add `ogImage()` decoding `OG_IMAGE_BASE64` once (module-level lazy `Uint8Array`) with headers `content-type: image/jpeg`, `cache-control: public, max-age=86400`. In `index.ts`: route `GET /og/room.jpg` → `ogImage()` before the share route; pass `new URL(request.url).origin` to `sharePage`.
- [ ] **Step 5: Run** `pnpm lint && pnpm typecheck && pnpm test` at repo root — expect PASS with coverage thresholds intact.
- [ ] **Step 6: Commit** `feat(play-api): Open Graph tags and image for share links`.

---

### Task 2: Protocol fixtures and local dev secret (`apps/play-api`)

Shared JSON fixtures so the Swift client decodes exactly what the server sends and encodes exactly what it accepts.

**Files:**
- Create: `apps/play-api/tests/protocol-fixtures.test.ts`, `apps/play-api/fixtures/protocol/server-messages.json`, `apps/play-api/fixtures/protocol/client-messages.json`, `apps/play-api/.dev.vars.example`
- Modify: `README.md` (root, a "Local dev server" paragraph)

**Interfaces:**
- Produces: `fixtures/protocol/server-messages.json` = `[{ "name": string, "message": ServerMessage }]`; `client-messages.json` = `[{ "name": string, "message": ClientMessage }]`. Names used by Task 5 tests: `snapshot-lobby`, `snapshot-playing-with-hand`, `snapshot-playing-no-hand`, `event-presence`, one `event-<kind>` per `GameEvent` kind (`event-roundStarted`, `event-drew-deck-own`, `event-drew-deck-other` (no `card`), `event-drew-discard`, `event-laidDown`, `event-hit`, `event-discarded`, `event-discarded-skip`, `event-skipped`, `event-turn`, `event-reshuffled`, `event-roundOver`, `event-roundOver-nobody`, `event-gameOver`), `moveCode`, `error-room_closed`, `error-bad_code`. Client names: `claim`, `configure-open`, `configure-bot`, `configure-closed`, `start`, `act-draw-deck`, `act-draw-discard`, `act-layDown`, `act-layDown-runStart`, `act-hit`, `act-discard`, `act-discard-skip`, `act-nextRound`, `presence-active`, `presence-background`, `moveSeat`, `claimMove`, `leave`.

- [ ] **Step 1: Write the test.** Snapshots come from a real `RoomCore` (`RoomCore.create("BCDFG", "devA", 1_000)`, `now = () => 1_000`, `rng = createRng([1,2,3,4])`): connect `devA`, `devB`; `claim` seat 0 Alice (devA), seat 1 Bob (devB), `configure` seat 2 bot; capture devB's lobby snapshot; `start`; capture devA's and a third connected spectator-free device's snapshots. Event samples are typed literals `satisfies ServerMessage`. Client samples are literals `satisfies ClientMessage`, and the test asserts `parseClientMessage(JSON.stringify(m))` deep-equals `m` for each.

```ts
const write = process.env.UPDATE_FIXTURES === "1";
function check(file: string, data: unknown) {
  const path = new URL(`../fixtures/protocol/${file}`, import.meta.url);
  const text = JSON.stringify(data, null, 2) + "\n";
  if (write) writeFileSync(path, text);
  expect(readFileSync(path, "utf8")).toBe(text);
}
test("server message fixtures match the server", () => check("server-messages.json", serverSamples()));
test("client message fixtures parse to themselves", () => { /* parse loop */ check("client-messages.json", clientSamples()); });
test("playing snapshot keys hands by string seat", () => {
  const snap = serverSamples().find((s) => s.name === "snapshot-playing-with-hand")!.message;
  expect(Object.keys(JSON.parse(JSON.stringify(snap)).room.game.hands)).toEqual(["0"]);
});
```
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run tests/protocol-fixtures.test.ts` — expect FAIL (no fixture files).
- [ ] **Step 3: Generate** with `UPDATE_FIXTURES=1` once, inspect the JSON by eye (string hand keys, no `seed`/`deck` leaks), then rerun without it — expect PASS.
- [ ] **Step 4: Add `.dev.vars.example`** (`# Copy to .dev.vars (gitignored). Any 64+ hex chars.\nTOKEN_SECRET=`) and a README paragraph: `cp apps/play-api/.dev.vars.example apps/play-api/.dev.vars`, fill with `openssl rand -hex 32`, `pnpm --filter @pounce/play-api exec wrangler dev --port 8787`.
- [ ] **Step 5: Run** root `pnpm lint && pnpm typecheck && pnpm test` — PASS.
- [ ] **Step 6: Commit** `test(play-api): shared protocol fixtures for the iOS client`.

---

### Task 3: iOS project scaffold

**Files:**
- Create: `apps/play-ios/project.yml`, `.gitignore`, `README.md` (skeleton), `scripts/bootstrap.sh`, `scripts/dev-server.sh`, `Pounce/Info.plist`, `Pounce/Pounce.entitlements`, `Pounce/App/PounceApp.swift` (shows a violet screen), `Pounce/Resources/Assets.xcassets` (AppIcon placeholder, AccentColor), `PounceKit/Package.swift`, `PounceKit/Sources/PounceKit/PounceKit.swift` (`public enum PounceKit { public static let protocolVersion = 1 }`), `PounceKit/Sources/pounce-e2e/main.swift` (prints usage), `PounceKit/Tests/PounceKitTests/Fixtures.swift`, `PounceKit/Tests/PounceKitTests/ScaffoldTests.swift`, `PounceUITests/SmokeTests.swift` (launch-only test)

**Interfaces:**
- Produces: targets `Pounce` (app), `PounceUITests`; package products `PounceKit` (library) and `pounce-e2e` (executable); scheme `Pounce`; `Fixtures.url(_ relative: String) -> URL` resolving under `apps/play-api/fixtures/` via `#filePath`; `Fixtures.serverMessages() throws -> [(name: String, json: String)]`, `Fixtures.clientMessages()` likewise (raw JSON text of each `message`, re-serialized with sorted keys).

- [ ] **Step 1: `PounceKit/Package.swift`**: `// swift-tools-version: 6.2`, platforms `.iOS(.v26), .macOS(.v26)`, Swift 6 language mode, `swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]` not needed in 6 mode; test target uses Swift Testing.
- [ ] **Step 2: Failing test** `ScaffoldTests.swift`: `@Test func fixturesAreReachable() throws { #expect(try Fixtures.serverMessages().contains { $0.name == "snapshot-lobby" }) }` and `#expect(PounceKit.protocolVersion == 1)`. Run `swift test --package-path apps/play-ios/PounceKit` — FAIL until `Fixtures` exists, then implement it — PASS.
- [ ] **Step 3: `project.yml`**: app `Pounce` (iOS 26, iPhone `TARGETED_DEVICE_FAMILY=1`, `PRODUCT_BUNDLE_IDENTIFIER=com.conleychaos.play`, `DEVELOPMENT_TEAM=B222J9J7B8`, `CODE_SIGN_STYLE=Automatic`, `SWIFT_VERSION=6.0`, `SWIFT_STRICT_CONCURRENCY=complete`, `INFOPLIST_FILE`, `CODE_SIGN_ENTITLEMENTS`, local package dependency `PounceKit`), per-config build setting `POUNCE_API_BASE_URL` = `http://localhost:8787` (Debug) / `https://play.conleychaos.com` (Release) surfaced in Info.plist as `PounceAPIBaseURL = $(POUNCE_API_BASE_URL)`; `PounceUITests` (bundle.ui-testing, target app `Pounce`); scheme `Pounce` with test targets `PounceUITests`.
- [ ] **Step 4: Info.plist**: `CFBundleDisplayName` `Pounce`; `UISupportedInterfaceOrientations` portrait only; `UIRequiresFullScreen` true; `UILaunchScreen` with background color asset `LaunchViolet`; `NSAppTransportSecurity.NSAllowsLocalNetworking` true; `ITSAppUsesNonExemptEncryption` false; `PounceAPIBaseURL`. Entitlements: `aps-environment` `development`, `com.apple.developer.associated-domains` `[applinks:play.conleychaos.com]`.
- [ ] **Step 5: Scripts.** `bootstrap.sh`: `command -v xcodegen || brew install xcodegen; cd "$(dirname "$0")/.." && xcodegen generate`. `dev-server.sh`: if `apps/play-api/.dev.vars` is missing, create it with `TOKEN_SECRET=$(openssl rand -hex 32)`; then `exec pnpm --dir <repo>/apps/play-api exec wrangler dev --port 8787 --ip 0.0.0.0`. `.gitignore`: `Pounce.xcodeproj/`, `Art/raw/`, `Art/cut/`, `build/`.
- [ ] **Step 6: Verify:** `scripts/bootstrap.sh`; `xcodebuild -project apps/play-ios/Pounce.xcodeproj -scheme Pounce -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` → `** BUILD SUCCEEDED **` (if simulator signing complains about provisioning, add `CODE_SIGNING_ALLOWED=NO` to verification builds and note it in the README); `xcodebuild … test` runs the launch-only UI test → `** TEST SUCCEEDED **`. Start `scripts/dev-server.sh` in the background and confirm `curl -s localhost:8787/healthz` returns `{"ok":true,"service":"play-api","configured":true}`; stop it. Confirm `git status` shows no `.dev.vars`.
- [ ] **Step 7: Commit** `feat(play-ios): XcodeGen project, PounceKit package, dev scripts`.

---

### Task 4: Rules mirror (`PounceKit/Rules`)

A faithful Swift port of `apps/play-api/src/rules/cards.ts`, `groups.ts`, `phases.ts` (read them; behavior must match exactly).

**Files:**
- Create: `Sources/PounceKit/Rules/Card.swift`, `Group.swift`, `Phases.swift`; `Tests/PounceKitTests/RulesTests.swift`

**Interfaces:**
- Produces:
  - `public typealias CardID = Int`, `public typealias Seat = Int`
  - `public enum Coat: String, Codable, CaseIterable, Sendable { case tabby, tuxedo, calico, gray }`
  - `public enum Card: Equatable, Sendable { case number(value: Int, coat: Coat); case yarn; case cucumber; public init(id: CardID); public static func points(_ id: CardID) -> Int; public static let deckSize = 108 }`
  - `public enum GroupKind: String, Codable, Sendable { case set, run, coat }`; `public struct Requirement: Equatable, Hashable, Sendable { public let kind: GroupKind; public let size: Int }`
  - `public enum Group: Equatable, Codable, Sendable { case set(cards: [CardID], value: Int); case run(cards: [CardID], start: Int, end: Int); case coat(cards: [CardID], coat: Coat); public var cards: [CardID]; public var kind: GroupKind }` — JSON shape exactly the server's: `{"kind":"set","cards":[..],"value":7}`, `{"kind":"run","cards":[..],"start":3,"end":6}`, `{"kind":"coat","cards":[..],"coat":"calico"}`.
  - `public struct LayGroup: Codable, Equatable, Sendable { public var cards: [CardID]; public var runStart: Int? }` (omit `runStart` when nil)
  - `public enum Rules { public static let phases: [[Requirement]]; public static func buildGroup(_ req: Requirement, cards: [CardID], runStart: Int? = nil) -> Group?; public static func canHit(_ group: Group, card: CardID) -> Group?; public static func matchPhase(_ phaseIndex: Int, groups: [LayGroup]) -> [Group]? }`

- [ ] **Step 1: Failing tests:**

```swift
@Test func cardDecoding() {
  #expect(Card(id: 0) == .number(value: 1, coat: .tabby))
  #expect(Card(id: 30) == .number(value: 7, coat: .tuxedo))
  #expect(Card(id: 95) == .number(value: 12, coat: .gray))
  #expect(Card(id: 96) == .yarn); #expect(Card(id: 104) == .cucumber)
}
@Test func points() { #expect([0, 9, 11, 96, 104].map(Card.points) == [5, 10, 10, 25, 15]) }
@Test func phasesMatchServer() {
  #expect(Rules.phases[1] == [Requirement(kind: .set, size: 3), Requirement(kind: .run, size: 4)])
  #expect(Rules.phases[7] == [Requirement(kind: .coat, size: 7)])
  #expect(Rules.phases.count == 10)
}
@Test(arguments: try! GroupVector.load()) func groupVectors(_ v: GroupVector) {
  // apps/play-api/fixtures/groups.json: { name, req, cards, runStart?, valid, ... }
  #expect((Rules.buildGroup(v.req, cards: v.cards, runStart: v.runStart) != nil) == v.valid, "\(v.name)")
}
@Test func hitRunExtendsBothEnds() {
  let run = Rules.buildGroup(.init(kind: .run, size: 4), cards: [2, 27, 52, 77])! // 3-4-5-6
  #expect(Rules.canHit(run, card: 6)?.cards.last == 6)          // 7
  #expect(Rules.canHit(run, card: 1)?.cards.first == 1)         // 2
  #expect(Rules.canHit(run, card: 104) == nil)                  // cucumber
}
@Test func matchPhaseNeedsPhaseOrderAndDistinctCards() { /* phase 2: [set3, run4] passes; reversed order fails; shared card fails */ }
@Test func groupJSONRoundTrips() throws { /* decode {"kind":"run","cards":[2,27,52,77],"start":3,"end":6} and re-encode equal */ }
```
`GroupVector` is a test-local `Decodable` mirroring each entry of `groups.json` (inspect the file for its exact keys; extra keys are ignored).
- [ ] **Step 2: Run** `swift test --package-path apps/play-ios/PounceKit --filter RulesTests` — FAIL.
- [ ] **Step 3: Implement** by porting the TypeScript line for line (`buildRun` start window `lowest = max(1, maxValue - size + 1)`, `highest = min(minValue, 13 - size)`, default start = lowest; Yarn fills empty slots in order; run hit with Yarn extends the end first, else the start).
- [ ] **Step 4: Run** — PASS. **Step 5: Commit** `feat(pouncekit): Cat Tower rules mirror tested against server vectors`.

---

### Task 5: Protocol types and codec (`PounceKit/Protocol`)

**Files:**
- Create: `Sources/PounceKit/Protocol/Models.swift`, `GameEvent.swift`, `Messages.swift`, `Codec.swift`; `Tests/PounceKitTests/ProtocolTests.swift`

**Interfaces:**
- Consumes: Task 4 `CardID`, `Seat`, `Group`, `LayGroup`, `Coat`.
- Produces (all `Sendable`, `Equatable`):
  - `public struct Person: Codable, Hashable, Identifiable { public var id: String; public var name: String; public var cat: Int }` (id = lowercase UUID string)
  - `public enum Presence: String, Codable { case awake, away, asleep }`, `public enum SeatKind: String, Codable { case open, closed, human, bot }`, `public enum RoomStatus: String, Codable { case lobby, playing, over }`, `public enum TurnStep: String, Codable { case draw, play }`, `public enum GameStatus: String, Codable { case playing, roundOver, gameOver }`, `public enum DrawSource: String, Codable { case deck, discard }`
  - `public struct SeatView: Codable { public var kind: SeatKind; public var person: Person?; public var yours: Bool; public var presence: Presence? }`
  - `public struct GameView: Codable { round, dealer: Seat, turn: Seat, step: TurnStep, status: GameStatus, deckCount: Int, discardTop: CardID?, discardCount: Int, phase: [Int], scores: [Int], laid: [[Group]?], handCounts: [Int], hands: [Seat: [CardID]], pendingSkip: [Bool], winners: [Seat] }` — `hands` decodes from a JSON object with string keys and encodes back the same way.
  - `public struct RoomView: Codable { code: String, status: RoomStatus, youAreHost: Bool, seats: [SeatView], game: GameView? }`
  - `public struct HitTarget: Codable, Hashable { public var seat: Seat; public var group: Int }`
  - `public enum GameEvent: Codable { case roundStarted(round: Int, dealer: Seat); case drew(seat: Seat, from: DrawSource, card: CardID?); case laidDown(seat: Seat, groups: [Group]); case hit(seat: Seat, card: CardID, target: HitTarget, group: Group); case discarded(seat: Seat, card: CardID, skipTarget: Seat?); case skipped(seat: Seat); case turn(seat: Seat); case reshuffled(deckCount: Int); case roundOver(wentOut: Seat?, points: [Int], advanced: [Seat], scores: [Int], phase: [Int]); case gameOver(winners: [Seat]) }` — discriminator key `kind`.
  - `public enum RoomEvent: Codable { case presence(seat: Seat, presence: Presence); case game(GameEvent) }` — discriminator `kind` = `presence` | `game` (game payload under `event`).
  - `public struct ErrorCode: RawRepresentable, Codable, Hashable { public let rawValue: String }` with statics for every server code (`badMessage = "bad_message"`, …, `roomClosed = "room_closed"`, `botStalled = "bot_stalled"`, `badCode = "bad_code"`, `tooManyAttempts = "too_many_attempts"`, `notYourTurn`, `badStep`, `seatsOpen`, `notEnoughPlayers`, …); unknown strings decode without failing.
  - `public enum ServerMessage: Decodable { case snapshot(protocol: Int, seq: Int, room: RoomView); case event(seq: Int, event: RoomEvent); case moveCode(seat: Seat, code: String); case error(ErrorCode) }` (discriminator `t`)
  - `public enum Action: Encodable { case draw(DrawSource); case layDown([LayGroup]); case hit(card: CardID, target: HitTarget); case discard(card: CardID, skipTarget: Seat?); case nextRound }` (discriminator `type`; `skipTarget` omitted when nil)
  - `public enum ConfigureKind: String, Codable { case open, bot, closed }`, `public enum PresenceState: String, Codable { case active, background }`
  - `public enum ClientMessage: Encodable { case claim(seat: Seat, person: Person); case configure(seat: Seat, kind: ConfigureKind); case start; case act(seat: Seat, action: Action); case presence(PresenceState); case moveSeat(seat: Seat); case claimMove(code: String); case leave(seat: Seat) }` — `presence` encodes as `{"t":"presence","state":"active"}`.
  - `public enum Codec { public static func decode(_ text: String) throws -> ServerMessage; public static func encode(_ message: ClientMessage) throws -> String }`

- [ ] **Step 1: Failing tests:**

```swift
@Test func decodesEveryServerFixture() throws {
  for (name, json) in try Fixtures.serverMessages() { #expect(throws: Never.self, "\(name)") { _ = try Codec.decode(json) } }
}
@Test func playingSnapshotHasStringKeyedHand() throws {
  guard case .snapshot(let p, _, let room) = try Codec.decode(fixture("snapshot-playing-with-hand")) else { Issue.record(); return }
  #expect(p == 1); #expect(room.game?.hands.keys.sorted() == [0]); #expect(room.game?.hands[0]?.count == 11 || room.game?.hands[0]?.count == 10)
}
@Test func otherSeatsDeckDrawHasNoCard() throws {
  guard case .event(_, .game(.drew(_, .deck, let card))) = try Codec.decode(fixture("event-drew-deck-other")) else { Issue.record(); return }
  #expect(card == nil)
}
@Test func encodesEveryClientFixture() throws {
  // build the Swift ClientMessage for each fixture name and compare JSON objects (key order-insensitive)
  for (name, json) in try Fixtures.clientMessages() { #expect(try jsonEqual(Codec.encode(sample(name)), json), "\(name)") }
}
@Test func unknownErrorCodeStillDecodes() throws { #expect(try Codec.decode(#"{"t":"error","code":"new_thing"}"#) == .error(ErrorCode(rawValue: "new_thing"))) }
```
- [ ] **Step 2: Run** `swift test --filter ProtocolTests` — FAIL. **Step 3: Implement** with hand-written `init(from:)`/`encode(to:)` using a `kind`/`t`/`type` discriminator; a private `StringKeyedSeats` wrapper for `hands`. **Step 4: Run** — PASS. **Step 5: Commit** `feat(pouncekit): protocol 1 types and codec matched to server fixtures`.

---

### Task 6: Codes, deep links, credentials, API client, local stores

**Files:**
- Create: `Sources/PounceKit/Protocol/RoomCode.swift`, `DeepLink.swift`; `Sources/PounceKit/Net/APIConfig.swift`, `Credentials.swift`, `APIClient.swift`; `Sources/PounceKit/Identity/PeopleStore.swift`, `TableCache.swift`, `NameGenerator.swift`; tests `CodesTests.swift`, `APIClientTests.swift`, `StoresTests.swift`

**Interfaces:**
- Consumes: Task 5 `Person`, `RoomView`, `RoomStatus`.
- Produces:
  - `public enum RoomCode { public static let alphabet: String; public static func isValid(_ s: String) -> Bool /* 5 */; public static func isValidMoveCode(_ s: String) -> Bool /* 6 */ }`
  - `public enum DeepLink: Equatable, Sendable { case join(code: String); case move(code: String, moveCode: String); public static func parse(_ url: URL) -> DeepLink? }` — accepts `https://play.conleychaos.com/j/<CODE>[?move=<M>]` (and the same path on any host in DEBUG for local testing is NOT needed — production host only); invalid codes → nil.
  - `public struct APIConfig: Sendable { public let baseURL: URL; public init(baseURL: URL); public func socketURL(code: String) -> URL /* http→ws, https→wss, /v1/rooms/<code>/ws */ }`
  - `public struct DeviceCredential: Codable, Equatable, Sendable { public let deviceId: String; public let token: String }`
  - `public protocol CredentialStore: Sendable { func load() -> DeviceCredential?; func save(_ c: DeviceCredential); func clear() }`; `public final class KeychainCredentialStore: CredentialStore` (generic password, service `com.conleychaos.play.device`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`); `public final class MemoryCredentialStore: CredentialStore` (lock-protected).
  - `public struct TableEntry: Codable, Equatable, Sendable { public let code: String; public let status: String; public let yourTurn: Bool; public let updatedAt: Double }`
  - `public enum APIError: Error, Equatable { case notConfigured, rateLimited, unauthorized, badRequest, notFound, server(Int), transport(String) }`
  - `public actor APIClient { public init(config: APIConfig, credentials: CredentialStore, session: URLSession = .shared); public func credential() async throws -> DeviceCredential /* mint via POST /v1/devices if none */; public func setPushToken(_ hex: String) async throws; public func listTables() async throws -> [TableEntry]; public func createRoom() async throws -> String }` — any authenticated call that gets 401 clears the credential, mints once, retries once.
  - `public struct LocalPeople: Codable, Equatable, Sendable { public var owner: Person?; public var others: [Person] }`; `public final class PeopleStore { public init(directory: URL); public func load() -> LocalPeople; @discardableResult public func setOwner(name: String, cat: Int) -> Person; @discardableResult public func add(name: String, cat: Int) -> Person; public func update(_ p: Person); public func remove(id: String) }` (file `people.json`; new ids `UUID().uuidString.lowercased()`; names trimmed, clamped to 20 characters)
  - `public struct CachedSeat: Codable, Equatable, Sendable { public var kind: SeatKind; public var name: String?; public var cat: Int?; public var yours: Bool }`; `public struct CachedTable: Codable, Equatable, Sendable { public var code: String; public var status: RoomStatus; public var seats: [CachedSeat]; public var turn: Seat?; public var phase: [Int]; public var updatedAt: Date }`; `public final class TableCache { public init(directory: URL); public func all() -> [String: CachedTable]; public func store(_ room: RoomView, now: Date = .now); public func remove(code: String); public func contains(code: String) -> Bool }` (file `tables.json`)
  - `public enum NameGenerator { public static let names: [String] /* ≥ 40 cat-ish names, ASCII, 3–12 chars, e.g. "Mochi", "Biscuit", "Pickle" */; public static func random<G: RandomNumberGenerator>(using g: inout G) -> String }`

- [ ] **Step 1: Failing tests:** `RoomCode.isValid("K7QM4")`, `!isValid("K7QMA")` (A not in alphabet), `!isValid("K7QM")`; `DeepLink.parse(URL("https://play.conleychaos.com/j/K7QM4")) == .join(code: "K7QM4")`, `?move=BCDFGH` → `.move`, bad move code → `.join` ignored? → **nil** (call: a malformed move link is rejected entirely), other host → nil, `/j/k7qm4` lowercase → nil. `APIConfig.socketURL` for `http://localhost:8787` → `ws://localhost:8787/v1/rooms/K7QM4/ws`. APIClient with a `URLProtocol` stub: mints once and caches (second `credential()` makes no request); `createRoom` sends `POST /v1/rooms` body `{"game":"cat-tower"}` with `Authorization: Bearer <token>` and returns the code from 201; a 401 on `listTables` triggers exactly one re-mint and one retry; 503 `{"error":"not_configured"}` → `.notConfigured`; 429 → `.rateLimited`. PeopleStore round-trips through a temp directory and clamps a 30-char name to 20. TableCache stores a fixture `RoomView`, reloads equal, removes.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS. **Step 5: Commit** `feat(pouncekit): codes, deep links, device credential, API client, local stores`.

---

### Task 7: RoomSocket — one live room connection with reconnect

**Files:**
- Create: `Sources/PounceKit/Net/WebSocket.swift`, `RoomSocket.swift`; `Tests/PounceKitTests/RoomSocketTests.swift`

**Interfaces:**
- Consumes: Task 5 `Codec`, `ServerMessage`, `ClientMessage`; Task 6 `APIConfig`, `DeviceCredential`.
- Produces:
  - `public protocol WebSocketConnection: Sendable { func send(_ text: String) async throws; func receive() async throws -> String; func sendPing() async throws; func close() async }`
  - `public enum SocketConnectError: Error, Equatable { case notFound, unauthorized, failed(String) }`
  - `public protocol WebSocketConnector: Sendable { func connect(url: URL, token: String) async throws -> any WebSocketConnection }`; `public struct URLSessionWebSocketConnector: WebSocketConnector` (sets `Authorization: Bearer`; maps an upgrade failure whose `HTTPURLResponse.statusCode == 404` to `.notFound`, 401 to `.unauthorized`)
  - `public enum SocketEvent: Equatable, Sendable { case connecting; case connected; case message(ServerMessage); case disconnected; case notFound; case closed }`
  - `public protocol RoomSocketing: Sendable { var events: AsyncStream<SocketEvent> { get }; func start() async; func send(_ m: ClientMessage) async throws; func reconnectNow() async; func stop() async }`
  - `public actor RoomSocket: RoomSocketing { public init(code: String, config: APIConfig, credential: @escaping @Sendable () async throws -> DeviceCredential, connector: any WebSocketConnector = URLSessionWebSocketConnector(), backoff: [Duration] = [.milliseconds(250), .milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8)], pingInterval: Duration = .seconds(25), sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) }`

Behavior: `start()` connects (emits `.connecting` then `.connected`), then a receive loop decodes each frame and emits `.message`. Undecodable frames are dropped. Connection loss → `.disconnected`, wait `backoff[min(attempt, last)]`, reconnect; the attempt counter resets when a `snapshot` arrives. `.notFound` on connect → emit `.notFound` and stop (no retry). An `error room_closed` message → emit it as `.message`, then `.closed`, close the connection, stop. `stop()` closes without reconnecting. `reconnectNow()` drops the current connection and reconnects immediately (attempt 0). A ping task sends `sendPing()` every `pingInterval`; two consecutive ping failures force a reconnect. `send` throws when not connected.

- [ ] **Step 1: Failing tests** with a `FakeConnector`/`FakeConnection` (scripted frames, controllable failures) and `sleep` recording requested durations without waiting:
  - `connectsAndForwardsSnapshot` — events `[.connecting, .connected, .message(.snapshot…)]`.
  - `reconnectsWithBackoffAfterDrop` — two drops before a snapshot → recorded sleeps `[0.25 s, 0.5 s]`; after a snapshot then another drop → `[…, 0.25 s]` (reset).
  - `notFoundIsTerminal` — connector throws `.notFound` → events end with `.notFound`, connector called once.
  - `knownCode404IsClosed` is in Task 14 (app-level mapping); here only assert `.notFound`.
  - `roomClosedIsTerminal` — frame `{"t":"error","code":"room_closed"}` → `.message(.error(.roomClosed))`, `.closed`, no further connects.
  - `stopPreventsReconnect`, `reconnectNowReconnectsImmediately`, `badFramesAreIgnored`, `sendWhileDisconnectedThrows`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement** (single actor; one `Task` for the receive loop, one for pings; `AsyncStream.makeStream`). **Step 4: Run** — PASS. **Step 5: Commit** `feat(pouncekit): RoomSocket with backoff, terminal close and liveness pings`.

---

### Task 8: RoomStore reducer

**Files:**
- Create: `Sources/PounceKit/Store/RoomStore.swift`, `TableIntent.swift`; `Tests/PounceKitTests/RoomStoreTests.swift`

**Interfaces:**
- Consumes: Task 7 `RoomSocketing`, `SocketEvent`; Task 5 types.
- Produces:
  - `public enum TableIntent: Equatable, Sendable { case reconcile; case versusIntro; case game(GameEvent, seq: Int); case presence(seat: Seat, presence: Presence); case rejected(ErrorCode); case lobbyNope(ErrorCode) }`
  - `public enum RoomPhase: Equatable, Sendable { case connecting, lobby, playing, over, closed, notFound, needsUpdate, stalled }`
  - `@MainActor @Observable public final class RoomStore { public init(code: String, socket: any RoomSocketing); public let code: String; public private(set) var room: RoomView?; public private(set) var phase: RoomPhase; public private(set) var lastSeq: Int /* -1 before first snapshot */; public private(set) var actionInFlight: Bool; public private(set) var connected: Bool; public private(set) var moveCode: (seat: Seat, code: String)? /* store as a small struct MoveCode: Equatable */; public private(set) var lastError: ErrorCode?; public let intents: AsyncStream<TableIntent>; public func run() async /* consumes socket.events until the stream ends */; public func handle(_ event: SocketEvent) /* the reducer; internal tests call it directly */; @discardableResult public func act(seat: Seat, _ action: Action) -> Bool; public func send(_ message: ClientMessage) /* lobby/presence/move messages; never locks */; public func close() async }`

Reducer rules (spec §7.3):
- `snapshot`: `protocol != 1` → `phase = .needsUpdate`, `socket.stop()`. Otherwise apply unconditionally (even `seq == lastSeq`), `lastSeq = seq`, clear `actionInFlight`, set `phase` from `room.status` (`.lobby`/`.playing`/`.over`), emit `.versusIntro` if the previous room status was `.lobby` and the new one is `.playing`, then `.reconcile`.
- `event`: `seq <= lastSeq` → ignore. `seq > lastSeq + 1` → ignore and `socket.reconnectNow()`. `seq == lastSeq + 1` → `lastSeq = seq`; apply to `room` where the event carries the data (presence → `seats[s].presence`; game events are animated, the authoritative numbers arrive with the next snapshot or are derivable: update `game.turn` on `.turn`, `game.status` on `.roundOver`/`.gameOver`); emit `.presence` or `.game(event, seq)`; any game event clears `actionInFlight`.
- `moveCode` → set `moveCode`.
- `error`: `roomClosed` → `phase = .closed`, `socket.stop()`. `botStalled` → `phase = .stalled`. Otherwise if `actionInFlight` → clear it, emit `.rejected(code)`; else emit `.lobbyNope(code)`. Always set `lastError`.
- `.notFound` → `phase = .notFound`. `.closed` → `phase = .closed` unless already `.needsUpdate`. `.disconnected` → `connected = false`, keep `actionInFlight` (the reconnect snapshot clears it). `.connected` → `connected = true`.
- `act`: returns false without sending when `actionInFlight` or not `.playing`; otherwise sets `actionInFlight = true` and sends `.act`.

- [ ] **Step 1: Failing tests** (a `FakeSocket: RoomSocketing` recording sends and calls; decode messages from Task 2 fixtures where possible):
  - `snapshotWithEqualSeqIsApplied` — snapshot seq 5, event seq 6, snapshot seq 6 → `room` equals the second snapshot, intents end `.reconcile`.
  - `eventGapRequestsReconnect` — lastSeq 5, event seq 7 → `reconnectNow` called once, `lastSeq == 5`.
  - `staleEventIgnored`, `presenceEventUpdatesSeat`.
  - `lobbyToPlayingEmitsVersusIntro`.
  - `secondActWhileInFlightIsRefused` — `act` twice → one send, second returns false.
  - `errorWhileInFlightRejects` — act then `error not_your_turn` → `.rejected(.notYourTurn)`, `actionInFlight == false`.
  - `lobbyErrorNopes` — no act in flight, `error seats_open` → `.lobbyNope(.seatsOpen)`.
  - `inFlightClearsOnReconnectSnapshot` — act, `.disconnected`, `.connected`, snapshot with same seq → `actionInFlight == false`, room applied.
  - `roomClosedIsTerminal` — `phase == .closed`, socket `stop` called.
  - `wrongProtocolNeedsUpdate`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS. **Step 5: Commit** `feat(pouncekit): RoomStore applying the protocol 1 client contract`.

---

### Task 9: TableModel, pass-and-play, and a small solver

**Files:**
- Create: `Sources/PounceKit/Store/TableModel.swift`, `PassAndPlay.swift`; `Sources/PounceKit/Rules/Solver.swift`; tests `TableModelTests.swift`, `PassAndPlayTests.swift`, `SolverTests.swift`

**Interfaces:**
- Consumes: Tasks 4–5.
- Produces:
  - `public struct TableModel: Equatable, Sendable { public init(room: RoomView); public let room: RoomView; public var game: GameView? ; public var mySeats: [Seat] /* seats with yours == true */; public var isMultiSeat: Bool; public var currentSeat: Seat?; public var isMyTurn: Bool /* status .playing, game .playing, turn ∈ mySeats */; public func opponents(bottom: Seat) -> [Seat] /* other seats in turn order starting after bottom */; public func drawSources(for seat: Seat) -> Set<DrawSource> /* empty unless seat's turn & step .draw; .discard only if discardTop exists and isn't a Cucumber */; public func canPlay(_ seat: Seat) -> Bool /* seat's turn & step .play */; public func trays(for seat: Seat) -> [Requirement] /* Rules.phases[phase[seat]] when laid[seat] == nil and phase[seat] < 10, else [] */; public func hitTargets(card: CardID, seat: Seat) -> [HitTarget] /* only when canPlay(seat) and laid[seat] != nil; every laid group of any seat that Rules.canHit accepts */; public func skipTargets(for seat: Seat) -> [Seat] /* other seats with pendingSkip false */; public func discardAction(card: CardID, target: Seat?) -> Action /* Cucumber: uses target if it's in skipTargets; if skipTargets is empty sends no skipTarget */; public var canStart: Bool /* lobby, I hold ≥1 seat, no .open seats, humans+bots ≥ 2 */; public var firstOpenSeat: Seat?; public var blockingSeats: [Seat] /* open seats while in lobby */ }`
  - `public enum CurtainState: Equatable, Sendable { case none; case curtain(Seat); case revealed(Seat) }`
  - `public struct PassAndPlay: Equatable, Sendable { public init(); public private(set) var revealed: Seat?; public private(set) var state: CurtainState; public mutating func update(_ model: TableModel); public mutating func completeHold(); public mutating func peek(_ seat: Seat); public mutating func hide() }`
  - `public enum Solver { public static func findPhase(hand: [CardID], phaseIndex: Int) -> [LayGroup]?; public static func hits(hand: [CardID], laid: [[Group]?]) -> [(card: CardID, target: HitTarget)] }`

PassAndPlay rules: single-seat phone → `state = .revealed(mySeat)` always (no curtain). Multi-seat phone: if it's one of my seats' turn and `revealed != turn` → `.curtain(turn)` (revealed nil). `completeHold()` on `.curtain(s)` → `.revealed(s)`. Turn moves to a seat I don't hold → `.none`, revealed nil. `peek(s)` (s ∈ mySeats, not during my own active turn) → `.curtain(s)`; `hide()` → `.none`. A new round (round number changes) with my seat to move → curtain again.

Solver: greedy, good enough for the e2e driver — sets by value with Yarn top-up, runs by sliding windows over 1…12 using Yarn for gaps, coat by most-common coat; tries naturals first, uses at most the Yarn needed, never Cucumbers; groups returned in `Rules.phases` order with `runStart` set for runs; returns a result only if `Rules.matchPhase` accepts it.

- [ ] **Step 1: Failing tests:** `drawSourcesExcludeCucumberTop`, `traysFollowPhaseOrder` (phase index 1 → `[set3, run4]`), `hitTargetsOnlyAfterLaying`, `cucumberWithNoTargetsDiscardsPlain` (all others pending → `.discard(card: 104, skipTarget: nil)`), `cucumberTargetsSkipPending`, `canStartNeedsNoOpenSeats`, `opponentsInTurnOrder` (4 seats, bottom 2 → `[3, 0, 1]`); PassAndPlay `singleSeatNeverCurtains`, `curtainBetweenLocalSeats` (seats 0 and 1 local: turn 0 → curtain(0) → hold → revealed(0); turn 1 → curtain(1)), `remoteTurnHidesHand` (turn 2 remote → `.none`), `peekShowsCurtainThenHides`, `newRoundCurtainsAgain`; Solver `findsTwoSetsOfThree`, `findsRunWithYarnGap` (phase 4, run of 7 with one Yarn) and `returnsNilWhenImpossible`, each validated by `Rules.matchPhase`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS. **Step 5: Commit** `feat(pouncekit): table model, pass-and-play curtain logic, phase solver`.

---

### Task 10: TableLayout (pure geometry)

**Files:**
- Create: `Sources/PounceKit/Layout/TableLayout.swift`; `Tests/PounceKitTests/TableLayoutTests.swift`

**Interfaces:**
- Produces: `public struct TableLayout: Sendable { public init(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat, opponents: Int); public var opponentSlots: [CGPoint]; public var deck: CGPoint; public var discard: CGPoint; public var towerFrame: CGRect; public func shelf(_ index: Int) -> CGPoint /* 0…9 bottom to top */; public var traysFrame: CGRect; public func trayFrames(count: Int) -> [CGRect]; public func hand(count: Int, lifted: Int?) -> [CardPlacement]; public func laidRow(slot: Int, of total: Int) -> CGRect; public var cardSize: CGSize; public var miniCardSize: CGSize }`; `public struct CardPlacement: Equatable, Sendable { public var position: CGPoint; public var rotation: CGFloat /* radians */; public var z: CGFloat }`.

Coordinates are SpriteKit scene points: origin bottom-left, y up, scene size = view size (`scaleMode = .resizeFill`). Bands top → bottom: opponents bar (below safe top, height 96), rug center with deck left / discard right of center, laid zone around the piles, trays (height 64) above the hand, hand arc (bottom, above safe bottom). Tower: left edge, 44 pt wide, from below the opponents bar to above the trays. Card size 64×90 at 390 pt width, scaled by `size.width / 390`, clamped to 56…76 wide.

- [ ] **Step 1: Failing tests** for 390×844 and 430×932 with 1…5 opponents: every point inside the scene; opponent slots evenly spaced and ordered left → right; hand placements for 1…14 cards stay within the width, are symmetric about the center, have rotations within ±0.35 rad and strictly increasing `z`; `lifted` raises that card by ≥ 24 pt; tray frames don't overlap; tower shelves strictly increase in y; deck and discard don't overlap.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS. **Step 5: Commit** `feat(pouncekit): table layout for 2–6 seats`.

---

### Task 11: Art pipeline, asset manifest, placeholders, sound effects

**Files:**
- Create: `apps/play-ios/Art/manifest.json`, `Art/prompts/*.txt` (one per batch, see Tasks 21–23), `Art/tools/gen.sh`, `Art/tools/cutout.swift`, `Art/tools/build-assets.sh`, `Art/tools/placeholders.sh`, `Art/tools/sfx.swift`; generated `Pounce/Resources/Assets.xcassets/**` placeholders and `Pounce/Resources/Sounds/*.caf`; `Pounce/Design/ArtName.swift`

**Interfaces:**
- Produces: the asset names every later task uses (manifest is the source of truth; `ArtName.swift` mirrors it):
  - Atlas `Cats`: `cat{0…7}-{idle,awake,away,asleep,leap,terrified,celebrate}` (160×160 pt). Cat roster by index: 0 orange tabby, 1 tuxedo, 2 calico, 3 gray, 4 black, 5 white fluffy, 6 siamese, 7 tortie.
  - Atlas `Cards`: `card-face` (blank white face + violet rim, 64×90), `card-back`, `coat-tabby|tuxedo|calico|gray` (center cat face art, 48×48), `glyph-tabby|tuxedo|calico|gray` (16×16), `card-yarn`, `card-cucumber` (center art 52×52), `card-glow`, `card-shadow`.
  - Atlas `Table`: `rug` (360×360), `tower-base`, `tower-shelf`, `tower-top` (44 wide), `shelf-badge`, `ring` (72×72), `ring-glow`, `tray`, `tray-gold`, `paw-swipe`, `crown`, `sunburst` (400×400).
  - Atlas `FX`: `fx-star`, `fx-fur`, `fx-yarn`, `fx-confetti`, `fx-sparkle` (24×24).
  - Imagesets: `room-bg` (390×844 @2x/@3x), `home-bg`, `curtain-stage`, `game-tile`, `state-closed`, `state-stalled`, `state-offline`, `state-full`, `state-update`, `push-priming`, and icons `icon-plus`, `icon-keypad`, `icon-share`, `icon-qr`, `icon-play`, `icon-back`, `icon-gear`, `icon-paw-menu`, `icon-sort`, `icon-bell`, `icon-check`, `icon-dice`, `icon-home`, `icon-move`, `icon-sound-on`, `icon-sound-off`, `icon-haptics-on`, `icon-haptics-off`, `badge-phone`, `badge-remote`, `badge-bot`, `badge-skip`, `badge-laid`, `icon-trophy`, `icon-zzz`, `icon-hold`; `AppIcon` (1024).
  - Sounds: `sfx-pop`, `sfx-flip`, `sfx-bat`, `sfx-thud`, `sfx-nope`, `sfx-sparkle`, `sfx-whoosh`, `sfx-scream`, `sfx-leap`, `sfx-fanfare`, `sfx-tick` (`.caf`).
  - `enum ArtName { static func cat(_ index: Int, _ pose: CatPose) -> String; static func coat(_ c: Coat) -> String; static func glyph(_ c: Coat) -> String; … }` and `enum CatPose: String, CaseIterable { case idle, awake, away, asleep, leap, terrified, celebrate }`.

Tools:
- `gen.sh <prompt.txt> <out.png> [ref.png…]` — runs `codex exec --skip-git-repo-check -s workspace-write -i Art/style-samples/chosen-d-loud-toy.png [-i ref…] -` with the prompt plus "Save the PNG as <abs out>"; fails if the file doesn't appear. Writes into `Art/raw/`.
- `cutout.swift` — `swift Art/tools/cutout.swift <in.png> <outdir> --names a,b,c` : Vision `VNGenerateForegroundInstanceMaskRequest`; with one name exports the whole foreground; with N names exports each instance (row-major: sort by instance center y into rows of similar height, then x) trimmed with 4 px padding as transparent PNG; fails if the instance count ≠ N. Writes into `Art/cut/`.
- `build-assets.sh <name>…|--all` — for each manifest entry with a cut PNG, resizes to @2x and @3x of its point size (`magick … -resize WxH`) and writes the `Contents.json` + images into the right `.spriteatlas`/`.imageset`/`AppIcon.appiconset`.
- `placeholders.sh` — for every manifest entry without real art, renders a placeholder PNG (rounded rect in a palette color, thick dark outline, the asset's short label) at @2x/@3x so the app builds and lays out with final sizes.
- `sfx.swift` — synthesizes each sound (≤ 0.6 s, 44.1 kHz mono): pop = pitched sine blip with fast decay; flip = filtered noise swish; bat = short noise + low thump; thud = low sine drop; nope = two descending square blips; sparkle = rising sine arpeggio; whoosh = noise sweep; scream = fast vibrato sine glide; leap = rising slide; fanfare = 4-note major arpeggio; tick = 5 ms click. Writes `.caf` via `AVAudioFile`.

- [ ] **Step 1: Write `manifest.json`** with every entry above: `{ "name", "dest": "atlas:Cats" | "imageset" | "appicon", "points": [w, h], "batch": "cats" | "table" | "ui" }`.
- [ ] **Step 2: Write the tools.** Test `cutout.swift` on `Art/style-samples/chosen-d-loud-toy.png` with `--names rug,c1,c2,c3,c4,yarn,cucumber,shelf` → 8 transparent PNGs; open two and confirm transparent corners (`magick identify -format '%[pixel:p{0,0}]'` prints an `srgba(…,0)` value).
- [ ] **Step 3: Run** `placeholders.sh` and `swift Art/tools/sfx.swift Pounce/Resources/Sounds`; regenerate the project; build — `** BUILD SUCCEEDED **`. Add a tiny XCTest-free check: `scripts/check-assets.sh` verifies every manifest name exists in the asset catalog (exit 1 listing missing names); run it — exits 0.
- [ ] **Step 4: Commit** `feat(play-ios): art pipeline, asset manifest, placeholders, synthesized SFX`.

From here, Tasks 21–23 (real art) may run in the background in parallel with Tasks 12–20; they only replace files by name.

---

### Task 12: Design system and app shell

**Files:**
- Create: `Pounce/Design/Palette.swift`, `OutlinedText.swift`, `PillButton.swift`, `Juice.swift`, `Haptics.swift`, `Sound.swift`, `Settings.swift`; `Pounce/App/AppConfig.swift`, `AppModel.swift`, `Route.swift`, `AppDelegate.swift`; modify `Pounce/App/PounceApp.swift`

**Interfaces:**
- Consumes: PounceKit Tasks 4–9, `ArtName`.
- Produces:
  - `enum Palette { static let violet, magenta, teal, orange, sky, lime, ink /* outline #1B0B3A */, night /* background #2A0F5C */: Color; static let playerRings: [Color] /* violet, magenta, teal, orange, sky, lime */ }`
  - `struct OutlinedText: View { init(_ text: String, size: CGFloat, fill: Color = .white, outline: Color = Palette.ink, width: CGFloat = 3) }` — SF Pro Rounded `.black` weight; outline drawn by 8 offset copies.
  - `struct PillButton: View { init(icon: String /* asset name */, color: Color, size: PillSize = .large, accessibilityLabel: LocalizedStringKey, action: @escaping () -> Void) }` — glossy pill with 6 pt bottom "lip", presses down 4 pt, haptic tick + `sfx-tick`.
  - View modifiers in `Juice.swift`: `.pop(trigger:)`, `.wiggle(trigger:)`, `.shake(trigger:)`, `.bounceLoop(active:)` — all respect `accessibilityReduceMotion` (fades instead).
  - `@MainActor final class Haptics { static let shared; func tick(); func drop(); func success(); func thump(); func celebrate() }` (Core Haptics patterns; no-op when settings off or hardware lacks haptics).
  - `@MainActor final class Sound { static let shared; func play(_ name: String) }` (pre-loaded `AVAudioPlayer` pool, ambient session so it mixes with music, respects mute).
  - `@MainActor @Observable final class Settings { var soundOn: Bool; var hapticsOn: Bool; var pushPrimed: Bool; var pushDeclinedOnce: Bool }` (UserDefaults).
  - `struct AppConfig { static func load(bundle: Bundle = .main, env: [String: String] = ProcessInfo.processInfo.environment) -> APIConfig }` — env `POUNCE_API_BASE_URL` wins over Info.plist `PounceAPIBaseURL`.
  - `enum Route: Equatable { case pickCat(then: DeepLink?); case home; case join; case room(code: String, intent: RoomIntent) }`, `enum RoomIntent: Equatable { case create, join, rejoin, move(moveCode: String) }`
  - `@MainActor @Observable final class AppModel { init(config: APIConfig, credentials: CredentialStore, dataDirectory: URL); var route: Route; var people: LocalPeople; var tables: [TableEntry]; var cache: [String: CachedTable]; let api: APIClient; func bootstrap() async /* load people, mint credential in background */; func finishPickCat(name: String, cat: Int); func refreshTables() async; func newGame() async; func open(code: String, intent: RoomIntent); func handle(_ link: DeepLink); func goHome() }`
  - Launch argument `-uitest-reset` → AppModel uses a fresh temp data directory and a `MemoryCredentialStore`.

- [ ] **Step 1: Failing test** `ConfigResolverTests` in PounceKit for the pure resolver `public enum ConfigResolver { public static func baseURL(info: [String: Any], env: [String: String]) -> URL? }` (file `Sources/PounceKit/Net/ConfigResolver.swift`; `AppConfig.load` calls it): env wins; Info.plist used otherwise; nil when both are missing or not http(s) URLs.
- [ ] **Step 2: Run** — FAIL; implement; PASS.
- [ ] **Step 3: Implement the design system and shell**; `PounceApp` hosts a `RootView` that switches on `appModel.route` with a spring transition, forwards `onOpenURL` and `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` to `DeepLink.parse` → `appModel.handle`. A `#Preview` gallery shows `PillButton`s and `OutlinedText` on `Palette.night`.
- [ ] **Step 4: Build** — `** BUILD SUCCEEDED **`. **Step 5: Commit** `feat(play-ios): design system, config, app model and routing`.

---

### Task 13: Pick your cat, Home, People on this phone

**Files:**
- Create: `Pounce/Shell/PickCatView.swift`, `HomeView.swift`, `TableCard.swift`, `PeopleSheet.swift`; modify `AppModel.swift`; `PounceKit/Sources/PounceKit/Store/HomeTables.swift` + test `HomeTablesTests.swift`

**Interfaces:**
- Consumes: Task 12 shell; Task 6 stores.
- Produces: `public struct HomeTableItem: Equatable, Sendable, Identifiable { public var id: String /* code */; public var yourTurn: Bool; public var status: String; public var seats: [CachedSeat]; public var turnCat: Int?; public var updatedAt: Double }`; `public enum HomeTables { public static func merge(entries: [TableEntry], cache: [String: CachedTable], now: Date) -> [HomeTableItem] }` — your-turn first (newest first within), then playing/lobby by `updatedAt` desc, then `over` tables updated < 24 h ago; codes missing from `entries` are dropped.
- Accessibility identifiers: `pickcat.cat.<i>`, `pickcat.name`, `pickcat.dice`, `pickcat.confirm`, `home.newGame`, `home.join`, `home.table.<CODE>`, `home.people`, `home.settings`.

- [ ] **Step 1: Failing test** `HomeTablesTests`: ordering (your turn first), over-and-old dropped, missing-from-server dropped, cats filled from cache. Run — FAIL; implement; PASS.
- [ ] **Step 2: Build the screens** per spec §5.2–5.3 and mocks `m1-home.jpg`: Pick your cat = hero cat (`cat<i>-idle`, blinking via a timer that swaps to `awake` briefly) over a 4×2 grid, name field prefilled from `NameGenerator`, dice rerolls, check button disabled until a name exists → `finishPickCat`. Home = `home-bg`, `game-tile` hero, two `PillButton`s (`icon-plus` violet → `newGame()`, `icon-keypad` teal → `.join`), horizontal `TableCard` row (your-turn cards glow orange and `.bounceLoop`), owner cat bottom-left → `PeopleSheet`, gear → settings popover (sound/haptics toggles as icon buttons). `refreshTables()` on appear and on `scenePhase == .active`.
- [ ] **Step 3: Build** and run in the simulator against `scripts/dev-server.sh`: fresh install shows Pick your cat; confirm reaches Home. **Step 4: Commit** `feat(play-ios): pick your cat, home tables, people on this phone`.

---

### Task 14: Join, deep links, Lobby, share

**Files:**
- Create: `Pounce/Shell/JoinView.swift`, `CodeKeypad.swift`, `LobbyView.swift`, `SeatMenu.swift`, `ShareRoom.swift`, `TableScreen.swift` (room container: owns `RoomStore`, switches lobby ↔ table ↔ state cards), `StateCard.swift`; `PounceKit/Sources/PounceKit/Store/RoomEntry.swift` + test `RoomEntryTests.swift`

**Interfaces:**
- Consumes: Tasks 8–9, 12–13.
- Produces:
  - `public enum RoomEntry { public static func autoClaim(model: TableModel, owner: Person) -> ClientMessage? /* lobby + I hold no seat + an open seat exists → .claim(firstOpenSeat, owner) */; public static func notFoundMeaning(code: String, known: Bool) -> NotFoundMeaning }`, `public enum NotFoundMeaning { case badCode, roomClosed }` (known = in table cache or last `/tables`).
  - `RoomContainer` (in `TableScreen.swift`): creates `RoomSocket` + `RoomStore` for the route's code, runs it, sends `presence active/background` on scene phase changes (and closes the socket on background), on first lobby snapshot applies `RoomEntry.autoClaim`; for `.create` the host auto-claims seat 0.
  - Accessibility identifiers: `join.tile.<i>`, `join.key.<char>`, `lobby.code`, `lobby.share`, `lobby.qr`, `lobby.seat.<i>`, `seatmenu.invite`, `seatmenu.here`, `seatmenu.bot`, `seatmenu.remove`, `lobby.start`.

- [ ] **Step 1: Failing tests** `RoomEntryTests`: `autoClaimFirstOpenSeat`, `noAutoClaimWhenAlreadySeated`, `noAutoClaimWhenPlaying`, `knownCode404IsClosed` (`notFoundMeaning(known: true) == .roomClosed`), `typedCode404IsBadCode`. Run — FAIL; implement; PASS.
- [ ] **Step 2: Build Join** (mock `m2-join.jpg`): 5 tiles + `CodeKeypad` built from `RoomCode.alphabet` (letters row-wrapped, digits last row), delete key, auto-submit at 5 → `open(code:, intent: .join)`; on `.notFound` with `.badCode` → tiles `.shake` + clear, gray cat head-shake, `sfx-nope`.
- [ ] **Step 3: Build Lobby** (mock `m3-lobby.jpg`) per spec §5.5: code in `OutlinedText` + share + QR toggle (CoreImage `CIQRCodeGenerator` of the share link, scaled with nearest-neighbor, in a white rounded tile); rug with 6 cushions laid out on an ellipse; cushion states human (cat + badge `badge-phone` if `yours`, `badge-remote` otherwise, presence pose: awake→`awake`, away→`away`, asleep→`asleep`), bot (`cat0-idle`-style House Cat art + `badge-bot` — use cat index 3 gray with the bot badge), open (pulsing `icon-plus`), closed (dashed outline). `SeatMenu` radial with four `PillButton`s mapped to `configure`/claim; "On this phone" opens a person picker (local people + "new person" quick create: cat grid + name). Your own cat → leave/swap. Start = big orange `icon-play` pill, disabled → `blockingSeats` cushions `.wiggle`. `lobbyNope` intents wiggle the last tapped control.
- [ ] **Step 4: Build share**: `ShareRoom` presents `UIActivityViewController` with an `NSObject & UIActivityItemSource` that returns the URL and `LPLinkMetadata` (title `Cat Tower`, `iconProvider`/`imageProvider` = host cat `cat<i>-idle` image, `originalURL`/`url` = share link).
- [ ] **Step 5: Connection and cleanup**: while `!store.connected` show a small unraveling-yarn indicator in a corner (no text) and disable input; on `.closed`, or `.notFound` with `.roomClosed`, remove the code from `TableCache` and refresh Home tables.
- [ ] **Step 6: State cards**: `StateCard(kind: .closed | .stalled | .offline | .full | .update)` = art + one `icon-home` pill (offline also `icon-play` retry). Lobby → full when the room isn't in lobby and I hold no seat.
- [ ] **Step 7: Manual check** with two simulators against the dev server: A creates, B joins by code and is auto-seated; A adds a bot and starts; both leave the lobby. **Step 8: Commit** `feat(play-ios): join by code or link, lobby seats, share and QR`.

---

### Task 15: Table scene foundation

**Files:**
- Create: `Pounce/Table/TableView.swift`, `TableScene.swift`, `AnimationDirector.swift`, `CardFaceFactory.swift`, `CardNode.swift`, `CatNode.swift`, `HandNode.swift`, `PileNode.swift`, `TowerNode.swift`, `LaidZoneNode.swift`, `TrayNode.swift`, `OpponentsNode.swift`, `TableAccessibility.swift`; `Pounce/App/DemoMode.swift`; `PounceKit/Sources/PounceKit/Demo/DemoFixtures.swift` + test `DemoFixturesTests.swift`

**Interfaces:**
- Consumes: Tasks 8–10, 11 names.
- Produces:
  - `struct TableView: UIViewRepresentable { let scene: TableScene }` — `SKView` with `preferredFramesPerSecond = 60`, `ignoresSiblingOrder = true`, `shouldCullNonVisibleNodes = true`, `isPaused` controlled by the director.
  - `@MainActor final class TableScene: SKScene { init(store: RoomStore, passAndPlay: Binding-free callbacks: onCurtainChange: (CurtainState) -> Void); func reconcile(_ model: TableModel, revealed: Seat?); func play(_ intent: TableIntent) async; var director: AnimationDirector { get } }` — `scaleMode = .resizeFill`, layers by zPosition: background 0, rug 10, piles 20, laidZone 30, tower 40, opponents 50, trays 60, hand 70, drag 90, fx 100.
  - `@MainActor final class AnimationDirector { init(view: SKView?); func run(_ action: SKAction, on node: SKNode) async; func emit(_ emitter: SKEmitterNode, at: CGPoint, in: SKNode, lifetime: TimeInterval); func wake(); var isIdle: Bool; var framesRendered: Int /* DEBUG counter */ }` — counts running actions/emitters; pauses the view 0.1 s after the last finishes and no touch is active; `wake()` unpauses.
  - `@MainActor final class CardFaceFactory { static let shared; func texture(for card: CardID) -> SKTexture; func back() -> SKTexture }` — composites `card-face` + `coat-<c>` + numeral (SF Pro Rounded Black, violet fill `Palette.violet`, ink outline, top-left) + `glyph-<c>` once per id with `UIGraphicsImageRenderer`, caches.
  - `CardNode(card: CardID?)` (nil = back), `CatNode(cat: Int, ringColor: Color)` with `func setPose(_ pose: CatPose)`, `func setBadges(bot: Bool, skip: Bool, laid: Bool)`, `func setPresence(_ p: Presence?)`, `func setActive(_ on: Bool)`.
  - Accessibility: each interactive node is a `UIAccessibilityElement` via the scene's `accessibilityElements`, identifiers `table.deck`, `table.discard`, `table.hand.<index>`, `table.opponent.<seat>`, `table.tray.<i>`, `table.laydown`, `table.group.<seat>.<g>`, `table.menu`, `table.turn` (value `mine` or `other`), `table.frames` (DEBUG: value = `framesRendered`).
  - `public enum DemoFixtures { public static func table(seats: Int, mySeat: Seat, phase: Int) -> RoomView; public static func lobby() -> RoomView; public static func roundOverEvents() -> [GameEvent] }` and DEBUG launch argument `-demo <lobby|table|celebrate|curtain>` that renders those screens without a server (`DemoMode.swift`).

- [ ] **Step 1: Failing test** `DemoFixturesTests`: fixtures are internally consistent (hand counts match `handCounts`, every card id unique across visible hands/laid/discard top, `TableModel(room:).isMyTurn` for `table(…)`). Run — FAIL; implement; PASS.
- [ ] **Step 2: Implement the scene and nodes**; `reconcile` is idempotent: diff by card id / seat, move nodes to layout positions without animation, create/remove as needed; only the revealed seat's hand nodes exist (Review Focus 3). Opponents bar shows cats in `opponents(bottom:)` order with ring colors from `Palette.playerRings[seat]`, card-count bubble (`OutlinedText`-style numeral texture), presence pose, badges. Tower shows each seat's mini cat head at `shelf(phase)`.
- [ ] **Step 3: Verify** `xcrun simctl launch booted com.conleychaos.play -demo table` and screenshot; compare against `Art/mockups/m0-table.jpg` for structure (opponents top, tower left, rug + piles center, hand fan bottom). Idle: after 2 s `table.frames` stops increasing (checked again in Task 24). **Step 4: Commit** `feat(play-ios): SpriteKit table scene with render-on-demand and demo mode`.

---

### Task 16: Table interactions

**Files:**
- Create: `Pounce/Table/TableInput.swift`; modify `TableScene.swift`, `HandNode.swift`, `TrayNode.swift`, `PileNode.swift`, `LaidZoneNode.swift`; `PounceKit/Sources/PounceKit/Store/TrayState.swift` + test `TrayStateTests.swift`

**Interfaces:**
- Consumes: Task 9 `TableModel` (`drawSources`, `canPlay`, `trays`, `hitTargets`, `skipTargets`, `discardAction`), Task 8 `RoomStore.act`.
- Produces: `public struct TrayState: Equatable, Sendable { public init(requirements: [Requirement]); public private(set) var slots: [[CardID]]; public mutating func add(_ card: CardID, to tray: Int); public mutating func remove(_ card: CardID); public func isValid(_ tray: Int) -> Bool; public var allValid: Bool; public func layGroups() -> [LayGroup] /* phase order; runs sorted ascending with Yarn placed by runStart; runStart = explicit placement or Rules default */; public mutating func moveYarn(_ card: CardID, inTray: Int, toIndex: Int); public var cardsInTrays: Set<CardID> }`.

Gestures (spec §5.7–5.8): drag or tap-tap. Draw: drag a glowing pile to the hand or tap it → `act(.draw(source))`. Discard: drag a hand card onto the discard pile → `act(model.discardAction(card:target:nil))` unless it's a Cucumber with skip targets, in which case opponents' cats glow and the drop must land on a glowing cat (`target`), or tap card then tap cat. Trays: drag into a tray; valid tray → `tray-gold`; when `allValid` the `table.laydown` paw pops → `act(.layDown(trayState.layGroups()))`. Hit: when laid, dragging a card enlarges the laid zone and glows `hitTargets`; drop → `act(.hit(card, target))`. Reorder: drag within the hand; sort toggle (`icon-sort`) cycles number/coat order (local only). Illegal drop → card returns with the Nope verb. Provisional: the dropped card animates to its target immediately; on `.rejected` it animates back (Task 17 owns the animation, this task calls `director.provisional(...)`/`rollback()` hooks — define them here as no-op-capable methods on `TableScene`: `func provisionalMove(card: CardID, to: CGPoint)`, `func rollbackProvisional()`). Input is disabled while `store.actionInFlight`.

- [ ] **Step 1: Failing tests** `TrayStateTests`: phase-2 trays accept a set of 3 and a run of 4 and produce groups in phase order; a run with Yarn yields the default `runStart`; `moveYarn` to the front changes `runStart` by −1 when legal; invalid tray stays invalid with a Cucumber; removing a card un-golds. Run — FAIL; implement; PASS.
- [ ] **Step 2: Implement gestures**; every gesture has the tap-tap path and a VoiceOver custom action on hand cards (`Discard`, `Put in tray 1/2`, `Add to group`) and on piles (`Draw`).
- [ ] **Step 3: Manual check** against the dev server with 1 human + 2 bots: draw from both piles, discard, aim a Cucumber, and keep playing until phase 1 can be laid down through the trays, then hit a bot's group. (TrayState unit tests cover the tray logic; the e2e driver in Task 24 covers server acceptance of lay-downs.) **Step 4: Commit** `feat(play-ios): draw, discard, aim, lay down and hit by drag or tap`.

---

### Task 17: Event animations and juice

**Files:**
- Create: `Pounce/Table/IntentAnimations.swift`, `Effects.swift`; modify `TableScene.swift`, `AnimationDirector.swift`

**Interfaces:**
- Consumes: Task 8 `TableIntent`, Task 12 `Haptics`/`Sound`, Task 15 nodes.
- Produces: `extension TableScene { func animate(_ event: GameEvent) async }` covering every `GameEvent` kind with the spec §9.1 verbs; `enum Effects { static func burst(_ kind: BurstKind, at: CGPoint, in: SKNode, director: AnimationDirector); static func shake(_ node: SKNode, amplitude: CGFloat, duration: TimeInterval) -> SKAction; static func pop() -> SKAction; static func squash() -> SKAction; static func nope() -> SKAction }`, `enum BurstKind { case stars, fur, yarn, sparkle, confetti }` (emitters built in code from `fx-*` textures, birth ≤ 80/s, lifetime ≤ 0.8 s, total particles ≤ 60).

Mapping (timings from spec §9.1): `drew` deck → mine: lift + flip (x-scale 1→0→1, swap texture) 0.3 s, sparkle on Yarn, wobble + `sfx-scream` quiet on Cucumber; others: back card slides to their cat. `drew` discard → top card arcs to hand/cat. `discarded` → Bat (arc + spin + `paw-swipe`, pile squash, `sfx-bat`, haptic drop). `discarded` with `skipTarget` → cucumber flies to target cat → Cucumber terror (target `terrified` pose + jump + fur burst + 4 pt shake 0.2 s, `sfx-scream`, haptic thump). `skipped` → target cat shows `badge-skip` pop then fades. `laidDown` → cards fly to the laid zone with 40 ms stagger, squash + stars, `sfx-pop` per card, haptic success. `hit` → arc + group bump. `turn` → ring handoff; mine also bounces the hand and glows piles, `sfx-tick`. `reshuffled` → riffle discard into deck, `sfx-whoosh`. `roundStarted` → deal animation (cards from deck to each seat, 25 ms stagger). `roundOver`/`gameOver` → hand off to Task 18. After each intent: `reconcile`. `rejected` → `rollbackProvisional()` + Nope + `sfx-nope`. Reduce Motion: arcs become 0.15 s fades, no shake, bursts halved. Idle flourishes: a random cat blinks/flicks (swap to `awake` 0.15 s) every 5–9 s for 60 s after the last change, via the director so the view unpauses only for the flourish.

- [ ] **Step 1: Implement**, then **Step 2: verify** in demo mode with a DEBUG "replay" that plays `DemoFixtures` events in a loop; record a simulator video (`xcrun simctl io booted recordVideo`) of 20 s and watch it for stutter; check `table.frames` stops increasing within 1 s after the loop ends. **Step 3: Commit** `feat(play-ios): juicy event animations, particles, haptics and sound`.

---

### Task 18: Round over, game over, versus intro, tower leap

**Files:**
- Create: `Pounce/Table/Celebrations.swift`, `Pounce/Shell/GameOverView.swift`; modify `TableScene.swift`, `TowerNode.swift`, `TableScreen.swift`

**Interfaces:**
- Consumes: Task 17 effects; `GameEvent.roundOver`, `.gameOver`; `TableIntent.versusIntro`.
- Produces: `extension TableScene { func playVersusIntro() async; func playRoundOver(wentOut: Seat?, points: [Int], advanced: [Seat]) async /* ≤ 5 s total */; func playGameOver(winners: [Seat]) async }`; `ScoreboardOverlay` (SwiftUI, opened by tapping the tower: each seat's cat, phase badge and score as outlined numerals, tap anywhere to close; accessibility id `table.tower`); `TowerNode.leap(seat: Seat, from: Int, to: Int) async`; `GameOverView(winners: [Person], onHome:, onNewGame:)` (SwiftUI overlay with `sunburst`, `crown`, confetti, `icon-home` and `icon-plus` pills).

Round over: my leftover cards flip face up (others show only their numbers), points pop as outlined numerals off each cat in seat order (0.3 s stagger), then each advanced cat does the Shelf leap (squat 0.08 s → arc 0.35 s → squash → star burst → `shelf-badge` with the new phase number pops, `sfx-leap`, haptic celebrate), staggered 0.45 s. Versus intro: cats slide in on diagonal color slashes (1.2 s) then the deal. Game over: winner cat on the top shelf, `celebrate` pose, crown drop, sunburst rotate (one slow loop, stops after 4 s), confetti, `sfx-fanfare`; then `GameOverView`.

- [ ] **Step 1: Implement. Step 2: Verify** with `-demo celebrate` (plays round over → leap → game over) and screenshot the leap peak and the game-over frame; compare with `Art/mockups/m5-celebrate.jpg` (tower center/left, cat mid-leap, burst, badge). **Step 3: Commit** `feat(play-ios): round over, shelf leap, versus intro and game over`.

---

### Task 19: Pass-and-play curtain

**Files:**
- Create: `Pounce/Shell/PassCurtainView.swift`; modify `TableScreen.swift`, `TableScene.swift`, `LobbyView.swift` (multi-local seat flow is in Task 14; verify it here)

**Interfaces:**
- Consumes: Task 9 `PassAndPlay`, `CurtainState`.
- Produces: `PassCurtainView(person: Person, onRevealed: () -> Void)` — `curtain-stage` art, spotlight, the cat (`cat<i>-idle`), the name once in `OutlinedText`, a glowing paw `icon-hold` button that fills a ring over 0.6 s while pressed (releasing early resets), accessibility label "Hold to show <name>'s cards" with an accessibility action that reveals immediately. Local cats row: on a multi-seat phone, small cats of my seats along the bottom when it isn't my turn; tapping one → `passAndPlay.peek(seat)`; tapping the table after a peek → `hide()`.

- [ ] **Step 1: Implement**: `TableScreen` owns `PassAndPlay`, calls `update(TableModel)` on every reconcile, shows `PassCurtainView` above `TableView` for `.curtain(s)`, passes `revealed` into `scene.reconcile`. The curtain appears before any hand node for that seat is created.
- [ ] **Step 2: Verify** with one simulator holding two local seats + a bot against the dev server: curtain appears for each local turn; during the bot turn no hand is visible; screenshot the curtain and compare with `m4-pass.jpg`. **Step 3: Commit** `feat(play-ios): pass-and-play curtain with hold to reveal and peek`.

---

### Task 20: Push, reminders, table menu, move my seat

**Files:**
- Create: `Pounce/App/PushCoordinator.swift`, `Pounce/Shell/PushPrimingView.swift`, `TableMenuSheet.swift`, `MoveSeatSheet.swift`; modify `AppDelegate.swift`, `AppModel.swift`, `TableScreen.swift`; `PounceKit/Sources/PounceKit/Store/PushPolicy.swift` + test `PushPolicyTests.swift`

**Interfaces:**
- Consumes: Task 6 `APIClient.setPushToken`, Task 8 `RoomStore.moveCode`, `send(.moveSeat/.claimMove)`.
- Produces:
  - `public enum PushPolicy { public static func shouldPrime(model: TableModel, primed: Bool) -> Bool /* playing, and some human seat is not mine */; public static func reminderDelay(model: TableModel) -> Duration? /* .seconds(600) when isMyTurn, else nil */; public static func hexToken(_ data: Data) -> String; public static func code(fromPayload userInfo: [AnyHashable: Any]) -> String? /* top-level "code", validated by RoomCode.isValid */ }`
  - `@MainActor final class PushCoordinator: NSObject, UNUserNotificationCenterDelegate { func registerEveryLaunch(); func requestAuthorization() async -> Bool; func didRegister(token: Data) /* upload every time */; func scheduleTurnReminder(code: String, name: String, after: Duration); func cancelTurnReminder(code: String) }` — foreground presentation suppressed when that code's table is on screen; tap → `appModel.open(code:, intent: .rejoin)`.

- [ ] **Step 1: Failing tests** `PushPolicyTests`: prime only when a remote human exists; never for bots-only or all-local; reminder only on my turn; `hexToken` of `Data([0xAB, 0x01])` is `"ab01"`; payload code validated (`"K7QM4"` ok, `"bad"` nil). Run — FAIL; implement; PASS.
- [ ] **Step 2: Implement**: `AppDelegate` calls `registerForRemoteNotifications()` every launch (if authorized) and forwards the token; `PushPrimingView` (spec §10, `push-priming` art with a mock "your turn" banner drawn from the player's cat + name) shown once when `shouldPrime`; declined → `pushDeclinedOnce`, a small `icon-bell` on Home re-offers once. On background during my turn → `scheduleTurnReminder` (title = my seat's person name, body "Your turn", thread id = code); cancel on foreground. `TableMenuSheet` (`table.menu`): sound, haptics, move my seat, home. `MoveSeatSheet`: pick seat if several → `send(.moveSeat)` → show 6 code tiles + QR of `https://play.conleychaos.com/j/<CODE>?move=<M>` + share; receiving phone handles `DeepLink.move` → `RoomIntent.move` → after the snapshot sends `.claimMove(code:)`; `bad_code` shakes, `too_many_attempts` → state card.
- [ ] **Step 3: Verify** on simulator: priming appears when a second device holds a seat; `xcrun simctl push booted com.conleychaos.play payload.json` with `{"aps":{"alert":{"title":"Mia","body":"Your turn"}},"code":"<CODE>"}` opens that table; move-seat between two simulators moves the hand. **Step 4: Commit** `feat(play-ios): push priming and routing, turn reminder, table menu, move seat`.

---

### Task 21: Art batch — cats

**Files:**
- Create: `Art/prompts/cat-<i>.txt` (8), `Art/prompts/cat-poses.txt`; replace `Cats.spriteatlas` placeholders

- [ ] **Step 1: Idle sheet.** One Codex image per cat (`gen.sh prompts/cat-<i>.txt raw/cat<i>-idle.png`): "a single <coat description> cartoon cat, full body sitting, front-facing, big eyes, centered on a flat plain light-gray background, no shadow, no text", style D. Review all 8 together (contact sheet via `magick montage`); regenerate any that look off-style, beige, or inconsistent.
- [ ] **Step 2: Pose sheets.** Per cat, one image with the 6 other poses in a 3×2 grid (awake = alert ears up; away = curled up eyes half-closed; asleep = curled with closed eyes; leap = stretched mid-jump; terrified = fur standing, arched, eyes wide; celebrate = paws up, mouth open), flat light-gray background, passing that cat's idle PNG as an extra `-i` reference. `cutout.swift --names cat<i>-awake,cat<i>-away,cat<i>-asleep,cat<i>-leap,cat<i>-terrified,cat<i>-celebrate`; if the instance count is wrong, regenerate or fall back to one image per pose.
- [ ] **Step 3:** `build-assets.sh` the 56 sprites; `check-assets.sh`; build; screenshot `-demo lobby` and `-demo table`; review cats at size (readable faces, thick outlines, no halo fringe — if Vision leaves a light fringe, add `-morphology Erode Disk:1` on alpha in `build-assets.sh`).
- [ ] **Step 4: Commit** `art(play-ios): eight cats with seven poses`.

---

### Task 22: Art batch — cards, table, effects

**Files:**
- Create: `Art/prompts/cards.txt`, `table.txt`, `fx.txt`; replace `Cards`, `Table`, `FX` atlas placeholders and `room-bg`

- [ ] **Step 1: Generate** (style reference + prompts derived from `chosen-d-loud-toy.prompt.txt`): blank card face (white, glossy violet rim, no numeral, no art) and card back (violet, big paw); the 4 coat cat faces (head only, matching the D sample) on one sheet → cutout `--names coat-tabby,coat-tuxedo,coat-calico,coat-gray`; 4 glyphs on one sheet (stripe mark, bow tie, three-patch blob, paw print; thick ink outline) → cutout; Yarn and Cucumber center art; rug; room background (top-down cozy living room at night, empty center for the rug, no text); tower base/shelf/top + shelf badge; ring + ring glow; tray + gold tray; paw swipe; crown; sunburst; FX sheet (star, fur puff, yarn bit, confetti piece, sparkle).
- [ ] **Step 2:** Build assets; verify card faces composite cleanly via `-demo table` (numeral sits top-left above the glyph, cat face centered, rim intact at 64×90 and in the 0.6× laid zone); readable at mini size.
- [ ] **Step 3: Commit** `art(play-ios): cards, table, tower and effects`.

---

### Task 23: Art batch — UI icons, state art, app icon

**Files:**
- Create: `Art/prompts/icons.txt`, `states.txt`, `appicon.txt`; replace icon/state imagesets and `AppIcon`

- [ ] **Step 1: Generate** icons in sheets of 6–9 (glossy chunky icons, thick ink outline, no letters) → cutout with `--names`; badges; state art (closed: cat asleep on empty rug; stalled: gray cat tangled in yarn; offline: cat looking at an unplugged yarn ball; full: curled cat on a full rug; update: cat holding a wrench-shaped yarn hook — any no-text "update" metaphor), `home-bg`, `curtain-stage`, `game-tile`, `push-priming`; app icon (orange tabby on a cat tower on violet, full-bleed square, no text, no rounded corners — iOS masks it).
- [ ] **Step 2:** Build; `check-assets.sh` — no placeholders left (`placeholders.sh --report` lists zero). Screenshot Home, Join, Lobby, Curtain and compare with `m1`–`m4` mocks.
- [ ] **Step 3: Commit** `art(play-ios): icons, state art and app icon`.

---

### Task 24: End-to-end game, UI smoke test, idle render test, screenshots

**Files:**
- Create: `PounceKit/Sources/pounce-e2e/main.swift` (replace stub), `apps/play-ios/scripts/e2e.sh`, `scripts/screenshots.sh`, `PounceUITests/SmokeTests.swift`, `PounceUITests/IdleRenderTests.swift`

**Interfaces:**
- Consumes: Tasks 4–9 (Solver, APIClient, RoomSocket, RoomStore-free raw handling is fine), Task 14/15 accessibility identifiers.

`pounce-e2e --base http://localhost:8787 --local 2 --bots 2 --timeout 1800`: mints a device, creates a room, claims seats 0…local-1 with distinct `Person`s on the same device (pass-and-play path), configures `bots` seats as bot and the rest closed, starts, then plays every local turn: draw (discard top if it completes `Solver.findPhase`, else deck); if not laid and `Solver.findPhase` succeeds → `layDown`; if laid → apply all `Solver.hits` one by one; discard the highest-points non-Yarn card (Cucumber aimed via `TableModel.discardAction` at the first skip target). Waits for each resulting event/snapshot before the next action; exits 0 printing `rounds=<n> winners=<seats> phases=<…>` on `gameOver`, exits 1 on timeout, any `error` other than expected, or a stall.

- [ ] **Step 1: Write `e2e.sh`**: start `scripts/dev-server.sh` in the background, wait until `/healthz` reports `"configured":true` (30 s max), `swift run --package-path PounceKit pounce-e2e …`, always kill the server; exit with the driver's status.
- [ ] **Step 2: Run** `scripts/e2e.sh` (in the background; it can take several minutes) — expect exit 0 and a `winners=` line. Fix bugs it finds in PounceKit with a regression test each.
- [ ] **Step 3: Smoke UI test** `SmokeTests.testCreateBotStartDrawDiscard` (launch args `-uitest-reset`, env `POUNCE_API_BASE_URL=http://localhost:8787`): `pickcat.confirm` → `home.newGame` → `lobby.seat.1` → `seatmenu.bot` → `lobby.start` → wait until `table.turn` value is `mine` (≤ 30 s; bots move in 1.2 s) → tap `table.deck` → tap `table.hand.0` → tap `table.discard` → wait until `table.turn` value is `other`. Requires the dev server (run via a test plan pre-action or start it before `xcodebuild test`).
- [ ] **Step 4: Idle test** `IdleRenderTests.testTableStopsRenderingWhenIdle` (launch `-demo table`): read `table.frames`, wait 3 s, read again — equal. Then tap `table.deck` area (wake) — value increases.
- [ ] **Step 5: Run** `xcodebuild test -scheme Pounce -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` with the dev server up — `** TEST SUCCEEDED **`.
- [ ] **Step 6: Screenshots** `scripts/screenshots.sh` → `apps/play-ios/Art/screenshots/{lobby,table,curtain,celebrate,home,join}.png` using `-demo` modes and `xcrun simctl io booted screenshot`; compare each with its mockup and fix glaring differences (layout bands, palette, no text). Commit the screenshots (resized to 1400 px tall JPEG).
- [ ] **Step 7: Commit** `test(play-ios): scripted e2e game, UI smoke, idle render check, screenshots`.

---

### Task 25: TestFlight script, README, final verification

**Files:**
- Create: `apps/play-ios/scripts/testflight.sh`, `apps/play-ios/ExportOptions.plist`; finish `apps/play-ios/README.md`; modify root `README.md` (link to the iOS README)

- [ ] **Step 1: `testflight.sh`**: `set -euo pipefail`; `--dry-run` prints the commands without running them; runs `bootstrap.sh`; bumps `CURRENT_PROJECT_VERSION` to `$(date +%Y%m%d%H%M)`; `xcodebuild archive -project Pounce.xcodeproj -scheme Pounce -configuration Release -destination 'generic/platform=iOS' -archivePath build/Pounce.xcarchive -allowProvisioningUpdates`; `xcodebuild -exportArchive -archivePath build/Pounce.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build/export -allowProvisioningUpdates` (ExportOptions: `method` `app-store-connect`, `destination` `upload`, `teamID` `B222J9J7B8`, `signingStyle` `automatic`). Optional App Store Connect API key via env (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` → `-authenticationKeyPath …`), never committed. Verify: `bash -n` and `scripts/testflight.sh --dry-run` print the expected commands. Do **not** run the upload.
- [ ] **Step 2: README**: prerequisites (Xcode 27, xcodegen, pnpm), bootstrap, dev server, run on simulator/phone (LAN: `POUNCE_API_BASE_URL=http://<mac-ip>:8787` in the scheme), tests (`swift test`, `xcodebuild test`, `scripts/e2e.sh`), art pipeline (gen → cutout → build-assets), demo modes, TestFlight, and **JD prerequisites**: App ID capabilities (Push Notifications, Associated Domains), APNs `.p8` into 1Password + deploy secrets, App Store Connect record, TestFlight testers, server deployed to `play.conleychaos.com`; note debug builds get sandbox APNs tokens and won't receive production pushes.
- [ ] **Step 3: Final verification** (all must pass, paste outputs into the ledger): `swift test --package-path apps/play-ios/PounceKit`; `xcodebuild … build` and `test` with the dev server; `scripts/e2e.sh`; root `pnpm lint && pnpm typecheck && pnpm test`; `gitleaks detect --source . --no-banner` (and `gitleaks protect --staged`) — no leaks; `git status` clean, no `.dev.vars` tracked.
- [ ] **Step 4: Commit** `chore(play-ios): TestFlight script and README`.
