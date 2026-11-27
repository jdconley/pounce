# Toy Tumble engine and server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Toy Tumble rules engine in TypeScript with cross-language fixtures, the live wire, and the room that referees real-time rounds with House Cats. The game stays off in production behind `GAMES`.

**Architecture:**
- A pure, deterministic box engine lives in `apps/play-api/src/tumble/`. It is fed one ordered event stream per box.
- A turn-free `GameModule` (`games/tumble.ts`) keeps the slow state (rounds, wins, options) in the room's stored state.
- An in-memory `TumbleRound` keeps the fast state. It checks each event, issues hits, drives House Cats on a capped tick, and says who's out and who won.
- `RoomCore` and `GameRoom` route messages and timers to it through small hooks keyed on the game.

**Tech Stack:** TypeScript, Cloudflare Workers and Durable Objects, vitest, pnpm.

**Spec:** `docs/superpowers/specs/2026-11-26-toy-tumble-design.md`. Section numbers below are the spec's.

## Global Constraints

- The other games' names and the trade words for their pieces appear nowhere: code, comments, tests, fixtures, docs and commits. Code says toy, box, row, junk and trick.
- The game id is `tumble` and the display name is "Toy Tumble".
- The box is 12 columns by 18 rows, plus 4 hidden rows (y 18 to 21). Cells are indexed `y * 12 + x`, with y = 0 at the bottom.
- Rows cleared send junk as 1→0, 2→1, 3→2, 4→4 (§4.3).
- Junk waits 2000 ms on the receiving device (§4.5). The server enforces landing 4000 ms after the ack (§6.5). Hits must be acknowledged within 3000 ms.
- A device goes "reconnecting" at 3000 ms without a message, and its box is out at 15000 ms (§6.6).
- The client rate limit is 30 batches a second. `m` events are relayed at most every 66 ms per box (§6.3, §6.4).
- House Cats: one room tick of at most 10 Hz, levels `easy` and `quick` (§6.9). The budget is under 10 ms of CPU per second of round per room.
- PRs stay flag-off in production: `tumble` is not added to `GAMES` in `wrangler.jsonc`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Two devices of one player.** A second socket of the same device or person, for example the web player in two tabs, must not split the box's stream. Only the first socket that sends for the seat this round writes. Others get `not_allowed`. Pinned in Task 6.
2. **Late or duplicate acks.** An `a` for an already acked or unknown hit, and an ack arriving after the server already applied the hit at 3 s. Both must be refused with a sync, never applied twice. Pinned in Task 5.
3. **Events for an old round.** A batch with `r` of the previous round, sent during the countdown or the next round, is dropped silently, never refused with a sync. Pinned in Task 5.
4. **A target that goes out between issue and ack.** The hit is void. Nobody waits for its ack. Pinned in Task 5.
5. **A server restart mid-countdown or mid-round.** The room comes back to a countdown for the same round number, with wins intact. Pinned in Task 7.

---

## File structure

| File | Responsibility |
| --- | --- |
| `apps/play-api/src/tumble/rng.ts` | xoshiro128** with explicit state (`Seed` in, `[uint32, Seed]` out) |
| `apps/play-api/src/tumble/toys.ts` | toy ids, base cells, rotation, spawn position |
| `apps/play-api/src/tumble/queue.ts` | the bag-of-8 toy queue from a round seed |
| `apps/play-api/src/tumble/box.ts` | the `Box` type and every box operation (set-down, junk, hits, tricks) |
| `apps/play-api/src/tumble/codec.ts` | `Box` to and from the fixture text form (row strings) |
| `apps/play-api/src/tumble/wire.ts` | client and server message types, parse and validate |
| `apps/play-api/src/tumble/round.ts` | `TumbleRound`: the referee, hits, outs, timers, sync |
| `apps/play-api/src/tumble/cats.ts` | House Cat placement and trick choice |
| `apps/play-api/src/games/tumble.ts` | the `GameModule` for the lobby and standings |
| `apps/play-api/fixtures/tumble/*.json` | the engine fixtures shared with Swift |
| `apps/play-api/scripts/tumble-fixtures.ts` | the fixture generator |
| `apps/play-api/scripts/tumble-soak.ts` | the bot soak and cost benchmark |
| `apps/play-api/scripts/tumble-latency.ts` | the real-network latency tool |
| `apps/play-api/src/words.test.ts` | the banned-words test |
| `docs/live-protocol.md` | the Toy Tumble wire, for client builders |

---

### Task 1: State-carrying RNG, toys and the queue

**Files:**
- Create: `apps/play-api/src/tumble/rng.ts`, `toys.ts`, `queue.ts`, `tumble.basics.test.ts` (in `src/tumble/`)

**Interfaces:**
- Produces:
  - `rngNext(s: Seed): [number, Seed]`, returning the uint32 output and the new state.
  - `rngFloat(u: number): number`, which is `u / 2**32`.
  - `rngShuffle<T>(items: readonly T[], s: Seed): [T[], Seed]`, Fisher-Yates from the end, `j = floor(float * (i + 1))`, as in `rules/rng.ts`.
  - `type ToyId = "i3"|"v3"|"i4"|"o4"|"t4"|"l4"|"j4"|"p5"|"u5"`, with `TOY_IDS` in that order.
  - `type Rot = 0|1|2|3`.
  - `toyCells(toy, rot): readonly [number, number][]`.
  - `boxSize(toy): number`.
  - `spawn(toy): { rot: 0; x: number; y: number }`.
  - `toyAt(roundSeed: Seed, n: number): ToyId`.

- [ ] **Step 1: Write the failing tests** in `tumble.basics.test.ts`:
  - `rngNext matches createRng`: for seed `[1,2,3,4]`, the first 1000 `rngFloat(rngNext(...)[0])` values equal `createRng([1,2,3,4])()` values.
  - `rotation`:
    - `toyCells("t4",0)` deep-equals `[[0,1],[1,1],[2,1],[1,2]]`.
    - `toyCells("t4",1)` equals the clockwise turn `(x,y) → (y, k-1-x)` with k = 3, which is `[[1,2],[1,1],[1,0],[2,1]]`.
    - Four turns return the start for every toy.
    - Every rotation of `o4` is the same cell set.
  - `spawn`: `spawn("i4")` → `{rot:0, x:4, y:16}`. That's k = 4, so x = floor((12-4)/2) = 4. The lowest cell y is 2, so y = 18 - 2 = 16. `spawn("v3")` → `{rot:0, x:5, y:18}`.
  - `queue`: for any seed, each bag of 8 (n = 0-7, 8-15, …) holds `i3 v3 i4 o4 t4 l4 j4` once each, plus `p5` in even bags and `u5` in odd bags. It is deterministic for a seed.

- [ ] **Step 2: Run, expect FAIL.** Run `pnpm --filter @pounce/play-api exec vitest run src/tumble/tumble.basics.test.ts`. Expect failures: the modules don't exist yet.

- [ ] **Step 3: Implement.**
  - Base cells (x right, y up, in a k×k box). These values are the contract with Swift:

    ```
    i3 k3 [[0,1],[1,1],[2,1]]            v3 k2 [[0,0],[0,1],[1,0]]
    i4 k4 [[0,2],[1,2],[2,2],[3,2]]      o4 k2 [[0,0],[1,0],[0,1],[1,1]]
    t4 k3 [[0,1],[1,1],[2,1],[1,2]]      l4 k3 [[0,1],[1,1],[2,1],[2,2]]
    j4 k3 [[0,1],[1,1],[2,1],[0,2]]      p5 k3 [[1,0],[0,1],[1,1],[2,1],[1,2]]
    u5 k3 [[0,0],[1,0],[2,0],[0,1],[2,1]]
    ```

  - Rotation applies `(x,y) → (y, k-1-x)` once per quarter turn, keeping the cell order.
  - Spawn: `x = floor((12-k)/2)`, and `y = 18 - min(cy of rot 0)`.
  - Queue: one state starts at `roundSeed`. Bag b is `rngShuffle([i3,v3,i4,o4,t4,l4,j4, b%2===0 ? "p5" : "u5"])`, continuing the state bag to bag. `toyAt` caches bags per seed (a small LRU of 8 seeds).

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit.** Run `git add apps/play-api/src/tumble && git commit -m "Toy Tumble: toys, turns and the toy queue"`.

### Task 2: The box engine

**Files:**
- Create: `apps/play-api/src/tumble/box.ts`, `codec.ts`, `box.test.ts`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - Types:

    ```ts
    export const W = 12, H = 18, TOTAL = 22;
    export const TRICKS = ["hairball","swipe","catnip","scoop","settle","nap","swap","bath"] as const;
    export type Trick = typeof TRICKS[number];
    export type Waiting = { id: number; rows: number; gap: number };
    export type Box = { cells: number[]; tricks: number[]; held: Trick[]; next: number; waiting: Waiting[]; rng: Seed; out: boolean; rows: number };
    export type Hit =
      | { k: "hairball"; gap: number } | { k: "swipe"; shifts: number[] }
      | { k: "catnip" } | { k: "nap" } | { k: "scoop" } | { k: "settle" } | { k: "bath" }
      | { k: "swap"; cells: number[]; tricks: number[] };
    export type SetDown = { box: Box; cleared: number; sent: number; blocked: { id: number; rows: number }[]; pocketed: Trick[]; out: boolean };
    ```

  - Functions:
    - `newBox(trickSeed: Seed): Box`
    - `fits(box, toy, rot, x, y): boolean`
    - `turn(box, toy, rot, x, y, dir: 1|-1): {rot,x,y} | null`, with the nudges (0,0),(-1,0),(+1,0),(0,+1),(-2,0),(+2,0)
    - `setDown(box, roundSeed, n, rot, x, y, landed: number[]): SetDown | { error: "not_next"|"bad_place"|"not_resting"|"bad_landed" }`
    - `receiveJunk(box, w: Waiting): Box`
    - `applyHit(box, hit: Hit): { box: Box; pocketed: Trick[] }`
    - `useTrick(box, slot): { box: Box; trick: Trick } | null`
    - `highest(box): number`, the highest filled y, or -1
    - `contents(box): { cells; tricks }`
  - Codec:
    - `toText(box)` gives `{ cells: string[22], tricks: string[22] }`, top row (y 21) first.
    - Cells: `.`, `1`–`9` for the toy index + 1, `#` for junk (value 10).
    - Tricks: `.`, or `a`–`h` in `TRICKS` order.
    - `fromText` reverses it.

- [ ] **Step 1: Write the failing tests** in `box.test.ts`, one `it` per rule, built from `fromText` boards:
  - `setDown refuses`:
    - a toy that isn't `box.next` gives `not_next`;
    - an overlap or out-of-bounds gives `bad_place`;
    - a toy that could still fall gives `not_resting`;
    - `landed` given when rows cleared gives `bad_landed`;
    - `landed` that isn't the waiting list's prefix, oldest first, gives `bad_landed`.
  - `clears and attack`: 1, 2, 3 and 4 full rows give `cleared` 1 to 4 and `sent` 0, 1, 2 and 4.
  - `blocking`: with waiting `[{id:1,rows:2},{id:2,rows:3}]`, a 3-row clear (attack 2) gives `blocked=[{id:1,rows:2}]`, `sent=0`, waiting `[{id:2,rows:3}]`. A 4-row clear (attack 4) after that gives `blocked=[{id:2,rows:3}]` and `sent=1`.
  - `landing`: a set-down clearing nothing with `landed=[1]` pushes 2 junk rows under the stack, with the gap at `gap`, moves tricks up with their cells, and removes id 1.
  - `tricks spawn`: after a 2-row clear, exactly 2 new tricks sit on filled cells that had none, chosen by `box.rng` (assert the exact cells and kinds for seed `[9,9,9,9]` from a golden value computed once and checked by hand against the rules).
  - `danger weights`: with the highest cell y ≥ 12 after the clears, the weights are `[20,15,12,36,12,10,9,9]`. Otherwise they are `[20,15,12,18,12,10,3,3]`.
  - `pocketing`: tricks on cleared rows go to `held` bottom row first, left to right. A 7th is dropped.
  - `out`: a set-down leaving any cell at y ≥ 18 sets `out`. So does toy `n+1` overlapping at its spawn.
  - `hits`:
    - hairball adds 1 junk row with that gap;
    - swipe shifts row y by `shifts[y]` with wrap, tricks along;
    - scoop removes y 0 and 1 and pockets their tricks;
    - settle drops each column's cells down in order, then removes full rows, pocketing, with no new tricks;
    - bath empties cells, tricks and `waiting`;
    - swap replaces cells and tricks, keeping `held` and `waiting`;
    - catnip and nap change nothing;
    - any hit leaving a cell at y ≥ 18 sets `out`.

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement `box.ts` and `codec.ts`.**
  - `setDown` runs in this order:
    1. check;
    2. write the cells;
    3. remove full rows bottom-up and pocket their tricks;
    4. block, oldest waiting first, partial blocks allowed;
    5. spawn one trick per cleared row: kind first by weights using `rngFloat * total`, then the cell, uniform over filled cells without a trick in index order, skipped if there are none;
    6. land `landed` if nothing cleared;
    7. check for out;
    8. `next = n + 1`.
  - `rows` counts every cleared row, for the cats' tiebreak.

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit.** `git commit -m "Toy Tumble: the box engine"`

### Task 3: Shared fixtures and the generator

**Files:**
- Create: `apps/play-api/scripts/tumble-fixtures.ts`, `apps/play-api/fixtures/tumble/` (`basics.json`, `tricks.json` and `random-0.json` to `random-19.json`), and `apps/play-api/src/tumble/fixtures.test.ts`
- Modify: `apps/play-api/package.json`, adding the script `"tumble:fixtures": "tsx scripts/tumble-fixtures.ts"`, or the runner the package already uses for scripts

**Interfaces:**
- Produces the fixture JSON. Swift reads exactly this:

  ```json
  { "name": "...", "roundSeed": [1,2,3,4], "trickSeed": [5,6,7,8],
    "queue": ["t4","i3", "... first 32 toys"],
    "steps": [
      { "do": ["setDown", 0, 1, 4, 0, []],
        "expect": { "cleared": 0, "sent": 0, "blocked": [], "pocketed": [], "out": false,
                    "box": { "cells": ["......"], "tricks": ["..."], "held": [], "next": 1, "waiting": [], "rng": [0,0,0,0], "out": false, "rows": 0 } } },
      { "do": ["junk", {"id": 3, "rows": 2, "gap": 7}], "expect": { "box": { } } },
      { "do": ["hit", {"k": "swipe", "shifts": [0,1,-2]}], "expect": { "pocketed": [], "box": { } } },
      { "do": ["use", 0], "expect": { "trick": "nap", "box": { } } },
      { "do": ["turn", "l4", 0, 0, 3, 1], "expect": { "to": [1, 0, 3] } }
    ] }
  ```

  - A refused step has `"expect": { "error": "bad_place" }` and leaves the box unchanged.

- [ ] **Step 1: Write `fixtures.test.ts`.** It loads every file in `fixtures/tumble`. For each step it runs the op from a `newBox(trickSeed)`, asserts `toText` and every field deep-equal, and asserts `queue[i] === toyAt(roundSeed, i)`.
- [ ] **Step 2: Hand-write `basics.json` and `tricks.json`.**
  - Cover every refusal in Task 2;
  - turns and nudges against both walls and a stack;
  - every hit kind;
  - blocking with partial blocks;
  - landing two attacks in order;
  - pocketing up to the limit of 6;
  - both ways of going out.
- [ ] **Step 3: Write the generator.** It plays seeded random games with a greedy placer: lowest y, then fewest holes. It interleaves junk, hits and uses at random and writes `random-N.json` with 150 to 300 steps each.
- [ ] **Step 4: Run the generator, then the fixture test, expecting PASS.** Run `pnpm --filter @pounce/play-api tumble:fixtures && pnpm --filter @pounce/play-api exec vitest run src/tumble`.
- [ ] **Step 5: Commit.** `git commit -m "Toy Tumble: engine fixtures shared with the app"`

### Task 4: The wire

**Files:**
- Create: `apps/play-api/src/tumble/wire.ts`, `wire.test.ts`, `docs/live-protocol.md`, `apps/play-api/fixtures/protocol/tumble-client-messages.json`, `tumble-server-messages.json`
- Modify: `apps/play-api/src/protocol.ts` (`parseClientMessage` accepts `t: "tumble"` through `parseTumble`), `protocol.games.test.ts`

**Interfaces:**
- Produces:

  ```ts
  export type ClientEvent = ["m", number, Rot, number, number] | ["l", number, Rot, number, number, number, number[]] | ["a", number] | ["u", number, number];
  export type TumbleClient = { t: "tumble"; r: number; ev: ClientEvent[] };
  export type HitWire = { t: "tumbleHit"; r: number; id: number; from: number; to: number; k: Hit["k"] | "junk" | "napped"; x?: object };
  export type TumbleRelay = { t: "tumble"; r: number; s: number; q: number; ev: ClientEvent[] };
  export type BoxSync = { s: number; box: Box; q: number; waitingLeft: number[]; catnipLeft: number; napLeft: number; status: "ok" | "lag" | "out" };
  export type TumbleSync = { t: "tumbleSync"; r: number; boxes: BoxSync[] };
  export type TumbleSeat = { t: "tumbleSeat"; r: number; s: number; st: "ok" | "lag" };
  export function parseTumble(raw: unknown): TumbleClient | null;
  ```

- [ ] **Step 1: Write the failing tests.**
  - Valid batches parse.
  - Exactly the keys listed and nothing more.
  - Integers in range: rot 0 to 3; x -2 to 13; y 0 to 25; n 0 or more; `ms` 0 to 600000; `landed` at most 16 ids; seat 0 to 5; slot 0 to 5.
  - At most 64 events.
  - Extra keys, wrong types, floats or negative ids give null.
  - `parseClientMessage('{"t":"tumble",...}')` returns it.
  - The protocol fixture files parse.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Write `docs/live-protocol.md` from spec §6.3 to §6.6 with these exact shapes and every error.
- [ ] **Step 4: Run `pnpm --filter @pounce/play-api test`, expect PASS.**
- [ ] **Step 5: Commit, push and open the PR "Toy Tumble rules engine and its wire (no game yet)".** Merge it on green. Clients build on this.

### Task 5: The referee, `TumbleRound`

**Files:**
- Create: `apps/play-api/src/tumble/round.ts`, `round.test.ts`

**Interfaces:**
- Consumes: Tasks 1 to 4.
- Produces:

  ```ts
  export type RoundSeat = { kind: "human" | "cat" | "away" };
  export type RoundOut = { to: "all" | { seat: number } | { except: number }; message: TumbleRelay | HitWire | TumbleSync | TumbleSeat };
  export class TumbleRound {
    constructor(o: { r: number; seats: RoundSeat[]; roundSeed: Seed; trickSeeds: Seed[]; startsAt: number; cats: "easy" | "quick"; catRng: Seed });
    input(seat: number, msg: TumbleClient, now: number): RoundOut[];
    heard(seat: number, now: number): RoundOut[];
    tick(now: number): RoundOut[];
    sync(seats: number[] | "all", now: number): TumbleSync;
    result(): { over: boolean; winner: number | null; outs: number[] };
  }
  ```

  The room maps `{seat}` and `{except}` to sockets.

- [ ] **Step 1: Write the failing tests**, with a fake clock, two human seats and a scripted box for seat 0:
  - **Relay:** a legal `l` relays to `{except:0}` with q 1, 2, 3 and so on. Batched `m` events coalesce to at most one relay per 66 ms. `r` that isn't this round is dropped with no output (Review Focus 3).
  - **Refusals:** an illegal `l`, an `a` for an unknown or already acked id (Review Focus 2), and `u` for a slot that isn't held or a seat that is out each give `{seat:0}` a `tumbleSync` of seat 0 and relay nothing.
  - **Attacks:** a 4-row clear with no waiting junk issues `tumbleHit k:"junk" x:{rows:4,gap}` to `"all"`, one per other live box, with ids increasing.
  - **Acks:** applying an ack updates the server's box. A hit unacked for 3000 ms is applied by the server, with `tumbleSync` of that box to `"all"`. A late ack after that is refused (Review Focus 2).
  - **Owed junk:** junk acked more than 4000 ms ago and not landed by the next non-clearing `l` is landed by the server, with a sync to `"all"`.
  - **Tricks:** `u` on a napping box gives a `napped` hit and no effect. Swap issues one hit to each of the two boxes, carrying the other's contents as last seen. A target going out before its ack voids the hit (Review Focus 4).
  - **Presence:** no `heard` for 3000 ms gives `tumbleSeat st:"lag"`. 15000 ms makes the box out. Junk to a lagging box waits, and junk to an out box is dropped.
  - **Round end:** the last box gives `result()` `over`, with that winner. All humans out with 2 cats left makes the winner the cat with more `rows`. Two outs within 100 ms leave nobody standing, so `winner: null`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
  - The server's boxes come from `newBox(trickSeeds[s])`.
  - `tick` handles the deadlines and drives the cats (Task 8 hook: `this.cats?.tick(now)`; a no-op until then).
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit.**

### Task 6: The module, the room hooks, the gates

**Files:**
- Create: `apps/play-api/src/games/tumble.ts`, `apps/play-api/src/room/core.tumble.test.ts`
- Modify:
  - `src/games/index.ts`: register `tumble` and its title "Toy Tumble". Add `GAME_MIN_APP = { tumble: "1.4" }` and `gamesFor(header, app, dev)`.
  - `src/room/core.ts`: a `"tumble"` dispatch case, plus connect and disconnect sync hooks, `tumbleTick(now)`, and the snapshot's `tumble` field.
  - `src/room/game-room.ts`: a 100 ms interval while a round plays, and delivery of `RoundOut`.
  - Every call site of `gamesListed` for apps, so it goes through `gamesFor`.
  - `room/live-relay.ts`: use it if it's on `main`. Otherwise create it with `class LiveRelay { constructor(perSecond: number); allow(key: string, now: number): boolean }` and nothing Purrtrait-specific.

**Interfaces:**
- Produces the module state stored in the room:

  ```ts
  type TumbleState = { seats: number; cats: "easy" | "quick"; wins: number[]; left: boolean[]; away: boolean[];
    status: "countdown" | "playing" | "between" | "over"; r: number; startsAt: number; roundSeed: Seed; trickSeeds: Seed[]; outs: number[]; winner: number | null; waitingSince: number | null };
  ```

  - Module actions are applied by the room, never by clients:
    - `{k:"start", at, roundSeed, trickSeeds}`
    - `{k:"out", seat}`
    - `{k:"end", winner}`
    - `{k:"away", seat, away}`
    - `{k:"leave"}` (this is `forfeitAction`)
  - `currentActor` → null. `progressKind: "score"`. `progress` is the wins.
  - `minSeats` 2, `maxSeats` 6.
  - `defaultOptions {cats:"easy"}`. `parseOptions` accepts exactly `{cats:"easy"|"quick"}`.
  - The view is the state minus the seeds until the round starts. Clients need `roundSeed` and `trickSeeds` from `startsAt` on.

- [ ] **Step 1: Write the failing tests** in `core.tumble.test.ts`, following `core.birdwatch.test.ts`:
  - **Start:** Start is refused until every human seat's device is connected. A device may hold only one seat at a Toy Tumble table (`claim` of a second seat gives `not_allowed`).
  - **The round cycle:** start gives a countdown of 3000 ms, then playing. A round end makes the state `between` for 5000 ms. The next countdown starts only while every non-left human is connected. Otherwise `waitingSince` is set. After 20000 ms the host's `setOptions`-style action `{t:"act", action:{k:"playWithout"}}` marks the missing seats away. With no human connected, nothing runs and no alarm is set.
  - **First to 3** gives `over`. `leave` takes a seat out for the game. Fewer than 2 seats left, or no human left, ends the game, and the most wins wins.
  - **Sync:** a screen connecting while playing gets a `tumbleSync` of every box. A seat's device reconnecting within 15 s gets one too.
  - **Two sockets** of one device (Review Focus 1): only the first to send this round writes. The other gets `not_allowed`.
  - **Gates:**
    - `x-pounce-games: tumble` from an iOS app at 1.3 does not list `tumble`. At 1.4 it does.
    - A dev server (`devSpeed`) lists it at 1.3.
    - A browser (`app=web`) lists it.
    - With `GAMES` off, room creation for `tumble` is refused, as for any game.
  - **Streaks:** each round a human seat plays counts one turn for it.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement**, following Birdwatch's hooks in `core.ts` and `game-room.ts`. The interval starts on `status:"playing"` and stops on anything else.
- [ ] **Step 4: Run `pnpm --filter @pounce/play-api test`, expect PASS.**
- [ ] **Step 5: Commit.**

### Task 7: Restart replays the round

**Files:**
- Modify: `src/room/game-room.ts` (`load`), `src/room/core.ts`
- Test: `src/room/core.tumble.test.ts`

- [ ] **Step 1: Write the failing test.** A stored state with `status:"playing"` or `"countdown"` and no in-memory round loads as a new countdown, with the same `r`, new seeds and the same `wins` (Review Focus 5).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement it in the load path.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit.**

### Task 8: House Cats

**Files:**
- Create: `apps/play-api/src/tumble/cats.ts`, `cats.test.ts`
- Modify: `round.ts` (drive cats on `tick`)

**Interfaces:**
- Produces:
  - `place(box: Box, toy: ToyId, sloppy: number, rng: Seed): [{ rot, x, y }, Seed]`.
    - It scores every rotation and column of the current toy, resting position only.
    - The score is `-4*holes - 1*aggregateHeight - 1*bumpiness + 3*cleared`.
    - With probability `sloppy` it takes the second best.
  - `chooseTrick(view: { me: number; boxes: Box[]; wins: number[]; humans: boolean[] }, held: Trick[], level): { slot: number; seat: number } | null`.
  - `CAT_LEVELS = { easy: { think: [1400, 2400], sloppy: 0.35, tricks: ["hairball","swipe","scoop","nap"] }, quick: { think: [800, 1600], sloppy: 0.15, tricks: "all" } }`.
- Cats write through the same `input` path as a phone, with `m` steps about 5 a second, then `l`. They ack hits at once and land owed junk on time.

- [ ] **Step 1: Write the failing tests.**
  - `place` picks a hole-free placement on a flat board.
  - `place` takes a 4-row clear when one is offered.
  - `sloppy: 1` takes the second best.
  - Harmful tricks target the human with the most wins, then the lowest stack.
  - Swap is never used from a lower stack.
  - Easy never uses catnip, settle, swap or bath.
  - A round with 1 human idle and 2 cats ends with a cat winner within the Zoomies.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement it, and hook it into `TumbleRound.tick`, at most one decision per cat per tick.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit.**

### Task 9: Soak, cost and the words test

**Files:**
- Create: `apps/play-api/scripts/tumble-soak.ts`, `apps/play-api/src/words.test.ts`
- Modify: the spec's §9.3 and §6.9, adding the measured numbers and any tuning.

- [ ] **Step 1: Write `words.test.ts`.**
  - It walks the paths `apps/play-api/src/tumble`, `src/games/tumble.ts`, `fixtures/tumble`, `docs/live-protocol.md`, `docs/superpowers/specs/2026-11-26-toy-tumble-design.md`, `docs/superpowers/plans/2026-11-26-toy-tumble-*.md`, `apps/play-web/src/tumble` and `apps/play-ios/**/Tumble*`. It skips any that don't exist yet.
  - It fails on any banned word, matched case-insensitively.
  - The list is stored ROT13-encoded and decoded at run time, exactly `["Grgevf", "GrgevArg", "grgebzvab", "Grgevzvab"]`. Never write the decoded words anywhere in the repo.
- [ ] **Step 2: Write the soak.** It runs 10,000 rounds offline through `TumbleRound` with a fake clock: 2 to 6 cats, both levels, and a scripted kid (think 2500 to 4000 ms, sloppy 0.5, no tricks) against one easy cat. It reports:
  - round length p50, p95 and max;
  - the share of rounds over 5 minutes;
  - the share of `p5` and `u5` placements forced into a hole;
  - each trick's share of rounds where its use preceded the decisive out within 5 s;
  - kid win rate;
  - CPU ms per round-second, and messages out per round-second, for 1 human plus 5 cats plus a screen.
- [ ] **Step 3: Run it.** Run `pnpm --filter @pounce/play-api exec tsx scripts/tumble-soak.ts --rounds 10000`. Tune until:
  - every round ends, with under 1% over 5 minutes;
  - the kid wins at least 1 in 3;
  - CPU is under 10 ms per second.

  If 5-cell dead ends exceed 15% of their placements, lower their share to one bag in two. Record the numbers and changes in the spec.
- [ ] **Step 4: Run `pnpm --filter @pounce/play-api test`, expect PASS.**
- [ ] **Step 5: Commit, push and open the PR "Toy Tumble on the server: rounds, House Cats and the referee (still off)".**

### Task 10: The latency tool

**Files:**
- Create: `apps/play-api/scripts/tumble-latency.ts`, `docs/perf/toy-tumble-latency.md`

- [ ] **Step 1: Write the tool.** It takes `--base <url>` and `--players N`, and does the following:
  - it makes a table with `N-1` scripted browser-protocol clients plus a screen;
  - it plays for 60 s, sending 4-row clears;
  - it measures, as p50, p95 and max:
    - ping RTT;
    - hit delivery, from the thrower's send to the target's `tumbleHit`, with clocks aligned by the RTT/2 offset;
    - screen lag, from an `l` send to the screen's relay.
- [ ] **Step 2: Run it from this Mac against a local `wrangler dev` on a free port** (not 8787 or 4343) to prove it works.
- [ ] **Step 3: Before switch-on, run it against a deployed dev Worker.** Run it from this Mac and from a GitHub Actions runner (a `workflow_dispatch` job), and record both in `docs/perf/toy-tumble-latency.md` against §6.7's targets. A phone on cellular is measured during cross-play from the clients' debug overlay.
- [ ] **Step 4: Commit.**
