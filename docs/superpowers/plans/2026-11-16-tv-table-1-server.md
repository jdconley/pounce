# Pounce on the TV, stage 1: server — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The play-api server lets a TV join a room as a *screen* (a seatless device that says so), tells every phone when a screen is present, relays live `aim` pointing, makes the first phone to sit the host of a table a TV made, and links a phone's table to a TV through a QR token or backup code.

**Architecture:** All rules live in the pure `RoomCore` (`apps/play-api/src/room/core.ts`, 100% coverage). The `GameRoom` Durable Object only carries the screen role from the Worker and delivers. Screen links are a new SQLite Durable Object class, `ScreenLinks`, one instance per link token and one per backup code, holding the TV's hibernatable waiting socket. Everything is additive: `PROTOCOL_VERSION` stays 1, new snapshot fields are absent unless true, and `aim` carries no `seq`.

**Tech Stack:** TypeScript, Cloudflare Workers and Durable Objects, vitest, Miniflare (integration tests), Swift (one PounceKit decode test), the play-web vitest suite (one decode test).

**Spec:** `docs/superpowers/specs/2026-11-16-tv-table-design.md` (§1, §2, §3 "Live pointing", Testing "Server").

**The four stages.** This plan is stage 1. Stages 2 (web), 3 (iPhone) and 4 (Apple TV) each get their own plan file in this folder, written when the stage starts, because each builds on interfaces this stage produces (listed under "Produces" below and in `docs/tv-protocol.md`). Order and merge rules are in "After stage 1".

## Global Constraints

- `PROTOCOL_VERSION` stays exactly 1. Every wire change is additive. Shipped apps require `protocol === 1` and decode strictly only what they know; unknown keys and unknown message types are ignored (`Messages.swift:126`, `RoomSocket.swift:242`, `play-web/src/store/room.ts:306`).
- The pinned fixtures in `tests/fixtures-pinned.test.ts` must not change by one byte. New samples go in a new file.
- A screen never receives a hand, a rack, or a drawn card or tile, in a snapshot or an event. It gets exactly what a device that controls no seats gets.
- A screen never controls a seat: `claim`, `moveSeat`, `claimMove`, `act`, `aim` and every other seat action from a screen are refused with `not_allowed`.
- A screen counts as a member of the room for the join-guess rules (`knows()` → `member`) and appears in no table list (`tableDevices`, `DeviceIndex.upsertTable`, `Player.upsertTable`).
- `screen` goes false 10 seconds after the last screen disconnects (`SCREEN_GRACE_MS = 10_000`).
- Screen link token: at least 128 bits (16 random bytes, base64url, 22 characters). Backup code: 6 characters from `ROOM_CODE_ALPHABET`. Both expire after 10 minutes (`SCREEN_LINK_TTL_MS = 600_000`).
- Wrong backup codes count against the phone with `DEVICE_JOIN_RULE` (and its address with `IP_JOIN_RULE`), on their own limiter keys (`screen:device:<id>`, `screen:ip:<ip>`), so a mistyped TV code never locks a phone out of joining tables.
- Only a device in the room (seated, or the host) may link it to a TV.
- `aim`: only the device controlling the acting seat, on its turn, mid-round. Relayed to every other connected device, never stored, never persisted. At most `AIM_PER_SECOND = 10` per device per rolling second; extras are dropped silently.
- The server feature flag is `TV` (`"on"` in `wrangler.jsonc`). Off: `/v1/screens*` and `/tv/*` are 404, `role=screen` sockets are refused (404), `screen` and `aim` are never sent, `aim` from a client is `bad_message`. Every other answer is as before.
- Main-thread rule: no new code path blocks. (Server code has no main thread; the DO keeps `aim` off storage entirely.)
- Production smoke tests must not send a `cf-connecting-ip` header.

## Review Focus

1. **A TV on flaky Wi-Fi.** A screen socket that drops and comes back within 10 s must not flip any phone's layout: no snapshot without `screen` reaches the phones. (Task 3 test `"a screen back within the grace changes nothing for the phones"`.)
2. **The same browser as a phone and a TV.** A device that holds a seat (or is the host) asking for `role=screen` is refused (409 `seated`) and does not become a screen; a screen asking without the role is still a screen. (Task 3 and Task 6 tests.)
3. **Play again at a TV table.** The new table must know the TV: the `RematchIntent` carries the screens, so the TV following `{t:"rematch"}` is a member and a screen there, and the new room's host is the asker, never the TV. (Task 3 test `"play again keeps the table's screens"`; Task 6 integration step.)
4. **A TV-made table before anyone sits.** No host: `/j/<code>` names nobody, nothing is pushed "from the host", the tables index is never asked about device `""`. (Task 6 tests.)
5. **Aim at the turn's edge.** An `aim` that arrives just after the turn moved on, or from a pass-and-play device for a seat it holds but that isn't acting, is dropped silently, never an error toast. (Task 4 tests.)

---

### Task 1: The `TV` flag, and the wire types

**Files:**
- Modify: `apps/play-api/src/env.ts` (add `TV?: string` to `Env`, `tvOn()`)
- Modify: `apps/play-api/src/protocol.ts` (types and parsing)
- Modify: `apps/play-api/wrangler.jsonc` (`"TV": "on"` with a comment in the house style)
- Test: `apps/play-api/src/env.test.ts`, `apps/play-api/src/protocol.test.ts`

**Interfaces:**
- Produces:
  - `export function tvOn(env: Pick<Env, "TV">): boolean` (same truthy words as `linkOn`).
  - In `protocol.ts`:
    - `RoomView.screen?: true` — present only while a screen shows the table or is within its grace.
    - `export type CatTowerAim = { target: { seat: Seat; group: number } }`
    - `export type TilesAim = { table: TileId[][] }`
    - `export type GameAim = CatTowerAim | TilesAim`
    - `ClientMessage` gains `{ t: "aim"; seat: Seat; aim?: GameAim }` — no `aim` key clears the pointing.
    - `ServerMessage` gains `{ t: "aim"; seat: Seat; aim?: GameAim }` — no `seq`, not a state change.
    - `export type AimParser = (raw: unknown) => GameAim | null`
    - `parseClientMessage(raw: string, parseAction?: ActionParser, parseAim?: AimParser)`; `parseAim` defaults to Cat Tower's (`parseAim` exported from `games/cat-tower.ts`, Task 2).

- [ ] **Step 1: Write the failing tests**

In `protocol.test.ts`:
```ts
it("parses aim with a game's aim, and with none (clears)", () => {
  expect(parseClientMessage('{"t":"aim","seat":1,"aim":{"target":{"seat":0,"group":1}}}'))
    .toEqual({ t: "aim", seat: 1, aim: { target: { seat: 0, group: 1 } } });
  expect(parseClientMessage('{"t":"aim","seat":1}')).toEqual({ t: "aim", seat: 1 });
});
it("refuses a malformed aim", () => {
  for (const raw of ['{"t":"aim"}', '{"t":"aim","seat":-1}', '{"t":"aim","seat":0,"aim":5}', '{"t":"aim","seat":0,"aim":{"target":{"seat":0}}}', '{"t":"aim","seat":0,"x":1}'])
    expect(parseClientMessage(raw)).toEqual({ error: "bad_message" });
});
it("passes aim to the room's own aim parser", () => {
  const parseAim = vi.fn(() => ({ table: [[1, 2, 3]] }));
  expect(parseClientMessage('{"t":"aim","seat":0,"aim":{"table":[[1,2,3]]}}', undefined, parseAim)).toEqual({ t: "aim", seat: 0, aim: { table: [[1, 2, 3]] } });
  expect(parseAim).toHaveBeenCalledWith({ table: [[1, 2, 3]] });
});
```
In `env.test.ts`: `tvOn({ TV: "on" })` true, `tvOn({})` false, `tvOn({ TV: "off" })` false.

- [ ] **Step 2: Run them to see them fail**

Run: `pnpm --filter @pounce/play-api exec vitest run src/protocol.test.ts src/env.test.ts`
Expected: FAIL (`aim` is `bad_message`; `tvOn` not exported).

- [ ] **Step 3: Implement**

`case "aim"` in `parseObject`: keys `["t","seat"]` plus optional `["aim"]`, `isInt(seat, 0)`; with `aim` present, `parseAim(o.aim)` must be non-null. Add the types above with doc comments in the file's voice.

- [ ] **Step 4: Run the tests to see them pass**

Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/play-api/src/env.ts apps/play-api/src/env.test.ts apps/play-api/src/protocol.ts apps/play-api/src/protocol.test.ts apps/play-api/wrangler.jsonc
git commit -m "Server: the TV flag, and the aim and screen wire types"
```

---

### Task 2: Each game checks its own aim

**Files:**
- Modify: `apps/play-api/src/games/module.ts` (two members on `GameModule`)
- Modify: `apps/play-api/src/games/cat-tower.ts`, `apps/play-api/src/games/tiles.ts`
- Modify: `apps/play-api/src/games/index.ts` if `RoomGame` needs the members spelled out
- Test: `apps/play-api/src/games/cat-tower.test.ts`, `apps/play-api/src/games/tiles.test.ts`

**Interfaces:**
- Consumes: `CatTowerAim`, `TilesAim` (Task 1).
- Produces on `GameModule<S, A, V, E, Err>`:
  - `parseAim(raw: unknown): object | null` — the shape, fully validated; null when not this game's aim.
  - `aimAllowed(s: S, seat: Seat, aim: object): boolean` — the aim points only at real public things.
  - `export function parseAim(raw: unknown): CatTowerAim | null` from `games/cat-tower.ts` (the default parser).

Rules:
- Cat Tower `parseAim`: exactly `{ target: { seat, group } }`, both non-negative ints. `aimAllowed`: `target.seat < s.seats` and `s.laid[target.seat]` is non-null and `target.group < s.laid[target.seat].length`.
- Tiles `parseAim`: exactly `{ table }`, an array of at most 60 arrays, each of 1–13 tile ids (valid `TileId` per `tiles/` helpers), at most 106 ids in all, no id twice. `aimAllowed`: every id is on `s.table` or in `s.racks[seat]`.

- [ ] **Step 1: Write the failing tests**

Cat Tower: `parseAim` accepts `{target:{seat:1,group:0}}`, refuses `{target:{seat:1}}`, `{target:{seat:1,group:0},x:1}`, `null`, `[]`. `aimAllowed` true for a laid group of another seat, false for a seat that hasn't laid, for `group` past the end, for `seat >= seats`.
Tiles: `parseAim` refuses an id twice, 61 sets, an empty set, a non-tile id. `aimAllowed` true for a draft mixing table pieces and the seat's own rack pieces; false when any id is on another seat's rack or still in the pool.

- [ ] **Step 2: Run them to see them fail**

Run: `pnpm --filter @pounce/play-api exec vitest run src/games`
Expected: FAIL (`parseAim` undefined).

- [ ] **Step 3: Implement** in each module; add the two members to `GameModule` with doc comments.

- [ ] **Step 4: Run to pass.** Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/play-api/src/games
git commit -m "Server: each game checks a live aim points only at public pieces"
```

---

### Task 3: Screens in the room core

**Files:**
- Modify: `apps/play-api/src/room/core.ts`
- Create: `apps/play-api/src/room/core.screen.test.ts`

**Interfaces:**
- Consumes: `tvOn` via `RoomFeatures.tv` (Task 1).
- Produces:
  - `RoomFeatures.tv?: boolean`.
  - `RoomState.screens?: string[]` — device ids that are screens here, for good (sticky: a device listed here is a screen on every connect).
  - `RoomState.screenLeftAt?: number` — when the last connected screen went, while within the grace.
  - `DeviceRecord` unchanged; a screen's record is an ordinary one.
  - `export const SCREEN_GRACE_MS = 10_000;`
  - `RoomCore.create(code, hostDeviceId: string, now, name?, look?, game?, screen?: string)`: with `screen`, `hostDeviceId` must be `""` (no host) and `screens = [screen]`.
  - `isScreen(deviceId: string): boolean`
  - `mayScreen(deviceId: string): boolean` — false when the device controls a seat or is the host (it then can't become a screen).
  - `connect(deviceId: string, players?: Record<string, string>, role?: "screen"): Outbound[]` — with `role` (or when already listed) the device is recorded in `screens`. Callers check `mayScreen` first.
  - `mayLink(deviceId: string): boolean` — the host or a device controlling a seat, never a screen.
  - `addScreen(deviceId: string): void` — lists a device as a screen here before it connects (a link).
  - `screenShown(): boolean` — a screen is connected, or `now < screenLeftAt + SCREEN_GRACE_MS / speed` (the grace divides by the dev speed like the room's other timers).
  - `RematchIntent.screens?: string[]` — carried to the new table; `rematchState` copies it into `RoomState.screens`.

Behaviour:
- Every message from a screen except `ping`, `presence` and `link` → `error not_allowed`. (Covers `claim`, `moveSeat`, `claimMove`, `act`, `aim`, `configure`, `start`, `leave`, `rename`, `renameSeat`, `rematch`, `setLook`, `nudge`, `retire`.)
- `claim` in a room with `hostDeviceId === ""` makes the claimer the host.
- Snapshot: `...(this.features.tv && this.screenShown() ? { screen: true } : {})`.
- A screen connecting when `screenShown()` was false: `seq += 1` (no `touch`) and every connected device gets a snapshot. When it was already true (grace), only the screen gets its snapshot and `screenLeftAt` is dropped.
- The last screen disconnecting: `screenLeftAt = now`; `nextAlarm()` includes `screenLeftAt + SCREEN_GRACE_MS`; `tick()` past it with no screen connected deletes `screenLeftAt`, `seq += 1`, and sends every connected device its snapshot.
- `knows`-style membership lives in `GameRoom` (Task 6) and reads `isScreen`.

- [ ] **Step 1: Write the failing tests** in `core.screen.test.ts` (copy the helpers at the top of `core.lobby.test.ts`; `features = { streaks: true, tv: true }`):

```ts
it("a screen gets no hand and claims nothing", ...)          // connect("tv", {}, "screen"); every seat message → not_allowed; snapshot game.hands is {}
it("a screen-made room has no host until the first phone sits", ...) // create(..., "", ..., "tv"); youAreHost false for tv and a; a claims → a's snapshot youAreHost true; b claims → b not host
it("screen appears while a screen is connected", ...)       // phones' snapshots lack screen; tv connects → each phone gets a snapshot with screen: true and seq+1
it("a screen back within the grace changes nothing for the phones", ...) // disconnect tv, clock += 9_999, reconnect: no Outbound to a or b; tick → nothing
it("screen goes after the grace", ...)                      // disconnect, nextAlarm() === now + 10_000, clock += 10_000, tick → a and b snapshots without screen
it("a seated device or the host can't become a screen", ...) // mayScreen false for a seated "a" and for the host
it("a screen stays a screen without the role", ...)          // connect("tv", {}, "screen"); disconnect; connect("tv") → still not_allowed on claim
it("only the host or a seated device may link", ...)         // mayLink: host true, seated true, spectator false, screen false
it("addScreen lists a device before it connects", ...)
it("play again keeps the table's screens", ...)              // finish a game (stub game as in core.play.test.ts), rematch from a → drainRematch().screens toEqual ["tv"]; rematchState(...).screens toEqual ["tv"]
it("without the TV feature nothing says screen", ...)       // features.tv false → no screen key even with tv connected
```

- [ ] **Step 2: Run them to see them fail**

Run: `pnpm --filter @pounce/play-api exec vitest run src/room/core.screen.test.ts`
Expected: FAIL.

- [ ] **Step 3: Implement in `core.ts`.** Refuse screen messages at the top of `dispatch`. Keep `core.ts` at 100% coverage.

- [ ] **Step 4: Run the whole server suite with coverage**

Run: `pnpm --filter @pounce/play-api test`
Expected: PASS, `src/room/core.ts` 100%.

- [ ] **Step 5: Commit**

```bash
git add apps/play-api/src/room/core.ts apps/play-api/src/room/core.screen.test.ts
git commit -m "Server: a TV is a seatless screen; the first phone to sit hosts its table"
```

---

### Task 4: The `aim` relay

**Files:**
- Modify: `apps/play-api/src/room/core.ts`
- Create: `apps/play-api/src/room/core.aim.test.ts`

**Interfaces:**
- Consumes: `GameModule.parseAim/aimAllowed` (Task 2), `isScreen` (Task 3).
- Produces:
  - `RoomCore.parseAim = (raw: unknown) => GameAim | null` (the room's game's), passed to `parseClientMessage` by `GameRoom`.
  - `export const AIM_PER_SECOND = 10;`
  - `handle(deviceId, { t: "aim", seat, aim? })` → to every connected device but the sender: `{ t: "aim", seat, aim? }`. Not persisted state: no `seq`, no `touch`, no `state` change (the rate window is a private, unpersisted `Map<string, number[]>`).

Dropped silently (returns `[]`): `features.tv` off is the exception — that answers `bad_message`. Otherwise silent when: not mid-round, `seat` isn't `actor()`, the device doesn't control `seat`, `aimAllowed` is false, or the device sent `AIM_PER_SECOND` aims in the last 1000 ms. A screen's `aim` is `not_allowed` (Task 3).

- [ ] **Step 1: Write the failing tests** in `core.aim.test.ts`:

```ts
it("relays the acting seat's aim to everyone else, with no seq", ...) // a's turn, a aims at b's laid group → b and tv get {t:"aim",seat:0,aim}; a gets nothing; state.seq unchanged
it("clears with no aim", ...)
it("drops an aim from a seat that isn't acting", ...)                 // b aims on a's turn → []
it("drops an aim from a pass-and-play device for its seat that isn't acting", ...)
it("drops an aim at a group that isn't there", ...)
it("drops the 11th aim in a second, and takes one again a second later", ...)
it("drops an aim between rounds and in the lobby", ...)
it("relays a tile draft from the seat's own rack and the table", ...) // tiles room
it("drops a tile draft with another seat's piece", ...)
it("answers bad_message with the TV feature off", ...)
```

- [ ] **Step 2: Run to fail.** `pnpm --filter @pounce/play-api exec vitest run src/room/core.aim.test.ts` → FAIL.

- [ ] **Step 3: Implement** `aim` in `dispatch` and `parseAim` on `RoomCore`.

- [ ] **Step 4: Run the suite with coverage.** `pnpm --filter @pounce/play-api test` → PASS, `core.ts` 100%.

- [ ] **Step 5: Commit**

```bash
git add apps/play-api/src/room/core.ts apps/play-api/src/room/core.aim.test.ts
git commit -m "Server: relay where the player is pointing, live, to the TV and the table"
```

---

### Task 5: The TV never sees a private piece (property test)

**Files:**
- Create: `apps/play-api/src/room/core.screen-privacy.test.ts`

**Interfaces:**
- Consumes: `RoomCore` with screens (Task 3), `gameModule(id).botAction` to choose moves for human seats.

The test plays random whole games through `RoomCore` and checks every `Outbound` addressed to the screen.

- [ ] **Step 1: Write the test**

For each game id in `["cat-tower", "tiles"]` and seeds 1..40 (Cat Tower) / 1..60 (tiles):
- Seats: 2–4 (tiles) or 2–6 (Cat Tower) from the seed; each seat is, by seed, a human on its own device, one of two seats on a pass-and-play device `"pp"`, or a House Cat.
- Devices `"tv"` (screen, created the room) and `"spectator"` (connected, no seat) are connected. At seeded points the TV disconnects and reconnects.
- Loop until `status === "over"` or 3000 steps: when the actor is a human seat, `handle(device, { t: "act", seat, action: gameModule(id).botAction(state.gameState, seat, rng) })`; human devices also send an `aim` for the seat on the move now and then; otherwise advance the clock to `nextAlarm()` and `tick()`.
- For every outbound to `"tv"`:
  - a snapshot's `room.game?.hands` and `room.tiles?.racks` deep-equal `{}`;
  - a `game` event of kind `drew` has no `card`; a `tiles` event of kind `drew` has no `tile`;
  - `room.seats.every(s => !s.yours)` and `room.youAreHost === false`;
  - every TV snapshot deep-equals the `"spectator"` snapshot at the same seq, except `screen`.
- Assert every game ended (`status === "over"`).

- [ ] **Step 2: Run it**

Run: `pnpm --filter @pounce/play-api exec vitest run src/room/core.screen-privacy.test.ts`
Expected: PASS (the property holds by construction). Then temporarily make `snapshotFor` pass `[0]` as the screen's controlled seats and confirm the test FAILS; revert.

- [ ] **Step 3: Commit**

```bash
git add apps/play-api/src/room/core.screen-privacy.test.ts
git commit -m "Server: prove over random games that the TV never sees a hand, rack or drawn piece"
```

---

### Task 6: Screens through the Worker and the room's Durable Object

**Files:**
- Modify: `apps/play-api/src/room/game-room.ts`
- Modify: `apps/play-api/src/index.ts` (`openSocket`, `createRoom`)
- Modify: `apps/play-api/src/http/browser-socket.ts` (`asAppSocket` keeps `role`)
- Modify: `apps/play-api/src/safety/safety.ts` (`peekInvite` with no host)
- Create: `apps/play-api/tests/screens.test.ts` (Miniflare; copy `worker()`, `connect`, `mint` helpers from `tests/worker.test.ts`, with `TV: "on"`, `STREAKS: "on"`)
- Modify: `apps/play-api/src/http/browser-socket.test.ts` or `tests/web-player.test.ts` (whichever tests `asAppSocket`)

**Interfaces:**
- Consumes: Task 3's `RoomCore` API.
- Produces:
  - Internal header `export const ROLE_HEADER = "x-play-role";` in `game-room.ts`, value `"screen"`. The Worker deletes any client-sent copy and sets it from the query `role=screen` (only while `tvOn`).
  - `GET /v1/rooms/{code}/ws?role=screen` (apps and browsers; for browsers `asAppSocket` keeps `role` in the URL and drops the rest of the query). With `TV` off: 404.
  - The room answers a screen upgrade from a device that holds a seat or hosts with 409 `{ "error": "seated" }` (a browser sees close code 4409).
  - `POST /v1/rooms` accepts `{ game, screen: true }` (no `name` with `screen`): the room is made with no host and the caller listed as its screen; no `table_created` funnel step. 400 when `TV` is off.
  - `GameRoom.init(code, hostDeviceId, name?, look?, game?, screen?: string)`.
  - `GameRoom.knows()` → `member` for a listed screen too.
  - `GameRoom.mayLink(deviceId: string): Promise<"ok" | "not_seated" | "none">` and `GameRoom.addScreen(deviceId: string): Promise<void>` (used by Task 7).
  - `GameRoom.webSocketMessage`: for `t === "aim"`, deliver `core.handle(...)` and return without `persist`, `setAlarm`, funnel or tables work. `parseClientMessage(data, core.parseAction, core.parseAim)`.
  - `tableDevices()` skips `""`. `askToUpdate` and `refusal` already cope with `""`; `peekInvite` treats `""` as not a kitten without asking the index.
  - `features()` passes `tv: tvOn(this.env)`.

- [ ] **Step 1: Write the failing integration tests** in `tests/screens.test.ts`:

```ts
test("a TV makes a table, connects as its screen, and the first phone to sit hosts it")
  // mint tv, a, b; POST /v1/rooms {game:"cat-tower", screen:true} as tv → 201 code
  // tv ws ?role=screen → snapshot youAreHost false, no screen key for tv? (tv's own snapshot has screen: true)
  // a ws → snapshot.room.screen === true, youAreHost false; a claims seat 0 → youAreHost true
  // tv sends claim → error not_allowed
test("a TV table's invite page names nobody until someone sits")
  // GET /j/<code> before a claims: no person's name in the HTML; after: "Alice"
test("a seated phone can't open the same table as a screen")  // a seated; a ws ?role=screen → 409 seated
test("a browser screen says role in the query")                // subprotocol pounce + token, ?role=screen&games=tiles → accepted as screen
test("the TV is in nobody's tables list")                      // GET /v1/devices/me/tables as tv → no tables; as a → the table
test("the phones see screen go 10 seconds after the TV leaves") // DEV_SPEED unaffected; close tv ws, wait for alarm ≈ 10 s (test timeout 20 s) → a gets a snapshot without screen
test("aim reaches the TV and stays out of storage")             // a's turn after start with a House Cat seat: a aims; tv receives {t:"aim"}; reconnecting b gets no aim replay
test("play again takes the TV along")                          // finish via a 2-seat game with forfeit (see core.forfeit tests for the shortest path), rematch → tv gets {t:"rematch",code}; tv ws to the new code with role=screen → accepted, no join guess counted
test("with TV off, role=screen is refused and screen:true rooms are a bad request")
test("blocks still hold at a TV table")                        // reuse tests/safety.test.ts's block setup: a (first to sit, host) blocks Bob's player; Bob's claim → blocked
```

- [ ] **Step 2: Run to fail.** `pnpm --filter @pounce/play-api exec vitest run tests/screens.test.ts` → FAIL.

- [ ] **Step 3: Implement** the Worker and Durable Object changes above.

- [ ] **Step 4: Run the whole suite.** `pnpm --filter @pounce/play-api test && pnpm --filter @pounce/play-api typecheck && pnpm lint` → PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/play-api/src apps/play-api/tests/screens.test.ts
git commit -m "Server: TVs connect as screens through the Worker; a TV can make a table"
```

---

### Task 7: Screen links (`/v1/screens`) and `/tv/<token>`

**Files:**
- Create: `apps/play-api/src/screens/screens.ts` (pure: token and code minting, body parsing, the link decision)
- Create: `apps/play-api/src/screens/screens.test.ts`
- Create: `apps/play-api/src/screens/screen-links.ts` (the `ScreenLinks` Durable Object)
- Modify: `apps/play-api/src/env.ts` (`SCREEN_LINKS: DurableObjectNamespace<ScreenLinks>`)
- Modify: `apps/play-api/src/index.ts` (routes; `export { ScreenLinks }`)
- Modify: `apps/play-api/wrangler.jsonc` (binding `SCREEN_LINKS` → `ScreenLinks`; migration `{ "tag": "v7", "new_sqlite_classes": ["ScreenLinks"] }`)
- Modify: `apps/play-api/vitest.config.ts` (exclude `src/screens/screen-links.ts` from coverage, like `links.ts`)
- Test: `apps/play-api/tests/screens.test.ts` (add the link cases; add `SCREEN_LINKS` to that file's Miniflare `durableObjects`)

**Interfaces:**
- Consumes: `GameRoom.mayLink`, `GameRoom.addScreen` (Task 6); `Limiter.guess` with `DEVICE_JOIN_RULE`/`IP_JOIN_RULE`; `isMoveCode`-style check (6 chars of `ROOM_CODE_ALPHABET`).
- Produces (all need `TV` on; otherwise 404):
  - `POST /v1/screens` (device token; body `{}` or `{ "showing": "<ROOM CODE>" }`) → 201 `{ token: string, code: string, url: "<origin>/tv/<token>", expiresIn: 600000 }`.
  - `GET /v1/screens/{token}/ws` (device token, app headers or browser subprotocols) → the waiting socket, only for the device that made the link (else 404). Server → TV messages:
    - `{ "t": "linked", "room": "<ROOM CODE>" }` — then the token is spent; also sent at once to a socket that connects after the link happened, until expiry.
    - `{ "t": "expired" }` — then the server closes the socket (1000).
  - `POST /v1/screens/link` (phone's device token; body exactly one of `token` or `code`, plus `room`, optional `move: true`) →
    - 200 `{ "linked": true }`
    - 404 `{ "error": "not_found" }` — no such live token or code (a wrong code counts as a miss)
    - 429 `{ "error": "too_many_attempts", "retryAfter": n }` (+ `retry-after` header)
    - 403 `{ "error": "not_seated" }` — the phone is not the host and holds no seat there (also for a room that doesn't exist: no oracle)
    - 409 `{ "error": "showing" }` — the TV is showing another table and `move` wasn't sent
    - 400 `{ "error": "bad_request" }`
    On 200 the room lists the TV as a screen (`addScreen`) before the TV is told, so its socket is a member's.
  - `GET /tv/{token}` → 302 to `/play/tv-link/{token}` (a phone without the app; the app takes the universal link once stage 3 adds `/tv/*` to the site association — not in this stage, so shipped apps never open a link they can't handle).
  - In `screens.ts`:
    - `export const SCREEN_LINK_TTL_MS = 600_000;`
    - `export function newLinkToken(bytes: Uint8Array /* 16 */): string` (base64url, 22 chars)
    - `export const LINK_TOKEN = /^[A-Za-z0-9_-]{22}$/;`
    - `export function newLinkCode(rng: Rng): string` (6 chars of `ROOM_CODE_ALPHABET`)
    - `export function parseLinkBody(body: Record<string, unknown> | null): { token: string } & LinkRest | { code: string } & LinkRest | null` where `LinkRest = { room: string; move: boolean }`
    - `export function linkDecision(link: { showing: string | null; spent: boolean; expires: number } | null, room: string, move: boolean, now: number): "link" | "already" | "showing" | "gone"` (`already`: the TV already shows `room` → 200 without re-linking)
  - `ScreenLinks` (instance `token:<token>` or `code:<code>`):
    - `open(owner: string, token: string, code: string, showing: string | null, now: number): Promise<void>` (token instance; alarm at expiry)
    - `reserve(token: string, now: number): Promise<boolean>` (code instance; false when a live row for another token exists)
    - `tokenFor(now: number): string | null` (code instance)
    - `link(room: string, move: boolean, now: number): Promise<"link" | "already" | "showing" | "gone">` (token instance; on `link`, sends `linked` to open sockets and marks spent)
    - `fetch(request)`: socket upgrade; `DEVICE_HEADER` must equal `owner`.
    - `alarm()`: sends `expired`, closes sockets, `deleteAll()`.

Renewal is the TV asking `POST /v1/screens` again before 10 minutes; the old link simply expires.

- [ ] **Step 1: Write the failing unit tests** in `screens.test.ts`: token is 22 base64url chars from 16 bytes; code is 6 alphabet chars; `parseLinkBody` takes `{token, room}`, `{code, room, move:true}`, refuses both token and code, neither, a bad room code, extra keys, lower-case code (codes are upper-cased first: `"bcdfgh"` → `"BCDFGH"`); `linkDecision` table: null → gone, expired → gone, spent → gone, showing other & !move → showing, showing other & move → link, showing same → already, idle → link.

- [ ] **Step 2: Write the failing integration tests** in `tests/screens.test.ts`:

```ts
test("a phone links its table to a TV by the QR token")      // tv POST /v1/screens; tv opens /v1/screens/{token}/ws; a seated at a table POSTs link {token, room} → 200; tv socket gets {t:"linked",room}; tv opens room ws role=screen → member, snapshot as a screen; a's next snapshot has screen
test("and by the backup code, in any case")                   // link {code: code.toLowerCase(), room}
test("a link is spent once used")                              // second link with the same token → 404
test("a link expires after ten minutes and a new one replaces it") // Miniflare: run the DO alarm via a short TTL? Use DEV_SPEED, which divides SCREEN_LINK_TTL_MS like other timers, → tv socket gets {t:"expired"}; token → 404; a fresh POST /v1/screens works
test("only a phone at the table may link it")                 // spectator device (connected, no seat) → 403 not_seated; unknown room → 403 not_seated
test("wrong codes back off like room codes")                   // 5 wrong codes → 404 each; 6th → 429 with retryAfter; the phone can still join a table by code (separate key)
test("moving a TV that shows another table needs move")       // tv showing table X (POST /v1/screens {showing:X}); phone at Y links → 409 showing; with move:true → 200
test("only the TV that made a link may wait on it")           // a opens /v1/screens/{token}/ws → 404
test("/tv/<token> sends a phone without the app to the web player") // 302 Location /play/tv-link/<token>
test("with TV off every screens route is a 404")
```

`SCREEN_LINK_TTL_MS` divides by `devSpeed(env)` in the DO (like the room's timers), so the expiry test runs with `DEV_SPEED: "100"` (6 s).

- [ ] **Step 3: Run to fail.** `pnpm --filter @pounce/play-api exec vitest run src/screens tests/screens.test.ts` → FAIL.

- [ ] **Step 4: Implement** `screens.ts`, `screen-links.ts`, the routes, the binding and the migration.

- [ ] **Step 5: Run everything.** `pnpm lint && pnpm typecheck && pnpm test` (repo root) → PASS, coverage thresholds hold.

- [ ] **Step 6: Commit**

```bash
git add apps/play-api
git commit -m "Server: link a phone's table to a TV by its QR or backup code"
```

---

### Task 8: Old clients keep playing (fixtures and decode tests)

**Files:**
- Create: `apps/play-api/fixtures/protocol/screen-server-messages.json`
- Create: `apps/play-api/tests/screen-protocol-fixtures.test.ts` (builds the samples from a real `RoomCore` and checks the file matches, like `tests/tiles-protocol-fixtures.test.ts`)
- Create: `apps/play-ios/PounceKit/Tests/PounceKitTests/ScreenProtocolTests.swift`
- Create or modify: a play-web unit test beside the store's existing tests (find with `ls apps/play-web/tests`)

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: the fixture file, an object `{ "snapshot": <Cat Tower snapshot with "screen": true>, "tilesSnapshot": <tiles snapshot with "screen": true>, "aim": <{t:"aim"} Cat Tower>, "tilesAim": <{t:"aim"} tiles>, "aimClear": {"t":"aim","seat":0} }`.

- [ ] **Step 1: Write the fixture generator test** (fails until the file exists; write the file from its output, as the tiles fixtures test does).

- [ ] **Step 2: Swift test, against the decoder shipped today**

```swift
func testSnapshotWithScreenDecodesAsBefore() throws  // ServerMessage decodes fixture "snapshot" and "tilesSnapshot"; room fields equal the same JSON with "screen" removed
func testSocketSkipsAim() throws                     // the RoomSocket message decode path (RoomSocket.swift:242) returns nil/skip for all three aim samples, no error
```
Read the fixture through `Fixtures.swift` like `ProtocolTests` does.

- [ ] **Step 3: Web test** — the store's snapshot handling accepts the `screen` snapshot unchanged and ignores the `aim` samples (no state change, no error).

- [ ] **Step 4: Run**

Run: `pnpm --filter @pounce/play-api exec vitest run tests/screen-protocol-fixtures.test.ts tests/fixtures-pinned.test.ts && swift test --package-path apps/play-ios/PounceKit --filter ScreenProtocolTests && pnpm --filter @pounce/play-web test`
Expected: PASS, pinned hashes unchanged.

- [ ] **Step 5: Commit**

```bash
git add apps/play-api/fixtures/protocol/screen-server-messages.json apps/play-api/tests/screen-protocol-fixtures.test.ts apps/play-ios/PounceKit/Tests/PounceKitTests/ScreenProtocolTests.swift apps/play-web
git commit -m "Server: pin that today's apps read a TV table's messages and skip aim"
```

---

### Task 9: The protocol note, cross-platform check, and the PR

**Files:**
- Create: `docs/tv-protocol.md` — the wire contract for stages 2–4: the `role=screen` socket, `screen`, `aim` shapes and rules, `/v1/screens` routes and socket messages, `/tv/<token>`, error codes, the 10 s grace, the 10 min link life. Short, exact, no narrative.

- [ ] **Step 1: Write `docs/tv-protocol.md`** from the Interfaces blocks above.
- [ ] **Step 2: Cross-platform matrix before merge** on a dev server on its own port (`DEV_SERVER_URL=http://localhost:8791`, never 4343):
  - `apps/play-ios/scripts/e2e.sh full --local 2 --bots 2` (the iPhone client) passes.
  - `pnpm --filter @pounce/play-web e2e` (browser phones) passes.
  - A scripted screen (a small node script in the scratchpad using `ws`) joins a game the e2e client is playing and receives only public data; `pounce-e2e` plays to the end with the screen attached.
- [ ] **Step 3: Open the PR** titled "Getting ready for Pounce on the TV" (family-readable; server-only, no app change visible yet), with the design doc commits, the plan and this stage. Merge once `check`, `build`, `e2e-web` pass and the production smoke (no `cf-connecting-ip`) shows `/healthz` and `POST /v1/screens` working.

---

## After stage 1

- **Stage 2, web** (`docs/superpowers/plans/2026-11-16-tv-table-2-web.md`): split `CatTowerTable` and the tiles table into a public table and hand/controller parts; `/play/tv` (no first run, its own device token key in storage, home with the link QR and two game buttons, d-pad focus, Start press for audio and full screen, Wake Lock, lobby with invite QR and code, TV table layouts at 1920×1080, celebrations, menus); `/play/tv-link/<token>`; the phone controller layout with the Cards/Table switch, Show on TV, `aim` sending and the glow, sound rule; e2e for every item in the spec's "Web e2e" list and a TV project in `e2e/main-thread.spec.ts`.
- **Stage 3, iPhone** (`…-3-iphone.md`): controller layouts for both games, Cards/Table switch per table, tips, Show on TV with the camera scanner (purpose string, privacy answers unchanged) and typed backup code, `/tv/*` in the site association plus universal link handling, `aim` sending, quiet game sounds on Cards, the haptic on your turn.
- **Stage 4, Apple TV** (`…-4-appletv.md`): `.tvOS(.v26)` in PounceKit with tests in CI, a tvOS target in `project.yml` with the iPhone's bundle id, the shared SpriteKit table (one copy of the drawing code; a cross-platform seam for `UIScreen`/`UIApplication`/`UIColor`), the focus-engine shell, Keychain-only storage, main-thread lint over the target, `FrameRateTests` on the Apple TV simulator, TestFlight to Family and Friends. Adding tvOS to the App Store Connect record needs JD's OK through the manager session first.
- Stages 2 and 3 may run side by side after stage 1 merges (separate worktrees; they touch different apps).
