# App accounts, sync and age (daily habit PR 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The iOS app gets players and person keys, Sign in with Apple (upgrade, merge, household, sign out, delete), sync of settings, people, archive and tutorial, cross-device badge clearing, the age screen with the under-13 limits, and the privacy paperwork, all on top of the server PR 1 shipped.

**Architecture:** Pure logic (wire types, last-writer-wins merge, age mapping, keypad, profile building, push payload rules) lives in PounceKit with Swift Testing tests. The app adds an `AccountModel` (main actor, observable) that owns the account flows and talks to an `AccountService` protocol: `APIClient` in real runs, an in-memory stub under the Debug launch flag `-stub-accounts <scenario>`, which also swaps the Apple sign-in provider for a stub. Age checking sits in front of pick-a-cat as a new route. The server gains `profile` in `GET /v1/me/state` and a `/privacy` page.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, AuthenticationServices, DeclaredAgeRange, PermissionKit, UserNotifications, Swift Testing, XCUITest; TypeScript Workers + vitest + Miniflare.

**Spec:** `docs/superpowers/specs/2026-11-04-daily-habit-design.md` (§10.5, §12.5, §12.6, §13.1, §13.4, §14, §14.1, §15 row 2, §16).

## Global Constraints

- iOS 26.0 deployment target, Swift 6 strict concurrency, Apple frameworks only, XcodeGen `project.yml`.
- No emoji anywhere. On screen only names, table names and numerals; everything else is art or icons. Apple's Sign in with Apple button text is the one exception. Push copy and Apple's own system dialogs may hold sentences.
- Loud, saturated Loud Toy art (Palette violet, magenta, teal, orange, sky, lime, ink); never beige or muted. New art may be SwiftUI-drawn placeholders built from existing art.
- Sign in with Apple: no scopes; a fresh raw nonce per request (32 random bytes, base64url); Apple gets `SHA-256(raw)` as lowercase hex; the server gets the raw nonce.
- Person key: 32 random bytes, base64url (43 chars, `^[A-Za-z0-9_-]{43}$`), Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synchronizable.
- Profile body: `{timeZone, ageBand?, people: [{id, name, cat, key, ageBand?, at}]}`, at most 8 people, 2 KB. Owner band at profile level, each household person's band per person, `at` always sent.
- State patch: sections `settings`, `tutorial`, `archive`, each `{key: {v, at}}`, at most 64 keys per section, values at most 256 bytes JSON, body at most 8 KB; keys `^[A-Za-z][A-Za-z0-9_.]{0,31}$` (archive keys are room codes).
- Age bands `kitten` (<13), `teen` (13–17), `adult` (18+). Declared Age Range gates 13 and 18. Never store a birth year.
- Kitten: names only from `NameGenerator` dice, no sign-in offer anywhere on a kitten-owned device and never for a kitten household person, no APNs token upload, local turn reminder off by default.
- Debug-only stubs (`#if DEBUG`); Release must not contain them.
- Never touch the :4343 server, the shared :8787 dev server's process, the physical iPhone, or other sessions' simulators.

## Review Focus

1. The user cancels the Apple sheet (ASAuthorizationError.canceled): nothing changes, no shake, no error state. Test: `AccountModelTests` stub scenario `cancel` in the UI test `testCancelledSignInChangesNothing`.
2. Offline at launch: profile upload fails, the app plays on and uploads again on the next foreground. Test: `ProfileUploaderTests.testFailureLeavesUploadPending` (PounceKit).
3. A `rejected` person id: a new id and key are minted once, tips move to the new id, and a second rejection in the same pass does not loop. Test: `ProfileUploaderTests.testRejectedMintsNewIdOnce`.
4. Last-writer-wins ties and clock skew: equal `at` keeps the local value and pushes nothing; a remote write never undoes a newer local one. Test: `SyncMergeTests.testTieKeepsLocal`, `testNewerLocalIsPushedNotOverwritten`.
5. Age keypad edge years: future, more than 120 years back, fewer than four digits and leading zeros all shake with no hint, and quitting before the check leaves no record (the keypad comes back). Test: `BirthYearEntryTests`, UI `AgeGateTests.testKeypadCannotBeRetried`.

---

### Task 1: Server: profile in `/v1/me/state`, `/privacy`, paperwork

**Files:**
- Modify: `apps/play-api/src/players/player.ts` (`MeState`, `getState`)
- Create: `apps/play-api/src/http/privacy.ts`, `apps/play-api/src/http/privacy.test.ts`
- Modify: `apps/play-api/src/index.ts` (route `GET /privacy`)
- Modify: `apps/play-api/tests/accounts.test.ts` (state carries profile)
- Create: `docs/privacy/retention-policy.md`, `docs/privacy/security-program.md`

**Interfaces:**
- Produces: `MeState.profile: {name: string; cat: number; at: number} | null` (`at` = stored `name_at`). `privacyPage(): Response` (HTML, `text/html; charset=utf-8`, `public, max-age=300`, the share page's CSP).

- [ ] Step 1: tests. `privacy.test.ts`: `privacyPage` is 200 HTML with the CSP, no `<script`, contains "Privacy", "Children", "Conley Chaos", "Sign in with Apple", "kitten" absent (no app jargon), a section id `coppa` and the contact address `privacy@conleychaos.com`; `accounts.test.ts`: after a profile upload with `at: 1234`, `GET /v1/me/state?person=<id>` has `profile: {name, cat, at: 1234}`.
- [ ] Step 2: run `pnpm --filter @pounce/play-api test` and see them fail.
- [ ] Step 3: implement; `getState` adds `profile` from meta (`null` when the player does not exist). The page follows §14 and §14.1: what is collected, why, who sees it, retention (120 days, 90 days, 30 days, 24 hours, 7 days), deletion in the app, the COPPA direct notice (operator, what is collected from a child under 13 without consent: a persistent identifier, a generated name, game state; no push; parent rights to review and delete; contact).
- [ ] Step 4: paperwork drafts: retention policy (§ 312.10: each data class, purpose, period, deletion method) and security program (§ 312.8: coordinator JD Conley, risk assessment, safeguards, vendors Cloudflare and Apple, annual review each November, incident steps).
- [ ] Step 5: tests pass; commit.

### Task 2: PounceKit sync model and last-writer-wins merge

**Files:**
- Create: `PounceKit/Sources/PounceKit/Account/SyncModel.swift`, `Tests/PounceKitTests/SyncMergeTests.swift`

**Interfaces:**
- Produces: `enum JSONValue: Codable, Equatable, Sendable { case string, number(Double), bool, null, array, object }`; `struct SyncEntry: Codable, Equatable, Sendable { var v: JSONValue; var at: Int64 }`; `typealias SyncSection = [String: SyncEntry]`; `enum SyncSectionName: String, CaseIterable { case settings, tutorial, archive }`; `struct StatePatch: Codable, Equatable { var settings, tutorial, archive: SyncSection? }`; `struct HouseholdPerson: Codable { personId, playerId, name, cat }`; `struct RemoteProfile: Codable { name, cat, at: Int64 }`; `struct MeState: Codable { settings, tutorial, archive: SyncSection; people: [HouseholdPerson]; profile: RemoteProfile? }`; `enum SyncMerge { static func reconcile(local: SyncSection, remote: SyncSection) -> (push: SyncSection, apply: SyncSection); static func chunks(_ patch: StatePatch, maxKeys: Int = 64, maxBytes: Int = 7_500) -> [StatePatch] }`.

- [ ] Step 1: tests: `testNewerRemoteIsApplied`, `testNewerLocalIsPushedNotOverwritten`, `testTieKeepsLocal` (neither side), `testLocalOnlyKeyIsPushed`, `testRemoteOnlyKeyIsApplied`, `testChunksSplitAt64Keys` (130 archive keys → 3 patches, every key once), `testChunksStayUnderBytes`, `testDecodesServerState` (the JSON shape from `tests/accounts.test.ts`, with `profile` present and absent).
- [ ] Step 2: run `swift test --package-path PounceKit --filter SyncMergeTests`; fail.
- [ ] Step 3: implement. Step 4: pass. Step 5: commit.

### Task 3: APIClient account endpoints

**Files:**
- Modify: `PounceKit/Sources/PounceKit/Net/APIClient.swift`
- Create: `PounceKit/Sources/PounceKit/Account/AccountWire.swift`; Test: `Tests/PounceKitTests/AccountAPITests.swift`

**Interfaces:**
- Consumes: Task 2 types.
- Produces: `APIError` gains `.forbidden` (403) and `.conflict(String)` (409, the body's `error`). Wire types: `struct ProfileBody: Encodable { timeZone; ageBand: AgeBand?; people: [ProfilePerson] }`, `struct ProfilePerson: Encodable { id, name, cat, key, ageBand: AgeBand?, at: Int64 }`, `struct ProfileReply: Decodable { players: [String: String]; rejected: [String] }`, `struct AppleProof: Encodable { identityToken, nonce, authorizationCode: String? }`, `struct SignInReply: Decodable { playerId; outcome: Outcome (upgraded, merged, same); account: Bool; profile: {name, cat} }`, `enum LinkResult: Equatable { case linked(merged: Bool), mergeNeeded(name: String, cat: Int) }`. Methods on `APIClient`: `uploadProfile(_:) -> ProfileReply`, `signIn(provider: String, proof: AppleProof, personId: String, personKey: String) -> SignInReply`, `link(provider:proof:confirmMerge:person:) -> LinkResult`, `unlink(provider:person:)`, `signOut()`, `deleteMe(person: String?)`, `state(person: String?) -> MeState`, `patchState(_:person:)`. `person` becomes `?person=<id>`. Bodies are any `Encodable`.

- [ ] Step 1: tests with `StubServer`: each method's method, path, query and body JSON; `testLinkMergeNeededReadsOtherPlayer` (409 `{"error":"merge_needed","otherPlayer":{"name":"Mia","cat":2}}`); `testForbiddenIsForbidden`; `testOptionalFieldsAreOmitted` (no `ageBand` key when nil).
- [ ] Step 2: fail. Step 3: implement (`authenticatedCall` takes `Data?` body and a query). Step 4: pass, plus the old `APIClientTests`. Step 5: commit.

### Task 4: Person keys, account store and the profile uploader

**Files:**
- Create: `PounceKit/Sources/PounceKit/Account/PersonKeys.swift`, `AccountStore.swift`, `ProfileUploader.swift`; Tests: `PersonKeysTests.swift`, `ProfileUploaderTests.swift`
- Modify: `PounceKit/Sources/PounceKit/Identity/PeopleStore.swift` (`replaceID(_:with:)`, `Person` stays `{id,name,cat}`), `Tutorial/TutorialStore.swift` (`moveTips(from:to:)`, `replace(_:)`)

**Interfaces:**
- Produces: `protocol PersonKeyStore: Sendable { func key(for personId: String) -> String; func remove(_ personId: String) }` (creates on first use), `MemoryPersonKeyStore`, `KeychainPersonKeyStore(service: "com.conleychaos.play.person")`; `PersonKeys.random() -> String`. `struct AccountRecord: Codable, Equatable { var accountPersonId: String?; var playerIds: [String: String]; var providers: [String]; var signedIn: Set<String> /* person ids signed in */; var bands: [String: AgeBand] /* household */; var changedAt: [String: Int64] /* name or cat */; var imported: [String] /* household person ids from the account */; var ledger: [String: SyncSection] /* last known local value per section */ }`; `final class AccountStore(directory:fileName:)` with `load()`, `save(_:)`, `static fileName(for: APIConfig)` = `account.<host>_<port>.json`. `enum ProfileUploader { static func body(people: LocalPeople, record: AccountRecord, ownerBand: AgeBand?, timeZone: String, keys: PersonKeyStore) -> ProfileBody?; static func apply(_ reply: ProfileReply, to record: inout AccountRecord) -> [String] /* rejected ids */ }`. Imported people are left out; the owner first; `at` from `changedAt` or 1 when unknown; nil when there is no owner.

- [ ] Step 1: tests: `testKeyIs43Base64URLAndStable`, `testBodyLeavesOutImported`, `testBodyCarriesBandsAndAt`, `testBodyCapsAtEightPeople`, `testRejectedMintsNewIdOnce` (drives `PeopleStore.replaceID`, `TutorialStore.moveTips`, key removal), `testFailureLeavesUploadPending` (uploader state machine `ProfileSync` keeps `pending = true` after a thrown error).
- [ ] Step 2: fail. Step 3: implement. Step 4: pass. Step 5: commit.

### Task 5: Age bands, birth-year keypad, re-check, significant change

**Files:**
- Create: `PounceKit/Sources/PounceKit/Account/Age.swift`; Test: `Tests/PounceKitTests/AgeTests.swift`

**Interfaces:**
- Produces: `enum AgeBand: String, Codable, CaseIterable, Sendable { case kitten, teen, adult }`; `AgeBand.from(lowerBound: Int?, upperBound: Int?) -> AgeBand?` (upper < 13 → kitten; lower ≥ 18 → adult; lower ≥ 13 or upper < 18 → teen; neither bound → nil); `AgeBand.from(birthYear: Int, now: Date, calendar: Calendar) -> AgeBand` (age = thisYear − year − 1, the youngest the person can be); `struct BirthYearEntry { digits: String; mutating func type(_ d: Int); mutating func delete(); func year(now:) -> Int? }` (4 digits, 1 + thisYear − 120 … thisYear, else nil); `struct AgeRecord: Codable, Equatable { var band: AgeBand; var source: Source (declared, keypad); var checkedAt: Date }` with `needsRecheck(now:) -> Bool` (7 days); `protocol AgeRecordStore`, `MemoryAgeRecordStore`, `KeychainAgeRecordStore(service: "com.conleychaos.play.age")`; `struct AgeLimits { init(band: AgeBand?) ; signInOffered; uploadsPushToken; turnReminderDefault; typedNames }` (nil band behaves as kitten until known); `AgeLimits.needsGeneratedName(_ name: String) -> Bool`; `enum SignificantChange { enum Action { none, askParent, notifyAdult } static func action(requiresConsent: Bool, requiresNotice: Bool, band: AgeBand, isNewInstall: Bool, done: Bool) -> Action }`.

- [ ] Step 1: tests: ranges (`0–12`, `13–17`, `18+`, `nil/nil`, `13/nil`), birth years at the edges for 2026-11-04 (2014 → kitten, 2013 → kitten, 2012 → teen, 2008 → teen, 2007 → adult), keypad (`testFutureYearIsNil`, `testTooOldIsNil`, `testThreeDigitsIsNil`, `testFifthDigitIgnored`, `testDeleteOnEmpty`), `testRecheckAfterAWeek`, limits per band, significant change table.
- [ ] Step 2: fail. Step 3: implement. Step 4: pass. Step 5: commit.

### Task 6: Push rules: dismiss, badge, token gate

**Files:**
- Modify: `PounceKit/Sources/PounceKit/Store/PushPolicy.swift`; Test: `Tests/PounceKitTests/PushPolicyTests.swift`

**Interfaces:**
- Produces: `PushPolicy.dismissCode(fromPayload: [AnyHashable: Any]) -> String?` (`kind == "dismiss"` and a valid room code); `PushPolicy.badgeCount(_ tables: [TableEntry]) -> Int` (your turn and not over); `PushPolicy.matches(code:userInfo:threadId:) -> Bool`.

- [ ] Steps: tests (`testDismissPayloadFromServerShape` with `{aps:{content-available:1},kind:"dismiss",code:"GH2VD"}`, non-dismiss → nil, bad code → nil, badge counts), fail, implement, pass, commit.

### Task 7: Capabilities, the age screen and kitten limits in the app

**Files:**
- Modify: `Pounce/Pounce.entitlements` (`com.apple.developer.applesignin` = `[Default]`, `com.apple.developer.declared-age-range` = true), `Pounce/Info.plist` (`UIBackgroundModes` = `[remote-notification]`), `Pounce/Resources/PrivacyInfo.xcprivacy` (Product Interaction, Other Usage Data; App Functionality, linked, no tracking)
- Create: `Pounce/App/AgeGate.swift` (`AgeRangeAsking` protocol, `LiveAgeRange` on `AgeRangeService.shared.requestAgeRange(ageGates: 13, 18, in:)`, Debug `StubAgeRange` from `-age-range <kitten|teen|adult|declined|unavailable>`), `Pounce/Shell/AgeGateView.swift` (birth-year keypad, the `KeyStyle` keys, four tiles, no default, no hint), `PounceUITests/AgeGateTests.swift`
- Modify: `Pounce/App/Route.swift` (`.age(then: DeepLink?)`), `RootView.swift`, `AppModel.swift` (band, limits, kitten rename, weekly re-check, `turnReminder`), `Pounce/Design/Settings.swift` (`turnReminderOn`), `Pounce/Shell/PickCatView.swift` (`diceOnly`), `PushCoordinator.swift` (no token upload or remote registration while `!limits.uploadsPushToken`)

**Interfaces:**
- Produces: `AppModel.ageBand: AgeBand?`, `AppModel.limits: AgeLimits`, `AppModel.finishAge(_ band: AgeBand, source:)`. Under `-uitest-reset` without `-age-range` the band is preset `adult` (existing tests keep their flow); under any `-anim-speed` without `-age-range` the stub answers `adult`.
- Accessibility ids: `screen-age`, `age.key.<0-9>`, `age.key.delete`, `age.confirm`, `age.tile.<i>`.

- [ ] Step 1: UI tests `AgeGateTests`: `testDeclinedShowsKeypadThenPickCat` (`-age-range declined`, types 1990, check → pick-a-cat with the name field), `testKittenGetsDiceOnly` (2016 → pick-a-cat has `pickcat.dice` and no `pickcat.name` text field), `testKeypadCannotBeRetried` (finish keypad, terminate, relaunch without reset of the Keychain stub: the band persists; uses `-age-store file` Debug store in the data dir), `testSharedRangeSkipsKeypad` (`-age-range teen` → pick-a-cat directly), `testBadYearShakes` (2030 stays on `screen-age`).
- [ ] Step 2: build-for-testing; tests fail. Step 3: implement. Step 4: run `scripts/ui-tests.sh -only-testing:PounceUITests/AgeGateTests` on the private simulator and port; pass. Step 5: commit.

### Task 8: AccountModel: profile upload and sync

**Files:**
- Create: `Pounce/App/AccountModel.swift`, `Pounce/App/AccountService.swift` (protocol + `APIClient` conformance + Debug `StubAccountService`)
- Modify: `AppModel.swift` (owns `account`; people edits mark `changedAt` and schedule an upload; archive/restore and tips write the ledger), `PounceApp.swift` (time-zone change: `NSNotification.Name.NSSystemTimeZoneDidChange`)

**Interfaces:**
- Consumes: Tasks 2–5.
- Produces: `protocol AccountService: Sendable` mirroring the `APIClient` methods of Task 3; `@MainActor @Observable final class AccountModel { record; isSignedIn; accountPerson: Person?; func uploadProfile() async; func sync() async; func signIn(person: Person) async -> SignInOutcome; func confirmMerge() async; func signOut() async; func deleteAccount() async -> Bool }`. Sync runs after sign-in, on launch and on foreground when signed in: reconcile each section against the ledger, apply remote values to `Settings` (`soundOn`, `hapticsOn`, `turnReminderOn`), `TableArchive` (v = updatedAt or null = restored) and `TutorialStore` (account person's tips, v = true/false), push the rest in chunks, import household people (`imported`) and apply `profile` when newer.

- [ ] Steps: PounceKit tests for the pieces already exist (Tasks 2, 4); here the check is the app build plus Task 10's UI tests. Commit.

### Task 9: Sign in with Apple, link and merge, sign out, delete

**Files:**
- Create: `Pounce/App/AppleSignIn.swift` (`AppleSigning` protocol; `LiveAppleSignIn` with `ASAuthorizationController`, no scopes, nonce; Debug `StubAppleSignIn` for `-stub-accounts`), `PounceKit/Sources/PounceKit/Account/Nonce.swift` (`Nonce.raw() -> String`, `Nonce.sha256Hex(_:) -> String`) + `NonceTests.swift`
- Modify: `AccountModel.swift`

**Interfaces:**
- Produces: `enum SignInOutcome { case upgraded, merged(name: String, cat: Int), mergeNeeded(name: String, cat: Int), cancelled, refused, failed }`. Stub scenarios (`-stub-accounts <upgraded|merged|merge-needed|cancel|signed-in>`).
- [ ] Steps: `NonceTests` (`testRawIs43Chars`, `testSha256HexKnownVector` for "abc" → `ba7816bf…`), fail, implement, pass, commit.

### Task 10: Account UI: people sheet, gear sheet, merge, delete, household age

**Files:**
- Create: `Pounce/Shell/AccountViews.swift` (`SignInOffer`, `AccountCard`, `ProviderIcons`, `MergeView`, `DeleteConfirmView`, `SettingsPathView`, `AgeBandPicker`), `Pounce/Shell/GearSheet.swift` (sound, haptics, reminder, how to play, privacy, account), `PounceUITests/AccountTests.swift`
- Modify: `Pounce/Shell/PeopleSheet.swift` (offer under the grid, long-press a household cat to sign them in, band picker before adding), `HomeView.swift` (gear opens `GearSheet` as a sheet)

**Interfaces:**
- Accessibility ids: `people.signin`, `gear.signin`, `gear.account`, `gear.provider.apple`, `gear.signout`, `gear.delete`, `delete.confirm`, `delete.back`, `settings.path`, `merge.confirm`, `merge.back`, `screen-merge`, `age.band.kitten|teen|adult`, `gear.privacy`, `settings.reminder`.
- [ ] Step 1: UI tests: `testSignInFromPeopleSheetUpgrades`, `testMergedShowsTwoCatsThenAccount`, `testMergeNeededAsksFirst` (back keeps the guest; check merges), `testCancelledSignInChangesNothing`, `testSignOutReturnsToGuest`, `testDeleteConfirmsThenShowsSettingsPath`, `testKittenSeesNoSignIn` (`-age-band kitten`), `testHouseholdKittenPicksDiceName` (band picker kitten → dice-only editor).
- [ ] Step 2: fail. Step 3: implement. Step 4: pass. Step 5: commit.

### Task 11: Across devices and the significant change

**Files:**
- Modify: `Pounce/App/AppDelegate.swift` (`didReceiveRemoteNotification:fetchCompletionHandler:` → dismiss), `PushCoordinator.swift` (`dismiss(code:)` removes delivered notifications whose thread or `code` matches, then refreshes; `refreshBadge(tables:)` via `UNUserNotificationCenter.setBadgeCount`), `AppModel.refreshTables` (sets the badge)
- Create: `Pounce/App/SignificantChangeGate.swift` (iOS 26.4+: `AgeRangeService.shared.requiredRegulatoryFeatures`; minor with `.significantAppChangeRequiresParentalConsent` → `AskCenter.shared.ask(PermissionQuestion(significantAppUpdateTopic:))`, accounts features held until `.approval` arrives on `AskCenter.shared.responses(for:)`; adult with `.significantAppChangeRequiresAdultNotification` → `showSignificantUpdateAcknowledgment` once)
- Modify: `scripts/push.sh` gains `dismiss` (a `simctl push` of the dismiss payload); `PounceUITests/PushTests.swift` gains `testDismissPushClearsTable` only if `simctl push` delivers background pushes on the simulator (otherwise documented in MANUAL-CHECKLIST).
- [ ] Steps: build; run PushTests touched; commit.

### Task 12: Screenshots, docs, full verification

**Files:**
- Create: `Art/screenshots/accounts/*.jpg` (people-signin, gear-signedin, merge, age-keypad, household-age; iphone portrait, ipad portrait and landscape)
- Modify: `apps/play-ios/README.md` (flags, JD prerequisites), `MANUAL-CHECKLIST.md` (account deletion, two devices)
- [ ] Steps: create own simulators; capture via `IPadScreenshotTests` with `POUNCE_SHOTS`; convert to JPEG; run `swift test --package-path PounceKit`, the app build, the touched UI tests, `pnpm --filter @pounce/play-api test`; commit.
