# Players and identities (PR 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The play API learns who people are: every person is a player from the first launch, Sign in with Apple upgrades a guest in place or merges a second device, seats and tables belong to players, settings sync, and pushes reach every device of a player, all without changing what today's app sees.

**Architecture:** Two new SQLite Durable Objects, `Player` (one per `playerId`) and `Identities` (a single index `(provider, subject_hash) → playerId`). An `accounts` module in the Worker orchestrates them with the existing `DeviceIndex` and `GameRoom`. `RoomCore` learns which players each connected device controls (passed by the Worker in `x-play-player`) and stamps `playerId` on seats. Device tokens stay the only session.

**Tech Stack:** Cloudflare Workers, SQLite Durable Objects, WebCrypto (RS256, ES256, SHA-256), vitest + Miniflare, TypeScript strict.

**Spec:** `docs/superpowers/specs/2026-11-04-daily-habit-design.md` (§13.1 identity, §13.2 DOs, §13.4 API, §12.5 across devices, §14 deletion and retention, §14.1 age bands, §15 row 1).

## Global Constraints

- The current iOS app must keep working unchanged: a device that never uploads a profile plays exactly as today (seats by `deviceId`).
- `PROTOCOL_VERSION` stays 1; no field leaves the server that today's client would choke on. `playerId` never appears in `RoomView`.
- `playerId` = `"p_"` + 16 random bytes, base64url (22 chars). Never derived from a provider subject.
- `subject_hash = SHA-256(provider + ":" + subject)`, lowercase hex. Raw provider subjects are never stored.
- `personKey` = 32 random bytes base64url (43 chars); the server stores only its SHA-256 hex (trust on first use).
- Sign in with Apple: no scopes; verify RS256 against Apple's JWKS by `kid`; `iss` = `https://appleid.apple.com`, `aud` = `SIWA_CLIENT_ID` (`com.conleychaos.play`), `exp` in the future, `nonce` claim = SHA-256 hex of the raw nonce the app sends; a nonce is accepted once.
- `SIWA_KEY_P8` / `SIWA_KEY_ID` are optional secrets. Without them sign-in works, no refresh token is stored, and nothing is revoked.
- Age bands: `kitten` (<13), `teen` (13–17), `adult`. A `kitten` device gets no push of any kind. A `teen` device gets no alert push between 00:00 and 06:00 local time. A `kitten` player can't sign in.
- Never log player ids, pair ids, tokens, names or subjects.
- Merged guest stubs are deleted after 30 days; a guest player (no sign-in identity) unseen for 90 days is deleted.
- Never touch the server on `:4343`; never handle real keys or tokens (tests generate their own).

## Review Focus

1. **An old app** (no profile upload, no `x-play-player`) seats, plays, gets pushes and lists tables exactly as before. Pinned by the existing suites staying green plus Task 4's "no players" cases.
2. **A stolen person id** (seen at a table) without the person key can't bind, sign in, or read state. Task 6: profile with the right id and wrong key is rejected; sign-in with a wrong key is 404.
3. **A replayed Apple token** is refused the second time. Task 6: the same token and nonce twice gives 401.
4. **A device that signs out** stops controlling the account's seats on its next socket, and its next profile upload makes a fresh guest. Task 6.
5. **A deleted account's seats** fall back to the device that last held them and the game goes on. Task 6: after `DELETE /v1/me`, the seat holder's device still acts.

---

### Task 1: Ids, parsing and state merge (pure)

**Files:**
- Create: `apps/play-api/src/players/ids.ts`, `apps/play-api/src/players/parse.ts`, `apps/play-api/src/players/state.ts`, `apps/play-api/src/players/age.ts`
- Test: `apps/play-api/src/players/ids.test.ts`, `parse.test.ts`, `state.test.ts`, `age.test.ts`

**Interfaces:**
- Produces (`ids.ts`): `PLAYER_ID: RegExp`, `PERSON_ID: RegExp` (UUID), `PERSON_KEY: RegExp`, `newPlayerId(): string`, `base64url(bytes: Uint8Array): string`, `sha256Hex(text: string): Promise<string>`, `subjectHash(provider: string, subject: string): Promise<string>`.
- Produces (`parse.ts`): `type AgeBand = "kitten" | "teen" | "adult"`; `type ProfilePerson = { id: string; name: string; cat: number; key: string; ageBand?: AgeBand; at?: number }`; `type Profile = { timeZone: string; ageBand?: AgeBand; people: ProfilePerson[] }`; `parseProfile(body: unknown): Profile | null` (1–8 people, unique ids, name via the same 1–20 rule as `Person`, cat 0–7, `timeZone` accepted by `Intl.DateTimeFormat`); `type Entry = { v: unknown; at: number }`; `type Section = Record<string, Entry>`; `type StatePatch = { settings?: Section; tutorial?: Section; archive?: Section }`; `parseStatePatch(body: unknown): StatePatch | null` (≤64 keys per section; keys `/^[A-Za-z][A-Za-z0-9_.]{0,31}$/`, archive keys must match `ROOM_CODE`; each `v` JSON ≤256 bytes; `at` a non-negative integer); `parseSignIn(body: unknown): { proof: unknown; person: { id: string; key: string } } | null`; `parseLink(body: unknown): { proof: unknown; confirmMerge: boolean } | null`.
- Produces (`state.ts`): `mergeSection(current: Section, patch: Section, now: number): Section` — last writer wins per key by `at`; a tie keeps `current`; `at` above `now + 60_000` is clamped to `now + 60_000`.
- Produces (`age.ts`): `pushBlocked(band: AgeBand | null): boolean` (kitten), `alertsBlocked(band: AgeBand | null, timeZone: string | null, now: number): boolean` (teen and local hour in [0, 6); a bad or missing zone is UTC).

- [ ] **Step 1: Write the failing tests.** `newPlayerId()` matches `PLAYER_ID` and two calls differ; `subjectHash("apple","x")` equals SHA-256 hex of `"apple:x"`; `parseProfile` accepts a valid body and rejects: 9 people, duplicate ids, a 42-char key, cat 8, `timeZone: "Mars/Base"`, an unknown key; `parseStatePatch` rejects a 300-byte value, key `"1a"`, archive key `"hello"`, 65 keys; `mergeSection` keeps the newer entry, keeps current on a tie, clamps a far-future `at`; `alertsBlocked("teen","America/Los_Angeles", <03:00 PT>)` is true, at 06:00 PT false, `adult` always false; `pushBlocked("kitten")` true.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run src/players` — FAIL (modules missing).
- [ ] **Step 3: Implement the four modules.**
- [ ] **Step 4: Run** the same command — PASS.
- [ ] **Step 5: Commit** `feat(play-api): player ids, profile and state parsing`.

### Task 2: Identity providers (device, apple)

**Files:**
- Create: `apps/play-api/src/players/apple.ts`, `apps/play-api/src/players/providers.ts`
- Modify: `apps/play-api/src/env.ts` (add `PLAYERS`, `IDENTITIES`, `SIWA_CLIENT_ID: string`, `SIWA_KEY_P8?`, `SIWA_KEY_ID?`)
- Test: `apps/play-api/src/players/apple.test.ts`, `providers.test.ts`

**Interfaces:**
- Produces (`apple.ts`): `type AppleProof = { identityToken: string; nonce: string; authorizationCode?: string }`; `parseAppleProof(proof: unknown): AppleProof | null`; `verifyAppleToken(token: string, opts: { clientId: string; nonce: string; nowSec: number; fetcher: typeof fetch }): Promise<{ sub: string; exp: number } | null>` (never throws; JWKS from `https://appleid.apple.com/auth/keys`, cached 1 h in the isolate, refetched once on an unknown `kid`); `appleClientSecret(p8: string, keyId: string, teamId: string, clientId: string, nowSec: number): Promise<string>` (ES256, `aud` `https://appleid.apple.com`, `exp` = iat + 300); `exchangeAppleCode(env: Env, code: string, fetcher: typeof fetch, nowSec: number): Promise<string | null>` (POST `/auth/token`, returns `refresh_token`; null without the key or on failure); `revokeAppleToken(env: Env, refreshToken: string, fetcher: typeof fetch, nowSec: number): Promise<void>`; `resetAppleKeyCache(): void` (tests).
- Produces (`providers.ts`):
  ```ts
  export type ProviderId = "device" | "apple";
  export type Verified = { subject: string; secret?: string; nonce?: { hash: string; expiresAt: number } };
  export type IdentityProvider = {
    id: ProviderId;
    /** Offered by POST /v1/identities/{provider}; `device` binds through the profile instead. */
    signIn: boolean;
    verify(proof: unknown, env: Env, fetcher: typeof fetch, nowSec: number): Promise<Verified | null>;
    revoke?(secret: string, env: Env, fetcher: typeof fetch, nowSec: number): Promise<void>;
  };
  export function provider(id: string): IdentityProvider | null;
  ```
  `apple.verify` returns `nonce.hash` = the token's nonce claim and `expiresAt` = `exp * 1000`, and `secret` only when the code exchange succeeded.

- [ ] **Step 1: Write the failing tests.** Generate an RSA-2048 key in the test, publish its JWK with a `kid` through a fake fetcher, sign tokens. `verifyAppleToken` passes a good token; returns null for: wrong `aud`, wrong `iss`, expired, nonce hash mismatch, tampered payload, unknown `kid` after one refetch, `alg: "none"`. The JWKS is fetched once for two verifications. `appleClientSecret` verifies with the public half and carries `iss`=team, `sub`=client id. `exchangeAppleCode` returns null with no key set and makes no request; with a key it posts `grant_type=authorization_code` and returns the refresh token. `provider("apple")?.signIn` is true, `provider("device")?.signIn` false, `provider("google")` null.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run src/players/apple.test.ts src/players/providers.test.ts` — FAIL.
- [ ] **Step 3: Implement.** RS256 via `crypto.subtle.importKey("jwk", …, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" })`. Reuse `createApnsJwt`'s PEM handling by moving `pemBody` to `ids.ts`.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `feat(play-api): Sign in with Apple verification and the provider interface`.

### Task 3: Rooms know players

**Files:**
- Modify: `apps/play-api/src/room/core.ts`
- Test: `apps/play-api/src/room/core.players.test.ts` (new); existing core tests stay green unchanged.

**Interfaces:**
- Produces:
  - `SeatInfo.playerId?: string`; `RoomState.devices[id].players?: Record<string, string>` (personId → playerId).
  - `connect(deviceId: string, players: Record<string, string> = {}): Outbound[]` — stores the map.
  - `controlledSeats(deviceId)`: a seat whose `deviceId` matches, or whose `playerId` is a value of that device's map.
  - `adopt(rule: { person: Record<string, string> } | { from: string; to: string | null }): Outbound[]` — `person`: sets `playerId` on seats whose `person.id` is a key and that have no `playerId`; `from/to`: replaces (or with `null`, removes) `playerId`. Sends snapshots only if a seat changed.
  - `seatPlayers(): string[]` (distinct, human seats).
  - `type YourTurnIntent = { kind: "your_turn"; deviceId: string; playerId?: string; seat: Seat; personName: string; tableName: string; code: string }`; `type DismissIntent = { kind: "dismiss"; playerId: string; exceptDeviceId: string; code: string }`; `type PushIntent = YourTurnIntent | DismissIntent`.
- Behavior:
  - `claim` stamps `playerId` from the device's map; `person_seated` also when that `playerId` already holds a seat.
  - A seat's presence is the best of the devices that control it (awake > away > asleep; none → away). Presence events fire only when a seat's aggregate changes. `yours` = controlled.
  - "Your turn" pushes are queued when the seat's aggregate presence isn't awake, with `playerId` when the seat has one.
  - When a seat with a `playerId` acts and a "your turn" push was sent for the turn it is ending, queue a `DismissIntent` excluding the acting device.

- [ ] **Step 1: Write the failing tests.** Device "ipad" with map `{P1: "p_A"}` controls a seat claimed by "phone" with the same map; a device with no map doesn't; `claim` stamps `playerId`; a second person mapping to the same player is `person_seated`; seat presence stays awake while one of two devices is awake and goes away when both are; no push while the iPad is awake; push intent carries `playerId`; acting after a push queues one dismiss excluding the actor; acting without a prior push queues none; `adopt({person})` backfills and emits snapshots, a second identical adopt emits nothing; `adopt({from, to: null})` removes control from the iPad but the seat's device still controls it; `seatPlayers()`.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run src/room` — new tests FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `pnpm --filter @pounce/play-api test` — PASS with `core.ts` at 100% coverage.
- [ ] **Step 5: Commit** `feat(play-api): seats belong to players`.

### Task 4: Storage — Player, Identities, DeviceIndex, pushes

**Files:**
- Create: `apps/play-api/src/players/player.ts` (`Player` DO), `apps/play-api/src/players/identities.ts` (`Identities` DO), `apps/play-api/src/room/tables.ts` (the tables SQL shared by `DeviceIndex` and `Player`)
- Modify: `apps/play-api/src/room/device-index.ts`, `apps/play-api/src/push/apns.ts`, `apps/play-api/wrangler.jsonc` (bindings `PLAYERS`→`Player`, `IDENTITIES`→`Identities`; migration `v2` `new_sqlite_classes: ["Player", "Identities"]`; var `SIWA_CLIENT_ID: "com.conleychaos.play"`), `apps/play-api/src/index.ts` (export the classes), `apps/play-api/vitest.config.ts` (exclude the two DOs and `accounts.ts` from coverage, as for `device-index.ts`), `apps/play-api/tests/push-entry.ts`, `tests/worker.test.ts` and `tests/push.test.ts` Miniflare configs (new bindings)
- Test: `apps/play-api/src/push/apns.test.ts`, `apps/play-api/tests/push.test.ts`

**Interfaces:**
- `Identities` (one instance, `idFromName("global")`):
  `bind(provider: string, subjectHash: string, playerId: string, verifier?: string): { playerId: string; created: boolean } | { mismatch: true }`;
  `lookup(provider, subjectHash): { playerId: string; verifier: string | null } | null`;
  `repoint(from: string, to: string): void`; `remove(provider, subjectHash, playerId): void`; `removePlayer(playerId): void`;
  `useNonce(hash: string, expiresAt: number, now: number): boolean` (false if seen; prunes expired).
- `Player`:
  - `type PlayerMeta = { name: string; cat: number; ageBand: AgeBand | null; forwardTo: string | null; signedIn: boolean }`
  - `type IdentityRow = { provider: string; subjectHash: string; deviceId: string | null; secret: string | null }`
  - `type HouseholdPerson = { personId: string; playerId: string; name: string; cat: number }`
  - `type MeState = { settings: Section; tutorial: Section; archive: Section; people: HouseholdPerson[] }`
  - `type PlayerExport = { identities: IdentityRow[]; devices: string[]; tables: TableEntry[]; settings: Section; tutorial: Section; archive: Section; household: (HouseholdPerson & { deviceId: string })[] }`
  - methods: `touch(t: { deviceId: string; name: string; cat: number; ageBand?: AgeBand; at: number; now: number }): void` (creates; name/cat last writer wins by `at`); `meta(): PlayerMeta | null`; `addIdentity(row: IdentityRow): void`; `identities(): IdentityRow[]`; `removeIdentities(provider: string, deviceId?: string): IdentityRow[]`; `attachDevice(deviceId, now)`; `detachDevice(deviceId)`; `deviceIds(): string[]`; `setHousehold(deviceId, people: HouseholdPerson[])`; `upsertTable(entry)`, `removeTable(code)`, `listTables()` (no-ops without meta); `getState(): MeState`; `patchState(patch: StatePatch, now)`; `exportForMerge(): PlayerExport`; `absorb(e: PlayerExport, now)`; `becomeStub(to: string, now)`; `destroy()`.
  - `alarm()`: a stub 30 days after `becomeStub`, or a guest 90 days after its last `touch`, is deleted (`deleteAll`).
- `DeviceIndex` additions: `setProfile(p: { timeZone: string; ageBand: AgeBand | null; people: Record<string, string> }): { changed: Record<string, string>; tables: string[] }`; `setAccount(playerId: string | null)`; `players(): { people: Record<string, string>; account: string | null }`; `forgetPlayer(playerId): string[]` (removed personIds; clears `account` if it matches); `repointPlayer(from, to)`; `push(intent: YourTurnIntent | DismissIntent)` — skips everything for a kitten device, alerts for a teen at 00:00–06:00.
- `apns.ts`: `sendApns(fetcher, cfg, token, payload: { kind: "alert"; title; body; code } | { kind: "background"; data: Record<string, unknown>; collapseId: string })` — background uses `apns-push-type: background`, `apns-priority: 5`, `aps: { "content-available": 1 }`; `pushDismiss(env, token, code, fetcher?, nowSec?)` sends `{ kind: "dismiss", code }`.

- [ ] **Step 1: Write the failing tests.** `apns.test.ts`: a background payload sends the right headers and body and no alert. `push.test.ts` (through `push-entry.ts`'s test routes): a kitten device sends nothing; a teen device at 02:00 local sends no alert but does send a dismiss; an adult device at 02:00 sends.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run src/push tests/push.test.ts` — FAIL.
- [ ] **Step 3: Implement** the DOs, `tables.ts`, the `DeviceIndex` additions and the APNs payload.
- [ ] **Step 4: Run** `pnpm --filter @pounce/play-api test && pnpm --filter @pounce/play-api typecheck` — PASS.
- [ ] **Step 5: Commit** `feat(play-api): Player and Identities storage, background pushes and age-band gates`.

### Task 5: Accounts flows and routes

**Files:**
- Create: `apps/play-api/src/players/accounts.ts`
- Modify: `apps/play-api/src/index.ts`, `apps/play-api/src/room/game-room.ts`
- Test: `apps/play-api/tests/accounts.test.ts` (new, Miniflare, Apple JWKS served by `outboundService`)

**Interfaces:**
- `accounts.ts` (each takes `env` and returns data; `index.ts` maps to HTTP):
  - `uploadProfile(env, deviceId, profile: Profile, now): Promise<{ players: Record<string, string>; rejected: string[] }>` — per person: `Identities.bind("device", subjectHash("device", id), newPlayerId(), sha256Hex(key))`; a mismatch is rejected; `Player.touch`, `attachDevice`; then `DeviceIndex.setProfile`; for changed mappings, `GameRoom.adopt({ person })` on the device's tables; on a signed-in device, `Player(account).setHousehold(deviceId, people not mapping to the account)`.
  - `devicePlayers(env, deviceId): Promise<Record<string, string>>` — the device's map plus the account's household.
  - `resolveMe(env, deviceId, personId: string | null): Promise<string | null>` — the named person if it's in `devicePlayers`, else the account, else null.
  - `signIn(env, deviceId, providerId, body, now, fetcher)`: verify (401 `bad_proof`), use the nonce once (401), look up the person's device identity and check the key (404 `unknown_person`), kitten (403 `not_allowed`), guest already has this provider (409 `already_signed_in`); `Identities.bind(provider, hash, guest)`: created → `upgraded`; same player → `same`; another → `merge(guest → owner)` → `merged`. Then set the device account if it has none, attach the device. Returns `{ playerId, outcome, account: boolean, profile: { name, cat } }`.
  - `linkIdentity(env, me, providerId, body, now, fetcher)`: 409 `already_linked`; owned by another player → 409 `{ error: "merge_needed", otherPlayer: { name, cat } }` unless `confirmMerge`, then `merge(other → me)`.
  - `unlinkIdentity(env, deviceId, me, providerId, now, fetcher)`: removes, revokes; if no sign-in identity remains, `detach` every other device.
  - `signOut(env, deviceId)`: `DeviceIndex.forgetPlayer(account)`, the account's device identities held by this device are removed from `Identities` and the `Player`, `detachDevice`.
  - `deleteMe(env, me, fetcher, now)`: revoke secrets, `Identities.removePlayer`, `forgetPlayer` on each device, `GameRoom.adopt({ from: me, to: null })` on each table, `Player.destroy()`.
  - `merge(env, from, to, now)`: `exportForMerge` → `Identities.repoint` → `absorb` → `DeviceIndex.repointPlayer` on each from-device → `GameRoom.adopt({ from, to })` on each from-table → `becomeStub`. Each step is idempotent, so a retried sign-in finishes a half-done merge.
- Routes (device-token auth; `/v1/me/*` take `?person=<uuid>`):
  - `PUT /v1/devices/me/profile` (2 KB) → 200 `{ players, rejected }`
  - `POST /v1/identities/{provider}` (4 KB) → 200 per `signIn`
  - `POST /v1/me/identities/{provider}` (4 KB), `DELETE /v1/me/identities/{provider}` → 204, `POST /v1/me/signout` → 204, `DELETE /v1/me` → 204
  - `GET /v1/me/state` → 200 `MeState`; `PATCH /v1/me/state` (8 KB) → 204
  - `GET /v1/devices/me/tables` → the device's tables merged with each of its players' tables by code (newest `updatedAt` wins, `yourTurn` from the newest).
  - No player for `/v1/me/*` → 404 `no_player`.
- `GameRoom`: `fetch` reads `PLAYER_HEADER = "x-play-player"` (JSON `Record<personId, playerId>`, validated, max 16 entries) and passes it to `connect`; the Worker strips any client copy. `adopt(rule)` RPC runs `core.adopt` through `after`. Push routing: `your_turn` with `playerId` → `Player.deviceIds()` ∪ the seat's device; `dismiss` → `Player.deviceIds()` minus `exceptDeviceId`. `updateTables` also reports to each `seatPlayers()` player (`yourTurn` = the actor's seat has that `playerId`) and keeps the listed players in `listed` (new `players` column) so a close removes them.

- [ ] **Step 1: Write the failing tests** in `tests/accounts.test.ts`: profile binds two people and returns two `p_` ids, a second upload returns the same ids; same id with another key is rejected; a guest signs in with Apple → `upgraded`, same `playerId`; the same token again → 401; an iPad guest signs in with the same Apple sub → `merged`, then the iPad's socket controls the phone's seat (acts on it) and `GET /v1/devices/me/tables` on the iPad lists the table; `PATCH`/`GET /v1/me/state` round-trips from the iPad and the phone sees it; a kitten person → 403; sign out on the iPad → its next socket can't act on the seat; `DELETE /v1/me` on the phone → the phone's device still acts on its seat, the iPad's tables list drops it, and sign-in with the same sub makes a new player (`upgraded`); a client-supplied `x-play-player` header is ignored; the `/v1/me/state` routes without a player → 404.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run tests/accounts.test.ts` — FAIL.
- [ ] **Step 3: Implement** `accounts.ts`, the routes, and the `GameRoom` changes.
- [ ] **Step 4: Run** `pnpm --filter @pounce/play-api test && pnpm --filter @pounce/play-api typecheck && pnpm --filter @pounce/play-api lint` — PASS.
- [ ] **Step 5: Commit** `feat(play-api): accounts, the anonymous upgrade and sync routes`.

### Task 6: Deploy config and docs

**Files:**
- Modify: `.github/workflows/ci.yml` (sync `PLAY_API_SIWA_KEY_P8`/`_ID` as `SIWA_KEY_P8`/`SIWA_KEY_ID`, both or neither, with the APNs pair's warning style), `README.md` (secrets table rows), `apps/play-api/wrangler.jsonc` comment (secrets list).

- [ ] **Step 1:** Edit the three files.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api test` (a config test reads `wrangler.jsonc`) — PASS.
- [ ] **Step 3: Commit** `ci(play-api): optional Sign in with Apple key secrets`.
