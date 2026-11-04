# Server streaks (daily habit PR 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shared "Us" streaks on the server: the `Pair` Durable Object, turn reporting from rooms, the both-in rule with the late move pass and held days, settlement, naps, win-back, pause, milestones, gifts and toys, the streak routes, and the `streak`, `rematch`, `setLook`/`look` socket additions, all behind `STREAKS`.

**Architecture:** All streak math lives in pure modules under `src/streaks/` (day keys and cutoffs, the catalog and reward draws, and a pure pair state machine over a JSON `PairState`), unit-tested with a fake clock and a seeded rng. `RoomCore` stays pure: with the streaks feature on it emits `StreakIntent`s (drained beside push intents) and handles `setLook` and `rematch`. Thin glue (`src/streaks/pairs.ts`, the `Pair` DO, `Player` additions, `GameRoom` and route wiring) is covered by Miniflare tests.

**Tech Stack:** TypeScript, Cloudflare Workers + SQLite Durable Objects, vitest + v8 coverage, Miniflare, esbuild.

**Spec:** `docs/superpowers/specs/2026-11-04-daily-habit-design.md` (§6, §7, §8, §9, §10.4, §13.1 merge rules, §13.2–13.4, §14, §15 row 3, §16).

## Global Constraints

- Everything new is behind `STREAKS` (`"on"`, `"1"` or `"true"` turns it on). It is never listed in `wrangler.jsonc` `vars`; tests set it. With it off, routes, rooms and snapshots behave exactly as on main and the existing suites pass unchanged.
- `PROTOCOL_VERSION` stays 1. Protocol additions are additive. The shared fixture files `fixtures/protocol/{server,client}-messages.json` are not changed (the Swift tests decode every server sample and count the client samples); new samples go in `fixtures/protocol/streaks-{server,client}-messages.json` for PR 4.
- No blame: no route or message says who played or missed a past day. Only today's two paws are per person.
- No ids, tokens or names in logs. Day rows are kept 120 days.
- Day key: the local calendar date, rolling over at 04:00 local. Evening cutoff: quiet-hours start − 2 h. Settlement: both people's day ended + 10 min.
- Coverage: new pure modules (`src/streaks/clock.ts`, `catalog.ts`, `rewards.ts`, `pair-core.ts`, `profile.ts`) at 100%; `src/room/core.ts` stays 100%. DO glue (`src/streaks/pair.ts`, `src/streaks/pairs.ts`) is excluded from coverage like the other DOs and covered by Miniflare.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Only `apps/play-api` and this plan change.

## Decisions where the spec is silent (recorded here; each also goes in the PR report)

1. **Rollover on DST days** uses the local wall clock (a turn before 04:00 local belongs to the previous date), not "instant − 4 h", which would put 04:00–05:00 on a spring-forward morning in the wrong day.
2. **The player's time zone** is `Player.meta.time_zone`, written on every profile upload by any of the player's devices (most recent report wins, §6.3). Stored even with `STREAKS` off (invisible). The pair caches each person's zone and is refreshed on profile upload.
3. **Quiet-hours start** comes from the synced setting `quiet.start` = `{h, m}` (the shape PR 1's parse test already uses); without it, 21:00 for a teen and 22:00 otherwise (§12.3, §14.1).
4. **"A shared table in play all day"** (held days) = for each person, a shared table was in the pair's `moves` throughout that person's window from 04:00 to their cutoff. Tracked as a per-person `gap` flag alongside `held`.
5. **Pair formation** needs both players to have completed a turn at that table; the room remembers each player's last turn time (`streakTurns`) and the new pair credits those turns, so the first day can be kept at once.
6. **Naps and win-back apply only while the count is above 0**; a missed day at 0 is just missed.
7. **Win-back:** kept days during it raise the count as usual; the first miss ends it at 0; held, paused and nap days neither count toward the two days nor end it. Success turns the missed day into a nap day.
8. **Perfect week:** seven kept days without a nap or miss in between; held and paused days don't reset it.
9. **Pause:** starts today unless today is already kept (then tomorrow); `days` 1–14 runs to start + days − 1, extending never beyond today + 13. A paused day is paused even if both play (spec order: paused first). Ending a pause after your evening cutoff keeps today paused; before it, today counts again.
10. **Milestones after 365:** 400, 500, 600, … Big gift tier: 7, 30, 100, 365 and every milestone above 365.
11. **Catalog lineup** (§18): 24 toys (16 common, 6 shiny, 2 golden); backs `back-violet-paw` (default), `back-yarn-swirl`, `back-moonlit-fish`, `back-cucumber-chaos` (normal), `back-crown`, `back-heart-paws` (rare), `back-golden-yarn` (full toy set only); rugs `rug-classic` (default), `rug-night-sky`, `rug-candy-stripe`, `rug-fish-pond`, `rug-royal-violet`.
12. **Toy odds:** golden 3%, shiny 15%, common 82%, with pity (shiny or better by the 7th kept day, golden by the 30th); no duplicates until all 24 are owned.
13. **Gift items** become the pair's at once (so they're never re-gifted), but a person's unlocks count a gift's item only once that person opens it. `setLook` checks the setter's unlocks across all their pairs (§17: "Table looks come from your own unlocks", which overrides §9.4's "ownership isn't checked").
14. **`{t:"streak"}` carries `person`** (the local person id the view is for), because a pass-and-play phone speaks for both people of a pair and gets both views.
15. **Pair state is one JSON row** in the `Pair` DO (like `GameRoom`'s room row), not the §13.2 tables; §18 leaves schemas to the builder.
16. **The pair-creation coordinator** is the `Player` with the smaller id, so two rooms can't create two pairs for the same two people.
17. **Rematch rotates seats** by one (old seat 1 becomes seat 0), so the first move moves on one person; the requesting device hosts the new room.

## Review Focus

1. **A player in two seats after a merge** — they must never pair with themself, and their turns still count once. Test: a room with one player in seats 0 and 1 reports no pair (Task 4 core test, Task 6 glue).
2. **Late or retried reports** — a report for a day that has already settled must not change it, and a retried report must not draw a second toy. Test in Task 3.
3. **A partner with no time zone yet** — falls back to the partner's zone, then `America/Los_Angeles`. Test in Task 3.
4. **A pair idle for months** — advancing across a long gap must settle in order, end the streak at 0, keep 120 day rows, and not loop forever. Test in Task 3.
5. **`STREAKS` off** — `rematch`/`setLook` are `bad_message`, snapshots carry no `look`, streak routes 404. Tests in Task 4 (core) and Task 6 (worker).

---

### Task 1: Day keys, cutoffs and settlement times

**Files:**
- Create: `apps/play-api/src/streaks/clock.ts`, `apps/play-api/src/streaks/clock.test.ts`

**Interfaces:**
- Produces: `type Day = string` (`YYYY-MM-DD`); `ROLLOVER_MIN = 240`; `FALLBACK_ZONE = "America/Los_Angeles"`; `isZone(z: unknown): z is string`; `dayKey(instant: number, zone: string): Day`; `addDays(day: Day, n: number): Day`; `daysBetween(a: Day, b: Day): number` (b − a); `localToInstant(day: Day, minutes: number, zone: string): number` (minutes may be ≥ 1440); `dayStart(day, zone)`; `dayEnd(day, zone)`; `cutoffAt(day: Day, zone: string, quietStartMin: number): number`; `localMinutes(instant, zone): number`.

- [ ] **Step 1: Write the failing tests.** In `America/Los_Angeles`: 2026-11-04 03:59 → `"2026-11-03"`, 04:01 → `"2026-11-04"`, 01:00 → previous date ("tonight"). DST spring (2026-03-08) and fall (2026-11-01): 03:59 and 04:01 local map to the previous and same date; `dayEnd − dayStart` is 23 h on 2026-03-08 and 25 h on 2026-11-01. `America/New_York` vs LA for the same instant at 02:00 LA gives different keys. `cutoffAt("2026-11-04", LA, 22*60)` = 20:00 local; quiet start 01:00 → 23:00 the same date; quiet start 05:00 → 03:00 the next date; quiet start 05:30 → stays ≤ `dayEnd`. `addDays("2026-12-31", 1)` = `"2027-01-01"`; `daysBetween("2026-11-01","2026-11-08")` = 7. `isZone("Mars/Base")` false.
- [ ] **Step 2:** Run `pnpm --filter @pounce/play-api exec vitest run src/streaks/clock.test.ts`; expect failures (module missing).
- [ ] **Step 3: Implement** with one cached `Intl.DateTimeFormat` per zone (`hourCycle: "h23"`); `localToInstant` guesses with the offset at the naive UTC time and corrects once.
- [ ] **Step 4:** Re-run; PASS.
- [ ] **Step 5:** Commit `feat(play-api): streak day keys, cutoffs and rollover`.

### Task 2: Catalog, milestones and reward draws

**Files:**
- Create: `src/streaks/catalog.ts`, `src/streaks/rewards.ts`, `src/streaks/catalog.test.ts`, `src/streaks/rewards.test.ts`, `src/streaks/profile.ts`, `src/streaks/profile.test.ts`

**Interfaces:**
- Produces (`catalog.ts`): `type Rarity = "common" | "shiny" | "golden"`; `TOYS: readonly {id: string; rarity: Rarity}[]` (24); `BACKS`, `RUGS` (ids above), `DEFAULT_BACK = "back-violet-paw"`, `DEFAULT_RUG = "rug-classic"`, `NORMAL_BACKS`, `RARE_BACKS`, `FULL_SET_BACK = "back-golden-yarn"`; `isBack(id)`, `isRug(id)`; `isMilestone(n)`, `nextMilestone(n)`, `isBigMilestone(n)`; `condoStage(lifetimeKept): number` (0–10, thresholds 1, 3, 7, 14, 30, 50, 100, 150, 200, 365).
- Produces (`rewards.ts`): `type Pity = { shiny: number; golden: number }` (kept days since the last shiny-or-better / golden); `drawToy(owned: readonly string[], pity: Pity, rng: Rng): { toy: string; pity: Pity }`; `giftItem(milestone: number, owned: readonly string[], rng: Rng): string` (`"confetti"` when nothing is left).
- Produces (`profile.ts`): `quietStartMinutes(settings: Section, band: AgeBand | null): number`; `streaksOn(env: { STREAKS?: string }): boolean`.

- [ ] **Step 1: Write the failing tests.** Milestones: `isMilestone` true for 3, 7, 14, 30, 50, 75, 100, 150, 200, 250, 300, 365, 400, 500; false for 1, 360, 450; `nextMilestone(0)` = 3, `nextMilestone(365)` = 400. `isBigMilestone(7|30|100|365|400)` true, `(3|14|50)` false. `condoStage(0)` 0, `(1)` 1, `(29)` 4, `(30)` 5, `(365)` 10. Toys: 24 unique, 16/6/2. `drawToy` over 24 seeded draws from nothing owned yields 24 distinct toys; across 200 kept days with any seed, the gap between shiny-or-better draws is ≤ 7 and between goldens ≤ 30 while goldens remain unowned or the set is complete; a full set may repeat. `giftItem(3, [])` is a toy or a normal back; `giftItem(7, [])` is a rug or a rare back; with every rug and rare back owned, 7 gives a toy; with everything owned, `"confetti"`; the same seed gives the same item. `quietStartMinutes({ "quiet.start": {v:{h:23,m:30},at:1} }, "adult")` = 1410; malformed → band default (teen 1260, adult/null 1320). `streaksOn({})` false, `{STREAKS:"on"}` true, `{STREAKS:"off"}` false.
- [ ] **Step 2:** Run; FAIL.
- [ ] **Step 3: Implement.** Rarity roll: golden if `pity.golden ≥ 29`, else shiny if `pity.shiny ≥ 6`, else by `rng()` (< 0.03 golden, < 0.18 shiny). If the rolled rarity has no unowned toy while the set is incomplete, fall back to unowned toys of any rarity, best rarity first. Pity: golden resets both; shiny resets `shiny` and bumps `golden`; common bumps both.
- [ ] **Step 4:** Run; PASS.
- [ ] **Step 5:** Commit `feat(play-api): streak catalog, milestones, toys and gifts`.

### Task 3: The pure pair state machine

**Files:**
- Create: `src/streaks/pair-core.ts`; tests `src/streaks/pair-core.days.test.ts` (both-in, cutoff, held, zones, DST), `src/streaks/pair-core.settle.test.ts` (naps, win-back, pause, perfect weeks, idle gaps), `src/streaks/pair-core.rewards.test.ts` (milestones, gifts, toys, view, merge, repoint)

**Interfaces:**
- Consumes: Task 1 and Task 2 exports; `createRng`, `Seed` from `src/rules/rng.ts`.
- Produces:
  - `type PairPerson = { id: string; name: string; cat: number; zone: string | null; quietStart: number }`
  - `type DayState = "live" | "kept" | "nap" | "held" | "paused" | "missed" | "winback"`
  - `type DayRow = { turns: Record<string, number>; held: Record<string, boolean>; gap: Record<string, boolean>; state: DayState; applied: boolean; toy: string | null }`
  - `type Gift = { id: string; milestone: number; item: string; openedBy: string[] }`
  - `type PairState = { id; people: [PairPerson, PairPerson]; createdAt; lastAt; moves: Record<string, { holder: string | null; since: number }>; days: Record<Day, DayRow>; lastSettled: Day | null; firstDay: Day; streak: { count; best; lifetimeKept; perfectWeeks; perfectRun; naps; winback: { missedDay: Day; kept: number } | null; pausedFrom: Day | null; pausedUntil: Day | null; pausedBy: string | null; breakId }; owned: string[]; toys: string[]; gifts: Gift[]; pity: Pity; lastTurnAt: number; rng: { seed: Seed; calls: number } }`
  - `type TableReport = { code: string; at: number; by: string | null; holder: string | null; over: boolean }`
  - `type StreakView = { pair; partner: {name, cat}; count; me: boolean; them: boolean; naps; winback: { kept: number } | null; pausedUntil: Day | null; best; lifetimeKept; perfectWeeks; week: WeekDot[]; next: number; condoStage; toys: string[]; todayToy: string | null; unlocked: { backs: string[]; rugs: string[] }; gifts: { id: string; milestone: number; item: string }[]; myMove: string[]; theirMove: string[]; pounce: { sent: boolean; resting: boolean }; lastTurnAt: number }` with `WeekDot = { day: Day; state: "kept" | "nap" | "held" | "paused" | "missed" | "live" | "none" }` (a `winback` day shows as `missed`).
  - `newPair(id: string, people: [PairPerson, PairPerson], now: number, seed: Seed, turnedAt?: Record<string, number>): PairState`
  - `advance(s: PairState, now: number): void` — integrate to `now`, apply live keeps in day order, settle due days, prune to 120 days.
  - `report(s, r: TableReport, now): void` (advances first)
  - `pause(s, by: string, days: number, now): boolean`; `unpause(s, by: string, now): void`; `openGift(s, by, giftId): boolean`
  - `view(s, playerId, now): StreakView`; `unlockedFor(s, playerId): { backs: string[]; rugs: string[] }`
  - `setPerson(s, p: PairPerson, now): void`; `nextSettleAt(s): number | null`
  - `repoint(s, from, to): void`; `mergeStates(a: PairState, b: PairState): PairState`

- [ ] **Step 1: Write the failing tests** (fixed `now`s built with `localToInstant`; seed `[1,2,3,4]`):
  - Both in: A (LA) plays at 09:00 and B (LA) at 10:00 on D → day kept at B's report, count 1, a toy in `todayToy`; `view(A).me && view(A).them`.
  - Late move pass: A plays at 09:00 and passes the move to B at 20:01 (after B's 20:00 cutoff); B never plays → `view(B, 20:02).me` true and the day is kept at A's next report or at settlement. Passed at 19:59 → B not in, day missed at settlement.
  - Turns at 03:59 and 04:01 land on different days.
  - Two zones: A in LA, B in New York; settlement waits for LA's 04:00 + 10 min; `nextSettleAt` equals that instant.
  - DST: a kept day on 2026-03-08 and on 2026-11-01 in LA settles at 04:10 local the next day.
  - Held day: three-person table, C holds all day (holder = a non-member), neither plays → `held`, count unchanged, not broken. Same with no table in moves → `missed`.
  - Fallback zone: B with `zone: null` uses A's zone; both null → LA.
  - A report dated on an already-settled day changes nothing; the same kept report twice draws one toy.
  - Self-pair guard is not in the core (the glue never builds one); `newPair` throws on identical ids.
  - Naps: count 10, 1 nap, a missed day → `nap`, count 10, naps 0; naps earned at the 7-day milestone and per perfect week, capped at 2; count 0 + miss uses no nap.
  - Win-back: count 12, no naps, miss → `winback`, count 12, `view.winback = {kept: 0}`; two kept days → the missed day becomes `nap`, count 14, `winback` null. Failure on the first or second day → count 0, `breakId` + 1; a kept day after the failure starts at 1.
  - Pause: `pause(A, 14, now)` → `pausedUntil` = today + 13; 15 is refused; re-pausing extends but never past today + 13; paused days settle `paused` without breaking; pausing on a kept day starts tomorrow; `unpause` before the cutoff makes today normal, after it keeps today paused.
  - Perfect weeks: 7 kept in a row → `perfectWeeks` 1, a nap at 7 from the milestone and one from the week (naps 2); a nap day between resets the run.
  - Milestone gifts: reaching 3 adds a gift for both; `openGift(A)` then `view(A).gifts` empty, `view(B).gifts` length 1; a back from an unopened gift isn't in `unlockedFor(B)` but is in `unlockedFor(A)` after A opens; defaults are always unlocked.
  - Idle gap: count 5, then `advance` 200 days later → count 0, ≤ 120 day rows kept, terminates.
  - Week strip: 7 dots ending today, never names a person.
  - `mergeStates`: the longer count wins the streak; best, lifetime and perfect weeks take the max; owned and toys are unioned; naps max capped at 2; unopened gifts of both kept. `repoint(s, from, to)` renames every per-person key and the person row.
- [ ] **Step 2:** Run the three files; FAIL.
- [ ] **Step 3: Implement.** Integration: between calls the moves map is constant, so `integrate(s, to)` walks `[lastAt, to]` per person and per day window `[dayStart, cutoff]`: holding any move in the overlap sets `held`, an empty `moves` in the overlap sets `gap`, and time before `createdAt` counts as `gap`. Settlement per due day, first rule wins: kept-and-already-applied → kept; paused; both in with ≥1 turn → kept; no turns, no `held`, no `gap` → held; count > 0 and a nap → nap; count > 0 and no win-back → winback; otherwise missed (ending any win-back at 0). A live day whose earlier days are all settled is kept (effects applied) as soon as both are in.
- [ ] **Step 4:** Run; PASS; `pnpm --filter @pounce/play-api test` shows 100% for `src/streaks/*.ts` pure files.
- [ ] **Step 5:** Commit `feat(play-api): pure pair streak state machine`.

### Task 4: Room core and protocol additions (gated)

**Files:**
- Modify: `src/protocol.ts`, `src/protocol.test.ts`, `src/games/module.ts`, `src/games/cat-tower.ts`, `src/games/cat-tower.test.ts`, `src/room/core.ts`
- Create: `src/room/core.streaks.test.ts`, `fixtures/protocol/streaks-server-messages.json`, `fixtures/protocol/streaks-client-messages.json` (written by a new test in `tests/protocol-fixtures.test.ts`)

**Interfaces:**
- Produces (`protocol.ts`): `ClientMessage` adds `{t:"rematch"}` and `{t:"setLook"; rug?: string; back?: string}` (at least one; ids must be in the catalog); `RoomEvent` adds `{kind:"look"; seat; rug; back}`; `ServerMessage` adds `{t:"streak"; pair: string; person: string; view: StreakView}` and `{t:"rematch"; code: string}`; `RoomView` adds optional `look?: {rug, back}` and `rematch?: string`; `ErrorCode` adds `"not_over" | "too_soon" | "not_unlocked"`.
- Produces (`GameModule`): `endsTurn(events: E[], seat: Seat): boolean` (Cat Tower: a `turn` event, or `roundOver` with `wentOut === seat`).
- Produces (`core.ts`): constructor option `features: { streaks: boolean }` (6th arg, default off); `type StreakIntent = { code; at; by: string | null; holder: string | null; players: string[]; turnedAt: Record<string, number>; over: boolean }`; `drainStreakIntents(): StreakIntent[]`; `type RematchIntent = { name; look; seats: SeatInfo[]; hostDeviceId }`; `drainRematch(): RematchIntent | null`; `rematchDealt(code): Outbound[]`; `rematchFailed(): void`; `setLook(deviceId, msg, allowed: (playerId: string) => {backs: string[]; rugs: string[]}): Outbound[]` (the DO resolves `allowed` first); `static rematchState(code, host, now, spec: RematchIntent): RoomState`; `deal(): Outbound[]`; `lookPlayers(deviceId): string[]`; `devicesFor(playerId): {deviceId, personId}[]`.

- [ ] **Step 1: Write the failing tests** in `core.streaks.test.ts` (100% of the new branches): with streaks off, `rematch` and `setLook` are `bad_message`, snapshots have no `look`, no intents queue. With streaks on: a human discard queues `{by: <player>, holder: <next player>}`; a draw alone queues nothing; a bot turn queues `by: null`; game over queues `over: true`; the cleanup tick queues `over: true`; `players` is deduped when one player holds two seats; `turnedAt` records the last turn per player. `setLook`: a default rug from a seated human broadcasts `look` and updates snapshots; an item the setter hasn't unlocked → `not_unlocked`; a second change within 10 s → `too_soon`; an unseated device → `not_seated`. `rematch`: before over → `not_over`; an unseated device → `not_seated`; the first one queues a `RematchIntent` with seats rotated by one, the room's name and look; a second request while pending is ignored; after `rematchDealt("NEWCD")` everyone gets `{t:"rematch",code}`, the snapshot carries `rematch`, and a late request gets the code back; `rematchFailed` lets a later request through. `rematchState` + `deal()` start a game at once with the given seats and look. Protocol: parse accepts `{t:"rematch"}`, `{t:"setLook", rug:"rug-night-sky"}`; rejects `{t:"setLook"}`, unknown ids, extra keys.
- [ ] **Step 2:** Run; FAIL.
- [ ] **Step 3: Implement.** Intents are pushed in `afterGameChange` (and the cleanup branch of `tick`) only when `features.streaks`.
- [ ] **Step 4:** Run the whole suite; core.ts stays 100%; existing tests unchanged and green. Add fixture samples in the separate streaks files.
- [ ] **Step 5:** Commit `feat(play-api): room streak intents, table looks and rematch (behind STREAKS)`.

### Task 5: The Pair DO, Player additions and glue

**Files:**
- Create: `src/streaks/pair.ts` (DO), `src/streaks/pairs.ts` (glue)
- Modify: `src/players/player.ts`, `src/players/accounts.ts`, `src/env.ts`, `src/index.ts`, `src/room/game-room.ts`, `src/room/tables.ts`, `wrangler.jsonc` (binding `PAIRS` → `Pair`, migration `v3`), `vitest.config.ts` (exclude the DO glue)

**Interfaces:**
- `Pair` DO: `init(state: PairState): void`; `report(r: TableReport, now): Record<string, StreakView> | null`; `view(playerId, now): StreakView | null`; `pause(by, days, now): boolean`; `unpause(by, now): boolean`; `openGift(by, id, now): boolean`; `setPerson(p: PairPerson, now)`; `unlocked(playerId)`; `exportState(): PairState | null`; `replace(state: PairState)`; `repoint(from, to)`; `destroy()`; `settle(now)` (also the alarm).
- `Player` additions: tables `pairs(pair_id PRIMARY KEY, partner_id, pinned, created_at)`, `left(partner_id PRIMARY KEY, at)`; meta `time_zone`, `last_look`. Methods `createPair(partner, now): {pairId, created} | null`, `storePair(pairId, partner, now): boolean`, `dropPair(pairId)`, `leavePair(pairId, now): string | null` (adds the tombstone), `pairList()`, `pairWith(partner)`, `pin(pairId): boolean`, `streakProfile(): PairPerson | null`, `setLastLook(look)`, `lastLook()`, `absorbPairs(rows)`. `touch` takes `timeZone`.
- `pairs.ts`: `reportTable(env, intent: StreakIntent, now): Promise<Record<string, {pair: string; view: StreakView}[]>>`; `myStreaks(env, me, now)`; `pairAction(env, me, pairId, run)`; `leavePair(env, me, pairId, now)`; `leaveAllPairs(env, me)`; `mergePairs(env, from, to, now)`; `syncPairPeople(env, playerId, now)`; `unlocksFor(env, playerIds)`.
- Routes (STREAKS on only): `GET /v1/me/streaks` → `{pairs: StreakView[]}` (pinned first, then longest count, then latest turn); `PUT /v1/pairs/{pair}/pause` `{days: 1-14}` → 204; `DELETE /v1/pairs/{pair}/pause` → 204; `POST /v1/pairs/{pair}/gifts/{id}/open` → 204; `PUT /v1/pairs/{pair}/pin` → 204; `DELETE /v1/pairs/{pair}` → 204. Unknown or foreign pair → 404. All take `?person=` like other `/v1/me` routes.

- [ ] **Step 1: Write the failing Miniflare tests** in `tests/streaks.test.ts` with entry `tests/streaks-entry.ts` (hook `/__test/settle?pair=&now=`): two phones play a turn each → both sockets get `{t:"streak"}` with `count: 1`, `me`/`them` true for the right person; `GET /v1/me/streaks` lists the pair with the partner's name and cat; pause 3 then `DELETE` pause; pin; leave → the pair is gone for both and doesn't re-form after more turns; a guest merge re-points the pair (and two guest pairs with the same partner merge into one); deleting the account removes the pair for the partner; a merged player in two seats forms no pair with themself; `setLook` with a default rug reaches both sockets as a `look` event; an unowned rug → `not_unlocked`; `rematch` deals a new room at once and both sockets get `{t:"rematch", code}`, and the new room is `playing`; settling via the hook after the day ends keeps the count. With `STREAKS` unset: the streak routes 404 and `setLook` is `bad_message`.
- [ ] **Step 2:** Run; FAIL.
- [ ] **Step 3: Implement.** `GameRoom.after()` drains streak intents into a per-instance promise chain, `ctx.waitUntil`, one retry, `console.error("streak_report_failed")` with no ids; views go to the sockets of devices whose players map holds that player, as `{t:"streak", pair, person, view}`. `merge()` calls `mergePairs` before the stub; `deleteMe` and `Player.expire` call `leaveAllPairs`. `uploadProfile` and `patchState` call `syncPairPeople` when STREAKS is on. A new room starts with the creator's `last_look` when STREAKS is on.
- [ ] **Step 4:** Run the whole suite, `typecheck`, `lint`.
- [ ] **Step 5:** Commit `feat(play-api): Pair durable object, streak routes and room reporting (behind STREAKS)`.
