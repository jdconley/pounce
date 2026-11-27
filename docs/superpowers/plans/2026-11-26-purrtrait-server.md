# Purrtrait server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The server half of Purrtrait: the words, a pure engine, the game module, the room's turn clock, same-room admission (near keys), the live ink relay, `remove`, fixtures and the privacy lines, behind the `GAMES` flag.

**Architecture:** `src/purrtrait/` holds the pure rules (words, engine, view, parser, ink checks). `src/games/purrtrait.ts` adapts it to `GameModule`. The room gains generic abilities that other games never use (a turn clock through two optional module hooks, a `removed` list, host handoff), and Purrtrait-only behaviour keyed on `state.game === "purrtrait"` (screen-only creation, near keys, ink, refusals). Ink lives only in `RoomCore` memory, like `aimTimes`.

**Tech Stack:** TypeScript on Cloudflare Workers and Durable Objects, Vitest, Miniflare.

**Spec:** `docs/superpowers/specs/2026-11-26-purrtrait-design.md`. Parents: `docs/tv-protocol.md`, `2026-11-25-birdwatch-design.md` §7-8 (options, fixtures, rollout).

## Global Constraints

- Code id `purrtrait`, display title "Purrtrait", 2 to 10 seats. Never the commercial draw-and-guess game's name, category names or wording anywhere. No emoji.
- `GAMES` in `apps/play-api/wrangler.jsonc` stays `"tiles,birdwatch"`. `.dev.vars.example` and tests list `purrtrait`.
- Cat Tower, Tuna Tiles and Birdwatch payloads stay byte for byte (`tests/fixtures-pinned.test.ts`).
- Ink is never written to Durable Object storage, logs, reports or analytics. Only the screen and the drawer's device get it.
- The word reaches no view or event but the drawer's device before the reveal.
- `pnpm check` passes. Local server on port 8796; never 8787 or 4343.

## Wire contract (the web and iOS sessions build against this)

```ts
type PurrOptions = { timer: 45 | 60 | 90 };            // default { timer: 60 }
type PurrPhase = "choosing" | "drawing" | "reveal" | "over";
type Level = "easy" | "tricky";
type Group = "animals" | "food" | "home" | "outside" | "things" | "actions" | "jobs" | "places";

type PurrAction =
  | { type: "choose"; level: Level }
  | { type: "gotIt"; seat: Seat }
  | { type: "giveUp" }
  | { type: "timeUp" } | { type: "nextTurn" }   // room only: refused from a client (not_allowed)
  | { type: "forfeit" };

type PurrView = {
  seats: number; timer: 45 | 60 | 90; rounds: 2;
  phase: PurrPhase; round: number;              // 1 or 2
  drawer: Seat | null;                           // null once over
  order: Seat[];                                 // drawing order, seats still in
  scores: number[]; out: boolean[];              // per seat
  group: Group | null;                           // set once a word is chosen
  level: Level | null;
  remainingMs: number | null; paused: boolean;   // the phase's clock at snapshot time
  turn: string;                                  // turnKey, echoed in ink
  last: { word: string; guesser: Seat | null; points: number } | null;  // the reveal, and after
  winners: Seat[];
  // The drawer's device only (§10.2 of the spec):
  choices?: { easy: string; tricky: string };    // choosing; for a kitten device both are Easy words (ruling 5)
  word?: string;                                 // drawing
  youDraw?: true;                                // this device owns the drawing turn
};

type PurrEvent =
  | { type: "turn"; drawer: Seat; round: number }
  | { type: "chosen"; drawer: Seat; group: Group; level: Level }
  | { type: "guessed"; drawer: Seat; guesser: Seat; points: number; word: string }
  | { type: "missed"; drawer: Seat; word: string; reason: "time" | "gaveUp" | "left" }
  | { type: "over"; winners: Seat[]; scores: number[] };
```

Room messages (Purrtrait rooms only; anything else is answered `not_allowed`):

```jsonc
// client → server
{ "t": "ink", "seat": 3, "turn": "2:5", "ops": [["s",0,0,1,384,210,3,-1],["p",0,2,2],["u",0],["c"]] }
{ "t": "ink", "seat": 3, "turn": "2:5", "ops": [["c"], ...], "last": true }   // the last message of a resend reply
{ "t": "remove", "seat": 4 }                       // host only
// server → client (no seq; never in a snapshot)
{ "t": "ink", "seat": 3, "turn": "2:5", "ops": [...] }          // to the screen, and the drawer's other sockets (never `last`)
{ "t": "inkSync", "turn": "2:5", "ops": [...] }                 // after a screen's or the drawer's snapshot
{ "t": "inkResend", "turn": "2:5" }                             // to the drawer's device after a wake
{ "t": "error", "code": "easel_full" | "not_near" | "removed" }
```

Client rules for ink:
- **inkSync replaces.** On `inkSync`, drop whatever is on the easel for that turn and draw its `ops`. It has no `["c"]`, and undone strokes are already gone. It may come with `ops: []`.
- **inkSync and inkResend reach every socket of the drawer's device**, not only the one that just connected. A socket that already shows the drawing gets the same drawing again. It replaces, so nothing changes. Answer `inkResend` from one socket only: the one that is drawing.
- **The resend reply.** Answer `inkResend` with the whole easel. The first message starts with `["c"]` and carries your own stroke ids, which only have to go up. The final message carries `"last": true`, including when the reply is a single message. From the first message to the one marked last, the reply is exempt from the 25-a-second limit, once, for up to 5 seconds. Until the reply's first message arrives, the room drops ink that doesn't start with `["c"]`.
- **Send Clear on its own.** A batch that would take the easel past 500 strokes or 30 000 points is refused whole, with `easel_full`, even when it also holds a `["c"]`. After `easel_full`, send `["c"]` as its own message, then draw again.

Snapshot additions: `room.gameId: "purrtrait"`, `room.purrtrait: PurrView`, `room.options: { timer }`, and for the screen only `room.near: { key: string, code: string, expiresIn: number }` (`key` 8 chars, `code` = the 5-character room code + the first 3 chars of the key, 8 in all). Socket: `GET /v1/rooms/{code}/ws?near=<KEY>`, or `near=<8-char typed code>`. Refusal: 403 `{ "error": "not_near" }` (close 4403), 403 `{ "error": "removed" }` (close 4403). Each refusal carries its code in the header `X-Pounce-Error: not_near|removed` too, since an app can't read a refused upgrade's body (a browser keeps its close code). The first `choosing` snapshot after Start already carries the clock (`remainingMs` 10 000, `paused: false` with the TV here). The TV's QR: `https://play.conleychaos.com/e/<CODE>?near=<KEY>`.

## Rulings (where the spec leaves it open)

1. **turnKey** is `${round}:${turnIndex}`, `turnIndex` counting every turn in the game from 0.
2. **Drawing order** is seat order of the seats filled at start (after the room compacts seats). Round 2 repeats it. A seat out (left or removed) is skipped and stays in `scores`.
3. **Words** are drawn from the game's seed. The state keeps the used word ids. Choices are one Easy and one Tricky word not used yet this game. The list holds at least 250 Easy and 250 Tricky words, so a 10-player game (20 turns, 40 offered words) never runs dry.
4. **The drawer's device.** The first `choose` fixes `drawerDevice` in room memory and in `RoomState` (a device id is not a drawing). Before it, every device controlling the drawer seat sees `choices`. After it, only `drawerDevice` gets `word`, `youDraw`, `inkSync` and `inkResend`, and only it may send `ink`, `gotIt` and `giveUp`.
5. **Kittens.** A kitten device that controls the drawer seat gets `choices.tricky` replaced by a second Easy word, scored as Easy whatever key it picks. The room passes `kittenDevices` to `view` through the controlled-seat filter it already has (`controlledSeats`), not to the engine. The engine takes an `easyOnly: boolean` on `choose`, set by the room.
6. **Timers.** `GameModule` gains optional `turnLimitMs(s): number | null` (choosing 10 000, drawing `timer * 1000`, reveal null; the room's existing `betweenAction` path runs the 4-second reveal) and `timeUpAction: A | null` (`{ type: "timeUp" }`). The room keeps `timers.turnEndsAt` and `timers.pausedLeftMs`, both in `RoomState`, divided by `DEV_SPEED` like the others, and adds `turnEndsAt` to `nextAlarm`.
7. **Pause.** When `screenShown()` turns false at a Purrtrait table, the room moves the remaining time into `pausedLeftMs` and clears `turnEndsAt`; when it turns true, the reverse. 30 minutes paused (`STALL_END_MS`) ends the game with `endReason: "stalled"` and the current scores; winners are the highest.
8. **Scoring.** Easy 1, Tricky 2, to the guesser and the drawer each. `gotIt` with the drawer's own seat or an out seat is `bad_seat`.
9. **The game ends** after round 2's last turn, or at once when fewer than 2 seats are in. Ties share `winners`.
10. **Leaving and remove.** `leaveTakeover` is not declared. A drawer who leaves mid-turn: `missed` with `reason: "left"`, next turn. `remove` (host only, Purrtrait only): in the lobby the seat opens; in a game the engine gets that seat's `forfeit`. The device and the seat's player go on `RoomState.removed: { devices: string[]; players: string[] }`; Play again copies it. A removed device's socket upgrade gets 403 `removed`; its open sockets close with 4403.
11. **Host handoff.** At a Purrtrait table, when the host's seat leaves or is removed, `hostDeviceId` moves to the device of the next seat in seat order that is in and held by a person. No host is fine when nobody is seated.
12. **Near keys.** 8 chars from the room-code alphabet, minted in `tick()` every 30 s while status is lobby or playing (`nearKeys: [current, previous]` in `RoomState`, since a woken room must keep accepting the key on the TV). A guess with a wrong key goes through `guardJoin` as a wrong code (counted). A member, the screen, and a device in `removed` (refused) skip the key check.
13. **Screens.** `POST /v1/rooms` with `game: "purrtrait"` and no `screen: true` is 400 `bad_request`. `POST /v1/screens/link` to a Purrtrait room from the host replaces `state.screens` with the new device; from anyone else 403 `not_allowed`. The old screen's sockets close with 4403.
14. **Refusals at a Purrtrait table:** `moveSeat`, `claimMove`, `nudge`, `retire` and `configure` to `bot` are `not_allowed`; no push, live table, request-to-play or invite intent is queued (the room filters them by game). `GET /v1/rooms/{code}` peeks used by `/j/` say `game: "purrtrait"` and the page shows "Scan the code on the TV." with no button. `/e/<CODE>` 302s to `/play/e/<CODE>?near=…` (the web session builds that route); `/e/*` is listed in the site association only while `PURRTRAIT_APPLINKS` is `"on"` (default `"off"`).
15. **Ink checks** (`src/purrtrait/ink.ts`, pure): ops shape as the spec §6.2; colour 0-8, width 0-2, x 0-767, y 0-1023, deltas -768..768 and the running point stays on the grid; stroke ids start at 0 and a new `s` id is exactly the next one; `p` and `u` name an existing stroke. Caps 500 strokes, 30 000 points per turn (`easel_full` once per turn). Rate 25 messages a second per device, dropped beyond (the resend after `inkResend` is exempt once).
16. **Ink memory** (`RoomCore.ink: { turn: string; ops: InkOp[] } | null`, never in `RoomState`). `compact(ops)` drops undone strokes and everything before the last `c`. `inkSync` goes right after the snapshot to a screen or `drawerDevice` that connects while `phase === "drawing"`. On a turn change `ink` is set to null. A core built from storage with `phase === "drawing"` sends `inkResend` to `drawerDevice` once it is connected.
17. **Start** needs 2 seats filled and `screenShown()`; else `not_enough_players` / `no_screen` (new code).
18. **progressKind** `"score"`; `progress` per seat its score. `endsTurn` is true for `gotIt`, `giveUp` and `timeUp`.
19. **The web build** keeps compiling: add `purrtrait` to `tests/catalog.test.ts`'s list of server games the web doesn't draw yet, as Birdwatch did (web session removes it).

## Review Focus

1. **A TV that reconnects mid-turn after an undo and a clear:** it gets exactly the strokes that are visible. Test in Task 4: "inkSync after s,s,u,c,s carries one stroke".
2. **A phone that scanned a QR 70 seconds ago:** refused with `not_near`, counted as a wrong guess; a member reconnecting with no key passes. Test in Task 5.
3. **The drawer's second device** (a parent's iPad) after the pick: gets the guesser's view, no `word`, no ink, and its `ink` is dropped. Test in Task 6.
4. **The TV dropping for 10 s mid-turn:** the clock stops, `paused: true`, and resumes with the same remaining time. Test in Task 3.
5. **Storage after a full game with ink:** no stored key or value contains an `ops` array or a word other than in `last`. Test in Task 7 (reads every key from `ctx.storage.list()`).

---

### Task 1: Words and the engine

**Files:**
- Create: `src/purrtrait/words.ts`, `src/purrtrait/engine.ts`, `src/purrtrait/view.ts`, `src/purrtrait/parse.ts`
- Test: `src/purrtrait/words.test.ts`, `src/purrtrait/engine.test.ts`, `src/purrtrait/view.test.ts`, `src/purrtrait/parse.test.ts`

**Interfaces:**
- Produces: `WORDS: readonly { word: string; group: Group; level: Level }[]`; `create(seats: number, seed: Seed, options: PurrOptions): PurrState`; `apply(s, seat, a, ctx: { easyOnly: boolean })`; `view(s, controlled: readonly Seat[], drawerDevice: boolean, easyOnly: boolean): PurrView`; `parseAction(raw): PurrAction | null`; `parseOptions(raw): PurrOptions | null`; types in the wire contract.

- [ ] **Step 1: Write the failing tests.** `words.test.ts`: at least 250 of each level; every group used; no duplicate words; every word matches `/^[a-z][a-z ]{1,20}$/`; a deny list (`gun|blood|kill|dead|die|knife|bomb|beer|wine|god|church|butt|poop|naked`) matches none. `engine.test.ts`: "choices are one easy and one tricky unused word"; "choose then gotIt scores 1 each for easy, 2 for tricky"; "timeUp and giveUp score nothing and reveal"; "two rounds in seat order then over, ties share"; "a forfeited seat is skipped and the game ends below 2"; "no word twice in a 10-seat game"; "gotIt for the drawer's own seat is bad_seat". `view.test.ts`: "only drawerDevice sees word"; "before choose every controller sees choices"; "easyOnly offers two easy words and scores 1". `parse.test.ts`: every action and option shape, and `timeUp`/`nextTurn` parse but are flagged room-only.
- [ ] **Step 2: Run** `pnpm --filter @pounce/play-api exec vitest run src/purrtrait` and see them fail.
- [ ] **Step 3: Write the word list** (spec §4.5, our own words, a six-year-old knows each) **and the engine** per rulings 1-3, 5, 8-10, 18. Pure: words from the seed with the Cat Tower `rng` pattern (`seed`, `rngCalls` in state).
- [ ] **Step 4: Run** the tests and see them pass.
- [ ] **Step 5: Commit** "Purrtrait: the words and the rules".

### Task 2: The module and the registry

**Files:**
- Create: `src/games/purrtrait.ts`, `src/games/purrtrait.test.ts`
- Modify: `src/games/module.ts` (add `turnLimitMs?`, `timeUpAction?`), `src/games/index.ts` (`GAMES`, `TITLES`, unions), `src/protocol.ts` (`purrtrait` view in `RoomView`, new error codes `easel_full`, `not_near`, `removed`, `no_screen`), `.dev.vars.example`, `tests/games-entry.ts` and the harness env, `tests/catalog.test.ts` in play-web (ruling 19)

**Interfaces:**
- Consumes: Task 1.
- Produces: `purrtrait: GameModule<PurrState, PurrAction, PurrView, PurrEvent, PurrError, PurrOptions>` with `minSeats: 2`, `maxSeats: 10`, `turnLimitMs`, `timeUpAction`, `betweenAction: { type: "nextTurn" }`, `forfeitAction`, `fallbackAction` = `giveUp` for the drawer, `parseAim` always null.

- [ ] **Step 1: Failing tests** in `purrtrait.test.ts`: the module passes `modules.test.ts`'s shared contract; `turnLimitMs` is 10 000 choosing, `timer*1000` drawing, null in reveal; `games-header.test.ts` gains "an app without purrtrait in x-pounce-games gets 404 / 426".
- [ ] **Step 2: Run, see fail. Step 3: Implement. Step 4: Run** `pnpm --filter @pounce/play-api test` and see pass (pinned fixtures unchanged).
- [ ] **Step 5: Commit** "Purrtrait: the game module".

### Task 3: The room's turn clock and pause

**Files:**
- Modify: `src/room/core.ts` (`tick`, `nextAlarm`, `afterGameChange`, screen changes), `src/room/tables.ts` if `RoomState` types live there
- Test: `src/room/core.purrtrait.test.ts` (new)

**Interfaces:**
- Consumes: `turnLimitMs`, `timeUpAction`.
- Produces: `RoomState.timers.turnEndsAt: number | null`, `RoomState.timers.pausedLeftMs: number | null`; view's `remainingMs`/`paused` filled by the room (`gameFields`).

- [ ] **Step 1: Failing tests:** "choosing times out to the easy word"; "drawing times out to timeUp"; "the screen leaving pauses after the grace and resumes with the same remainingMs"; "30 minutes paused ends the game stalled"; "Cat Tower rooms never set turnEndsAt".
- [ ] **Steps 2-4:** run, implement rulings 6-7, run.
- [ ] **Step 5: Commit** "Purrtrait: the turn clock".

### Task 4: Ink

**Files:**
- Create: `src/purrtrait/ink.ts`, `src/purrtrait/ink.test.ts`
- Modify: `src/protocol.ts` (`ink` client and server messages, `inkSync`, `inkResend`; `parseClientMessage`), `src/room/core.ts` (`dispatch`, `connect`, the relay), `src/room/game-room.ts` (send `inkResend` after a wake)
- Test: `src/room/core.purrtrait.test.ts`, `src/protocol.test.ts`

**Interfaces:**
- Produces: `type InkOp = ["s", number, number, number, ...number[]] | ["p", number, ...number[]] | ["u", number] | ["c"]`; `checkInk(ops: unknown, easel: InkEasel): { ok: true; easel: InkEasel } | { ok: false; full: boolean }`; `compact(ops: readonly InkOp[]): InkOp[]`.

- [ ] **Step 1: Failing tests:** `ink.test.ts` every bad shape from ruling 15, caps at 500 strokes and 30 000 points, "inkSync after s,s,u,c,s carries one stroke". Room tests: "ink goes to the screen and the drawer's other sockets only" (a property test over random rooms of 2-10 seats with shared phones); "ink from a guesser, a stale turn or before choose is dropped"; "the 26th message in a second is dropped"; "a screen connecting mid-turn gets inkSync after its snapshot"; "a core rebuilt from storage asks the drawer for inkResend once"; "a new turn drops the ink".
- [ ] **Steps 2-4:** run, implement rulings 15-16, run.
- [ ] **Step 5: Commit** "Purrtrait: lines go live to the TV".

### Task 5: Same room: screen-made tables and near keys

**Files:**
- Modify: `src/index.ts` (create: ruling 13; socket: pass `near`), `src/room/game-room.ts` (`fetch` admission, `knows`), `src/room/core.ts` (near keys in `tick`, `near` in the screen's snapshot), `src/safety/safety.ts` (`guardJoin` takes the near result), `src/screens/screen-links.ts` + `src/index.ts` link route (ruling 13), `src/http/links.ts` (`/e/`, `/j/` page for Purrtrait, `PURRTRAIT_APPLINKS`), `src/env.ts`
- Test: `tests/purrtrait.test.ts` (Miniflare, new), `src/http/links.test.ts`

- [ ] **Step 1: Failing tests:** "a phone can't make a purrtrait room"; "a join with no key, a stale key (70 s), or the plain room code is 403 not_near and counted"; "the typed 8-char code works inside 60 s"; "a member reconnects with no key"; "only the screen's snapshot has near"; "the host links a new TV and the old one is refused; anyone else gets not_allowed"; "/j/ for a purrtrait room has no join button"; "/e/ redirects to /play/e/ with near"; "the association lists /e/* only with PURRTRAIT_APPLINKS on".
- [ ] **Steps 2-4:** run, implement rulings 12-14, run.
- [ ] **Step 5: Commit** "Purrtrait: join only from the TV's code".

### Task 6: Remove, host handoff, the drawer's device, refusals

**Files:**
- Modify: `src/protocol.ts` (`remove`), `src/room/core.ts`, `src/room/game-room.ts`
- Test: `src/room/core.purrtrait.test.ts`, `tests/purrtrait.test.ts`

- [ ] **Step 1: Failing tests:** "remove in the lobby opens the seat and the device is refused after"; "remove in a game skips the seat; Play again keeps it out"; "a non-host remove is not_allowed"; "the host leaving hands the role to the next seated person"; "the drawer's second device gets the guesser view after the pick and its ink is dropped"; "moveSeat, claimMove, nudge, retire and bot seats are not_allowed"; "no push, live or invite intent is queued"; "start needs the screen (no_screen)".
- [ ] **Steps 2-4:** run, implement rulings 4, 10, 11, 14, 17, run.
- [ ] **Step 5: Commit** "Purrtrait: the host can remove a player".

### Task 7: Fixtures, privacy lines, docs

**Files:**
- Create: `fixtures/protocol/purrtrait-server-messages.json`, `fixtures/protocol/purrtrait-client-messages.json`, `tests/purrtrait-protocol-fixtures.test.ts`, `tests/purrtrait-sim.test.ts`
- Modify: `src/http/privacy.ts`, `docs/privacy/app-store-label.md`, `docs/privacy/retention-policy.md`, `docs/app-review-notes.md`, `docs/tv-protocol.md` (a Purrtrait section: near keys, ink), `README.md` (games list: "coming", per AGENTS.md)

- [ ] **Step 1: Failing tests:** fixtures from real rooms (every phase snapshot for drawer device, guesser, screen; every event; every new error; `ink`, `inkSync`, `inkResend`); "storage after a full game holds no ink and no unrevealed word" (Review Focus 5); a simulated soak of 1 000 games at 2-10 seats with random chooses, ink, gotIt, giveUp, timeUp and removes that always ends.
- [ ] **Step 2-4:** run, write fixtures and the privacy lines verbatim from spec §8.2 (policy, label row, retention, review notes; not the notice), run `pnpm check`.
- [ ] **Step 5: Commit** "Purrtrait: fixtures and privacy facts". Then write the wire note `purrtrait-server-wire.md` in the shared notes folder, push, open the PR ("Purrtrait on the server: draw on your phone, the TV shows it live (still off)").
