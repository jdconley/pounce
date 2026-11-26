# Birdwatch: design

Date: 2026-11-25 · Owner: JD Conley (Conley Chaos LLC) · Status: draft for JD · Release: 1.3 · Lives in `github.com/jdconley/pounce`

Parent specs: `2026-10-31-pounce-cat-tower-design.md` (product principles, architecture), `2026-10-31-pounce-ios-design.md` (art direction, table, pass-and-play, forfeit), `2026-11-11-tile-game-design.md` (rooms and the wire for more than one game, the `GAMES` flag), `2026-11-15-web-player-design.md`, `2026-11-16-tv-table-design.md`. Where this document says nothing, those apply.

Marks: **(JD)** means JD decided it, in the brief or in answers on 2026-11-25. **(call)** means a builder call made while writing this, open to override.

## 1. What this is and why

Pounce's third table game is a partnership trick-taking game with bidding, a nest and one special card, the family of games played with a 57-card numbered deck. The mechanics are traditional. The name, theme, cards, art and every word of the rules are ours. **(JD)**

It is the first Pounce game played in teams, and the first one that needs 4 or more players. It is the game JD's family actually plays at the kitchen table, under house rules with family names. So it ships with three rule sets, picked per table. **(JD)**

**Success:** JD's family plays a full game to 300 or 500 on phones and the TV, with any mix of shared-phone, own-phone, remote and House Cat seats. Each household plays under its own rule set, and nobody has to explain to the app what a "Tucker game" is.

## 2. Goals, non-goals, anti-goals

**Goals**
- Three rule sets, enforced on the server: Official, Tucker and Friesen (§4). **(JD)**
- 4, 5 or 6 players. **(JD)**
  - 4 players: two teams of two.
  - 5 players: pick a partner. The bid winner calls a card, and whoever holds it is their secret partner for that hand. **(JD)**
  - 6 players: three teams of two. **(JD)**
- Any seat can be on a shared phone, its own phone, remote or a House Cat, as in every Pounce game.
- It plays on iPhone, on the web player and on the TV table, with the same rules and rooms, in 1.3.
- Streaks, turn reminders, nudges, retiring a stalled seat and "Play again" work as they do in Cat Tower.

**Non-goals (1.3)** **(call)**
- 2- or 3-player variants.
- Any rule set beyond the three. The rules engine takes a rule set as data, so a fourth is cheap later. There's no custom-rules editor.
- Bot levels other than House Cat.
- A daily single-player version.
- Chat, table talk or signals between partners.

**Anti-goals**
- Anything that reads as the commercial game: its name, its bird card, its card faces, its four colours or its rulebook wording. That covers code, comments, tests, docs, UI copy and commit messages. The house rule sets keep JD's family names, Tucker and Friesen, because those are ours. **(JD)**
- Telling the table who the 5-player partner is before the called card is played (§4.6).
- A bidding screen full of numbers and words. Bidding is one big number, a plus button and a pass button.
- Suits you can only tell apart by colour.

## 3. Theme and cards

### 3.1 The idea **(call)**

The cats are at the window watching the bird feeder. Every hand they bid on how many birds their team will spot. The **Bird** is the special card: a bright, round, cartoon songbird, ours, in the app's style. It is never black and never crow-shaped. The nest is the feeder.

| Rules word (code) | What players see |
| --- | --- |
| special card (`bird`) | the Bird |
| nest (`nest`) | the feeder |
| trump (`trump`) | the trump suit, a glowing badge |
| trick (`trick`) | the sill: the cards played this round, in the middle |
| counter (`points`) | a small seed badge on the card with its value |
| bid (`bid`) | a number on a sign the cat holds up |
| set (`set`) | "Missed" on the bid sign, the cat droops |

### 3.2 Suits **(call)**

Birdwatch reuses the four toy suits from Tuna Tiles (fish, mouse, feather, bell), with the same colours, silhouettes and texture bands. Families learn them once. Colour is never the only cue (Tuna Tiles spec §3.2).

### 3.3 Card faces **(call)**

- The style is Cat Tower's chunky card style: a saturated suit-coloured body, a big white outlined numeral and the suit silhouette.
- A counter card carries a seed badge with its value (5, 10, 15). That way a new player sees which cards are worth points without reading rules.
- The Bird has its own face on white, so it never passes for a suit, with a "20" seed badge.
- Card backs are Cat Tower's violet paw back.
- Each card must stay readable at the width it gets in a 15-card hand on a 393 pt phone. The style checkpoint has to show 14, 1 and the Bird at that size before art production starts.
- VoiceOver labels:
  - "10, fish, 10 points"
  - "Bird, 20 points, top trump"
  - "1, bell, 15 points" (Tucker and Friesen)

### 3.4 Name

**Birdwatch** **(JD)**. The code id is `birdwatch` and never changes, even if the display name does. Nobody has run a trademark or App Store search on the name yet, and it has to happen before 1.3 is submitted. If it fails, the display name changes and the id stays.

## 4. Rules, in our words

The in-app help is written from this section.

### 4.1 The three rule sets **(JD)**

| | Official | Tucker | Friesen |
| --- | --- | --- | --- |
| Rank, low to high | 5 to 14 | 5 to 14, then 1 | 5 to 14, then 1 |
| 1s | not in the deck | highest card of its suit, 15 points | highest card of its suit, 15 points |
| The Bird | top trump, may be played any time | top trump, may be played any time | top trump (above the 1), follows suit like any trump |
| Points a hand | 120 | 180 | 180 |

Friesen is Tucker with one change: the Bird is not wild. **(JD)**

Counters in every rule set: each 5 is worth 5, each 10 and each 14 is worth 10, and the Bird is worth 20. In Tucker and Friesen each 1 is also worth 15. With 2s, 3s and 4s in the deck (§4.2), each of those ranks under the 5 and is worth nothing.

### 4.2 The deck and the deal

The full deck has 1 to 14 in four suits, plus the Bird: 57 cards.

| Players | Official | Tucker and Friesen |
| --- | --- | --- |
| 4 | 5 to 14 + Bird = 41 cards, 9 each, 5 in the nest **(JD: the official rules)** | 1, 5 to 14 + Bird = 45 cards, 10 each, 5 in the nest **(JD: 2s, 3s and 4s out)** |
| 5 | 2 to 14 + Bird = 53 cards, 10 each, 3 in the nest **(call)** | all 57 cards, 10 each, 7 in the nest **(call)** |
| 6 | 2 to 14 + Bird = 53 cards, 8 each, 5 in the nest **(call)** | all 57 cards, 9 each, 3 in the nest **(call)** |

**Call, for JD to check:** JD said the 2s, 3s and 4s come out "for 4 player games". I read that as: with 5 or 6 players, they stay in. That gives everyone a full hand. Official rules never use 1s. The nest sizes are whatever divides evenly. The bid winner always takes the whole nest and puts back the same number of cards.

The deal rotates one seat to the left each hand. The first dealer is picked at random from the game's seed. Dealing order is cosmetic. The server shuffles and hands out the cards in one step.

### 4.3 Bidding **(official, with calls)**

- Bidding starts left of the dealer and goes around. On your turn, raise the high bid by 5 or more, or pass. Once you pass, you are out of the bidding for that hand.
- Official bids run from 70 to 120. Tucker and Friesen bids run from 100 to 180. **(call: the official range, scaled to the bigger deck)**
- Bidding ends when every player but one has passed. If every player passes without a bid, the dealer takes the hand at the minimum bid. **(call)**
- A bid of the maximum ends bidding at once.
- There are no redeals. **(call: the official rules allow a redeal for a hand with no points, which adds a decision for little gain)**

### 4.4 The nest and trump

The bid winner takes the nest into their hand. They put back the same number of cards, which may be any cards, including counters and the Bird. **(official)** Then they name trump. In 5-player games, they also call their partner (§4.6). The cards they put back stay face down until the hand ends. They go to whoever wins the last trick, counters included. **(official)**

### 4.5 Play

- The bid winner leads the first trick. After that, whoever won a trick leads the next one.
- **Follow suit.** You must follow the suit that was led if you can. If you can't, play any card, trump included.
- **Winning a trick.** The highest trump wins it. With no trump in it, the highest card of the suit that was led wins.
- **The Bird is always the highest trump.** When the Bird is led, trump has been led.
- **Official and Tucker.** The Bird may be played at any time, even when you could follow suit. When trump is led and the Bird is your only trump, you must play it. **(official)**
- **Friesen.** The Bird is simply the top trump card. You may play it only when trump is led or when you can't follow the suit that was led, as with any trump. **(JD)**
- The app never lets you make an illegal play. Cards you can't play are dimmed, so the server's reneging penalty can never happen here and is left out. **(call)**

### 4.6 Five players: pick a partner **(JD)**

- After taking the nest and naming trump, the bid winner calls one card. The app offers only cards the bid winner does not hold. **(call)**
- Whoever holds the called card is the bid winner's partner for that hand. Nobody else is told. The partner's own screen quietly marks them as the partner, so they know how to play.
- Everyone learns the partner when the called card is played. **(JD)** The partner's cat joins the bid winner's side on the table with a small flourish.
- If the called card is in the nest discards, the bid winner plays alone. This is revealed at the end of the hand. **(call)**
- Each player keeps their own score. The bid winner and the partner each score the side's result, made or missed. Each of the other three scores the points their side took. **(call)**

### 4.7 Scoring a hand **(official)**

Add up the counters each side took, including the nest discards won with the last trick. There is no bonus for the last trick or for taking the most cards.

- **Made it:** the bidding side took at least its bid, so it scores the points it took.
- **Missed:** the bidding side loses the amount of its bid. It scores nothing for the points it took.
- The other sides always score the points they took.

Scores can go below zero.

### 4.8 Winning **(call)**

- Official games go to 300, and Tucker and Friesen games go to 500. The 500 is a call, because the hands are worth half again as much.
- A game ends after the hand in which someone reaches the target.
- If more than one side reaches it, the highest total wins.
- A tie for highest plays one more hand.
- A side that missed its bid can't win on that hand, even if its total is over the target. **(call, a common house rule; JD to confirm)**

### 4.9 Leaving and forfeit **(call)**

This is a team game, so one player leaving must not end it for everyone. A forfeited or retired seat is taken over by a House Cat for the rest of the game. Its team keeps playing and its score stands. The game ends early only if every human at the table has forfeited. This replaces Cat Tower's "seat is out" rule for this game.

## 5. The table on a phone, the web and the TV

### 5.1 Lobby **(call)**

- The host picks Birdwatch on the shelf. The lobby adds one control: the rule set (Official, Tucker, Friesen), as three big pills with one line under the chosen one.
  - Official: "1s out, Bird wild."
  - Tucker: "1s high, worth 15."
  - Friesen: "1s high, Bird follows suit."
- The lobby needs 4, 5 or 6 seats, and Start stays dark until there are 4. It fills empty seats with House Cats only when the host asks, as in Cat Tower.
- With 4 or 6 seats, teammates are set by seat order: across from each other, with seats 0 and 2 on one team and 1 and 3 on the other, or 0 and 3, 1 and 4, and 2 and 5 with six. The host drags seats to choose teams. Teammates share a ribbon colour on their name tags.
- The table card on Home and the TV show the rule set's name.

### 5.2 The phone table, top to bottom (portrait) **(call)**

1. **Around the window:** every other seat's cat with a card-count bubble, a team ribbon, a dealer chip and the bid sign once there is one. The seat to act pulses.
2. **The sill:** the trick in the middle, each card in front of the cat that played it. Trump shows as a badge in the corner, and the high bid as a sign.
3. **Score strip:** one chip per side with its score and the points it has taken this hand. Tapping it opens the hand-by-hand score sheet.
4. **Your hand:** up to 17 cards in a fan, which is a bid winner's hand with the nest in Tucker or Friesen with 5 players. Cards are sorted by suit with trump on the right once it is named. Cards you can't play are dimmed. Tap to lift a card, tap again to play it, or drag it onto the sill.

### 5.3 Bidding, nest, trump and partner screens **(call)**

- **Bidding:** a big number on the cat's sign, a "+5" button, a long press to raise faster, a Bid button and a Pass button. Each other player's last bid or pass shows on their sign.
- **Nest:** the nest cards fly into your hand with a glow. You tap cards to put back until the count is right, then press Done.
- **Trump:** four big suit buttons, with a hint ring on the suit you hold the most of.
- **Partner (5 players):** a picker of the cards you don't hold. Each suit is a row, and the row for trump is first.

### 5.4 Between hands

A short summary shows the bid, made or missed, each side's points this hand, and the running totals. Then the next hand deals itself after the usual pause, as Cat Tower's rounds do.

### 5.5 Pass-and-play privacy

The parent spec's curtain applies before every hand reveal, nest, trump choice and partner call. The partner mark in a 5-player game shows only after the curtain.

### 5.6 TV table

The TV shows the sill, the cats and their bid signs, the score strip and the trump badge. Phones show only their own hand and the bid, nest, trump and partner controls. In a 5-player game, the TV never shows the partner mark until the called card is played.

### 5.7 Web player

The web player matches the phone table, with the same layout rules as the other two games, plus keyboard input. The left and right arrow keys move between cards, Enter plays the selected card, and the number keys pick a suit.

### 5.8 Teaching

There is one How to Play page per rule set, with three or four short tips each, taught on the table the way Cat Tower's coach marks are. On a table's first hand, the coach points at:
- the bid sign,
- the follow-suit dimming,
- the trump badge,
- in a 5-player game, the partner mark.

## 6. The House Cat **(call)**

The House Cat is `chooseAction(view, seat, rng)` in `src/bots/house-cat-birdwatch.ts`. It reads only its own seat's view, so it can't cheat, and it always returns a legal action.

- **Bidding:** it estimates a hand's worth from high trump in its longest suit, the Bird, 1s and 14s, and long suits. It bids up to that estimate. In a team game it adds a little when its partner has bid, and it never bids over its estimate.
- **Nest:** it keeps trump and high cards. It puts back short off-suits first and avoids putting back counters, unless they are the only cards left to put back.
- **Trump:** its longest suit, with ties broken by high cards.
- **Partner (5 players):** the highest trump it doesn't hold, and otherwise the highest off-suit 1 or 14 it doesn't hold.
- **Play:** it wins a trick cheaply when the trick holds counters, gives counters to a partner who is winning the trick, and throws its lowest card when it can't win. It leads trump when it is on the bidding side and holds the Bird or the top trump. It remembers which cards have been played, since all of those are public.
- **Speed:** under 50 ms a move.

## 7. The module

`src/games/birdwatch.ts` exports `birdwatch: GameModule<BirdState, BirdAction, BirdView, BirdEvent, BirdError>`, with id `birdwatch` and `minSeats: 4` and `maxSeats: 6`. It is pure and deterministic, as the other two games are.

The module needs to know the rule set at `create`. The builder adds an options argument, `create(seats, seed, options)`, that the room passes from the lobby, `{ rules: "official" | "tucker" | "friesen" }`. The two other games ignore it. The options are stored on the room so that "Play again" keeps them. **(call)**

Phases inside a hand: `bidding`, `nest` (bid winner only), `trump`, `partner` (5 players only), `play`, then `between` (the summary, through `betweenAction` as Cat Tower's rounds use it), and `over`.

Actions (sketch, the builder may refine):

```ts
type BirdAction =
  | { type: "bid"; amount: number }
  | { type: "pass" }
  | { type: "nest"; discard: CardId[] }
  | { type: "trump"; suit: Suit }
  | { type: "partner"; card: CardId }
  | { type: "play"; card: CardId }
  | { type: "nextHand" }
  | { type: "forfeit" };
```

**Hidden information:**
- A view never carries another seat's hand, the nest, the cards the bid winner put back, or who holds the called partner card. The partner seat appears in views and events only once the card is played, or at the end of the hand when it was in the nest.
- The holder's own view carries `youArePartner: true`.
- Every played card is public.
- At the end of a hand, the put-back cards are shown to everyone. They count for the last trick, and showing them reveals nothing that still matters.

Rule sets are data (`src/birdwatch/rules.ts`): the deck for each player count, the nest size, the rank order, the counters, the bid range, the target and whether the Bird is wild. One engine handles all three. A fourth set is one more entry.

## 8. Rooms, the wire and rollout

- Everything follows the Tuna Tiles spec §9. `GAMES` lists `birdwatch` in dev and tests. A 1.3 app sends `x-pounce-games: cat-tower,tiles,birdwatch`. An older app never meets a Birdwatch table: joining gets a 404, the table is left out of lists, and pushes skip that device.
- Snapshots carry `gameId: "birdwatch"` and a `birdwatch` view. Events are wrapped as `{ "kind": "birdwatch", "event": … }`. The error codes are new, the game's own.
- **The live table:** progress is each side's score, `progressKind: "score"`, for the TV and the widgets.
- **Rollout:** the server merges with the flag off in production. It turns on once 1.3 is in TestFlight and the web player draws the game. 1.3 then goes to the App Store, and the websites are updated per AGENTS.md. They claim the game only once people can play it.

## 9. Testing **(call)**

- Rules tests for each rule set:
  - deck sizes and deal counts for 4, 5 and 6 players,
  - the follow-suit cases, with the Bird wild and not wild,
  - trick winners,
  - nest discards going to the last trick,
  - made and missed scoring,
  - the target, ties, and missing your bid on the target hand.
- Counter totals: 120 and 180 every hand, summed across sides.
- Hidden-information tests: no view or event leaks a hand, the nest or the partner seat before the reveal.
- Bot soak: thousands of bot-only games across every rule set and player count. They check for no stalls and no illegal moves, and that every game ends.
- Shared fixtures for the Swift and web ports of the legal-play check, as Tuna Tiles uses `tiles-sets.json`.
- Cross-platform: one table played from iPhone, web and TV together, in each player count. That is the "every platform with every other" check before merge.

## 10. Left to the builder

- Card art, animation and sound, in the established style.
- Exact layout on small phones and iPad.
- Bot tuning, inside §6.
- The wording of tips and help, kept terse.
