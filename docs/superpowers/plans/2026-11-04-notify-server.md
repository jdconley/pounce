# Notifications and Pounce, server half (daily habit PR 5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The server half of §15 row 5: reminder alarms on `Player` (learned or fixed time), the last-chance reminder, caps, spacing, backoff and quiet hours; status, milestone, fresh-start, nap, win-back, paused and play-again pushes; the new "your move" copy; richer APNs payloads (§12.5, §12.7); pounces with limits, rests, targets and new-game creation; Messages links (`Links` DO, `/p/{token}` page, OG card, AASA); age-band rules and teen defaults; retention; WidgetKit push plumbing (§11.2). All behind `STREAKS`.

**Architecture:** Every decision is a pure function under `src/notify/` and `src/pounce/` over plain JSON state with the time passed in, unit-tested at 100% with a fake clock. The DOs only load, call, save and send: `Player` holds its notification state (one JSON meta row), the playtime histogram, pending deferred pushes and its pounces, and one alarm that is the earliest of retention, the next reminder slot, a deferred push and pounce pruning. `Pair` emits settlement events (`nap`, `winback`, `milestone`) that its glue turns into `Player.status` calls. `GameRoom` sends "your move" after the turn's streak report so the payload carries the pair's `streak` block and the "makes today count" copy. A new single-instance `Links` DO indexes pounce ids and link tokens.

**Tech Stack:** TypeScript, Cloudflare Workers + SQLite Durable Objects, vitest + v8 coverage, Miniflare, esbuild.

**Spec:** `docs/superpowers/specs/2026-11-04-daily-habit-design.md` (§2 anti-goals, §8.1–8.4 pushes, §10.4 play again, §11.2 widget push, §12 all, §13.2 Player and Links, §13.3 flows 4–5, §13.4 pounce routes and `/p/{token}`, §13.5, §14, §14.1, §15 row 5, §16). Base: `docs/superpowers/plans/2026-11-04-server-streaks.md` (PR 3).

## Global Constraints

- **Amended after review:** everything new here that sends or accepts something is behind a second flag, `NOTIFY` (on only with `STREAKS` on too; never in `wrangler.jsonc`; tests set it), because PR 4 turns `STREAKS` on before PR 5's app half exists. With `STREAKS` on and `NOTIFY` off, behavior equals PR 3's (tested). The `Links` binding and migration `v4` are unconditional.
- Everything new is behind `STREAKS` (`"on"`, `"1"`, `"true"`). With it unset: no new routes (404), `/p/*` is 404, AASA lists only `/j/*`, "your move" keeps the base payload and copy (`Your turn at <table>`), the `Player` alarm does only retention, and every existing suite passes unchanged.
- Copy: no emoji, no countdowns, no guilt or blame (§2, §12.2). Never "waiting on you", "don't break", "you missed". Titles: the recipient's own name for your move, reminders, last chance, fresh start, going quiet and pounce; the pounce sender's name for "pounce answered"; for streak status pushes the table's name when the pair has exactly one shared table, else the partner's name.
- Caps (§12.1): reminder-type pushes (daily, last chance, fresh start; going quiet counts too) at most 2 a day; spacing at most one push every 20 minutes for every kind except `your_move`, `pounce` and `pounce_answered`; in quiet hours reminders never go out and everything else is `passive`.
- Timing (§12.3): auto = 15 minutes before the weighted median of the first-turn-of-the-day histogram (48 half-hour buckets × weekday/weekend, decay ×0.85 a day), 19:30 until 5 days of data; fixed = weekday and weekend times; clamped outside quiet hours and at least 2 h before quiet start. Last chance 90 minutes before quiet start, streak ≥ 3. Default quiet 22:00–08:00.
- Backoff (days with no turn at a shared table): ≥ 2 no last chance; ≥ 4 daily every other day; ≥ 7 one "The cats will keep your seat warm." then nothing. A turn resets it.
- Pounce limits (§12.4): 3 an hour from one person to another; 1 h rest after "no"; 3 h rest after 3 unanswered in a row. Link tokens 16 random bytes, single use, 24 h. Pounces kept 7 days.
- Age bands (§14.1): kitten — no server push of any kind (alerts, background, widget), no histogram, no links, may send in-app pounces; teen — reminders, last chance and learned timing off by default, quiet 21:00–08:00, nothing at all 00:00–06:00.
- APNs (§12.5, §12.7): categories `YOUR_MOVE`, `REMINDER`, `POUNCE`, `STATUS`; `interruption-level` `active`/`passive` (never time-sensitive); `relevance-score` your move 1.0, pounce 0.9, reminders 0.6, status 0.2; `thread-id` room code / `pair:<pairId>` / `pounce:<pairId>`; collapse id ≤ 64 bytes; `mutable-content: 1`; `badge` = tables where it's your move; `from`; `streak` block.
- No ids, tokens or names in logs. Pure modules (`src/notify/**`, `src/pounce/**`, `src/streaks/**`, `src/room/core.ts`) at 100% coverage; new DO glue excluded like the others and covered by Miniflare.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Only `apps/play-api` and this plan change.

## Decisions where the spec is silent (each also goes in the report)

1. **Settings keys** (synced `settings` section): `reminders.on` (bool), `reminders.auto` (bool), `reminders.weekday` / `reminders.weekend` (`{h, m}`), `quiet.start` / `quiet.end` (`{h, m}`), `lastChance.on` (bool). Separate keys so last-writer-wins per key works per dial.
2. **The bell toggle** (`reminders.on`) silences every reminder-type push (daily, last chance, fresh start, going quiet); `lastChance.on` additionally silences last chance.
3. **Histogram** is recorded only while auto timing is on, never for kittens (minimal profiling); its "5 days of data" counts days across both day types; a day type with no data uses the other's median.
4. **Reminder subject** is the top pair (pinned, else longest count, then latest turn) among pairs that aren't paused, and its move must be at a table shared with that partner.
5. **"Opened the app"** = the player's latest profile upload (`touch`), which the app sends on launch and foreground (§6.3).
6. **Fresh start** fires at the daily slot on the first Monday or 1st after the break day (`brokeOn`, new in `Pair`), takes that day's daily slot, and has a month variant: "New month, new deal. One turn starts a streak with Mia."
7. **Spacing-deferred pushes** retry at the end of the 20 minutes; reminders give up at quiet hours; status pushes blocked by a teen's night are held until 06:00 local.
8. **Milestone** goes to members with no awake device at the reporting table (both, when settled by alarm).
9. **Play again**: "Mia dealt a new game." goes to the new table's other human players, except the first mover (who gets "your move") and anyone awake in the old room.
10. **Pounce `to`** is a pair id, not a player id: player ids never reach other players (PR 3 kept them out of views). Thread id `pounce:<pairId>` for the same reason.
11. **Link pounces** target only `"new"` or `"pick"`; the link token is consumed by the first answer; links count 3 an hour per sender.
12. **A pounce is answerable for 24 h**; `sent` and `waiting` show for 1 h (the widget's "until the hour passes"). Answers are idempotent; "play" is never downgraded.
13. **New-game seating**: the answerer takes seat 1 (Cat Tower's first move), the sender seat 0; name is the code's default name; look is the sender's last-used look.
14. **New error codes**: 429 `resting` (with `until`), 409 `not_shared`, 410 `expired`, 403 `not_allowed`.
15. **WidgetKit push** is included: route, storage, send, 15-minute throttle per device, kitten block; triggered for a pair's other person after a turn, on settlement events, on pause, and on a pounce answer. Skipped when the device got an alert in the last minute.
16. **Payload priority**: `apns-priority` 10 for active, 5 for passive.
17. **More copy lines** to reach seven of each rotated kind, so "no repeat within 7 days" holds (JD reviews them).

## Review Focus

1. **A player with no time zone or no pairs** — the reminder alarm must not throw or loop; it falls back to `America/Los_Angeles` and re-arms for tomorrow. Test in Task 4 (pure) and Task 8 (alarm with no pairs).
2. **Quiet hours that wrap midnight or are degenerate** (start = end, or start before 04:00) — `inQuiet` and the clamp stay sane. Tests in Tasks 1–2.
3. **DST days** — slot instants on 2026-03-08 and 2026-11-01 land at the wall-clock time. Test in Task 2.
4. **Retried pounce answers** (the app's background retry) — same result, no second game, no second push. Test in Task 9.
5. **STREAKS off** — base payload byte for byte, no new routes, AASA unchanged, `/p/` 404. Tests in Tasks 5, 8, 9.

---

### Task 1: Notification settings and the send gate

**Files:** Create `src/notify/settings.ts`, `src/notify/policy.ts`, tests beside them. Modify `vitest.config.ts` (100% thresholds for `src/notify/**`, `src/pounce/**`).

**Interfaces (Produces):**
- `type NotifySettings = { reminders: boolean; auto: boolean; weekday: number; weekend: number; quietStart: number; quietEnd: number; lastChance: boolean }` (times in minutes after local midnight); `notifySettings(settings: Section, band: AgeBand | null): NotifySettings`.
- `type NotifyKind = "your_move" | "pounce" | "pounce_answered" | "reminder" | "last_chance" | "fresh_start" | "going_quiet" | "nap" | "winback" | "paused" | "milestone" | "play_again"`; `type Level = "active" | "passive"`; `isReminder(kind)`, `isSpaced(kind)`, `SPACING_MS`, `MAX_REMINDERS`.
- `inQuiet(minutes: number, s: Pick<NotifySettings, "quietStart" | "quietEnd">): boolean`.
- `gate(i: { kind; band; zone; settings; now; spacedAt: number | null; remindersToday: number }): { send: true; level: Level } | { send: false; retryAt: number | null }`.

- [ ] **Step 1: Failing tests.** Defaults: adult `{reminders: true, auto: true, weekday: 1170, weekend: 1170, quietStart: 1320, quietEnd: 480, lastChance: true}`; teen reminders/auto/lastChance false, quietStart 1260; kitten all off. Synced values override, malformed ones fall back. `inQuiet`: 22:00–08:00 → 23:00 and 07:59 true, 08:00 and 21:59 false; start = end → never. `gate`: kitten → `{send:false, retryAt:null}`; teen at 02:00 → reminder null, status retry at 06:00 local; reminder with `reminders` off, in quiet, or 2 already today → null; spaced kind within 20 min → retry at `spacedAt + 20 min`; `your_move`/`pounce` ignore spacing; `nap` always passive; `your_move` passive in quiet, active outside.
- [ ] **Step 2:** `pnpm --filter @pounce/play-api exec vitest run src/notify`; FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** PASS. **Step 5:** Commit `feat(play-api): notification settings and send gate`.

### Task 2: Playtime histogram and reminder times

**Files:** Create `src/notify/playtime.ts`, `src/notify/schedule.ts`, tests.

**Interfaces (Produces):**
- `type Playtime = { weekday: number[]; weekend: number[]; days: { weekday: number; weekend: number }; lastDay: Day | null }`; `emptyPlaytime()`; `dayType(day: Day): "weekday" | "weekend"`; `recordPlay(p: Playtime, at: number, zone: string): void` (first turn of its day only; decay ×0.85 per day since `lastDay`); `learnedMinutes(p, type): number | null` (bucket start of the weighted median in day order from 04:00, i.e. bucket midpoint − 15 min; null under 5 days).
- `DEFAULT_REMINDER = 1170`; `reminderMinutes(day: Day, s: NotifySettings, p: Playtime | null): number` (clamped); `lastChanceMinutes(s): number`; `slotAt(day: Day, minutes: number, zone: string): number` (minutes before 04:00 run into the next date).

- [ ] **Step 1: Failing tests.** Five weekday turns at 20:10 → weekday learned 20:00; four → null → 19:30; turns at 23:40 and 00:20 across the 04:00 boundary order correctly (median in day order); decay: an old habit at 08:00 loses to three newer days at 21:00 after 10 days; a second turn the same day doesn't count; weekend falls back to weekday's median. Clamp: 21:30 with quiet 22:00 → 20:00; 06:00 with quiet end 08:00 → 08:00; quiet 10:00–12:00 → 08:00. `lastChanceMinutes` = 20:30. `slotAt` on 2026-03-08 and 2026-11-01 in LA gives 19:30 local wall time; `slotAt(d, 30)` lands on the next date.
- [ ] **Steps 2–4:** FAIL, implement, PASS. **Step 5:** Commit `feat(play-api): playtime histogram and reminder times`.

### Task 3: Copy and rotation

**Files:** Create `src/notify/copy.ts`, test.

**Interfaces (Produces):** `days(n): string` ("1 day"/"n days"); `yourMoveBody(from: string | null, table: string, completesToday: boolean)`; `pounceBody(from: string, target: { table: string } | "new" | "pick")`; `answeredBody(who, answer)`; `napBody(count)`, `winbackBody(count)`, `pausedBody(who, days)`, `milestoneBody(n)`, `playAgainBody(who)`, `freshStartBody(partner, month: boolean)`, `GOING_QUIET`; `type LineCtx = { table: string | null; partner: string; count: number }`; `DAILY_LINES`, `LAST_CHANCE_LINES` (each `{ id; needs: ("table" | "count")[]; text(c: LineCtx): string }`, seven or more); `pickLine(lines, ctx, used: Record<string, number>, cursor: number, now): { id: string; text: string; cursor: number } | null`.

- [ ] **Step 1: Failing tests.** The §12.2 strings exactly ("Mia played. Your move at Couch Cats.", "Mia played. Your turn makes today count.", "Mia wants to play. Couch Cats?" / "New game?" / "You pick.", "JD is coming." / "JD: in a bit." / "JD: not now.", "A cat nap covered yesterday. 12 days and counting.", "Two days in a row brings 12 back.", "Mia put the cats to bed for 3 days.", "30 days together. There's a gift on the rug.", "Mia dealt a new game.", "New week, new deal. One turn starts a streak with Mia.", "The cats will keep your seat warm."); no-mover your move "Your move at Couch Cats."; every line has no emoji (`/\p{Extended_Pictographic}/u`) and none of the banned phrases; `pickLine` round-robins, skips lines whose needs aren't met, never repeats within 7 days while another eligible line is older, and falls back to the least recently used.
- [ ] **Steps 2–4.** **Step 5:** Commit `feat(play-api): notification copy and rotation`.

### Task 4: Reminder decisions

**Files:** Create `src/notify/reminders.ts`, `src/notify/reminders.test.ts`.

**Interfaces:**
- Consumes Tasks 1–3, `Day` helpers, `StreakBlock` from Task 5's `payload.ts` (define the type in `reminders.ts`'s sibling `src/notify/types.ts`: `StreakBlock = { pair; count; me; them; naps; myMove: string[]; theirMove: string[] }`, `Outgoing = { kind; title; body; code?; thread; collapse; from?: {name, cat}; streak?: StreakBlock; data?: Record<string, Json> }`).
- Produces: `type NotifyState = { day: Day | null; reminders: number; spacedAt: number | null; decided: { daily: Day | null; lastChance: Day | null }; lastTurnDay: Day | null; lastDailyDay: Day | null; quietSent: boolean; lines: Record<string, number>; cursor: { daily: number; lastChance: number }; freshStart: string[]; playtime: Playtime }`; `emptyNotifyState()`; `type PairFacts = { pair; partner: string; count; me: boolean; kept: boolean; paused: boolean; myMove: string[]; breakId: number; brokeOn: Day | null; pinned: boolean; lastTurnAt: number; streak: StreakBlock }`; `type ReminderInput = { now; zone; band; settings: NotifySettings; name: string; lastOpenAt: number | null; pairs: PairFacts[]; tableNames: Record<string, string> }`; `dueSlots(st, i): ("daily" | "lastChance")[]`; `decide(st, i, slot): { push: Outgoing | null; retryAt: number | null }` (marks the slot decided unless retrying; counts and spaces what it returns); `nextWake(st, i): number`; `noteTurn(st, at, zone, learn: boolean): void`; `noteSent(st, kind, now, zone): void`; `freshStartDay(brokeOn: Day): Day`.

- [ ] **Step 1: Failing tests** (fake clock, LA): daily at 19:30 when the top pair isn't kept, you aren't in and it's your move → push `{kind: "reminder", title: "JD", thread: "pair:<id>", collapse: "reminder:<id>"}`; skipped when kept, in, not your move, opened within 2 h, paused (falls to the next pair), reminders off, or no pairs; one decision per slot per day; last chance at 20:30 only with count ≥ 3; at most 2 reminder-type pushes a day; spacing defers to +20 min; backoff 2 → no last chance, 4 → daily every other day, 7 → one going-quiet then nothing, a turn resets; fresh start on the first Monday after a break (and on a 1st that comes first), once per break, only while count is 0; `nextWake` after both slots is tomorrow's daily; a player with no zone uses LA; kitten never pushes; teen gets nothing by default and the fixed time when turned on.
- [ ] **Steps 2–4.** **Step 5:** Commit `feat(play-api): reminder decisions, caps and backoff`.

### Task 5: APNs payloads and widget push

**Files:** Create `src/notify/payload.ts`, `src/notify/types.ts`; modify `src/push/apns.ts`, `src/push/apns.test.ts`; create `fixtures/push/payloads.json` (checked by `tests/push-fixtures.test.ts`, regenerated with `UPDATE_FIXTURES=1`).

**Interfaces (Produces):** `category(kind)`, `relevance(kind)`, `collapseId(raw): string` (≤ 64 bytes), `MAX_CODES = 10`, `apnsBody(o: Outgoing, level: Level, badge: number): Record<string, unknown>`; in `apns.ts`: `ApnsPayload` adds `{ alert: Record<string, unknown>; collapseId: string; level: Level }` and `{ widget: true }`; `pushAlert(env, token, body, collapseId, level, fetcher?, nowSec?)`; `pushWidget(env, token, fetcher?, nowSec?)` (topic `<APNS_TOPIC>.push-type.widgets`, type `widgets`, priority 5, body `{"aps":{"content-changed":true}}`).

- [ ] **Step 1: Failing tests.** The §12.7 sample shape for `your_move`; passive status omits `sound` and has priority 5; `badge`; `from`; `streak` codes capped at 10; collapse ids over 64 bytes are shortened deterministically; the legacy `{title, body, code}` payload is unchanged byte for byte; widget push headers and body.
- [ ] **Steps 2–4.** **Step 5:** Commit `feat(play-api): rich APNs payloads and widget push`.

### Task 6: Pounce rules

**Files:** Create `src/pounce/limits.ts`, `src/pounce/parse.ts`, tests.

**Interfaces (Produces):** `type Answer = "play" | "later" | "no"`; `type Target = { table: string } | "new" | "pick"`; `type PounceRow = { id; to: string | null; target: Target; at: number; answer: Answer | null; answeredAt: number | null; code: string | null; quiet: boolean }`; `PER_HOUR = 3`, `NO_REST_MS`, `UNANSWERED_REST_MS`, `LIVE_MS`, `ANSWER_MS`, `KEEP_MS`; `restingUntil(rows: PounceRow[], now): number | null`; `type PounceView = { sent: boolean; resting: boolean; quiet: boolean; answer: Answer | null; code: string | null; waiting: { id: string; target: Target } | null }`; `pounceView(mine, theirs, now): PounceView`; `answerable(row, now): boolean`; `nextAnswer(row, answer): boolean` (false when it would downgrade "play" or repeat); `POUNCE_ID = /^pc_[A-Za-z0-9_-]{22}$/`, `LINK_TOKEN = /^[A-Za-z0-9_-]{22}$/`; `parsePounce(body): { to: string | null; target: Target } | null`; `parseAnswer(body): { answer: Answer; choice: string | null; link: string | null } | null`.

- [ ] **Step 1: Failing tests.** 3 in an hour → resting until the oldest + 1 h; a "no" → resting 1 h from the answer; 3 unanswered in a row → 3 h from the third, an answer clears it; `pounceView` `sent` within the hour only, `waiting` = their latest unanswered within the hour; `answerable` within 24 h; parse accepts the §13.4 bodies, rejects extra keys, bad codes, `choice` without `"pick"`.
- [ ] **Steps 2–4.** **Step 5:** Commit `feat(play-api): pounce limits and parsing`.

### Task 7: Pair events and facts

**Files:** Modify `src/streaks/pair-core.ts`; create `src/streaks/pair-core.notify.test.ts`.

**Interfaces (Produces):** `type PairEvent = { kind: "nap" | "winback" | "milestone"; count: number }`; `PairState.events?: PairEvent[]`; `drainEvents(s): PairEvent[]`; `Streak.brokeOn?: Day | null`; `facts(s, playerId, now): { view: StreakView; in: boolean; paused: boolean; breakId: number; brokeOn: Day | null; lastTurnAt: number; tables: string[] }`; `StreakView.pounce` widens to `PounceView`.

- [ ] **Step 1: Failing tests.** A settled nap queues `{nap, count}`; win-back queues `{winback}`; reaching 3 queues `{milestone, 3}` once; a break sets `brokeOn`; `facts.in` is true after your own turn and before any paw shows; `paused` reflects today.
- [ ] **Steps 2–4.** **Step 5:** Commit `feat(play-api): pair events and notification facts`.

### Task 8: Delivery glue — devices, Player reminders and status, rooms, pairs

**Files:** Create `src/notify/deliver.ts`; modify `src/room/device-index.ts`, `src/room/core.ts` (`YourTurnIntent.from`, `awakePlayers()`), `src/room/game-room.ts`, `src/players/player.ts`, `src/streaks/pair.ts`, `src/streaks/pairs.ts`, `src/index.ts` (`PUT /v1/devices/me/widget-push`), `vitest.config.ts`; tests `src/room/core.notify.test.ts`, `tests/notify.test.ts`, `tests/notify-entry.ts`.

**Interfaces:**
- `DeviceIndex.pushAlert(body, collapseId, level, playerBand): Promise<{sent}>`, `setWidgetToken(token)`, `pokeWidget(now): Promise<{sent}>`.
- `deliver.ts`: `type PushProfile = { id; name; band; zone; settings: NotifySettings; devices: string[] }`; `deliverToPlayer(env, profile, o: Outgoing, level: Level, extraCode?: string): Promise<boolean>` (badge per device from `deviceTables`); `pokeWidgets(env, playerId)`.
- `Player`: `pushProfile()`, `status(o: Outgoing & { shared?: string[]; partner?: string }, now)`, `recordTurn(at, now)`, `remind(now)` (the alarm's reminder pass; also `/__test` hook), `notifyState()`; alarm = min(retention, next reminder slot, deferred push).
- `GameRoom`: with STREAKS, "your move" goes after the turn's streak report with the new copy, `from`, `streak` and quiet-hours level; play again pushes.
- `Pair`: `facts(playerId, now)`; events dispatched through `pairs.ts` `dispatchEvents(env, s, events, awake)`; `pause` sends "paused" to the other person.

- [ ] **Step 1: Failing tests.** Core: `from` is the last human mover; `awakePlayers`. Miniflare (fake APNs via `outboundService`): with STREAKS, your move carries category, level, badge, `from`, `streak`; with it off, the base payload; reminder hook at 19:30 sends one reminder, a second call sends nothing; a kitten device gets nothing; a teen at 02:00 nothing; pause pushes the partner; widget token route stores and a turn pokes the partner's widget once in 15 minutes.
- [ ] **Steps 2–4.** **Step 5:** Commit `feat(play-api): reminder alarms, status pushes and rich your-move (behind STREAKS)`.

### Task 9: Pounces, Links and `/p/{token}`

**Files:** Create `src/links/links.ts` (DO), `src/pounce/pounces.ts` (glue); modify `src/players/player.ts` (pounce rows), `src/http/links.ts` (`pouncePage`, AASA), `src/index.ts`, `src/env.ts`, `wrangler.jsonc` (binding `LINKS` → `Links`, migration `v4`), `src/room/game-room.ts` (`initDealt`), `src/streaks/pairs.ts` (views' `pounce`); tests `src/http/links.test.ts`, `tests/pounce.test.ts`.

**Interfaces:** Routes (STREAKS only): `POST /v1/pounces` `{to?: pairId, target}` → 201 `{id, link?}`; `POST /v1/pounces/{id}/answer` `{answer, choice?, link?}` → 200 `{code?}`; `GET /v1/pounces/links/{token}` → `{id, from: {name, cat}, target}`; public `GET /p/{token}`, `GET /og/pounce.jpg`. `Links` DO: `put(key, kind: "pounce" | "link", playerId, pounceId, expires)`, `get(key, now)`, `take(key, now)`, `removePlayer(id)`, alarm prunes.

- [ ] **Step 1: Failing tests.** Push pounce reaches the partner with category `POUNCE`, the copy and `pounce` data; a 4th within the hour → 429 `resting`; "no" rests 1 h; answering "play" on "new" deals a room seating both and pushes "JD is coming."; a retried answer returns the same code and pushes nothing; "later" and "no" copy; a table target must be shared (409); link pounce returns `https://play.conleychaos.com/p/<token>`, preview works, `/p/<token>` serves the sender's name and OG tags, the answer consumes the token, a second use 404s; a kitten can push-pounce but gets 403 for a link and its device gets no pounce push; views carry `pounce.sent`/`resting`/`waiting`; STREAKS off → all 404, AASA unchanged.
- [ ] **Steps 2–4.** **Step 5:** Commit `feat(play-api): pounces, Messages links and the /p page (behind STREAKS)`.

### Task 10: Retention, deletion and merge

**Files:** Modify `src/players/player.ts`, `src/players/accounts.ts`; tests in `tests/pounce.test.ts`.

- [ ] **Step 1: Failing tests.** Pounces older than 7 days are pruned at the alarm; expired link rows are gone after 24 h; deleting an account removes its `Links` rows; a merge drops the guest's pounces and links.
- [ ] **Steps 2–4.** Run the whole suite, `typecheck`, `lint`. **Step 5:** Commit `feat(play-api): pounce retention`.
