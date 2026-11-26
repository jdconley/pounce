# Birdwatch server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** built (2026-11-25).

**Goal:** The server half of Birdwatch, Pounce's 1.3 trick-taking game: rules as data, a pure engine, the game module, the House Cat, and the room changes it needs (options, swap seats, a House Cat taking over a seat that leaves), behind the `GAMES` flag.

**Architecture:** `src/birdwatch/` holds the pure rules (cards, rule sets, engine, views, parser). `src/games/birdwatch.ts` adapts it to `GameModule`. The room gains three generic abilities (game options, swapping seats, `leaveTakeover`) that Cat Tower and Tuna Tiles never use, so their bytes on the wire don't change.

**Tech Stack:** TypeScript on Cloudflare Workers and Durable Objects, Vitest, Miniflare.

**Spec:** `docs/superpowers/specs/2026-11-25-birdwatch-design.md` (rooms and the wire: `2026-11-11-tile-game-design.md` §8, §9).

## Global Constraints

- Code id `birdwatch`, display title "Birdwatch", 4 to 6 seats.
- Never use the commercial game's name, its bird card or its wording anywhere. No emoji.
- `GAMES` stays `"tiles"` in `apps/play-api/wrangler.jsonc`. `.dev.vars.example` and tests list `birdwatch`.
- Cat Tower and Tuna Tiles payloads stay byte for byte as they are: `tests/fixtures-pinned.test.ts` pins them by hash, and this plan adds the tile game's two files to that list.
- The engine is pure and deterministic. Views never carry another seat's hand, the nest, the put-back cards or the holder of the called card before the reveal.
- `pnpm check` (lint, typecheck, tests with coverage thresholds) passes.

## Rulings (where the spec leaves it open)

1. **Card ids.** 0 to 55 are suited: suit `floor(id / 14)` in the order fish, mouse, feather, bell (the tile game's `Suit` names), rank `id % 14 + 1`. 56 is the Bird. Ids are the only card form on the wire.
2. **Suits on the wire** are the tile game's strings: `"fish" | "mouse" | "feather" | "bell"`.
3. **Order inside a hand:** bidding, nest, trump, partner (5 players only), play. The called card is public the moment it is called; who holds it is not.
4. **Bidding.** A bid is a multiple of 5 from the rule set's minimum to its maximum, and at least 5 over the high bid. Once every seat but one has passed, the one left wins at the high bid, or at the minimum if nobody bid (that seat is always the dealer, as the spec wants). A bid of the maximum ends bidding at once.
5. **Calling a put-back card is allowed.** The partner picker offers every card the bid winner does not hold after the nest, put-back cards included: calling one is choosing to play alone. That is revealed at the end of the hand.
6. **Teams.** `teams` lists the sides by seat: 4 players `[[0,2],[1,3]]`, 6 players `[[0,3],[1,4],[2,5]]`, 5 players one side per seat. `scores` has one entry per team. In 5 players the bid winner and the partner each score the bidding side's result, and every other seat scores the points the other side took.
7. **Winning.** After each hand, a side is eligible when its total is at least the target and it did not miss its bid on that hand. The highest eligible total wins. A tie for it plays another hand. No hand cap: totals move every hand.
8. **Hands are dealt from the game's seed.** The state keeps `seed` and `rngCalls` (Cat Tower's pattern); both are server-only. The first dealer is `floor(rng() * seats)`.
9. **Turns.** Every bidding, nest, trump, partner and play action ends the acting seat's turn (streaks count it) and is followed by a `turn` event for whoever acts next. `turnKey` is `${hand}:${moves}`.
10. **Leaving.** The module declares `leaveTakeover: true`. A client's `forfeit` (the module's `forfeitAction`) and a retire never reach the engine: the room flips the seat to `{ kind: "bot", botLevel: "house" }`, keeping its `person` (so the table still shows the name), its `deviceId` and `playerId` (so lists and streaks still know who left), plus `left: true`. A bot seat is controlled by no device. The room's `outSeats()` counts a left seat as out, so the tables lists and streak reports treat the person as gone, as a Cat Tower forfeit does. When no human seat is left, the room applies `forfeitAction`, which the engine reads as "the table is empty": the game ends with `endReason: "left"` and no winners.
11. **Room events.** A takeover sends the room event `{ kind: "houseCat", seat }` before the snapshots. Cat Tower and tiles never send it.
12. **Options.** `GameModule` gains `defaultOptions: O | null` and `parseOptions(raw): O | null`; `create(seats, seed, options)`. A room of a game with default options stores them at creation (`RoomState.options`), the lobby message `{ t: "setOptions", options }` replaces them (host only, lobby only, error `not_allowed` from anyone else), snapshots carry `options` only when the room has them, and "Play again" copies them. Cat Tower and tiles have none, so their rooms never gain the key.
13. **Swap seats.** `{ t: "swapSeats", seats: [a, b] }`: host only, lobby only, two different seats in range. It swaps the two seats whole (open, closed, bot or a person) and moves their move codes with them. Allowed at every game's table: an old app never sends it, so nothing changes for it.
14. **Lobby size.** A new lobby opens `max(2, minSeats)` seats (4 for Birdwatch), the rest closed, as many seats as `maxSeats`.
15. **Live table.** `progressKind` gains `"score"`; `progress` per seat is its side's score.
16. **Put-back cards in the bid winner's own view.** The device controlling the bid winner sees `fromNest` during the nest step (so the cards can glow) and `putBack` afterwards. Nobody else sees either until the hand ends, when `handOver` and the view show `putBack` to everyone.
17. **Abandoned and hand-cap safety.** The House Cat soak plays every rule set at 4, 5 and 6 seats; a game must end within 300 hands.
18. **Rule set at Play again.** The new table keeps it (`RematchIntent.options`).
19. **The web player builds.** It imports the server's types, so two small changes keep it compiling without drawing anything new: `gameOf` in `apps/play-web/src/ui/tv/tv-model.ts` narrows the room's id to the web catalog's (the server never lets the web player into a game it doesn't list), and `tests/catalog.test.ts` lists `birdwatch` as a server game the web doesn't draw yet. The web session removes it from that list when its table lands.
20. **Bot speed** is checked as the 99th percentile over the soak (under 5 ms), not the single slowest move, which a busy CI machine can stall.
21. **Invite pages.** A Birdwatch invite uses the default Open Graph image until the release adds its own preview (the websites change only at release, per AGENTS.md).

## Wire shapes

```ts
type CardId = number;                       // 0-56, ruling 1
type RuleSetId = "official" | "tucker" | "friesen";
type BirdOptions = { rules: RuleSetId };
type BirdPhase = "bidding" | "nest" | "trump" | "partner" | "play" | "between" | "over";
type TrickCard = { seat: Seat; card: CardId };
type HandResult = {
  hand: number; bidder: Seat; bid: number; partner: Seat | null; trump: Suit;
  made: boolean; taken: number[];           // per team, counters taken (put-back included)
  change: number[]; totals: number[];       // per team
};

type BirdAction =
  | { type: "bid"; amount: number } | { type: "pass" }
  | { type: "nest"; discard: CardId[] } | { type: "trump"; suit: Suit }
  | { type: "partner"; card: CardId } | { type: "play"; card: CardId }
  | { type: "nextHand" } | { type: "forfeit" };

type BirdView = {
  rules: RuleSetId; seats: number; target: number; minBid: number; maxBid: number; nestSize: number;
  teams: Seat[][]; scores: number[]; history: HandResult[];
  status: "playing" | "over"; phase: BirdPhase; hand: number; dealer: Seat;
  turn: Seat | null;                        // null between hands and once over
  handCounts: number[]; hands: Record<Seat, CardId[]>;   // only controlled seats
  bids: (number | null)[]; passed: boolean[]; high: { seat: Seat; amount: number } | null;
  trump: Suit | null; called: CardId | null; partner: Seat | null;
  trick: TrickCard[]; leader: Seat | null; lastTrick: { cards: TrickCard[]; winner: Seat } | null;
  played: CardId[]; points: number[]; tricks: number[];  // per seat, this hand
  winners: Seat[];
  // Only for the device that may use them:
  playable?: CardId[];                      // play, controlled actor
  bidRange?: { min: number; max: number; step: number };  // bidding, controlled actor
  fromNest?: CardId[];                      // nest, bid winner's device
  putBack?: CardId[];                       // after the nest: bid winner's device; at hand end: everyone
  partnerChoices?: CardId[];                // partner, bid winner's device
  youArePartner?: Seat;                     // a controlled seat holds the called card
  endReason?: "target" | "left";
};

type BirdEvent =
  | { kind: "dealt"; hand: number; dealer: Seat; handCounts: number[]; hands: Record<Seat, CardId[]> }  // controlled only
  | { kind: "bid"; seat: Seat; amount: number } | { kind: "passed"; seat: Seat }
  | { kind: "bidWon"; seat: Seat; amount: number }
  | { kind: "nest"; seat: Seat; cards?: CardId[] }          // cards: bid winner's device only
  | { kind: "putBack"; seat: Seat; count: number; cards?: CardId[] }  // cards: bid winner's device only
  | { kind: "trump"; seat: Seat; suit: Suit } | { kind: "called"; seat: Seat; card: CardId }
  | { kind: "turn"; seat: Seat } | { kind: "played"; seat: Seat; card: CardId }
  | { kind: "partner"; seat: Seat }                         // the called card was just played
  | { kind: "trick"; winner: Seat; cards: TrickCard[]; points: number }
  | { kind: "handOver"; result: HandResult; putBack: CardId[] }
  | { kind: "gameOver"; winners: Seat[]; scores: number[]; reason: "target" | "left" };

type BirdError = "game_over" | "bad_action" | "not_your_turn" | "bad_seat" | "wrong_phase"
  | "bid_too_low" | "bid_too_high" | "bad_bid" | "bad_card" | "not_your_card"
  | "wrong_count" | "duplicate_card" | "own_card" | "must_follow";
// Room messages: { t: "setOptions", options: BirdOptions }, { t: "swapSeats", seats: [a, b] }.
// Room event: { kind: "houseCat", seat }. Seat view: left?: true. RoomView: gameId "birdwatch", birdwatch?, options?.
```

## Review Focus

1. A 5-player partner leaking before the reveal through any field: `hands`, `youArePartner` on a device that doesn't hold the card, `putBack`, an event's `cards`. Task 3's leak sweep walks every view and event of whole bot games for every device.
2. A seat that leaves on its own move, mid-bidding or with the nest in hand: the House Cat must pick up that exact step at once. Task 7 tests a forfeit on the leaver's own nest step.
3. The last human leaving a table full of House Cats: the game must end, not play on forever with nobody watching. Task 7.
4. "Play again" after a takeover: the new table must not hand the leaver's seat back to a House Cat that still carries their device and player. Task 7.
5. Bidding where every seat passes, and a max bid on the first call. Task 2.

---

### Task 1: Cards and rule sets

**Files:** Create `src/birdwatch/cards.ts`, `src/birdwatch/rules.ts`; test `src/birdwatch/rules.test.ts`.

**Interfaces (produces):** `CardId`, `BIRD = 56`, `card(id): { suit: Suit; rank: number } | { bird: true }`, `isCardId`, `suitOf(id, trump): Suit | "bird"`, `RuleSetId`, `RULE_SETS: Record<RuleSetId, RuleSet>`, `RuleSet = { id; ranks(seats): number[]; nestSize(seats); handSize(seats); order: number[] (low to high); counter(id): number; minBid: 70; maxBid; bidStep: 5; target; birdWild; total }`, `deckFor(rules, seats): CardId[]`, `isRuleSetId`.

- [ ] Tests: for each rule set and 4, 5, 6 seats, `deckFor` length equals `hand * seats + nest` and matches the spec table (41/53/53 official, 45/57/57 tucker and friesen); the counters in each deck sum to 120 (official) or 180; Tucker and Friesen rank 1 above 14; Friesen `birdWild` false, the others true; targets 300/500/500; bid ranges 70-120 and 70-180.
- [ ] Implement, run `pnpm --filter @pounce/play-api exec vitest run src/birdwatch`, commit.

### Task 2: The engine

**Files:** Create `src/birdwatch/engine.ts`; tests `src/birdwatch/engine.bidding.test.ts`, `engine.play.test.ts`, `engine.scoring.test.ts`, test helpers `tests/birdwatch-helpers.ts`.

**Interfaces (produces):** `BirdState`, `BirdAction`, `BirdEvent`, `BirdError`, `newGame(seats, seed, options?: BirdOptions): BirdState`, `applyAction(s, seat, a)`, `playable(s, seat): CardId[]`, `trickWinner(trick, trump, rules): Seat`, `teamsFor(seats): Seat[][]`, `actor(s): Seat | null`.

- [ ] Bidding tests: bidding starts left of the dealer; under 70, not a multiple of 5, under high + 5 and over the max are refused (`bid_too_low`, `bad_bid`, `bid_too_high`); a passed seat is skipped and can't bid again; all-but-one passed ends it; all pass leaves the dealer at 70; a max bid ends it at once; the bid winner's hand grows by the nest.
- [ ] Nest, trump, partner tests: the put-back count must equal the nest size (`wrong_count`), cards must be in hand (`not_your_card`), no repeats; trump any suit; partner only in 5 players, never a held card (`own_card`), a put-back card is allowed.
- [ ] Play tests: follow suit (`must_follow`); Bird wild in official and tucker (playable off-suit even when you can follow; forced when trump is led and it is your only trump); Bird not wild in friesen; leading the Bird leads trump; trick winners (trump beats led suit, the Bird beats everything, a 1 beats a 14 in tucker); the trick winner leads next.
- [ ] Scoring tests: put-back cards go to the last trick's winner; made scores points taken; missed loses the bid; other sides score what they took; counters per hand sum to the rule set's total; 5-player scoring per ruling 6; the target, a tie playing on, and a side that missed on the target hand not winning (ruling 7); `forfeit` ends the game with `left`.
- [ ] Implement, run, commit.

### Task 3: Views, events, parser, hidden information

**Files:** Create `src/birdwatch/view.ts`, `src/birdwatch/parse.ts`; tests `src/birdwatch/view.test.ts`, `parse.test.ts`.

**Interfaces (produces):** `viewFor(s, controlled): BirdView`, `eventFor(e, controlled): BirdEvent`, `parseAction(raw): BirdAction | null`, `parseOptions(raw): BirdOptions | null`.

- [ ] Tests: each choice field appears only for the device that may use it (`playable`, `bidRange`, `fromNest`, `putBack`, `partnerChoices`, `youArePartner`); the partner seat stays null until the called card is played; a leak sweep plays whole House Cat games for each rule set and seat count and checks that no view or event for any device carries a card it may not see; the parser takes each action exactly and refuses extra keys, wrong types, ids over 56 and over-long discards.
- [ ] Implement, run, commit.

### Task 4: The module, the House Cat and the soak

**Files:** Create `src/games/birdwatch.ts`, `src/bots/house-cat-birdwatch.ts`; modify `src/games/module.ts` (options members, `leaveTakeover?`, `progressKind` adds `"score"`), `src/games/index.ts` (register, title "Birdwatch", union types), `src/games/cat-tower.ts`, `src/games/tiles.ts` (`defaultOptions: null`, `parseOptions: () => null`); tests `src/bots/house-cat-birdwatch.test.ts`, `src/games/birdwatch.test.ts`, `tests/birdwatch-sim.test.ts`.

- [ ] Bot tests (spec §6): always legal; bids no higher than its estimate; keeps trump and high cards in the nest and avoids putting back counters; names its longest suit; calls the highest trump it doesn't hold; throws its lowest card when it can't win; under 50 ms a move.
- [ ] Soak: every rule set at 4, 5 and 6 seats, many seeds, House Cats only, through the module: every action accepted, every game ends within 300 hands, counters per hand sum to the total.
- [ ] Implement, run, commit.

### Task 5: The room: options, game fields, events, live table

**Files:** Modify `src/room/core.ts`, `src/protocol.ts`, `src/live/live.ts`, `src/room/game-room.ts` (RematchIntent options), `src/http/links.ts`; test `src/room/core.birdwatch.test.ts`.

- [ ] Tests: a Birdwatch lobby opens 4 seats of 6 and stores `{ rules: "official" }`; `setOptions` from the host changes it, from others `not_allowed`, after start `not_lobby`, a bad rule set `bad_message`; start with 3 seats is `not_enough_players`; the snapshot carries `gameId: "birdwatch"`, `game: null`, `birdwatch` and `options`; events go out as `{ kind: "birdwatch" }`; Play again keeps the options; the live table sends `progressKind: "score"`; Cat Tower and tiles rooms never gain `options`.
- [ ] Implement, run, commit.

### Task 6: Swap seats

**Files:** Modify `src/protocol.ts`, `src/room/core.ts`; test in `src/room/core.lobby.test.ts`.

- [ ] Tests: the host swaps two seats (a person and a House Cat) and everyone gets a snapshot; a move code follows its seat; non-host `not_allowed`; same seat or out of range `bad_seat`; after start `not_lobby`; the parser refuses anything but two seat ints.
- [ ] Implement, run, commit.

### Task 7: A House Cat takes over

**Files:** Modify `src/room/core.ts`, `src/room/game-room.ts` (lists use the seats a device held), `src/protocol.ts`; test `src/room/core.takeover.test.ts`.

- [ ] Tests: a forfeit from a seat turns it into a House Cat with `left: true`, the room event `houseCat`, and the game plays on; on the leaver's own move the bot acts next tick; a retire does the same; the last human leaving ends the game (`left`); the streak report lists the leaver in `out`; Play again deals the leaver's seat as a plain House Cat; Cat Tower and tiles forfeits are unchanged.
- [ ] Implement, run, commit.

### Task 8: Wire fixtures, the flag and Miniflare

**Files:** Create `tests/birdwatch-protocol-fixtures.test.ts`, `fixtures/protocol/birdwatch-server-messages.json`, `birdwatch-client-messages.json`, `tests/birdwatch.test.ts`; modify `tests/fixtures-pinned.test.ts` (pin the tiles files), `.dev.vars.example`, `src/env.ts` comment, `vitest.config.ts` (`src/birdwatch/**` thresholds).

- [ ] Fixtures generated from a real room: lobby, each phase from the bid winner's and another device's side, a 5-player hand before and after the reveal, between hands, over, every event, every new error, the client messages.
- [ ] Miniflare: with `GAMES=birdwatch`, an app listing it creates a table, sets the rule set, seats four, starts, and plays a bid; an app that doesn't list it gets 404; without the flag creating is 400.
- [ ] `pnpm check`, commit, open the PR.
