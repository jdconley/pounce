# Notifications and Pounce, app half (daily habit PR 5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app half of §15 row 5: notification categories and actions, provisional authorization, the synced notification settings panel (gear sheet and the Us screen's gear), the Pounce sheet from the Us screen's bell and the answer flow (push actions and in-app for waiting pounces), the Messages share link (never from a kitten's device), universal links `/p/<token>`, and the `PounceNotify` Notification Service Extension that turns pushes from a person into communication notifications with the sender's cat as the avatar. Kitten devices never register for remote push; they get only local reminders. It also turns `NOTIFY` on in production.

**Architecture:** Everything with a rule in it is pure PounceKit code with Swift Testing tests: the push payload (decoded against `apps/play-api/fixtures/push/payloads.json`), categories and what each action does, notification settings and their band defaults (mirroring `apps/play-api/src/notify/settings.ts`), the settings store with per-key timestamps, the pounce wire types and routes, the Pounce sheet's tiles and the bell's state, the pending-answer queue, the `/p/` deep link and the communication-notification plan. The app wires them: `PushCoordinator` registers categories, asks for provisional authorization on priming's "not now", routes actions (background answers inside `beginBackgroundTask`, retried at the next launch from a file), and the new `PounceStore` holds sends and answers. SwiftUI draws the panel, the sheet and the answer card. The `PounceNotify` extension links PounceKit and reads the cat art from the containing app's bundle.

**Tech Stack:** Swift 6 (strict concurrency, must build with CI's Xcode 26.6), SwiftUI, UserNotifications, Intents (INSendMessageIntent), Swift Testing, XCUITest; TypeScript Workers + vitest for the wrangler change; ImageMagick for placeholders.

**Spec:** `docs/superpowers/specs/2026-11-04-daily-habit-design.md` (§10.2, §12 all, §14.1, §15 row 5, §16). Server contract: `docs/superpowers/plans/2026-11-04-notify-server.md`, PR #26 (`apps/play-api/src/notify/*`, `src/pounce/*`, `fixtures/push/payloads.json`). Base: PR 4, `docs/superpowers/plans/2026-11-04-streak-ui.md`.

## Global Constraints

- iOS 26.0, Swift 6 strict concurrency, Apple frameworks only, XcodeGen `project.yml`. Code must compile on Xcode 26.6 (CI): no Swift 6.4-only features, no local constant named like a method it calls in its own initializer.
- No emoji anywhere. On screen only names, table names and numerals; everything else is art or icons. No guilt copy, no countdowns. Notification text is the server's §12.2 copy; the app's own local notifications reuse §12.2 lines.
- Loud Toy palette (violet, magenta, teal, orange, sky, lime, ink); never beige or muted. New art as `_ph` placeholders in `Art/manifest.json` (batch `habit`), drawn by `Art/tools/habit-placeholders.sh`.
- Settings keys, exactly the server's: `reminders.on`, `reminders.auto`, `reminders.weekday`, `reminders.weekend` (`{h, m}`), `quiet.start`, `quiet.end` (`{h, m}`), `lastChance.on`. Defaults: adult reminders/auto/lastChance on, reminder 19:30, quiet 22:00–08:00; teen reminders/auto/lastChance off, quiet 21:00–08:00; kitten nothing from the server.
- Categories: `YOUR_MOVE` and `REMINDER` → Play (`.foreground`), In an hour (background, a local notification, no server call); `POUNCE` → Play (`.foreground`), In a bit, Not now (background, `POST /v1/pounces/{id}/answer` inside `beginBackgroundTask`, retried on next launch); `STATUS` → none. Never Time Sensitive.
- Kitten (§14.1): no `registerForRemoteNotifications`, no token upload, no notification settings sent, no share links; local turn reminder and a local daily 17:00 reminder only, both off by default. Teens: no prompts to turn on reminders or share beyond the one in-context place.
- Pounce routes: `POST /v1/pounces {to?: pairId, target: {table} | "new" | "pick"} -> {id, link?}`; `POST /v1/pounces/{id}/answer {answer, choice?, link?} -> {code?}`; `GET /v1/pounces/links/{token} -> {id, from: {name, cat}, target}`. All take `?person=`. 429 `resting`, 409 `not_shared`/`busy`, 410 `expired`, 403 `not_allowed`.
- Links: `https://play.conleychaos.com/p/<token>` (token `[A-Za-z0-9_-]{22}`), `pounce-dev://p/<token>` in Debug.
- Debug-only stubs and demos (`#if DEBUG`). Own simulators, private dev server port; never :4343, :8787, the physical iPhone or others' simulators.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Decisions where the spec is silent

1. **Guests' settings reach the server.** PR 2 syncs only for signed-in devices, but the server decides reminders for every player. Signed-in devices carry the notification keys in the existing settings ledger; a guest device (teen or adult) `PATCH`es just the changed notification keys itself. Kitten devices send none.
2. **Only chosen values are stored.** A key someone never touched isn't sent, so the server's band defaults apply (and change with the band, a kitten turning 13).
3. **Default tap on a pounce** = Play: a table or new-game pounce answers `play` and opens the table; a "you pick" pounce opens the pick sheet. A default tap on anything else opens its `code` as today.
4. **"In an hour"** re-posts the same content as a local notification 60 minutes later (id `snooze-<collapse>`), cancelled when that table opens or when the tables list shows it's no longer your move.
5. **Answer retry queue** is a JSON file of `{id, answer, choice, link, person}`; one entry per pounce id (a later answer replaces an earlier one unless the earlier is `play`); a 4xx drops the entry, a transport error keeps it. Retried at launch and on foreground.
6. **Communication notifications** for `your_move`, `pounce`, `play_again` and `pounce_answered` when `from` is present. The sender is an `INPerson` with the cat as a round, loudly coloured avatar; `speakableGroupName` is the push's own title, so the title stays the name of the person the push is for (§12.2) and the sender shows beside it. Conversation id is the `thread-id`.
7. **No App Group yet.** The extension's "write the streak block to the App Group and reload widgets" waits for PR 6, which creates the widgets and `group.com.conleychaos.play`. The extension reads cat art from the containing app's bundle, so it needs no group now.
8. **The waiting-pounce card** sits on the Us screen for the pair it's from (and Home's badge gets a small ringing bell that opens the Us screen on that pair). Answering in the app uses the same queue as the push actions.
9. **Sender bell states** on the Us screen: ready (bell), sent (bell ringing), quiet (bell with a moon), resting (sleeping bell, disabled), answered play (their cat leaping, tap opens `code`), later (clock), no (their cat asleep). Answer states show for the hour the server keeps them.
10. **The Pounce sheet's share button** makes a link pounce (`target` "new" when the new-game tile is chosen, else "pick"; links can't target a table) and opens the system share sheet with the URL. Hidden on a kitten's device. With no pairs, the Us screen's empty state shows a bell that opens the sheet in share-only mode.
11. **The Us screen's Play pill** (no shared table in play) opens the Pounce sheet with New game preselected instead of creating a game (§10.2).
12. **Clock dials** are round faces showing `HH:MM` numerals; drag around the ring sets the time in 15-minute steps over 24 hours; VoiceOver adjusts by 15 minutes. A reminder dial clamps the way the server does (outside quiet hours, at least 2 h before quiet starts) so it never shows a time the server won't use.
13. **The live-table toggle** (§12.6) waits for PR 7, which builds the live table.
14. **Kitten's panel** is just the local daily reminder's bell beside a fixed `17:00`; its copy is "The cats are on the rug." titled with the kitten's name.
15. **Home's re-offer bell** now shows while authorization is provisional (not only denied), since provisional is the quiet "not now" (§12.5).
16. **`PUT /v1/devices/me/widget-push`** waits for PR 6 (no widgets to push to).

## Review Focus

1. **A payload the app half-understands** (unknown kind, missing `from`, a `pounce` without `target`, a `streak` block with extra fields) must decode to something safe and never crash the extension. Test: `PushPayloadTests.testUnknownKindIsUnknown`, `testMissingFieldsDecode`, `CommunicationPlanTests.testNoFromIsNoPlan`.
2. **The background answer when the network is down or the app was killed**: it must be on disk before the POST and go out at the next launch, once. Test: `PounceStoreTests.testFailedAnswerRetriesOnce`, `testPlayIsNeverDowngraded`.
3. **Kitten device**: no remote registration, no settings upload, no share button. Test: `NotifySettingsTests.testKittenSendsNothing`, `PushPolicyTests.testKittenNeverRegisters`, UI `PounceTests.testKittenHasNoShare`.
4. **Guest edits a dial twice offline**: the last value goes up once the server answers. Test: `NotifySettingsTests.testUnsentSurvivesFailure`.
5. **Quiet hours wrapping midnight or degenerate** (start = end) in the dial clamp. Test: `NotifySettingsTests.testClampWrapsMidnight`, `testDegenerateQuietNeverClamps`.

---

### Task 1: Server: NOTIFY on in production

**Files:** Modify `apps/play-api/wrangler.jsonc` (`"NOTIFY": "on"`), `src/env.ts` and `src/streaks/profile.ts` doc comments, `src/env.test.ts`.

- [ ] Step 1: test `NOTIFY in production` — `wrangler.jsonc` has `"NOTIFY"` with a value that, with its `STREAKS`, makes `notifyOn` true. Step 2: fails. Step 3: set it. Step 4: `pnpm --filter @pounce/play-api test`, `typecheck`, `lint` pass. Step 5: commit `feat(play-api): NOTIFY on in production (daily habit PR 5, app half)`.

### Task 2: PounceKit push payload, categories and actions

**Files:** Create `PounceKit/Sources/PounceKit/Notify/PushPayload.swift`, `Notify/NotifyActions.swift`, `Notify/CommunicationPlan.swift`; tests `PushPayloadTests.swift`, `NotifyActionsTests.swift`, `CommunicationPlanTests.swift`; `Fixtures.swift` gains `pushPayloads() -> [(name, collapseId, body: [String: Any])]`.

**Interfaces (produces):**
- `enum PushKind: String { yourMove = "your_move", reminder, lastChance = "last_chance", freshStart = "fresh_start", goingQuiet = "going_quiet", nap, winback, paused, milestone, playAgain = "play_again", pounce, pounceAnswered = "pounce_answered", dismiss, unknown }`
- `enum PushCategory: String { yourMove = "YOUR_MOVE", reminder = "REMINDER", pounce = "POUNCE", status = "STATUS" }`
- `struct PushFace: Codable, Hashable { name; cat }`; `enum PounceTarget: Codable, Hashable { table(String), new, pick }`; `enum PounceAnswer: String, Codable { play, later, no }`
- `struct PushPayload { kind; category: PushCategory?; title: String?; body: String?; threadId: String?; code: String?; from: PushFace?; pounce: Pounce?{id, target?, answer?}; streak: Streak?{pair,count,me,them,naps,myMove,theirMove}; pair: String?; init?(userInfo: [AnyHashable: Any]) }`
- `enum NotifyAction: String { play = "PLAY", inAnHour = "IN_AN_HOUR", later = "LATER", notNow = "NOT_NOW"; foreground: Bool }`; `NotifyActions.actions(for: PushCategory) -> [NotifyAction]`; `enum NotifyOutcome: Equatable { open(code), answer(id, PounceAnswer, opensApp: Bool), pick(id, from: PushFace?), snooze(seconds), none }`; `NotifyActions.outcome(action: String, payload: PushPayload) -> NotifyOutcome` (`action` is the UN action id, or `com.apple.UNNotificationDefaultActionIdentifier`).
- `struct CommunicationPlan: Equatable { sender: PushFace; groupName: String?; conversation: String }`; `CommunicationPlan.make(_ p: PushPayload) -> CommunicationPlan?`.

- [ ] Step 1: tests: every fixture decodes with the kind its name starts with and the `aps.category` it carries; `your_move` has `code == "GH2VD"`, `from == PushFace(name: "Mia", cat: 2)`, streak count 12, myMove `["GH2VD"]`; `pounce-table` target `.table("GH2VD")`, `pounce-new` `.new`, `pounce-pick-quiet` `.pick`; `pounce_answered-later` answer `.later`; `testUnknownKindIsUnknown`; `testMissingFieldsDecode` (`{"kind":"pounce"}` → pounce nil); category actions as in Global Constraints; outcomes: default tap on your_move → `.open("GH2VD")`, PLAY on pounce-table → `.answer(id, .play, opensApp: true)`, default on pounce-pick → `.pick(id, from: Mia)`, LATER → `.answer(id, .later, opensApp: false)`, IN_AN_HOUR → `.snooze(3600)`, any action on STATUS → default open/none; plans for your_move, pounce, play_again, pounce_answered with group name = title; `testNoFromIsNoPlan`; reminder → nil.
- [ ] Step 2: `swift test --package-path apps/play-ios/PounceKit --filter "PushPayload|NotifyActions|CommunicationPlan"` fails. Step 3: implement. Step 4: pass. Step 5: commit `feat(pounce-kit): push payloads, categories, actions and communication plans`.

### Task 3: Notification settings and their store

**Files:** Create `PounceKit/Sources/PounceKit/Notify/NotifySettings.swift`, `Notify/NotifySettingsStore.swift`; test `NotifySettingsTests.swift`. Modify `Store/PushPolicy.swift` (`registersRemote(band:)`, `offersFullPrompt(status:)` over a mirrored `PushAuthorization` enum) and `PushPolicyTests.swift`.

**Interfaces (produces):**
- `struct ClockTime: Codable, Hashable, Sendable { h; m; minutes; init(minutes:) }` (wraps 0..<1440)
- `struct NotifySettings: Equatable { reminders; auto; weekday: ClockTime; weekend: ClockTime; quietStart; quietEnd; lastChance; static func defaults(band: AgeBand?) ; static func resolve(_ section: SyncSection, band:) ; static func inQuiet(_ minutes: Int, start:, end:) -> Bool; func clampedReminder(_ t: ClockTime) -> ClockTime }`; `enum NotifyKey { static let reminders = "reminders.on", ... ; static let all }`
- `@MainActor final class NotifySettingsStore(file: URL?)`: `entries: SyncSection` (chosen values only), `unsent: Set<String>`; `settings(band:) -> NotifySettings`; `set(_ key: String, _ value: JSONValue, now: Int64)`; `takeRemote(_ section: SyncSection)` (newer `at` wins); `values -> [String: JSONValue]`; `pendingPatch() -> StatePatch?`; `sent(_ patch: StatePatch)` (clears keys whose entry is unchanged).
- `KittenReminder.id = "kitten-daily"`, `KittenReminder.time = ClockTime(h: 17, m: 0)`.

- [ ] Step 1: tests: adult/teen/kitten defaults (values from Global Constraints); synced values override, malformed (`{h:25}`) fall back; kitten resolves reminders/auto/lastChance false even when set; `inQuiet` 22–08 at 23:00 and 07:59 true, 08:00 false; `testDegenerateQuietNeverClamps`; clamp 21:30 with quiet 22:00 → 20:00, 06:00 with quiet end 08:00 → 08:00; `testClampWrapsMidnight` (quiet 23:00–01:00, 00:30 → 21:00); store: set writes an entry and marks unsent, `pendingPatch` has only notification keys, `sent` clears; `testUnsentSurvivesFailure` (two sets, no `sent`, reload from file → latest value pending); `takeRemote` takes newer and ignores older; `testKittenSendsNothing` is in the app wiring task (store's `pendingPatch(band: .kitten) == nil`); PushPolicy `testKittenNeverRegisters`, unknown band never registers, teen/adult do; `offersFullPrompt` true for provisional and denied, false for authorized.
- [ ] Steps 2–4: fail, implement, pass. Step 5: commit `feat(pounce-kit): notification settings, band defaults and their synced store`.

### Task 4: Pounce wire, service, store, sheet rules and the `/p/` link

**Files:** Create `PounceKit/Sources/PounceKit/Pounce/PounceWire.swift` (`PounceState`, `LinkPounce`, `PounceSent`), `Pounce/PounceService.swift` (protocol + `APIClient`), `Pounce/PounceStore.swift`, `Pounce/PounceSheet.swift` (tiles, preselection, bell state), `Demo/DemoPounces.swift`; modify `Streaks/StreakWire.swift` (`StreakView.pounce`), `Protocol/DeepLink.swift` (`.pounce(token:)`), `Demo/DemoStreaks.swift` (pounce states); tests `PounceWireTests.swift`, `PounceAPITests.swift`, `PounceStoreTests.swift`, `PounceSheetTests.swift`, `DeepLinkTests` additions in `ProtocolTests.swift` or a new `PounceLinkTests.swift`.

**Interfaces (produces):**
- `struct PounceState: Codable, Equatable { sent; resting; quiet; answer: PounceAnswer?; code: String?; waiting: Waiting?{id; target}; static let none }`; `StreakView.pounce: PounceState` (default `.none`).
- `protocol PounceService: Sendable { send(to: String?, target: PounceTarget, person: String?) async throws -> PounceSent{id; link: URL?}; answer(id:, answer:, choice: String?, link: String?, person:) async throws -> String?; linkPounce(token:) async throws -> LinkPounce{id; from: PushFace; target} }`
- `struct PendingAnswer: Codable, Equatable { id; answer; choice; link; person }`
- `@MainActor @Observable final class PounceStore(service:, file: URL?)`: `sending: Bool`; `answering: Set<String>`; `send(pair:target:person:) async -> SendResult (.sent, .resting, .failed)`; `share(target:person:) async -> URL?`; `answer(_ a: PendingAnswer) async -> AnswerResult (.done(code: String?), .queued, .failed)`; `retryPending() async`; `pending: [PendingAnswer]`; `link(token:) async -> LinkPounce?`
- `enum PounceTile: Hashable { table(code, name, theirMove: Bool), new, pick }`; `PounceSheet.tiles(view: StreakView?, names: [String: String]) -> [PounceTile]`; `PounceSheet.preselect(_ tiles:, preferNew: Bool) -> PounceTile`; `PounceSheet.target(_ tile:) -> PounceTarget`; `PounceSheet.shareTarget(_ tile:) -> PounceTarget`; `enum BellState { ready, sent, quiet, resting, answered(PounceAnswer) }`, `BellState.make(_ p: PounceState) -> BellState`.
- `DeepLink.pounce(token: String)`; `DeepLink.pounceURL(token:)`.

- [ ] Step 1: tests: the PR 3 stub `{sent:false, resting:false}` and the full view decode; a missing `pounce` is `.none`; `waiting.target` table/new/pick; API: send with `to` → `POST /v1/pounces?person=…` body `{"to":…,"target":{"table":"GH2VD"}}`, without `to` body has no `to` and returns `link`; answer body `{answer, choice?, link?}` and `{code}` reply; 429 → `.resting`; link GET path; store: `testFailedAnswerRetriesOnce` (transport error → queued on disk; a new store on the same file retries once and empties), a 404/410 drops it, `testPlayIsNeverDowngraded` (pending play then later → still play), a double answer while in flight sends once; sheet: their-move tables first, then my-move, then new, then pick; preselect their-move table, else new; `preferNew` picks new; share target for a table tile is `.pick`; bell states; deep link parses `https://play.conleychaos.com/p/<22>` and `pounce-dev://p/<22>` (dev only), rejects 21/23 chars and other hosts.
- [ ] Steps 2–4. Step 5: commit `feat(pounce-kit): pounce wire, routes, store, sheet rules and the /p link`.

### Task 5: Placeholder art

**Files:** Modify `Art/manifest.json` (batch `habit`), `Art/tools/habit-placeholders.sh`, `Pounce/Design/ArtName.swift` (`ArtName.Habit`), the asset catalog.

New names (all `_ph`): `pounce-bell-asleep` (240), `pounce-new-game` (plus on a rug, 160), `pounce-pick` (dice on a rug, 160), `icon-clock`, `icon-moon`, `icon-sun`, `icon-auto`, `icon-weekday`, `icon-weekend`, `icon-last-chance` (28 pt each).

- [ ] Step 1: `scripts/check-assets.sh` fails listing them. Step 2: render. Step 3: `check-assets.sh` OK. Step 4: commit `feat(play-ios): placeholder art for pounce and notification settings`.

### Task 6: App: push plumbing — categories, provisional, kitten gating, actions, snooze, retry

**Files:** Modify `Pounce/App/PushCoordinator.swift`, `AppDelegate.swift`, `AppModel.swift` (`pounces: PounceStore`, `notify: NotifySettingsStore`, `handle(.pounce)`, `answerPounce`, `openPick`, guest settings upload, kitten daily reminder), `AccountModel.swift` (guest path), `Pounce/Shell/HomeView.swift` (bell while provisional), `Pounce/Info.plist` (`NSUserActivityTypes: INSendMessageIntent`), `Pounce/Pounce.entitlements` (`com.apple.developer.usernotifications.communication`).

- [ ] Step 1: tests are Tasks 2–4's; this task wires them. UI test `PushTests` stays green. Step 2: implement: `setNotificationCategories` at launch; register only when `PushPolicy.registersRemote`; priming "not now" requests `.provisional`; `didReceive` maps `NotifyActions.outcome` (background answers inside `UIApplication.beginBackgroundTask`); `willPresent` keeps today's rule plus refreshing streaks for pounce kinds; snooze; pending answers retried at launch and foreground. Step 3: Debug build passes. Step 4: commit `feat(play-ios): notification categories, actions, provisional and the pounce answer queue`.

### Task 7: App: settings panel, Pounce sheet, answer card, link sheet

**Files:** Create `Pounce/Shell/NotifyPanel.swift` (`NotifyPanel`, `ClockDial`), `Pounce/Shell/PounceSheet.swift` (`PounceSheetView`, `PouncePickView`, `WaitingPounceCard`), `PounceUITests/NotifyTests.swift`, `PounceUITests/PounceTests.swift`. Modify `UsView.swift` (bell and gear in the top bar, waiting card, Play pill → sheet), `GearSheet.swift` (embeds `NotifyPanel`), `HomeView.swift` (ringing bell on the badge for a waiting pounce), `RootView.swift` (link sheet overlay), `AppModel.swift` (`-demo-streaks` uses `DemoPounceService`; `-show-notify`, `-show-pounce`, `-show-link <token>`).

Accessibility ids: `us.bell` (value `ready|sent|quiet|resting|play|later|no`), `us.gear`, `sheet-notify`, `notify.reminders` (value on/off), `notify.auto` (on/off), `notify.weekday`, `notify.weekend`, `notify.quietStart`, `notify.quietEnd` (values `HH:MM`), `notify.lastChance`, `notify.kitten` (on/off), `sheet-pounce`, `pounce.tile.<i>` (value `table:<code>|new|pick`, selected trait), `pounce.send`, `pounce.share`, `pounce.close`, `us.waiting` (value target), `waiting.play`, `waiting.later`, `waiting.no`, `sheet-pick`, `pick.tile.<i>`, `pick.later`, `pick.no`, `home.pounce`.

- [ ] Step 1: UI tests (`-uitest-reset -seed-people -demo-streaks -show-us`): `NotifyTests.testAdultDefaults` (reminders on, auto on, quiet 22:00/08:00), `testAutoOffShowsDials` (tap auto → weekday/weekend dials at 19:30; increment → 19:45), `testTeenDefaults` (`-age-band teen`: reminders off, quiet 21:00), `testKittenPanel` (`-age-band kitten`: only `notify.kitten`, off), `testGearHasPanel`; `PounceTests.testSheetTargets` (bell → Mia's sheet: tile 0 `table:…`? Mia has their-move table → selected; tiles include `new` and `pick`), `testSendShowsSent` (send → `us.bell` value `sent`), `testRestingBellIsDisabled` (Nova), `testWaitingAnswerLater` (Kiki's card → later → card shows the clock, then gone), `testPlayPillPreselectsNew`, `testKittenHasNoShare` (`-age-band kitten`), `testLinkOpensPick` (`-show-link <token>` → `sheet-pick` with the sender's cat).
- [ ] Step 2: build-for-testing; fail. Step 3: implement. Step 4: run `NotifyTests`, `PounceTests`, `UsTests`, `SmokeTests`, `AccountTests` on the private iPhone simulator; pass. Step 5: commit `feat(play-ios): the notification settings panel, the Pounce sheet and answering pounces`.

### Task 8: The `PounceNotify` extension

**Files:** Create `PounceNotify/NotificationService.swift`, `PounceNotify/Info.plist`; modify `project.yml` (target `PounceNotify`, `app-extension`, bundle `com.conleychaos.play.notify`, depends on PounceKit, embedded in Pounce; scheme builds it), `scripts/push-sample.apns` or a new `scripts/push-pounce.apns` sample.

- [ ] Step 1: `CommunicationPlanTests` (Task 2) are its logic tests. Step 2: implement: decode with `PushPayload`, `CommunicationPlan.make`, `INPerson(personHandle: .init(value: "cat:\(name)", type: .unknown), nameComponents: nil, displayName: name, image: avatar, ...)`, `INSendMessageIntent(recipients: nil, outgoingMessageType: .outgoingMessageText, content: body, speakableGroupName: group, conversationIdentifier: conversation, serviceName: nil, sender: person, attachments: nil)`, donate, `content.updating(from:)`; any failure delivers the original. Avatar: `catN-idle` from the containing app's bundle on a coloured circle. Step 3: Debug simulator build and Release generic build (`CODE_SIGNING_ALLOWED=NO`) pass; `simctl push` of the pounce sample shows the avatar. Step 4: commit `feat(play-ios): PounceNotify, communication notifications with the cat avatar`.

### Task 9: Screenshots, docs, review, verification

- [ ] Own simulators "Pounce notify iPhone 17 Pro" and "Pounce notify iPad Pro 13": `notify`, `pounce`, `waiting`, and `push` (expanded, with avatar) → `Art/screenshots/notify/<screen>-<iphone|ipad>-<portrait|landscape>.jpg`, landscape stored upright (EXIF upper-left).
- [ ] README flags; MANUAL-CHECKLIST: pounce phone to phone, through Messages, the actions on the lock screen, provisional "not now".
- [ ] Whole-branch review; fix Critical/Important test-first.
- [ ] Full verification: `swift test --package-path apps/play-ios/PounceKit` (also under Xcode 26.2's toolchain for the CI floor), `pnpm --filter @pounce/play-api test` + typecheck + lint, Debug simulator and Release generic builds, `scripts/check-assets.sh`, the touched UI tests plus SmokeTests/UsTests/AccountTests.
