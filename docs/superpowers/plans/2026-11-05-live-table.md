# Live table (daily habit PR 7) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** §15 row 7, the Live Activity of §11.3. When you leave a table that's live (game playing and another person awake there, or you just answered a pounce with Play), the server starts a "live table" on your Lock Screen and Dynamic Island with push-to-start. It updates on every turn change, louder when the move comes to you. It ends when the round or game ends, when you come back to that table, after 30 minutes with no move, or 2 hours after it started. It shows the rug strip with every seat's cat, a glowing ring on whoever's move it is, a bell when it's yours, each phase numeral, the table name and the pair's paws. A synced toggle in the settings panel turns it off; it's on by default. A kitten's device never gets one, and a teen's gets nothing between 00:00 and 06:00.

**Architecture:**
- **Server, pure:** `src/live/live.ts` (100% coverage) holds the rules: the content state from a room, the start condition, deadlines (30 minutes idle, 2 hours cap, `stale-date`), and the three APNs bodies (start, update, end).
- **Server, room:** `RoomCore` keeps one `live` record per device (persisted in `RoomState`) and queues `LiveIntent`s (start, update, end) that `GameRoom` drains after every change, like push intents. `GameRoom` fills in the streak paws and checks the player's toggle, then hands each intent to the device's `DeviceIndex`.
- **Server, device:** `DeviceIndex` owns the tokens: the push-to-start token and the one live activity's update token (at most one live table per device). It sends through `pushLive` in `src/push/apns.ts`, refuses everything for a kitten and during a teen's night, and refuses "your move" for a table whose live table it can update.
- **Shared fixture:** `fixtures/push/live-activity.json` holds sample start, update and end bodies. Swift decodes their `content-state` and `attributes` into the app's `ActivityAttributes`, so the two can't drift.
- **App, pure (PounceKit, Swift Testing):** `LiveTable/` holds `LiveTableAttributes` and `LiveTableState`, the drawing rules (`LiveTableLook`), the token rule (`LiveTableToken`), which activities to end (`LiveTableSweep`), and `APIClient.setLiveActivity`.
- **App, extension:** `PounceWidgets` gains `LiveTableWidget` (an `ActivityConfiguration`) in `PounceWidgetsBundle`, drawn with `WidgetArt` / `ArtImage`; a tap opens `WidgetLink.table`.
- **App:** `LiveTableBridge` uploads `pushToStartTokenUpdates` and each activity's `pushTokenUpdates` (never from a kitten's device), keeps one activity, ends the table's activity when you open it, and sweeps stale ones. `NotifyPanel` gains the toggle.

**Tech Stack:** TypeScript, Cloudflare Workers with SQLite Durable Objects, vitest with v8 coverage, Miniflare; Swift 6 (it must build on CI's Xcode 26.6), SwiftUI, ActivityKit, WidgetKit, Swift Testing, XcodeGen, ImageMagick.

**Spec:** `docs/superpowers/specs/2026-11-04-daily-habit-design.md`: §4.4, §11.3, §12.1 ("no live table is running for it"), §12.5, §12.6, §12.7, §13.2 (`DeviceIndex` tokens, `GameRoom` Live Activity pushes), §13.4 (`PUT /v1/devices/me/live-activity`), §14.1 (kitten: no push-to-start or push updates; teen: nothing 00:00–06:00), §15 row 7, §16.

**Base:** PR 6, `docs/superpowers/plans/2026-11-05-widgets.md`; PR 5, `2026-11-04-notify-server.md` and `2026-11-04-notify-app.md`.

## Global Constraints

- **Gated by a new `LIVE` flag** (`liveOn(env)`), which also needs `NOTIFY` (so `STREAKS` too).
  - With it off, behavior is exactly PR 6's: no route (404), no live state in rooms, no suppression. This is tested.
  - This PR turns it on in `wrangler.jsonc`: the app half ships in the same PR, and nothing is sent until a device uploads a push-to-start token, which only this PR's app does. The flag is a kill switch that needs no app build.
- **Kitten (§14.1):** the app never uploads either token (an unknown band counts as kitten). The server stores no live token from a kitten's device and sends it nothing.
- **Teen:** no live push between 00:00 and 06:00 local, not even the end. `DeviceIndex.silenced` already covers this.
- **On screen:** no emoji. Only names, table names and numerals; everything else is art or icons. No countdowns: no timer text, and no `Text(timerInterval:)`. No guilt copy. No buttons on the live table.
- **Art:** loud Toy palette. The one new picture, `icon-live-table`, goes in as a `_ph` placeholder through `Art/tools/habit-placeholders.sh`, batch `habit`. Everything else reuses existing art: `rug`, `ring-glow`, `icon-bell`, the cat sprites, `paw-badge-*` and `widget-bg`.
- **Swift:** builds on Xcode 26.6. No Swift 6.4-only features, no local constant shadowing a method it calls in its own initializer, no `Test.cancel`.
- **Tests:** every Miniflare `describe` gets `{ timeout: 30_000 }`. `src/live/**` and `src/room/core.ts` stay at 100% coverage.
- **Logs:** no ids, tokens or names.
- **Environment:** my own simulators ("Pounce live iPhone 17 Pro", "Pounce live iPad Pro 13") and a private dev server port. Never :4343, :8787 or the physical iPhone.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Decisions where the spec is silent

1. **The `LIVE` flag:** see Global Constraints.
2. **When it starts:** a device's presence goes from awake to away, either by `presence: background` or by its socket closing, and all of these hold:
   - the room is `playing` and its game is mid-round (not `roundOver`);
   - the device controls a seat;
   - it has no live record here yet;
   - either another human seat that this device doesn't control is awake now, or one of the device's players answered Play to a pounce for this table within the last hour. The pounce mark is set by `answerPounce`, or by `initRematch` for a pounce's new game, and a start uses it up.
3. **Toggle:** the synced key `liveTable.on` (bool), read like the other notify settings.
   - Default on for adults and teens: it's the game, not an engagement nudge. Always off for a kitten.
   - The server reads it from the player in the device's first seat with a player; a seat with no player counts as on.
   - The app hides the toggle on a kitten's device.
4. **Content state** (≤ 1 KB at 6 seats):
   - `{table, seats: [{cat, phase, name?, bot, me}], turn: seat | null, mine, streak: {count, me, them} | null}`.
   - `phase` is the phase the seat is working on, 1 to 10. Bots have no `name`.
   - `me` marks the seats this device controls; `mine` is true when `turn` is one of them.
   - Attributes: `{code}`, type `LiveTableAttributes`. There are no dates in the state, so no date-decoding strategy is needed.
5. **Paws:** the device player's pair at this table, picked like "your move" picks one (`yourMoveContext`), from the room's latest views.
   - When the room has none yet (after an eviction), a start reads `myStreaks` and keeps the views listing this table.
   - With no pair, no paws are drawn.
6. **Updates:** one on each turn change (the turn key changes), to every live device.
   - Priority 5.
   - Priority 10 with an alert (sound `default`, title the name of the person whose move it is, body the "your move" copy) when the new turn's seat is one the device controls.
   - Each update moves the 30-minute idle clock.
7. **Start push:**
   - Priority 10 and `input-push-token: 1`, so the activity gets an update token.
   - It carries a silent alert (no sound), since APNs needs an alert to push-start: title the table name, body `Your move.` or `<Name>'s move.`
8. **Ends** (`event: end`, `dismissal-date` = now, the last content state):
   - the round or game ends, or the room closes;
   - that device comes back to the table (connects, sends `presence: active`, or acts);
   - 30 minutes pass with no turn change;
   - 2 hours pass since the start.
   - `stale-date` is now + 30 minutes on the start and on every update.
9. **One per device:** `DeviceIndex` keeps `live_code`, `live_token` and `live_state`. A start for another table first ends the older one with its last state, then switches. An update or end for any other code is ignored.
10. **"Your move" is suppressed only while the device can update its live table** (it holds an update token for that code), on both the rich and the legacy push paths. Before the token arrives, the regular push goes out: the spec's fallback until PR 8 verifies the upload timing.
11. **When a live table times out on your move,** the room sends that one device the regular "your move", `passive`. The activity is about to disappear, and the earlier "your move" was suppressed, so the push leaves a quiet trace in Notification Center instead of a second sound.
12. **The token route** is `PUT /v1/devices/me/live-activity` with body `{pushToStart?: hex | null, activities?: [{code, token: hex | null}]}`.
    - At most 4 activities, and at least one key. It returns 204, or 400 for anything else.
    - `null` clears a token: the app sends it when an activity ends on the device.
    - It needs `LIVE`. A kitten device's call returns 204 and stores nothing.
13. **The app's sweep**, at launch and on each foreground: it ends activities past their stale date or older than 2 hours, and every one but the newest.
    - This covers a teen's night, when the server may not send the end.
14. **The app ends a table's activity when you open that table**, at once, before the socket says so. Turning the toggle off ends every activity. Tokens still go up while the toggle is off: the server reads the setting, so turning it back on on another device works.
15. **Taps:** `widgetURL(WidgetLink.table(code).url)`, the PR 6 link. No buttons.
16. **Debug demo:** `-demo-live-table mine|theirs` starts a local activity from `DemoFixtures.liveTable(mine:)` at launch, for previews and screenshots. It is Debug only.
17. **iPad:** iPadOS doesn't show Live Activities (ActivityKit reports them disabled), so iPad gets no screenshots and needs no layout. The token upload still runs; the server just never hears a token from iPad.

## Review Focus

1. **A kitten's device never uploads a live token, from either the app or the server path, and an unknown band counts as kitten.**
   - Tests: `LiveTableTokenTests.testKittenNeverUploads`, `testUnknownBandNeverUploads`; Miniflare `kitten device stores and gets nothing`.
2. **Suppression never swallows a "your move" the person can't see.**
   - Suppression applies only while an update token is held.
   - A timeout on your move restores the push (passive).
   - Tests: Miniflare `your move suppressed only with an update token`, `timeout on your move sends a passive your move`.
3. **Teen night:** nothing at all goes out between 00:00 and 06:00, and the record is still cleared on end. Test: Miniflare `teen night sends nothing`.
4. **Content-state drift between TS and Swift.** Test: `LiveTableFixtureTests` decodes every body in `fixtures/push/live-activity.json`.
5. **Ordering:** an end clears `DeviceIndex`'s live record before the fallback "your move" checks it. Live intents run on the room's chain before push intents.
6. **Deadlines:** 30-minute idle and 2-hour cap, both edges, the alarm re-armed. Tests: `core.live.test.ts`, `live.test.ts`.

---

### Task 1: The plan

- [ ] Commit this file: `docs: daily habit PR 7 (live table) plan`.

### Task 2: Server — pure rules (`src/live/live.ts`)

**Files:** Create `src/live/live.ts`, `src/live/live.test.ts`. Modify `vitest.config.ts` (`src/live/**` at 100%), `src/streaks/profile.ts` (`liveOn`), `src/notify/settings.ts` (`liveTable`, key `liveTable.on`), `src/env.ts` (`LIVE`).

**Interfaces (Produces):**
- `IDLE_MS = 30 min`, `CAP_MS = 2 h`, `STALE_MS = 30 min`, `POUNCE_LIVE_MS = 1 h`.
- `type LiveSeat = { cat: number; phase: number; name?: string; bot: boolean; me: boolean }`.
- `type LiveState = { table; seats: LiveSeat[]; turn: number | null; mine: boolean; streak: { count; me; them } | null }`.
- `type LiveRecord = { startedAt: number; movedAt: number }`.
- `deadline(r): number`; `expired(r, now): "idle" | "cap" | null`.
- `startBody(code, state, now, alert)`, `updateBody(state, now, alert | null)`, `endBody(state, now)`. Dates are in seconds.
- `liveAlert(state, toName)`.

- [ ] **Step 1: Failing tests.**
  - The deadline is the earlier of idle and cap, with both edges tested.
  - The bodies: `timestamp`, `event`, `content-state`, `stale-date` = now + 1800 s, and `dismissal-date` = now on end.
  - A start carries `attributes-type: "LiveTableAttributes"`, `attributes: {code}`, `input-push-token: 1`, and an alert with no sound.
  - An update with an alert has sound `default`; one without has no alert.
  - A 6-seat body is under 4 KB.
  - Settings: `liveTable` defaults to true for adult and teen, false for kitten, and a synced false wins.
  - `liveOn` needs `NOTIFY` and `STREAKS`.
- [ ] **Steps 2–4:** FAIL, implement, PASS.
- [ ] **Step 5:** Commit `feat(play-api): live table rules and payloads`.

### Task 3: Server — `RoomCore` live records and intents

**Files:** Modify `src/room/core.ts` (`RoomFeatures.live`, `RoomState.live`, `RoomState.livePounce`, `LiveIntent`, `drainLiveIntents`, `notePounce`, `liveDropped`, `liveContent`, `expireLive(now)`). Create `src/room/core.live.test.ts`.

**Interfaces:**
- `type LiveIntent = { kind: "start" | "update" | "end"; deviceId; code; playerId: string | null; state: LiveState; alert: { to: string; from: string | null } | null; reason?: "idle" | "cap" | "back" | "over" | "replaced"; yourMove?: YourTurnIntent }`.

- [ ] **Step 1: Failing tests** (fake clock):
  - Backgrounding with the other seat awake starts one live table; a second background doesn't start another.
  - With the other seat away nothing starts, unless the player was pounced within the hour, and a start uses the mark up.
  - Nothing starts with the feature off, in the lobby, between rounds, or for a device with no seat.
  - A disconnect after a background doesn't start twice.
  - A turn change sends an update to each live device, with `mine` and an alert only for the device whose move it now is. A draw alone sends nothing.
  - Round over and game over end every live table. A reconnect, `presence: active` or an act ends that device's.
  - The idle and cap expiries end it. On your move the end carries a passive `yourMove`.
  - `nextAlarm` includes the live deadlines. `liveDropped` forgets a record. A closing room ends them all.
  - State: phases are 1-based and capped at 10, bots have no name, `me` follows the controlled seats.
- [ ] **Steps 2–4.** **Step 5:** Commit `feat(play-api): live tables in the room core`.

### Task 4: Server — APNs, `DeviceIndex`, `GameRoom`, route, fixtures

**Files:**
- Modify `src/push/apns.ts` (`pushLive`) and `src/push/apns.test.ts`.
- Modify `src/room/device-index.ts` (`setLiveTokens`, `liveStart`, `liveUpdate`, `liveEnd`, `liveRunning`, suppression in `push` and `pushAlert`).
- Modify `src/room/game-room.ts` (drain the live intents onto the chain before the pushes; fill the paws; check the toggle; `pounced(playerId)`; `checkLive(now)`; `initRematch` marks `quietFor`).
- Modify `src/pounce/pounces.ts` (mark the table on Play), `src/notify/deliver.ts` (`only` devices), `src/index.ts` (the route) and `wrangler.jsonc` (`LIVE: "on"`).
- Create `tests/live.test.ts`, `tests/live-entry.ts`, `tests/live-fixtures.test.ts` and `fixtures/push/live-activity.json`. Extend `tests/play-helpers.ts` (`live` option).

- [ ] **Step 1: Failing tests.**
  - Unit: `pushLive` headers (`apns-push-type: liveactivity`, topic `<topic>.push-type.liveactivity`, priority).
  - Miniflare start: the route stores tokens, and 400s on bad bodies. A background with the partner awake sends push-to-start to the start token. A partner who is away sends nothing. The toggle off sends nothing.
  - Miniflare updates: an uploaded update token gets an update on the next turn; the move coming to you is priority 10 with an alert.
  - Miniflare suppression: your move is suppressed only with an update token.
  - Miniflare ends: a reconnect ends it, and so does the round end. `checkLive` at +30 minutes ends it (idle) and at +2 hours (cap). A timeout on your move sends a passive your move.
  - Miniflare one per device: a newer table's start ends the older one.
  - Miniflare age bands: a kitten device stores and gets nothing; teen night sends nothing.
  - Miniflare flag: with `LIVE` off, the route 404s and nothing changes.
  - Fixtures: `live-activity.json` matches the builders.
- [ ] **Steps 2–4.** Run the whole suite, `typecheck` and `lint`.
- [ ] **Step 5:** Commit `feat(play-api): push-to-start, updates and ends for the live table (behind LIVE)`.

### Task 5: PounceKit — attributes, look, token rule, sweep, client

**Files:**
- Create `PounceKit/Sources/PounceKit/LiveTable/LiveTable.swift` (attributes, state), `LiveTableLook.swift`, `LiveTableToken.swift`, `LiveTableSweep.swift`, and `Demo/DemoLiveTable.swift`.
- Modify `Net/APIClient.swift` (`setLiveActivity`) and `Notify/NotifySettings.swift` (`liveTable`, `NotifyKey.liveTable`).
- Tests: `LiveTableFixtureTests.swift`, `LiveTableLookTests.swift`, `LiveTableTokenTests.swift`, `LiveTableSweepTests.swift`, `APIClientTests` additions, and `NotifySettingsTests` additions.

- [ ] **Step 1: Failing tests.**
  - Every fixture body's `content-state` decodes to `LiveTableState`, and its `attributes` to `LiveTableAttributes`. Re-encoding round-trips.
  - Look: the ring seat, the bell only when `mine`, your cat leading in the compact view, the trailing bell or the mover's cat, the paws (grey, one or both), numerals.
  - Token: teen and adult upload once; a new token or device uploads again; a kitten or unknown band never uploads.
  - Sweep: entering a table ends that code; stale ends; older than 2 hours ends; all but the newest end.
  - Client: `PUT /v1/devices/me/live-activity` with the exact body.
  - Settings: `liveTable` defaults on (adult and teen) and off (kitten).
- [ ] **Steps 2–4.** **Step 5:** Commit `feat(pounce-kit): live table state, look, token rule and sweep`.

### Task 6: Placeholder art, extension views, app bridge, toggle

**Files:**
- Modify `Art/manifest.json`, `Art/tools/habit-placeholders.sh`, `Pounce/Design/ArtName.swift` (`Habit.iconLiveTable`) and the asset catalog.
- Create `PounceWidgets/LiveTableWidget.swift` (Lock Screen and Dynamic Island) and `Pounce/App/LiveTableBridge.swift`.
- Modify `PounceWidgets/PounceWidgetsBundle.swift`, `PounceWidgets/Previews.swift`, `Pounce/Info.plist` (`NSSupportsLiveActivities`), `Pounce/App/AppModel.swift` (owns the bridge; open ends; foreground sweep; toggle), `Pounce/Shell/NotifyPanel.swift` (toggle) and `Pounce/App/DemoMode.swift` / the launch arguments (`-demo-live-table`).
- Create `PounceUITests/LiveTableTests.swift` (the toggle shows and flips) and `PounceUITests/LiveShotTests.swift`.

- [ ] **Step 1:** `scripts/check-assets.sh` fails on `icon-live-table`. Render the placeholder; it passes.
- [ ] **Step 2:** Previews for the Lock Screen and the Island, for my move, their move, no paws, and six seats.
- [ ] **Step 3:** Debug simulator build. Release generic build exactly as CI runs it (`CODE_SIGNING_ALLOWED=NO`).
- [ ] **Step 4:** UI tests: `LiveTableTests`, `SmokeTests`, `UsTests`, `NotifyTests`.
- [ ] **Step 5:** Commit `feat(play-ios): the live table on the Lock Screen and Dynamic Island, its tokens and toggle`.

### Task 7: Screenshots, docs, review, verification

- [ ] Own simulators. iPhone: the Lock Screen live table on your move and on their move; the Dynamic Island compact and expanded. iPad: only if it renders Live Activities. Save as `Art/screenshots/live/<name>-<iphone|ipad>-<portrait|landscape>.jpg`.
- [ ] README: the live table and the `LIVE` flag. MANUAL-CHECKLIST: start, update and end at 30 minutes on TestFlight builds.
- [ ] Whole-branch review against the base. Fix every Critical and Important finding test-first.
- [ ] Full verification: the server suite, `tsc` and `eslint`; `swift test`; the Debug build and the Release unsigned build; `check-assets`; the UI tests.
