# Pounce Server (play-api) Implementation Plan — Plan 1 of 3

> **Historical note:** this plan was written for, and executed inside, the private `everything` monorepo. The code then moved to this standalone repo before its first deploy. Monorepo-specific steps (target manifests, `affected-targets.mjs`, `deploy-sites.yml`) are replaced here by `.github/workflows/ci.yml`; the package is now `@pounce/play-api`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Cloudflare backend for Pounce's first game, Cat Tower (M1 "Play together"): an authoritative 10-phase rules engine, a House Cat bot, per-game Durable Objects with live WebSockets, guest device identity, share links, and "your turn" push.

**Architecture:** One Worker (`apps/play-api`) on `play.conleychaos.com`. A pure TypeScript rules engine (`src/rules/`) is wrapped by a pure room state machine (`src/room/core.ts`) that the `GameRoom` Durable Object (SQLite, WebSocket Hibernation, one alarm) persists and broadcasts. A `DeviceIndex` Durable Object per device holds its APNs token and its list of tables. Nothing needs D1 in M1.

**Tech Stack:** TypeScript, Cloudflare Workers + SQLite Durable Objects, wrangler/vitest/miniflare/esbuild from the pnpm catalog, WebCrypto (HMAC tokens, ES256 APNs JWT).

**Spec:** `docs/superpowers/specs/2026-10-31-pounce-cat-tower-design.md`

**Plan series:** 1 = this server (M1). 2 = iOS app + art (M1), consumes the protocol defined here. 3 = M2 social (Sign in with Apple, groups, D1, Nearby, nudges, reactions, Kitten/Alley Cat, bot-takeover vote).

## Global Constraints

- Lives in the `everything` monorepo at `apps/play-api`, package `@meanwhileso/play-api`, `targetId: app:play-api`, `kind: internal-app`. Work on a branch in a worktree; `main` deploys on merge.
- Tool versions come from the pnpm catalog (`catalog:`): wrangler, vitest, @vitest/coverage-v8, miniflare, typescript, @cloudflare/workers-types, @types/node, esbuild. No new third-party runtime dependencies; new dev packages must satisfy `minimumReleaseAge` (7 days).
- TDD for every task. `tsconfig.json` extends `../../tsconfig.base.json` with types `["@cloudflare/workers-types","node"]`.
- Server is authoritative. A device never receives the hand of a seat it does not control.
- 2–6 seats. Deck of 108: numbers 1–12 × 4 coats × 2 copies, 8 Yarn (wild), 4 Cucumber (skip). Coats: `tabby`, `tuxedo`, `calico`, `gray`.
- Scoring: 1–9 = 5, 10–12 = 10, Cucumber = 15, Yarn = 25.
- Bundle ID `com.conleychaos.play`; Apple team `B222J9J7B8`; domain `play.conleychaos.com`; share link `https://play.conleychaos.com/j/<CODE>`.
- Games inactive 7 days are deleted. No turn timer.
- Secrets never in code: `TOKEN_SECRET`, `APNS_KEY_P8`, `APNS_KEY_ID` come from 1Password via the deploy pipeline (`cloudflare-deploy-automation` skill).
- No user-facing English beyond push text and the link landing page; the app renders everything else from data.

## Review Focus

1. **Reconnect mid-turn** — a device that drops after drawing and reconnects gets a snapshot with `turnStep: "play"` and the drawn card in hand; it can discard normally. (Task 10 test.)
2. **Out-of-turn, duplicate, or stale actions** — two devices or a double-tap send the same action; exactly one applies, the other gets `error: not_your_turn`/`bad_step` and state is unchanged. (Task 3 + Task 10 tests.)
3. **Deck exhaustion** — draw pile empty: reshuffle discard except its top; if that leaves nothing to draw, the round ends with nobody going out (players who laid down still advance). (Task 3 test.)
4. **Malformed or oversized WebSocket messages** — non-JSON, unknown `t`, or > 8 KB: reply `error: bad_message`, keep the socket open, change nothing. (Task 8 + Task 11 tests.)
5. **Host disconnects in the lobby** — any other human device in the room may configure seats and start; "host" is only the creator's default privilege, not a requirement. (Task 9 test.)

---

## File Structure

```
apps/play-api/
  package.json, tsconfig.json, vitest.config.ts, wrangler.jsonc, target.manifest.json
  src/
    rules/rng.ts          seeded PRNG + shuffle
    rules/cards.ts        card ids, faces, deck, points
    rules/groups.ts       set/run/coat validation, hit-fit
    rules/phases.ts       the 10 phases + layDown matching
    rules/engine.ts       CatTowerState, newGame/applyAction (draw, discard, skip, layDown, hit, round end, scoring, win)
    rules/view.ts         CatTowerView per controlled seats; event privacy filter
    rules/solver.ts       find a phase / hits in a hand (used by bot)
    bots/house-cat.ts     chooseAction()
    games/module.ts       GameModule interface (future games)
    games/cat-tower.ts    GameModule adapter
    protocol.ts           Client/Server message types + parseClientMessage()
    auth.ts               device token issue/verify (HMAC)
    room/codes.ts         room code generator
    room/core.ts          RoomCore: lobby, seats, play loop, presence, timers (pure)
    room/game-room.ts     GameRoom DO (persistence, hibernating WS, alarm, push trigger)
    room/device-index.ts  DeviceIndex DO (apns token, tables list)
    push/apns.ts          ES256 JWT + send
    http/links.ts         apple-app-site-association + /j/:code page
    index.ts              Worker router
  fixtures/groups.json    shared validation vectors (consumed by iOS in Plan 2)
  tests/sim.test.ts       bot-vs-bot simulation
  tests/worker.test.ts    Miniflare integration
```

---

### Task 1: Scaffold app, RNG, cards, deck

**Files:**
- Create: `apps/play-api/{package.json,tsconfig.json,vitest.config.ts}`, `src/rules/rng.ts`, `src/rules/cards.ts`
- Test: `src/rules/cards.test.ts`, `src/rules/rng.test.ts`

**Interfaces:**
- Produces:
  - `type Rng = () => number` (0 ≤ n < 1); `createRng(seed: number): Rng` (mulberry32); `shuffle<T>(items: readonly T[], rng: Rng): T[]` (Fisher–Yates, returns new array).
  - `type CardId = number` (0–107). `type Coat = "tabby" | "tuxedo" | "calico" | "gray"`; `COATS: readonly Coat[]` in that order.
  - `type Card = { id: CardId; kind: "number"; value: number; coat: Coat } | { id: CardId; kind: "yarn" } | { id: CardId; kind: "cucumber" }`.
  - `card(id: CardId): Card` — ids 0–95: `coat = COATS[Math.floor(id / 24)]`, `value = (id % 12) + 1`; 96–103 yarn; 104–107 cucumber.
  - `ALL_CARD_IDS: readonly CardId[]` (0..107); `cardPoints(id: CardId): number`.

- [ ] **Step 1:** Copy the `package.json` scripts/devDependencies shape from `apps/deploy-broker/package.json` (name `@meanwhileso/play-api`, add `esbuild: "catalog:"`), `tsconfig.json` from the same app, and a `vitest.config.ts` with coverage include `src/**/*.ts`, thresholds 100% for `src/rules/**` and `src/room/core.ts`, 90% overall. Run `pnpm install` at repo root.
- [ ] **Step 2: Write failing tests**

```ts
test("deck has 108 cards: 96 numbers, 8 yarn, 4 cucumber", () => {
  const cards = ALL_CARD_IDS.map(card);
  expect(cards.filter(c => c.kind === "number")).toHaveLength(96);
  expect(cards.filter(c => c.kind === "yarn")).toHaveLength(8);
  expect(cards.filter(c => c.kind === "cucumber")).toHaveLength(4);
});
test("each number 1-12 appears exactly twice per coat", () => {
  for (const coat of COATS) for (let v = 1; v <= 12; v++)
    expect(ALL_CARD_IDS.map(card).filter(c => c.kind === "number" && c.coat === coat && c.value === v)).toHaveLength(2);
});
test("points", () => {
  expect(cardPoints(0)).toBe(5);   // tabby 1
  expect(cardPoints(9)).toBe(10);  // tabby 10
  expect(cardPoints(96)).toBe(25); // yarn
  expect(cardPoints(104)).toBe(15);// cucumber
});
test("shuffle is deterministic per seed and a permutation", () => {
  const a = shuffle(ALL_CARD_IDS, createRng(42)), b = shuffle(ALL_CARD_IDS, createRng(42));
  expect(a).toEqual(b); expect([...a].sort((x, y) => x - y)).toEqual([...ALL_CARD_IDS]);
  expect(shuffle(ALL_CARD_IDS, createRng(43))).not.toEqual(a);
});
```

- [ ] **Step 3:** Run `pnpm --filter @meanwhileso/play-api test:unit` → FAIL (modules missing).
- [ ] **Step 4:** Implement `rng.ts` and `cards.ts` per Interfaces.
- [ ] **Step 5:** Run tests → PASS.
- [ ] **Step 6:** Commit `feat(play-api): scaffold app with cards, deck, seeded rng`.

---

### Task 2: Group validation, phases, shared fixtures

**Files:**
- Create: `src/rules/groups.ts`, `src/rules/phases.ts`, `fixtures/groups.json`
- Test: `src/rules/groups.test.ts`, `src/rules/phases.test.ts`

**Interfaces:**
- Consumes: `card`, `CardId`, `Coat` (Task 1).
- Produces:
  - `type GroupKind = "set" | "run" | "coat"`.
  - `type Group = { kind: "set"; cards: CardId[]; value: number } | { kind: "run"; cards: CardId[]; start: number; end: number } | { kind: "coat"; cards: CardId[]; coat: Coat }` — `cards` stored in display order (runs ascending, Yarn placed at the value it stands for).
  - `type Requirement = { kind: GroupKind; size: number }`.
  - `PHASES: readonly (readonly Requirement[])[]` — index 0 = phase 1:
    `[[set3,set3],[set3,run4],[set4,run4],[run7],[run8],[run9],[set4,set4],[coat7],[set5,set2],[set5,set3]]`.
  - `buildGroup(req: Requirement, cards: CardId[], runStart?: number): Group | null` — null if invalid. Rules: exactly `req.size` cards; no Cucumbers; at least one natural card; set = all naturals same value; coat = all naturals same coat; run = consecutive, within 1..12, no wrap; for runs with Yarn, `runStart` chooses placement, default = the lowest start that fits.
  - `canHit(group: Group, id: CardId): { ok: true; group: Group } | { ok: false }` — set: same value or Yarn; coat: same coat or Yarn; run: value `start-1` or `end+1` within 1..12, or Yarn (extends `end` if `end < 12`, else `start`).
  - `matchPhase(phaseIndex: number, groups: { cards: CardId[]; runStart?: number }[]): Group[] | null` — groups in `PHASES[phaseIndex]` order.

- [ ] **Step 1: Write failing tests** (each also written as a vector into `fixtures/groups.json` as `{ "name", "req", "cards", "runStart"?, "valid" }` so the Swift client can replay them):
  - `set of 3 with one yarn is valid`; `set of 3 all yarn is invalid`; `set with a cucumber is invalid`.
  - `run 3-4-5-6 valid`; `run 10-11-12 + yarn defaults to start 9`; `run 11-12-1 (wrap) invalid`; `run with duplicate value invalid`; `run 2,yarn,4,5 valid with start 2`.
  - `coat of 7 tuxedo with two yarn valid`; `coat mixing tabby and gray invalid`.
  - `canHit run 3..6 accepts 2 and 7, rejects 5`; `canHit run 9..12 with yarn extends start to 8`; `canHit set of 7s rejects cucumber`.
  - `matchPhase(0, two sets of 3) returns 2 groups`; `matchPhase(1, groups in wrong order) returns null`; `matchPhase(3, run of 7) ok, run of 6 null`.
  - A vitest that loads `fixtures/groups.json` and asserts `buildGroup(...) !== null === valid` for every vector.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement `groups.ts`, `phases.ts`.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(play-api): group validation, phases, shared fixtures`.

---

### Task 3: Engine core — deal, draw, discard, Cucumber, reshuffle

**Files:**
- Create: `src/rules/engine.ts`
- Test: `src/rules/engine.turns.test.ts`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces:
  - `type Seat = number` (0-based).
  - `type CatTowerState = { seats: number; phase: number[] /* 0..10, 10 = finished all */; scores: number[]; round: number; dealer: Seat; deck: CardId[]; discard: CardId[] /* last = top */; hands: CardId[][]; laid: (Group[] | null)[]; turn: Seat; step: "draw" | "play"; pendingSkip: boolean[]; status: "playing" | "roundOver" | "gameOver"; winners: Seat[]; seed: number; rngCalls: number }`.
  - `type Action = { type: "draw"; from: "deck" | "discard" } | { type: "layDown"; groups: { cards: CardId[]; runStart?: number }[] } | { type: "hit"; card: CardId; target: { seat: Seat; group: number } } | { type: "discard"; card: CardId; skipTarget?: Seat } | { type: "nextRound" }`.
  - `type GameEvent = { kind: "roundStarted"; round: number; dealer: Seat } | { kind: "drew"; seat: Seat; from: "deck" | "discard"; card?: CardId } | { kind: "laidDown"; seat: Seat; groups: Group[] } | { kind: "hit"; seat: Seat; card: CardId; target: { seat: Seat; group: number }; group: Group } | { kind: "discarded"; seat: Seat; card: CardId; skipTarget?: Seat } | { kind: "skipped"; seat: Seat } | { kind: "turn"; seat: Seat } | { kind: "reshuffled"; deckCount: number } | { kind: "roundOver"; wentOut: Seat | null; points: number[]; advanced: Seat[]; scores: number[]; phase: number[] } | { kind: "gameOver"; winners: Seat[] }`. A `drew` from deck carries `card` only in the private copy (Task 6 filters).
  - `type ApplyResult = { ok: true; state: CatTowerState; events: GameEvent[] } | { ok: false; error: "not_your_turn" | "bad_step" | "bad_card" | "bad_groups" | "already_laid" | "not_laid" | "bad_target" | "empty_discard" | "cucumber_from_discard" | "round_not_over" }`.
  - `newGame(seats: number, seed: number): CatTowerState` — dealer 0, deals round 1.
  - `applyAction(state: CatTowerState, seat: Seat, action: Action): ApplyResult` — pure; never mutates input. RNG: recreate from `seed` and advance `rngCalls` (store the count) so state stays JSON-serializable.

Round start: shuffle full deck, deal 10 to each seat starting left of dealer, flip one to discard; first turn = dealer+1; if the flipped card is a Cucumber, that first seat is skipped (emit `skipped`, turn moves on).
Turn end (after discard): next seat = turn+1 mod seats; while that seat has `pendingSkip`, clear it, emit `skipped`, advance once more.
Cucumber discard: `skipTarget` required, must be another seat without `pendingSkip`; if every other seat already has a pending skip, `skipTarget` is omitted and the Cucumber is just discarded.

- [ ] **Step 1: Write failing tests:**
  - `newGame(4, 1)` deals 10 each, discard length 1, deck = 108 − 41, `step: "draw"`, turn = 1 (or 2 if flipped Cucumber — test with a seed found to flip one: assert `skipped` path by constructing state directly).
  - `draw from deck moves top card to hand and sets step play`; `draw from discard takes top`; `cannot draw cucumber from discard → cucumber_from_discard`; `draw when step is play → bad_step`.
  - `action by wrong seat → not_your_turn and state is === unchanged (deep equal)`.
  - `discard card not in hand → bad_card`; `discard advances turn and resets step to draw`.
  - `cucumber discard sets pendingSkip on target; target's turn is skipped once` (3 seats: 0 skips 2 → order 0,1,0...).
  - `two-player cucumber gives discarder two turns in a row`.
  - `cucumber with all others pending → discarded with no target`.
  - **Review Focus 3:** `empty deck reshuffles discard except top card (emits reshuffled)`; `empty deck and discard of 1 → roundOver with wentOut null; seats that laid down advance`.
  - **Review Focus 2:** `same draw applied twice: second returns bad_step, state unchanged`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement `newGame`, `applyAction` for `draw` and `discard` (layDown/hit/nextRound return `bad_step` until Tasks 4–5).
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(play-api): engine turns, cucumbers, reshuffle`.

---

### Task 4: Lay down and hit

**Files:**
- Modify: `src/rules/engine.ts`
- Test: `src/rules/engine.play.test.ts`

**Interfaces:**
- Consumes: `matchPhase`, `canHit` (Task 2); state/action types (Task 3).
- Produces: `layDown` and `hit` handling in `applyAction`; going out (hand empties via layDown/hit/discard) ends the round by calling `endRound` (stub in this task that sets `status: "roundOver"`; Task 5 fills scoring).

Rules: both only in `step: "play"` on your turn. `layDown` only if `laid[seat] === null`; cards must be in hand, disjoint, and `matchPhase(phase[seat], groups)` must succeed → `laid[seat] = groups`. `hit` only if `laid[seat] !== null`; target group must exist in `laid[target.seat]`; `canHit` decides; group replaced with the extended group. Emptying your hand on a layDown/hit is going out (no discard needed).

- [ ] **Step 1: Write failing tests:** `lay down phase 1 with two sets`; `lay down wrong phase → bad_groups`; `second layDown same round → already_laid`; `layDown in draw step → bad_step`; `hit before laying down → not_laid`; `hit onto another player's run extends it`; `hit invalid card → bad_target`; `hit last card ends round (status roundOver, wentOut = seat)`; `discarding last card ends round`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(play-api): lay down and hit`.

---

### Task 5: Round end, scoring, next round, winning

**Files:**
- Modify: `src/rules/engine.ts`
- Test: `src/rules/engine.rounds.test.ts`

**Interfaces:**
- Produces: `endRound` (internal), `nextRound` action, `gameOver`.

Round end: points = sum of `cardPoints` left in each hand; `scores += points`; every seat with `laid !== null` gets `phase += 1`; emit `roundOver`. If any seat now has `phase === 10`: winners = those seats with lowest score (ties share), `status: "gameOver"`, emit `gameOver`. Otherwise `nextRound` (any seat, only in `roundOver`) rotates dealer, clears laid/pendingSkip, deals.

- [ ] **Step 1: Write failing tests:** `points: hand [5,11,yarn,cucumber] = 5+10+25+15`; `only seats that laid down advance`; `nextRound rotates dealer and redeals`; `nextRound while playing → round_not_over`; `first to finish phase 10 wins`; `two finish phase 10 same round → lower score wins`; `equal scores share the win`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** Commit `feat(play-api): scoring, rounds, winners`.

---

### Task 6: Views and event privacy

**Files:**
- Create: `src/rules/view.ts`
- Test: `src/rules/view.test.ts`

**Interfaces:**
- Produces:
  - `type CatTowerView = { round: number; dealer: Seat; turn: Seat; step: "draw" | "play"; status: CatTowerState["status"]; deckCount: number; discardTop: CardId | null; discardCount: number; phase: number[]; scores: number[]; laid: (Group[] | null)[]; handCounts: number[]; hands: Record<Seat, CardId[]>; pendingSkip: boolean[]; winners: Seat[] }`.
  - `viewFor(state: CatTowerState, controlled: readonly Seat[]): CatTowerView` — `hands` contains only `controlled` seats.
  - `eventFor(event: GameEvent, controlled: readonly Seat[]): GameEvent` — strips `card` from `drew` (from deck) unless `event.seat` is controlled.

- [ ] **Step 1: Write failing tests:** `view for seat 1 only includes hand 1`; `view for [0,2] (shared phone) includes both`; `view for [] (spectating device) has no hands`; `deck draw event hides card from others, shows it to drawer`; `discard draw event shows card to all`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** Commit `feat(play-api): per-device views and event privacy`.

---

### Task 7: Solver, House Cat bot, simulation

**Files:**
- Create: `src/rules/solver.ts`, `src/bots/house-cat.ts`
- Test: `src/rules/solver.test.ts`, `src/bots/house-cat.test.ts`, `tests/sim.test.ts`

**Interfaces:**
- Produces:
  - `findPhase(hand: CardId[], phaseIndex: number): { cards: CardId[]; runStart?: number }[] | null` — a valid layDown if one exists (exhaustive over candidate groups; hand ≤ 11 cards).
  - `phaseProgress(hand: CardId[], phaseIndex: number): number` — max count of hand cards usable toward the phase (0..total size).
  - `findHits(hand: CardId[], laid: (Group[] | null)[]): { card: CardId; target: { seat: Seat; group: number } }[]`.
  - `chooseAction(view: CatTowerView, seat: Seat, rng: Rng): Action` (House Cat).

House Cat policy: draw step → take discard top if it is not a Cucumber and raises `phaseProgress`, else deck. Play step → if not laid and `findPhase` → layDown; if laid → first available hit; else discard: Cucumber first (target: seat with highest phase, tie → fewest hand cards, among valid targets); otherwise the card whose removal lowers `phaseProgress` least, tie → highest points. Never discards Yarn unless the hand is all Yarn.

- [ ] **Step 1: Write failing tests:** `findPhase finds two sets with a yarn`; `findPhase returns null one card short`; `findPhase run of 9 with two yarn`; `findHits finds extension of opponent run`; `bot lays down when possible`; `bot discards cucumber at leader`; `bot never returns an action applyAction rejects` (property: 200 random mid-game states).
- [ ] **Step 2:** `tests/sim.test.ts`: `300 games of 2–6 House Cats finish with gameOver, no rejected action, under 60 rounds each` — loop `applyAction(state, s, chooseAction(viewFor(state,[s]), s, rng))`, `nextRound` on roundOver.
- [ ] **Step 3–5:** FAIL → implement → PASS (sim under 30 s).
- [ ] **Step 6:** Commit `feat(play-api): phase solver, House Cat bot, simulation`.

---

### Task 8: Protocol, device tokens, room codes

**Files:**
- Create: `src/protocol.ts`, `src/auth.ts`, `src/room/codes.ts`, `src/games/module.ts`, `src/games/cat-tower.ts`
- Test: `src/protocol.test.ts`, `src/auth.test.ts`, `src/room/codes.test.ts`

**Interfaces:**
- Produces:
  - `type Person = { id: string /* uuid from device */; name: string /* 1–20 chars, trimmed */; cat: number /* 0–7 */ }`.
  - `type ClientMessage = { t: "claim"; seat: Seat; person: Person } | { t: "configure"; seat: Seat; kind: "open" | "bot" | "closed" } | { t: "start" } | { t: "act"; seat: Seat; action: Action } | { t: "presence"; state: "active" | "background" } | { t: "moveSeat"; seat: Seat } | { t: "claimMove"; code: string } | { t: "leave"; seat: Seat }`.
  - `type ServerMessage = { t: "snapshot"; seq: number; room: RoomView } | { t: "event"; seq: number; event: RoomEvent } | { t: "moveCode"; seat: Seat; code: string } | { t: "error"; code: string; ref?: string }`.
  - `parseClientMessage(raw: string): ClientMessage | { error: "bad_message" }` — rejects > 8192 bytes, non-JSON, unknown `t`, wrong field types (hand-written validators, no schema library).
  - `PROTOCOL_VERSION = 1`.
  - `issueDeviceToken(secret: string, deviceId: string): Promise<string>` → `v1.<deviceId>.<base64url HMAC-SHA256>`; `verifyDeviceToken(secret: string, token: string): Promise<string | null>` (returns deviceId, constant-time compare).
  - `ROOM_CODE_ALPHABET = "BCDFGHJKLMNPQRTVWXZ2346789"`, `newRoomCode(rng: () => number): string` (5 chars).
  - `interface GameModule<S, A, V, E> { id: string; minSeats: number; maxSeats: number; create(seats: number, seed: number): S; apply(s: S, seat: Seat, a: A): { ok: true; state: S; events: E[] } | { ok: false; error: string }; view(s: S, controlled: readonly Seat[]): V; filterEvent(e: E, controlled: readonly Seat[]): E; currentActor(s: S): Seat | null; botAction(s: S, seat: Seat, rng: Rng): A }`; `catTower: GameModule<CatTowerState, Action, CatTowerView, GameEvent>` (`currentActor` = `turn` while playing, null otherwise).
  - `RoomView`/`RoomEvent` are defined in Task 9; `protocol.ts` imports their types.

- [ ] **Step 1: Write failing tests:** **Review Focus 4:** `oversized message → bad_message`, `non-JSON → bad_message`, `unknown t → bad_message`, `act with string seat → bad_message`, `claim with 21-char name → bad_message`, `valid act parses`. `token round-trips`; `tampered token → null`; `token signed with other secret → null`. `room code is 5 chars from alphabet`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** Commit `feat(play-api): protocol, device tokens, room codes`.

---

### Task 9: RoomCore lobby — seats, local seats, start, move seat

**Files:**
- Create: `src/room/core.ts`
- Test: `src/room/core.lobby.test.ts`

**Interfaces:**
- Consumes: `GameModule`, `catTower`, `Person`, `ClientMessage`.
- Produces:
  - `type SeatInfo = { kind: "open" | "closed" | "human" | "bot"; person?: Person; deviceId?: string; botLevel?: "house" }`.
  - `type Presence = "awake" | "away" | "asleep"`.
  - `type RoomState = { code: string; game: "cat-tower"; hostDeviceId: string; status: "lobby" | "playing" | "over"; seats: SeatInfo[] /* length 6 */; gameState: CatTowerState | null; seq: number; lastActivity: number; devices: Record<string, { presence: Presence; since: number; connected: boolean }>; moveCodes: Record<string, { seat: Seat; expires: number }>; timers: { botAt: number | null; nextRoundAt: number | null; cleanupAt: number }; pushedForTurn: string | null /* "<round>:<turnCount>" dedupe key */ }`.
  - `type RoomView = { code: string; status: RoomState["status"]; youAreHost: boolean; seats: { kind: SeatInfo["kind"]; person?: Person; yours: boolean; presence: Presence | null }[]; game: CatTowerView | null }`.
  - `type RoomEvent = { kind: "seats" } | { kind: "presence"; seat: Seat; presence: Presence } | { kind: "game"; event: GameEvent }`.
  - `type Outbound = { to: "all" | string /* deviceId */; message: ServerMessage }`.
  - `class RoomCore { constructor(state: RoomState, now: () => number, rng: Rng); static create(code: string, hostDeviceId: string, now: number): RoomState; handle(deviceId: string, msg: ClientMessage): Outbound[]; connect(deviceId: string): Outbound[]; disconnect(deviceId: string): Outbound[]; tick(): Outbound[]; snapshotFor(deviceId: string): ServerMessage; controlledSeats(deviceId: string): Seat[]; state: RoomState; nextAlarm(): number }` — `handle` never throws; errors become `{ to: deviceId, message: { t: "error", code } }`.
  - Messages that broadcast a game event produce one `Outbound` per connected device with the event filtered by `controlledSeats` (`to: deviceId`).

Lobby rules: new room has seat 0 open, seats 1 open, 2–5 closed. `claim` on an open seat by any device (a device may claim several seats — local seats — each with its own `Person`); `configure` by any device that holds a seat (Review Focus 5), only in lobby; `start` needs ≥ 2 seats that are human/bot and no open seats (open → closed automatically on start? no: reject `seats_open`); seats are compacted in order at start so game seats are 0..n-1. `moveSeat` returns a 6-char code valid 10 minutes; `claimMove` by another device transfers `deviceId`. `leave` in lobby frees a seat; in play it's not allowed (`error: in_game`).

- [ ] **Step 1: Write failing tests:** `create has 2 open seats`; `device claims seat`; `same device claims second seat (local)`; `claim taken seat → seat_taken`; `configure bot`; `start with one seat → not_enough_players`; `start with open seat → seats_open`; **Review Focus 5:** `non-creator seated device can start when host never connected`; `unseated device cannot configure → not_seated`; `moveSeat code transfers seat to new device`; `expired move code → bad_code`; `snapshot for device lists yours=true only on its seats`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** Commit `feat(play-api): room lobby state machine`.

---

### Task 10: RoomCore play loop — actions, bots, presence, timers, push intents

**Files:**
- Modify: `src/room/core.ts`
- Test: `src/room/core.play.test.ts`

**Interfaces:**
- Produces:
  - `handle(...)` for `act` (device must control `seat`), `presence`; `tick()` runs due bot turns, presence decay, cleanup.
  - `type PushIntent = { deviceId: string; kind: "your_turn"; seat: Seat; personName: string }`; `RoomCore.drainPushIntents(): PushIntent[]`.
  - `RoomState.timers.botAt` = now + 1200 ms when the current actor is a bot; each tick performs one bot action (draw, then play steps, then discard as separate ticks so animations stay visible).
  - Round over: `nextRound` is applied automatically 6 s after `roundOver` (timer `nextRoundAt`), or immediately when any device sends `act nextRound`.

Presence: `connect` → `awake`; `presence background` or `disconnect` → `away`; `away` for ≥ 5 min (tick) → `asleep`. Push intent emitted when the turn passes to a human seat whose device presence is not `awake`, at most once per turn.
Cleanup: `cleanupAt = lastActivity + 7 days`; `tick()` past it sets `status: "over"` and returns `{ to: "all", message: { t: "error", code: "room_closed" } }`; the DO deletes storage.

- [ ] **Step 1: Write failing tests:** `act for seat not controlled → not_your_seat`; `valid act broadcasts filtered events with increasing seq`; **Review Focus 2:** `two devices race the same draw — second gets bad_step`; `bot seat moves on tick after botAt`; `bot game of 3 bots + 1 human: human's turn yields push intent when human is away, none when awake`; **Review Focus 1:** `device disconnects after draw; reconnect snapshot has step play and drawn card in hand; discard succeeds`; `presence decays away → asleep after 5 min`; `roundOver auto-advances after 6 s`; `cleanup after 7 days idle`; `nextAlarm returns earliest pending timer`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** Commit `feat(play-api): play loop, bots, presence, timers`.

---

### Task 11: Durable Objects and Worker router

**Files:**
- Create: `src/room/game-room.ts`, `src/room/device-index.ts`, `src/index.ts`, `wrangler.jsonc`
- Test: `tests/worker.test.ts` (Miniflare + esbuild, pattern from `apps/customer-runner-service/src/worker.test.ts`)

**Interfaces:**
- Consumes: `RoomCore`, auth, protocol.
- Produces (HTTP, JSON; all except `/healthz`, AASA, `/j/*` require `Authorization: Bearer <deviceToken>`):
  - `GET /healthz` → `{ ok: true, service: "play-api", configured: boolean /* TOKEN_SECRET present */ }`.
  - `POST /v1/devices` (no auth) → `{ deviceId, token }` — mints a random deviceId (rate-limit via the existing ratelimit binding pattern if available; else 10/min per IP in-memory).
  - `PUT /v1/devices/me/push` `{ apnsToken: string }` → 204 (stored in `DeviceIndex`).
  - `POST /v1/rooms` `{ game: "cat-tower" }` → `{ code }` — retry new code up to 5× if the room DO reports it exists.
  - `GET /v1/rooms/:code/ws` (WebSocket upgrade) → forwards to `GameRoom`; first server message is `snapshot`.
  - `GET /v1/devices/me/tables` → `{ tables: { code: string; status: string; yourTurn: boolean; updatedAt: number }[] }` from `DeviceIndex`.
  - `GameRoom` DO: stores `RoomState` as one JSON row in SQLite (`room` table) after every handled message; uses `ctx.acceptWebSocket(ws, [deviceId])` + `serializeAttachment({ deviceId })`; `webSocketMessage` → `parseClientMessage` → `RoomCore.handle` → send outbounds; `alarm()` → `tick()` and `setAlarm(nextAlarm())`; on any seat/status change calls `DeviceIndex.upsertTable(code, …)` for every seated device; push intents → `DeviceIndex.push(...)` (Task 13).
  - `DeviceIndex` DO (id = deviceId): `setApnsToken(token)`, `upsertTable(entry)`, `removeTable(code)`, `listTables()`, `push(payload)`.
  - `wrangler.jsonc`: name `conleychaos-play-api`, `workers_dev: false`, route `{ "pattern": "play.conleychaos.com", "custom_domain": true }`, DO bindings `ROOMS → GameRoom`, `DEVICES → DeviceIndex`, migration `{ tag: "v1", new_sqlite_classes: ["GameRoom","DeviceIndex"] }`, vars `APNS_TEAM_ID: "B222J9J7B8"`, `APNS_TOPIC: "com.conleychaos.play"`, `APNS_HOST: "api.push.apple.com"`, observability with invocation logs off.

- [ ] **Step 1: Write failing integration tests:** `healthz`; `device mint + token auth required on rooms (401 without)`; `create room → two devices connect over WS, claim seats, start, play draw+discard, each sees only own hand`; **Review Focus 4:** `garbage WS frame → error bad_message and socket stays open (next valid message works)`; `room survives hibernation: state reloads from storage after Miniflare restart of the DO`; `tables list shows room for both devices`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** Commit `feat(play-api): GameRoom/DeviceIndex durable objects and router`.

---

### Task 12: Universal Links and share landing page

**Files:**
- Create: `src/http/links.ts`; Modify: `src/index.ts`
- Test: `src/http/links.test.ts`

**Interfaces:**
- Produces:
  - `GET /.well-known/apple-app-site-association` → `application/json`: `{ "applinks": { "details": [{ "appIDs": ["B222J9J7B8.com.conleychaos.play"], "components": [{ "/": "/j/*" }] }] } }`.
  - `GET /j/:code` → small HTML page (no external assets): big room code, cat illustration placeholder (inline SVG), and a "Get the app" link to the TestFlight public link from var `TESTFLIGHT_URL` (omit link when unset). Invalid code format → 404.

- [ ] **Step 1: Write failing tests:** `AASA JSON exact`; `/j/BCDFG returns 200 html containing BCDFG`; `/j/bad! → 404`; `code is HTML-escaped`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** Commit `feat(play-api): universal links and share page`.

---

### Task 13: APNs "your turn" push

**Files:**
- Create: `src/push/apns.ts`; Modify: `src/room/device-index.ts`, `src/room/game-room.ts`
- Test: `src/push/apns.test.ts`

**Interfaces:**
- Produces:
  - `createApnsJwt(p8: string, keyId: string, teamId: string, nowSec: number): Promise<string>` — ES256 via WebCrypto `importKey("pkcs8")`; cached in-memory for 50 min.
  - `sendApns(fetcher: typeof fetch, cfg: { host: string; topic: string; jwt: string }, deviceToken: string, payload: { title: string; body: string; code: string }): Promise<{ ok: boolean; status: number; unregistered: boolean }>` — POST `https://{host}/3/device/{token}`, headers `authorization: bearer <jwt>`, `apns-topic`, `apns-push-type: alert`, `apns-priority: 10`, `apns-collapse-id: <code>`; body `{ aps: { alert: { title, body }, sound: "default", "thread-id": code }, code }`. Status 410 → `unregistered: true` and DeviceIndex clears the token.
  - Push copy (the only English): title = person name of the seat (e.g. "Sam"), body = `"Your turn"`.

- [ ] **Step 1: Write failing tests:** `JWT has ES256 header with kid and iss/iat claims, verifies with the public key` (generate a P-256 key in the test); `sendApns builds request exactly` (fake fetch); `410 marks unregistered`; `DeviceIndex.push without token is a no-op`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Verify HTTP/2 reachability** (spec risk): after deploy (Task 14), `curl -s https://play.conleychaos.com/healthz` then trigger a test push from a TestFlight device in Plan 2. If Workers `fetch` cannot reach APNs, file the fallback (relay) as a follow-up; do not block M1 server merge on it.
- [ ] **Step 6:** Commit `feat(play-api): APNs your-turn push`.

---

### Task 14: Monorepo wiring, secrets, deploy

**Files:**
- Create: `apps/play-api/target.manifest.json`
- Modify: `scripts/lib/affected-targets.mjs` (`DEPLOY_METADATA`, `SMOKE_METADATA`), `.github/workflows/deploy-sites.yml` (secret sync, per skill), any registries the repo's tests flag.

**Interfaces:**
- `target.manifest.json`: `{ "targetId": "app:play-api", "kind": "internal-app", "displayName": "Pounce Play API", "appPath": "apps/play-api", "packageName": "@meanwhileso/play-api", "deployable": true }`.
- `DEPLOY_METADATA['app:play-api'] = { app_name: 'conleychaos-play-api' }`; `SMOKE_METADATA['app:play-api'] = { url: 'https://play.conleychaos.com/healthz', text: '"configured":true' }`.

- [ ] **Step 1:** Invoke the `cloudflare-deploy-automation` skill; follow it to (a) confirm the `conleychaos.com` zone is in the account (`cloudflare-control-plane` skill), (b) make the deploy create the custom domain and sync secrets `TOKEN_SECRET`, `APNS_KEY_P8`, `APNS_KEY_ID` (and optional var `TESTFLIGHT_URL`) from 1Password one at a time. Create the 1Password items' names (values come from JD: `TOKEN_SECRET` = 64 random hex generated by `openssl rand -hex 32` into 1Password directly; APNs key from Apple).
- [ ] **Step 2:** Run the repo's target/registry tests (`pnpm test` at root scope that covers `scripts/lib/affected-targets.mjs`) → expect FAIL until manifest + metadata exist; add them; → PASS.
- [ ] **Step 3:** `pnpm --filter @meanwhileso/play-api typecheck && pnpm --filter @meanwhileso/play-api test` → PASS; `pnpm --filter @meanwhileso/play-api exec wrangler deploy --dry-run` → bundles without error.
- [ ] **Step 4:** Commit `feat(play-api): register target and deploy wiring`; open PR; `CI / pr-smoke` green; after merge, smoke `https://play.conleychaos.com/healthz` returns `"configured":true`.

---

## Self-review notes

- Spec coverage (server side of M1): rules §4 → Tasks 1–5; hidden info → 6, 11; bots (House Cat) → 7; live play/presence/resume/cleanup → 10–11; seat types incl. local + move seat → 9; share links/Universal Links → 12; your-turn push → 13; Cloudflare/everything deploy → 14; plugin interface for future games → 8. M2 items (Sign in with Apple, groups, D1, Nearby, nudges, reactions, Kitten/Alley Cat, takeover vote) are Plan 3. iOS client, art, Mobbin research → Plan 2.
- Edge-case calls taken from spec §4: natural card required per group; Cucumber pending-skip rule; first flip Cucumber skips first player; Yarn drawable from discard.
- Added call: round auto-advances 6 s after round over; bot actions 1.2 s apart; presence asleep after 5 min away.
