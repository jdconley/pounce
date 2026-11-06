# Streaks on Home, the trophy room and adding people Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `2026-11-06-trophy-room-design.md`, all of it. Home's single paw badge becomes a strip: your own streak (a day counts when you take a turn at a table with another person, D1), one chip per connection in top-pair order, and a plus that is always last (big and bouncing when there are no connections). Your own streak opens the new trophy room: personal records, the shelf of everything earned across your pairs, locked silhouettes with progress rings for the rest (D4), your connections and the plus. The plus opens the invite sheet: a Messages link (PR 5's link pounce, target `"new"`) and its QR; on a kitten's device a room code and its QR instead. Answering a link with Play makes the connection at once at 0 and deals a new table for both (D2). No cap on connections (D3). A `TROPHY` flag (needs `STREAKS`) is on in `wrangler.jsonc` at merge, like `LIVE`.

**Architecture:**
- **Server, pure (100% coverage, `src/streaks/**`):**
  - `personal.ts`: the personal streak record and its rules (`emptyPersonal`, `recordTurn`, `settlePersonal`, `ownView`, `mergePersonal`), built on `clock.ts` and the pair's nap, win-back and fresh-start rules.
  - `trophies.ts`: the `GET /v1/me/trophies` payload from the personal record and the player's pair states (`trophies(input)`): records, earned (merged across pairs), the catalog with each item's unlock numeral and progress, connections.
  - `profile.ts`: `trophyOn(env)`.
- **Server, glue (Miniflare-tested):** `Player` stores the record (meta `personal`, plus `pair_best`), `recordPersonalTurn`, `ownStreak`, merge; `GameRoom.reportStreak` feeds it; `pairs.ts` gains `connect` (D2), `myOwn` and `myTrophies`; `index.ts` adds `own` to `GET /v1/me/streaks` and the new route; `pounces.ts` calls `connect` before dealing.
- **App, pure (PounceKit, Swift Testing):** `OwnStreak`, `StreakList.own`, `Trophies` wire; `TrophyService` (+ `APIClient`) and `TrophyStore`; `StreakStrip` (chip order, empty state, plus size); `TrophyRoom` (records, shelf, locked plus progress); `InviteLink` (cache rule); `DemoTrophyService` from the demo streaks.
- **App:** `StreakStrip` view on Home (top center, replacing the badge), `TrophyRoomView` (route `.trophies`), `InviteSheet` (link and QR, or code and QR), a trophy button on the Us top bar, placeholder art.

**Tech Stack:** TypeScript, Cloudflare Workers, SQLite Durable Objects, vitest with v8 coverage, Miniflare; Swift 6 on CI's Xcode 26.6, SwiftUI, CoreImage (`CIQRCodeGenerator`), Swift Testing, XCUITest, XcodeGen, ImageMagick.

**Spec:** `docs/superpowers/specs/2026-11-06-trophy-room-design.md` (binding, §7 decisions D1–D4); background `2026-11-04-daily-habit-design.md` §6, §7, §8, §9, §10.1–10.2, §12.4, §14.1, §16.

**Base:** main at `7f3e060` (PRs 1–9).

## Global Constraints

- **`TROPHY` flag** (`trophyOn(env)`): needs `STREAKS`. Off means today's behavior exactly: no `own` in `GET /v1/me/streaks`, `GET /v1/me/trophies` is 404, no personal streak is recorded, and an answered link deals as before with no pair until both take a turn. Tested. `wrangler.jsonc` turns it on.
- **No emoji anywhere. On screen:** names, table names and numerals only; everything else is art or icons. No guilt copy, no countdowns, nothing that says a day was missed.
- **Art:** loud Toy palette (violet, magenta, teal, orange, sky, lime, ink), never beige or muted. Real PR 8 art where a manifest name exists; new pictures are `_ph` placeholders drawn by `Art/tools/habit-placeholders.sh`: `trophy-shelf`, `trophy-lock`, `chip-plus`, `qr-frame`, `icon-record-own`, `icon-record-best`, `icon-record-pair`, `icon-record-days`, `icon-record-weeks`.
- **Swift on Xcode 26.6:** no Swift 6.4-only features, no local constant shadowing a method it calls in its own initializer, no `Test.cancel`.
- **Server tests:** every Miniflare `describe` has `{ timeout: 30_000 }`; presence is set before the deal where bots could race; pure rules at 100%.
- **Kittens (§14.1, unchanged):** a kitten's device can't send links (the plus shows a room code and its QR); a kitten can accept a link; pushes follow PR 9's consent rules.
- **Environment:** simulators "Pounce trophy iPhone 17 Pro" and "Pounce trophy iPad Pro 13", shut down (not deleted) at the end; a private dev server port (not :4343 or :8787); never the physical iPhone; no secrets.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Decisions where the spec is silent

**Your own streak (server)**
1. **What counts (D1):** a turn counts for the person who took it when the room's report names them (`by`) and at least two different players hold seats at the table. That's the condition the room already checks before it reports to pairs, so a bot-only table never reports and never counts. Two household people on one phone are two players, so pass-and-play counts, as it does for pairs (§6.1). Cost if wrong: none for a family; a person who seats a second household person and plays both seats keeps a streak, which the pair streak allows too.
2. **Whose day:** the player's own time zone (the latest a device reported), else `America/Los_Angeles`, with the 04:00 rollover (`dayKey`). There is no late move pass: it exists so one person isn't blamed for the other's held move, and a personal streak has only one person.
3. **Naps, win-back and fresh start mirror `pair-core.ts`:** one nap at the 7th day and one per perfect week (seven kept days in a row with no nap), at most 2, used at settlement on a missed day; with none left, win-back (the bandage): keeping the next two days brings it back and turns the miss into a nap, missing one of them ends it at 0; best and total days stay. The win-back is included because the spec reuses "the same nap rules" and the pair's naps fall through to it. Cost if wrong: one extra mark on the own chip.
4. **No pause** for the personal streak: pausing is a pair's agreement (§8.3), and a person alone has naps and win-back. Cost if wrong: someone who pauses every pair for a trip longer than the naps cover loses their own count (best and total stay).
5. **Settled lazily,** on each turn and each read: the record sends no push and needs no alarm. A day settles once it has ended in the player's zone. A long absence settles day by day (cheap, and paid once: the read saves the result).
6. **Stored on the Player** as meta `personal` (JSON) and `pair_best` (the longest pair streak seen, a high-water mark updated on every streak and trophy read, so leaving a pair doesn't lower the record). An account merge merges the two records the way `mergeStates` merges pairs, after bringing both up to now (a stored count can be months stale; review I1): the longer current streak wins whole, and a turn the other record has on a day the winner hasn't settled counts for it too; best, total days, perfect weeks and pair best take the maximum; naps take the maximum, capped at 2. Guest expiry and deletion destroy it with the player.
7. **Recorded once per report, not per pair, before the pair reports** and outside their retry loop, so a failed pair report still counts the day. With `TROPHY` off, nothing is recorded.
8. **No socket message** for the own streak: Home refreshes on appear, on foreground and when back from a table, which is when the strip is seen.

**Wire**
9. `OwnStreak` = `{count, best, kept, naps, winback: {kept} | null, lifetimeKept, perfectWeeks, week: WeekDot[7]}`; `week` uses the pair's states (`kept`, `nap`, `missed`, `live`, `none`) so the app's badge mode rule works unchanged.
10. **`GET /v1/me/streaks`** gains `own: OwnStreak` with `TROPHY` on, so the strip is one request. Older apps ignore it.
11. **`GET /v1/me/trophies?person=`** → `{own, records: {current, best, longestPair, totalDays, perfectWeeks}, earned: {toys, backs, rugs, condoStage}, catalog: [{id, kind, at, progress}], connections: StreakView[]}`. `connections` is exactly `pairs` of `GET /v1/me/streaks`.
12. **Earned, merged across pairs:** what this person has unwrapped in any pair (`unlockedFor` semantics: a gift's item counts once they opened it), without the defaults (`back-violet-paw`, `rug-classic`), plus the highest condo stage of any pair. Toys come from the pairs' `owned`, less wrapped gifts.
13. **The catalog (D4)** lists every condo stage (`condo-1`…`condo-10`), the six unlockable backs, the four rugs and the 24 toys, in that order, each with `kind` (`condo`, `back`, `rug`, `toy`), `at` (the numeral on its ring) and `progress` (0–1, 1 when earned). The measure behind `at` and `progress`, always the best of the person's pairs:
    - a condo stage: its lifetime threshold (§9.1) against the most days together;
    - a normal back (yarn swirl, moonlit fish, cucumber chaos): the next small milestone (not 7, 30, 100, 365 or past 365) above the longest current pair streak;
    - a rug or a rare back (crown, heart paws): the next big milestone above it;
    - the golden yarn back: 24, against the most toys one pair has (it comes with a full set);
    - a toy: its rarity's guarantee in kept days (common 1, shiny 7, golden 30, §9.3), against that pair's pity counter (common progress 0).
    - With no pairs the measure is 0, so `at` is the tier's first milestone.
    - Past 300, the small tier has no milestone left for the current streak: `at` is 0 and the ring shows no numeral (review M6).
    The gift's content is random within its tier, so `at` is "can come at", not a promise. Cost if wrong: a ring shows a numeral that passes without that item; the shelf still only shows what arrived.
14. **No pause, held day or pounce** in `OwnStreak`; none applies to one person.

**Connections and invites (server)**
15. **D2:** with `TROPHY` on, answering a link pounce (`to` null) with Play calls `connect(env, answerer, sender, now)` (`ensurePair` without turns) before dealing, for any choice (new game or a table you pick). The pair starts at 0 and hears the new table's deal like any pair, so both lists show it at once with the table as a move; the answered push to the sender already names the pair and makes the sender's app refresh.
16. **Tombstones still hold:** if either person left the other's streak, the link deals the table but makes no pair; the leaver can undo it from the ghosted cat (§14). In-a-bit and Not now make no pair (they don't accept).
17. **Kittens:** answering is allowed as before (nothing is collected from the answerer); sending a link stays 403. No change to pushes.
18. **D3, no cap:** nothing limits pairs; the strip scrolls.

**App**
19. **Strip order:** own chip (when the server sent `own`), the pairs in the server's top-pair order, the plus. With no pairs the plus is big and bounces (for a teen it's big but still: §14.1 says no nudges to share links). The strip shows whenever the server says streaks are on, so the plus is there with no pairs; with `own` absent (TROPHY off) it's pairs and the plus.
20. **Ids:** the top pair's chip keeps `home.streak` (value `count|me|them|mode`, opens Us), so existing tests stand; later pairs are `home.pair.<i>` (i ≥ 1); own chip `home.own` (value `count|kept|mode`); the plus `home.add` (value `big` or `small`); the strip `home.strip`.
21. **Where the extras sit** (they "stay where PR 4 put them"): the gift box to the left of the strip's first chip, the sign-in cloud on the top pair's chip, and a waiting pounce's bell on that pair's chip. On a phone the strip sits under the bell and gear row at full width (a connection or two shows whole; the rest scroll), and the hero shrinks a little to make room.
22. **Chips:** a pair chip is the partner's cat over `PawBadge` (the same marks); a tap opens Us on that pair. The own chip is your cat on a paw with your numeral and its mark (bandage, nap blanket, fresh sparkle); it glows when today is kept.
23. **iPad** scales the strip 1.3× and centers it; it scrolls only if the chips still don't fit.
24. **The trophy room** is route `.trophies`, from the own chip and a trophy button on the Us top bar (shown when `own` is there). It loads `GET /v1/me/trophies` (404 → nothing but the connections and the plus from the streak list). Layout: records row (five icon-and-numeral tiles), the shelf (earned items on planks: the condo stage, rugs, backs, toys golden-first), still to earn (silhouettes: the item's art tinted ink, a lock, a progress ring and the `at` numeral; nearest first, then catalog order), connections (cat, name, numeral → Us on that pair) and the plus. iPad: two columns in landscape (records and shelf left, still-to-earn and connections right).
25. **The invite sheet, adult or teen:** mints a link pounce with target `"new"` and shows its QR (CoreImage, in the `qr-frame` art) with the share button (the system share sheet, PR 5's `ShareRoom`) and close. The link is kept in memory for an hour and reused, so opening the sheet again doesn't spend the 3-an-hour limit, but only while the server's preview (`GET /v1/pounces/links/{token}`) says nobody answered it (any answer uses it up) and no new connection appeared since (review I2). Resting (429) with no kept link, or no server, shows the sleeping bell and no QR; a tap tries again. The app can't tell a 429 from offline here (`PounceStore.share` answers nil for both), and the picture is the same either way.
26. **The invite sheet, kitten:** creates a table (`POST /v1/rooms`) and shows its room code and the QR of `/j/<code>` (scanning it with the Camera app opens Pounce through the existing universal link), with a Play pill that opens the table's lobby. Pounce room codes are five characters from the no-vowel alphabet, not six numerals as the spec says; the sheet shows the same code the lobby does. No share button. The table is made when the sheet opens, because the code must exist to be scanned; the same table is shown again within the hour (review M9), so only one empty lobby is left behind, like a Create that was backed out of.
27. **Demo:** `-demo-streaks` also serves `own` (count 12, a nap yesterday) and `DemoTrophyService` derives the trophies from the demo pairs with the server's rules mirrored only roughly (fixtures, not logic). `-demo-streaks empty` serves no pairs (the big plus). `-show-trophies` and `-show-invite` open them at launch. A kitten's demo code is `TB4XN`.
28. **Refresh:** the existing refreshes cover D2's "shows on both Homes": the answerer's app refreshes after answering; the sender's on the `pounce_answered` push and on foreground.

## Review Focus

1. **`TROPHY` off is today exactly:** no `own`, trophies 404, link answers make no pair, no personal record. Test: `trophy.test.ts` "with TROPHY off".
2. **D1 at the edges:** a bot-only table never counts; 03:59 counts for the day before; a nap covers one missed day; a second miss with no nap starts win-back; fresh start keeps best and total days. Test: `personal.test.ts`.
3. **D2 race and repeats:** two answers at once make one pair and one table; a retried answer makes no second pair; a tombstone blocks it. Test: `trophy.test.ts` "D2".
4. **Merged trophies never show a wrapped gift** as earned, nor a default as a trophy. Test: `trophies.test.ts`.
5. **The invite sheet on a kitten's device** never mints a link and never shows a share button. Test: `InviteLinkTests`, UI `TrophyTests.testKittenInviteShowsCode`.

---

### Task 1: Server: the `TROPHY` flag and the personal streak (pure)

**Files:** Create `apps/play-api/src/streaks/personal.ts`, `personal.test.ts`. Modify `src/streaks/profile.ts` (`trophyOn`), `profile.test.ts`, `src/env.ts` (`TROPHY?`), `wrangler.jsonc` (`"TROPHY": "on"`), `src/env.test.ts`.

**Interfaces (produces):**
- `trophyOn(env: {STREAKS?, TROPHY?}): boolean`
- `type Personal = {firstDay, lastSettled, count, best, lifetimeKept, perfectWeeks, perfectRun, naps, winback: {missedDay, kept} | null, days: Record<Day, "kept" | "nap" | "missed" | "winback">}`
- No record yet is `null`; `recordTurn(p: Personal | null, at, zone, now): Personal`; `settlePersonal(p, zone, now): void`; `ownView(p: Personal | null, zone, now): OwnStreak`; `mergePersonal(a: Personal | null, b: Personal | null): Personal | null`.

- [ ] Step 1: tests: a turn keeps today at once (count 1, kept); a second turn the same day changes nothing; 03:59 belongs to the day before; consecutive days count up and best follows; a missed day with no nap and count > 0 starts win-back, two kept days end it (the miss shows as a nap), a miss during win-back ends the streak at 0 with best and total days kept; the 7th day earns a nap and a perfect week another (at most 2), a nap covers a missed day; the week has seven dots ending today (`live` before a turn); a long absence settles to 0; merge rules; `trophyOn` needs both; wrangler has `TROPHY` on.
- [ ] Step 2: `pnpm --filter @pounce/play-api test` fails. Step 3: implement. Step 4: pass at 100% for `src/streaks/**`. Step 5: commit.

### Task 2: Server: the trophies payload (pure)

**Files:** Create `src/streaks/trophies.ts`, `trophies.test.ts`. Modify `src/streaks/catalog.ts` (export the milestone lists and condo thresholds if needed).

**Interfaces:** `trophies({own, pairBest, me, pairs: PairState[], connections, now, zone}): Trophies` with the shapes in decisions 11–13.

- [ ] Step 1: tests: records (longest pair from both the high-water mark and the pairs); earned merged across two pairs, wrapped gifts excluded, defaults excluded, highest condo stage; the catalog has 44 entries in order, earned items at progress 1; condo `at` and progress; small and big tier numerals above the best count; golden yarn at 24 against the most toys; toy rarity numerals with pity progress; no pairs gives first milestones at 0.
- [ ] Step 2–5 as above.

### Task 3: Server: glue, routes and D2 (Miniflare)

**Files:** Modify `src/players/player.ts` (`recordPersonalTurn`, `ownStreak`, `notePairBest`, `personalRecord`, export/absorb), `src/room/game-room.ts` (`reportStreak` records the turn), `src/streaks/pairs.ts` (`connect`, `myOwn`, `myTrophies`), `src/index.ts` (`own` in the streak list, `GET /v1/me/trophies`), `src/pounce/pounces.ts` (`connect` before dealing), `tests/play-helpers.ts` (`trophy` option). Create `tests/trophy.test.ts`, `tests/trophy-entry.ts` if a hook is needed.

- [ ] Step 1: tests: `GET /v1/me/trophies` after two humans take turns (own count 1 for both, records, catalog length, connections = the pair); a bot-only table gives no own streak; D2: an accepted link lists the pair at 0 for both before any turn, with the new table as a move; two answers at once make one pair; a kitten accepts a link (pair made) but can't make one (403); `TROPHY` off: no `own`, trophies 404, no pair from a link until turns.
- [ ] Step 2: fail. Step 3: implement. Step 4: whole suite, `typecheck`, `lint`. Step 5: commit.

### Task 4: PounceKit: wire, stores, strip, room and invite rules

**Files:** Create `PounceKit/Sources/PounceKit/Streaks/{TrophyWire,TrophyService,TrophyStore,StreakStrip,TrophyRoom,InviteLink}.swift`, `Demo/DemoTrophies.swift`; tests `TrophyWireTests`, `TrophyStoreTests`, `StreakStripTests`, `TrophyRoomTests`, `InviteLinkTests`. Modify `StreakWire.swift` (`StreakList.own`), `StreakStore.swift` (`own`), `DemoStreaks.swift` (own, empty), `StreakBadge.swift` (`mode(own:)`).

- [ ] Step 1: tests: decode `own` present and absent; trophies decode; `StreakStrip.chips` order (own, pairs in order, plus last), the empty state (plus big), no own without `own`; `TrophyRoom` records order and values, shelf order, locked nearest-first with progress and `at`, connections; `InviteLink` reuse within an hour, drop on a new connection, never for a kitten; `TrophyStore` 404 → off, offline keeps.
- [ ] Step 2: `swift test --package-path apps/play-ios/PounceKit` fails. Step 3: implement. Step 4: pass. Step 5: commit.

### Task 5: Art placeholders

- [ ] Add the nine `_ph` names to `Art/manifest.json` (batch `habit`), draw them in `habit-placeholders.sh`, mirror in `ArtName.Habit`; `scripts/check-assets.sh` passes. Commit.

### Task 6: App: strip, trophy room, invite sheet

**Files:** Create `Pounce/Shell/{StreakStripView,TrophyRoomView,InviteSheet}.swift`, `PounceUITests/TrophyTests.swift`. Modify `HomeView.swift`, `UsView.swift` (trophy button), `Route.swift` (`.trophies`), `RootView.swift`, `AppModel.swift` (`trophies`, `showTrophies`, `invite`), the demo flags.

- [ ] Step 1: UI tests (`-uitest-reset -seed-people -demo-streaks`): `testStripOrder` (own, then pairs, then plus small), `testOwnOpensTrophies`, `testTrophyRoomShowsRecordsShelfAndLocked`, `testEmptyStripShowsBigPlus` (`-demo-streaks empty`), `testPlusOpensInviteWithQR`, `testKittenInviteShowsCode`, `testPairChipOpensUsOnThatPair`.
- [ ] Step 2: fail. Step 3: implement. Step 4: run TrophyTests, UsTests, PounceTests, KittenTests, SmokeTests. Step 5: commit.

### Task 7: Screenshots, review, verification

- [ ] Screenshots on own simulators: `strip`, `strip-empty`, `trophies`, `invite`, `invite-kitten` → `apps/play-ios/Art/screenshots/trophies/<name>-<iphone|ipad>-<portrait|landscape>.jpg`, landscape stored upright (EXIF orientation upper-left, checked with `file`).
- [ ] README flags and MANUAL-CHECKLIST (invite by QR across two phones).
- [ ] Whole-branch review on the most capable model; fix Critical and Important findings test-first.
- [ ] Full verification: server suite, `tsc`, `eslint`; `swift test`; Debug simulator build; Release unsigned generic iOS build as `ios.yml` runs it; `check-assets`; SmokeTests, UsTests, PounceTests, KittenTests, TrophyTests.
- [ ] Rebase onto origin/main.
