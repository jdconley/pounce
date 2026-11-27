# The Daily Dish: daily puzzles and a family board

## Why

JD, 2026-11-20:

> "i want to add some more casual/fast single player games designed for daily play. and the family
> competes on a leaderboard every day. but make it secure so people can't cheat the leaderboard and
> just submit scores if they find the api. … make something that the family/connections will want
> to play every single day on their own and then talk about it and compare."

Pounce so far is games you play with each other. This adds four quick puzzles that each person
plays alone, once a day. Everyone gets the same puzzles that day, so the family has something to
compare at dinner and to watch land on the TV at night. They are the daily habit's other half: a
reason to open Pounce on a day nobody has dealt a table.

## Goals

- **Four daily puzzles**, each a new one every day, the same for everyone, made by the server from
  a seed. Nobody makes levels.
- **A board each day** for your family and connections: one per game and one overall.
- **Streaks:** a finished daily puzzle counts toward your own streak and toward every shared streak
  you have. Two connected people who each play a daily puzzle that day keep their shared streak.
  This reverses earlier decisions (below).
- **History and stats** per game, a share card that gives nothing away, and reminders that follow
  the kids and teens rules already in place.
- **The TV shows tonight's board,** live, on the Apple TV app and the browser TV page. A player can
  choose to show their puzzle on the TV while they play it.
- **Cheating takes more than finding the API.** The server never accepts a score. It referees every
  run and works out the score itself.
- **Every platform:** the iPhone and iPad app, the web player (phones, Android, laptops), the Apple
  TV app and the browser TV page all show the same puzzles, results and board.

## Non-goals

- Playing a daily puzzle with the TV remote. Puzzles are played on a phone, a tablet or a computer.
- Public or global leaderboards. The board holds only you and your connections.
- An archive of past puzzles to play. Each puzzle can be played on its own day only.
- New push types, such as "Mom finished Sniff". The existing reminders mention the puzzles instead.
- Game Center leaderboards.
- Offline play. Pounce is online-only (cat tower design, JD), and refereeing needs the server.

## Anti-goals (a failure even if it works)

- **A score the server didn't work out.** No route takes a score, a time or a "solved" flag from a
  client.
- **A copy of someone else's game.** We take only the rule sets. No names, word lists, art, colors,
  sounds or layouts from Wordle, the New York Times games, Block Blast or Zoodoku.
- **A board that shames.** No "last place", and nothing about who didn't play.
- **Spoiling it by accident.** Nobody sees a puzzle they haven't played unless a player chose to
  show it and someone pressed Watch on the TV.
- **A dropped frame.** Making, checking and replaying puzzles never run on the main thread.

## What exists today

Recon of `main` at `dbf8b8d`.

- **Identity.**
  - Requests carry a device token, `v1.<deviceId>.<HMAC>`, as a bearer token (`apps/play-api/src/auth.ts:33-67`).
  - People on a device are named with `?person=`. Each has a 32-byte person key, which the server
    checks against a stored hash (`players/identities.ts`, `PounceKit/Account/PersonKeys.swift`).
  - Nothing is signed per request. That's fine here: the defense is that no route accepts a result
    (below).
- **Storage.** Everything is SQLite-backed Durable Objects: `Player`, `Pair`, `GameRoom`,
  `DeviceIndex`, `Limiter`, `ScreenLinks` and others. There is no D1 database outside the funnel, and
  no KV.
- **Connections are pairs.** Each `Player` lists its `pairs`, and each pair is a `Pair` DO
  (`streaks/pairs.ts`). A pair forms when two people each take a turn at one table, or as soon as an
  invite link is accepted.
- **The streak day** runs from 04:00 to 04:00 in the person's own time zone (`streaks/clock.ts`).
  - Pair streaks need both people "in": each took a turn at a shared table, or was covered by the
    late move pass (`streaks/pair-core.ts`, `isIn`).
  - Your own streak (`streaks/personal.ts`) needs a turn at a table with another person
    (`game-room.ts:430`).
- **There is no seeded RNG in Swift.** The TS side has xoshiro128** (`rules/rng.ts`).
  - No golden vectors are shared between Swift and TS yet.
  - Swift tests already read the JSON fixtures in `apps/play-api/fixtures` by path
    (`PounceKitTests/Fixtures.swift`).
- **Rate limiting** has its own DO, `Limiter` (`safety/limiter.ts`).
- **TV links** use `ScreenLinks` and `POST /v1/screens/link`, with QR codes and backup codes
  (`docs/tv-protocol.md`).
- **There is no leaderboard, history or stats code.**

### The decisions this reverses

| Where | What it said | Now |
|---|---|---|
| Daily habit design §6.1 (:395-397) | A pair's day counts only turns at a shared table. "Bot seats are ignored." | A finished daily puzzle also counts as playing that day. |
| Daily habit design §7 (:446) | "No personal streak. A personal streak would reward playing alone (bots)." | Already reversed by the trophy room design §2. |
| Trophy room design §2 and D1 (:35, :74) | Your own streak counts "a turn at a table with at least one other human. Bots alone don't count." | A finished daily puzzle counts too. Bots alone still don't. |

JD: "partners and other connections in the game should get a streak if they both play a single
player game, contrary to previous decisions."

## Approaches considered

1. **The server referees as you play.** *Picked (JD).*
   - At the start, the server sends that day's puzzle and starts its own clock.
   - The client sends its moves as they happen, in small batches. The server checks each one with
     the same rules and keeps the state.
   - Sniff's answer never leaves the server; each guess is checked there. Box Fort's pieces come
     three at a time, so nobody sees ahead.
   - The server works out the score and the time. The same stream feeds live progress to the TV
     and lets a run carry on from another device.
   - Puzzles are made only on the server. Clients need each game's rules, not its puzzle maker.
   - Cost: play needs a connection. Pounce already does.
2. **The client gets a seed and the server replays the run at the end.** *Not picked.*
   - The puzzle makers would have to be built twice, in Swift and TS, and stay identical.
   - Every future Box Fort piece would be readable on the client.
   - Sniff would still need the server for each guess, and the TV would still need a live stream.
3. **Every tap waits for the server.** *Dropped.* It feels laggy, and Pounce has to stay smooth.

## The design

### 1. The four puzzles

Each puzzle has an original Pounce name and look: cat-themed, in Pounce's loud, cartoony style. The
names are placeholders until JD has seen them in the app.

| Name | Rule set | Played on |
|---|---|---|
| **Nine Lives** | the number grid | a 9 by 9 grid of paw tiles, digits 1 to 9 |
| **Box Fort** | block placing | an 8 by 8 rug of cardboard boxes |
| **Sniff** | five-letter word guessing | six guesses, letters on scent tags |
| **Cat Nap** | the Queens-style animal puzzle (Zoodoku's rule set; JD confirmed) | an N by N quilt of colored patches |

The hub is called **the Daily Dish**: four treats in a bowl, one a day each. *(My call; the name is
a placeholder too.)*

#### Nine Lives (the number grid)

- **Rules.** Fill the grid so each row, column and 3 by 3 box holds 1 to 9 once.
- **Puzzles** have one solution, and are graded by a logic solver by the hardest technique needed.
- **Controls.**
  - Tap a cell, then a number.
  - Notes (pencil marks) live on the client only. They never cost a life.
- **Three lives and three hints** (the family's request, via JD, 2026-11-26: "get rid of the hint
  penalty and give us 3 lives ... and you can also get 3 hints. separate helps."). See
  [Nine Lives: lives and hints](#nine-lives-lives-and-hints) below for the whole rule, the
  rulings and how older apps keep their rules.
- **Finish.** The run ends solved when every cell holds its answer, or missed on the third wrong
  number ("Out of lives").
- **Score:** the active time (§3, "The clock"). Hints cost no time.
- **Give up** ends the run, unsolved.

##### Nine Lives: lives and hints

*Added 2026-11-26. This replaces the first rules: no check against the solution, a clash shown
only against the visible rule, "Not quite" on a full grid with a mistake, and a hint that filled a
cell and added 30 seconds.*

- **What "wrong" means.** The first rules had no "wrong": the server never compared a cell with
  the solution, the board showed only clashes (a digit repeated in a row, column or box), and a full
  grid with a mistake said "Not quite". **Ruling:** a number is wrong when it isn't the solution's
  digit for that cell, checked by the server the moment it is entered. A clash is no longer the
  test: a digit that clashes is always wrong, and a digit that clashes with nothing can still be
  wrong.
- **Right away, not at the end** (JD, 2026-11-26: the family wants to know the moment a number is
  wrong). Each number goes to the server the moment it's placed, never waiting for a batch. A wrong
  one shows red with a short shake as soon as the answer is back, and a life goes.
- **Checked by the server, not on the phone.** *(Ruling.)* The phone never has the solution
  before the run ends, so the board stays honest. A solution on the phone would be readable from
  the start answer, and anyone could fill a perfect grid at human speed and top the board. The cost
  is one round trip, typically 100 to 200 ms, before the red mark shows. The digit shows at once,
  then turns red or stays.
- **A right number** stays and locks, like a given. It can't be cleared or changed.
- **A wrong number** costs one life. *(Ruling: it stays, marked, until the player clears it.)* It
  isn't placed: the cell stays empty to the server, and the phone shows the digit in the cell, red,
  until the player enters another or erases it. That reads better than having it vanish: the player
  sees what they tried. Erasing it costs nothing. The same wrong digit again in the same cell costs another life, so the apps
  don't send it.
- **Three lives.** The third wrong number ends the run: outcome `missed`, the same outcome Sniff
  uses when its sixth guess misses.
- **Three hints, separate from lives.** A hint fills one cell, from the server, as before. It costs
  no time and no life. After three, the Hint button is spent. Lives never limit hints, and hints
  never restore lives.
- **Notes** (pencil marks) stay on the phone, are never checked, and never cost a life.
- **Failing.** The board fills in the rest of the solution, kindly, under one short line ("Out of
  lives"), then the end screen. The server sends the solution only once the run has ended this way.
- **No second try.** A failed run is that day's run, as every run is: starting again returns it,
  ended (§3, "One run per player"). An account merge keeps one run per puzzle, as before.

**How a failed run counts** (the ruling, kept the same as the other Dish puzzles' losses):

| | Solved | Failed (out of lives) | Gave up | Closed at 04:00 |
|---|---|---|---|---|
| Outcome | `solved` | `missed`, as Sniff's sixth miss | `gaveUp` | `closed` |
| Your own and shared streaks (§5) | counts | counts | counts | doesn't |
| The game's own streak, in stats | counts | counts | counts | ends it |
| Stats: played / solved | both | played | played | played |
| The board (§6) | ranked by time | after every solved run, by percent, then time | the same | the same |
| The Dish's points (§6) | its place's points, plus 1 | the same: its place's, plus 1 | the same | its place's only |
| A board row shows | the time | its percent: "62%" | the same | the same |
| The end screen says | "Solved" | "Out of lives" | "Gave up" | "Out of time" |

- So a failed Nine Lives run is exactly a missed Sniff run: you played, you ended it, it ranks
  after the solvers. *(My call: a loss in the Dish is never worse for streaks than giving up, and
  never better than solving.)*

**Older apps keep their rules.** The 1.2 App Store app and the 1.3 build in review play the first
rules, and must never break.

- **The rules are fixed per run, at its first start.** A start that asks for them gets the new
  rules: `POST /v1/daily/nine-lives/start` with the body `{ "rules": "lives" }`. A start without it
  (every app before this change) gets the first rules, unchanged: no lives, unlimited hints, 30
  seconds a hint, clashes and "Not quite".
- **Why a declaration, not a version number.** Builds from `main` go to TestFlight with the same
  marketing version as the one in App Review (1.3), so a version gate can't tell them apart. An app
  saying what it can play is how the server already tells games apart (`X-Pounce-Games`). The web
  player ships with the server and always asks.
- **An old app is never held to lives it can't show.** *(Ruling, checked by the manager.)* Every
  app calls start before it plays. A start without `{ "rules": "lives" }` on an open lives run (the
  player started on the web or today's app, then opened the same puzzle in 1.2 or 1.3) puts that
  run back on the first rules, for good. The right numbers and hints stay; lives and wrong numbers
  go; hints already used stay free, and later ones cost 30 seconds. Asking for lives again later
  doesn't bring them back, and today's apps play the run on the first rules from then on.
- A run started on an old app and resumed on a new one plays the first rules.
- **A mixed family's board.** Everyone ranks by time. A run on the first rules still carries its
  30 seconds a hint, so free hints can't be had by the dozen; a run on the new rules has at most
  three. Both show the hinted mark. Old apps read a failed run as "Missed", which is true.
- **Nothing else changes for old apps:** the same routes, fields and outcomes. The new state fields
  and reveals are additive, and the old apps' decoders skip them.

#### Box Fort (block placing)

- **Rules.**
  - Pieces come three at a time. Drag each onto the 8 by 8 rug. Pieces don't rotate.
  - A full row or column clears.
  - When all three are placed, the next three come.
  - The run ends when none of the current pieces fits anywhere, or when the day's last set is
    placed.
- **The day's sequence of sets** is fixed by the seed, so everyone gets the same pieces in the same
  order. The rug may start with a few boxes already on it.
- **Score:** points.
  - One point for each square placed.
  - A bonus for each line cleared that grows with the number of lines cleared at once.
  - A combo bonus for clearing on consecutive placements.
  - The exact numbers are ours, tuned by the builder. They are not copied from another game.
  - Placing the day's last set earns a "full fort" bonus.
  - Ties go to the faster time.
- **No "solved" or "missed".** Running out of room is the normal ending. Every run ends with points,
  and the board ranks Box Fort by points alone. The puzzle maker doesn't need to prove that every set
  can be placed. *(My call.)*
- **Fairness:** the server deals each set only after it has accepted the placements of the set
  before.

#### Sniff (five-letter words)

- **Rules.**
  - Guess a five-letter word in six tries.
  - Each letter comes back marked: right spot, in the word but elsewhere, or not in the word.
  - Repeated letters follow the usual rule: a letter is marked only as many times as it appears in
    the answer, right spots first.
- **Marks are shapes as well as colors,** so they never rely on color alone: a filled paw, an
  outlined paw, and plain. The colors come from Pounce's palette, not green, yellow and gray.
- **A guess must be a word on our list of allowed guesses.** An unknown word shakes, isn't counted,
  and isn't sent.
- **Score:** guesses used (1 to 6, or a miss), then time.
- **Our own word lists** (below). The answer list never ships to a client.

#### Cat Nap (the animal puzzle)

- **Rules.**
  - The quilt is N by N, with N colored patches.
  - Put one sleeping cat in every row, every column and every patch.
  - No two cats may touch, not even at a corner.
- **Puzzles** have exactly one solution, reachable by logic. They are graded by a logic solver.
- **Controls.**
  - Tap once for a "no cat here" mark and twice for a cat.
  - Drag to mark many cells.
  - A rule the board breaks is shown: two cats in a row, or cats touching.
  - There's no "this is wrong" check against the solution.
- **Score:** the time. A hint places one cat, from the server, and adds 30 seconds.
- **Give up** ends the run, unsolved.

### 2. One day, and the difficulty week

- **Today** is your own day: 04:00 to 04:00 in your time zone, the same as streaks (JD).
  - The puzzles for date D unlock at 04:00 on D, your time.
  - A cousin in New York gets them three hours before you do in California.
  - Each board is for one date and fills in as each time zone reaches it.
- **A run started on day D belongs to D's board.** It closes when D ends, at 04:00 your time.
  - A run still open then ends unsolved. It shows on the board at its percent (§6, "Ranking"), but it doesn't count
    toward streaks: only a run you finish or give up counts.
  - There's no grace period past 04:00, so a run always ends before its streak day settles (10
    minutes after). Streak settlement doesn't move. *(My call.)*
  - Starting a puzzle in the last 15 minutes of the day shows "The Dish turns over at 4:00".
- **The weekday ramp**, the same for every player because it follows the date:

| | Mon | Tue | Wed | Thu | Fri | Sat | Sun |
|---|---|---|---|---|---|---|---|
| Level | 1 | 2 | 3 | 4 | 5 | 6 | 4, bigger |

- **What a level changes in each game.** The builder tunes the numbers, but keeps this shape:
  - **Nine Lives:** the hardest technique the solver needs, from singles on Monday to chains on
    Saturday.
  - **Box Fort:** a mix of more awkward pieces, more boxes on the rug at the start, and a longer
    run of sets on Sunday.
  - **Sniff:** how common the answer is, and repeated letters later in the week.
  - **Cat Nap:** the quilt grows from 5 by 5 on Monday to 8 by 8 on Saturday and 9 by 9 on Sunday,
    with deeper logic later in the week.
- **Numbering.** Each game's puzzles are numbered from that game's own first day in production:
  "Sniff 12". The share card and the board use the number. *(My call.)*

### 3. Refereeing: what the server does

**Seeds.**
- `seed(game, date) = HMAC-SHA256(dailyKey, "daily.v1|" + game + "|" + date)`.
- `dailyKey` is derived with HKDF from the Worker's existing `TOKEN_SECRET`, using its own label.
  So there's no new secret for JD to set *(my call)*.
- The seed drives xoshiro128** (`rules/rng.ts`) through each game's puzzle maker.

**Puzzles.**
- Each `(game, date)` is made once, then kept by a new `DailyPuzzle` DO, keyed by game and date.
  An alarm makes the next day's puzzles ahead of time.
- No client ever gets a seed, or a puzzle before its day.
- **Sniff:** the answer for date D comes from the answer list by a keyed shuffle of each cycle
  through the list, so no word repeats until the list is used up.
- **Box Fort:** the full sequence of sets is made up front and stays on the server.

**A run.**
- One run per player (the player `resolveMe` picks for `?person=`), per game, per date. Starting again returns the same run, so another device
  can carry on.
- The run lives in a `DailyRun` DO keyed by person, game and date *(builder's call: it could live
  in `Player` instead)*. It holds the moves, the state, the server's start time and the result.
- **Start.**
  - `POST /v1/daily/{game}/start?person=` checks that today has begun for that person, then returns:
    - the run id;
    - the puzzle: the givens, the patches, Box Fort's first set and starting rug, or Sniff's empty
      board;
    - the server's start time;
    - any moves already made, when the run already exists.
- **Moves.**
  - `POST /v1/daily/runs/{id}/moves` carries `{ from: seq, moves: [...] }`.
  - The server checks each move against the rules, in order, and refuses the whole batch at the
    first illegal one.
  - It answers with the authoritative state change: Sniff's marks, Box Fort's next set, a hint's
    cell. When the run has ended, it also answers with the result.
  - Clients send a batch at least every second while moves are waiting, and immediately for Sniff
    guesses and Box Fort's last piece of a set.
  - A Sniff guess or a hint waits for the answer, which takes about one round trip. Every other
    move shows on the client at once.
- **The clock is active time** (JD, 2026-11-26: "we should be more friendly with the daily app
  timers everywhere. just count active time in app looking at the puzzle. not worried about people
  cheating that."). *This replaces the first rule: the server's clock, from start to end, with no
  pause.*
  - A puzzle's clock runs only while the puzzle is on screen and the app is in front. It pauses
    when the app goes to the background, the screen locks, the player leaves for Home or a menu,
    or a sheet covers the puzzle. On the web it also pauses while the tab is hidden. It resumes
    where it left off, on any device.
  - The time shown while playing, on the end screen, on every board (phone, web and TV) and in
    stats is this active time, plus a hint's cost where the game has one (Cat Nap, and Nine Lives
    on its first rules).
  - **The client counts it and the server trusts it.** Every call on a run (moves, hint, give up)
    carries `activeMs`. The server checks only that it's sane: a whole number of milliseconds,
    never less than the run's last one, and never more than the time since the start. Start
    returns the run's `activeMs`, so a resumed run carries on from there.
  - What stays on the server's clock: the move budget against bots (§3, "Plausibility") and
    04:00, when an open run closes at its last active time. The time floors stay, now on active
    time.
  - **Apps that don't report it** (1.3 and before) keep showing their own clock. The server
    estimates their active time from the gaps between their calls, each gap counted up to five
    minutes, so a puzzle left for dinner costs five minutes, not an hour. *(My call: an old app's
    time then stands next to a new app's active time without being penalized for walking away.
    Its end screen shows the estimate, which can read less than its running clock did.)*
  - A run stored before active time keeps the server's clock.
- **The result** is worked out by the server: solved or not, guesses, points, hints, percent, and
  the time from the active time above.
- **Plausibility.**
  - A run faster than a game's floor (for example, Nine Lives under 45 seconds) is kept, but marked
    too fast and left off the board.
  - Only a finished run (solved, or Box Fort's normal ending) can be too fast. *(Ruling,
    2026-11-26, found in the cross-platform check: three wrong numbers in a minute is a quick loss,
    not a bot, and it belongs on the board at its percent.)*
  - Moves spaced closer than a human can make them are refused.
  - The builder sets the floors from playtests. They are written in one table in the code.
- **Limits.**
  - Run starts: 30 per device per hour.
  - Moves: 20 per second per run, and batches of at most 100 moves.
  - Sniff guesses: at most 6, each at least half a second apart.
  - All through the existing `Limiter`.
- **The day and time zones.**
  - A run's date is the person's day at start, in the time zone they most recently reported.
  - A time-zone change takes effect for daily puzzles only from the next 04:00 *(my call)*. So
    hopping zones never opens tomorrow's puzzle early.

**What this stops.**
- Posting a score, a time or "solved": no route takes one.
- A second try: one run per person per day.
- Seeing tomorrow's puzzles: they don't exist on any client until that day starts for that person.
- Knowing the Sniff answer before guessing: it never leaves the server.
- Planning ahead in Box Fort: future sets stay on the server.
- A bot that solves in a second: the floors and move spacing.

**What it can't stop.** These are stated plainly, for JD:
- **Solving the puzzle somewhere else and typing it in.** Someone can copy a Nine Lives or Cat Nap
  grid into a solver, or a Sniff board into a word helper, and enter the answer at human speed. It
  takes only a few minutes.
- **A second account to peek.** A new device is a new guest person. It can open today's puzzles,
  and its owner can then play on their real account knowing the answers. That second person isn't
  on anyone's board unless someone connects with them.
- **Help from the couch,** and watching someone else's puzzle on the TV before playing your own.
- **The list of possible answers.** The repo is public, so the Sniff answer list (about two
  thousand words) is public too. Which word goes with which day stays secret.

The board is only you and the people you play with, so what's left is the same trust a family
already has around a deck of cards.

### 4. Words

- **Allowed guesses:** about ten thousand five-letter words.
  - Built from a permissively licensed or public-domain English word list. The builder names it
    and its license in the repo.
  - Filtered for offensive and adult words.
  - It ships to clients, so a word can be checked without the network.
- **Answers:** about two thousand common five-letter words, picked by us.
  - Each has a tier by how common it is, which sets the weekday ramp.
  - No plurals made just by adding s, no proper nouns, nothing a parent would wince at.
  - The list is curated with a script plus a hand pass, and committed under `apps/play-api` only.
- **Neither list is taken** from Wordle, the New York Times or any other game.

### 5. Streaks

- **Played today** gains a second way in: a person who **ends a daily run** on day D played on D.
  - "Ends" means solved, missed (Sniff's sixth miss), given up, or for Box Fort, out of room or
    the last set placed. A run closed at 04:00 doesn't count (§2).
  - The run needs at least one move.
  - It counts for the streak day that holds the moment it ended, as a table turn does. That's the
    run's date except after a time-zone hop.
- **Your own streak:** a day counts with a turn at a table with another person, *or* an ended daily
  run. Bots alone still don't count.
- **Shared streaks:**
  - An ended daily run counts as that person's turn for the day, in every pair they're part of.
  - A day is kept when both people are in and at least one of them played. Mixing counts too: Mom
    took a turn at a table, and JD played Sniff.
  - **The rule, exactly** *(my call, from JD's "if they both play")*:
    - **A day with at least one table turn** by either person follows today's rules unchanged,
      the late move pass and held days included. A daily run on that day also counts as that
      person's turn. Example: Mom took a turn at their table and JD never held the move; the day
      is kept, as today. JD playing Sniff changes nothing there.
    - **A day whose only plays are daily runs** is kept only when both people ended a daily run.
      The late move pass doesn't apply, because no daily run is ever "waiting on" the other person.
      Example: JD plays Sniff and Mom plays nothing. The day isn't kept, even though Mom never held
      a move.
    - So days with only table play behave exactly as they do for shipped 1.1 and 1.2 apps today.
    - The other case the rule allows: A holds the move at their shared table all day and plays only
      Sniff, and B never held the move. That's a day with no table turn, so B must also play a
      daily puzzle for it to be kept.
    - In the code, `bothIn` gains the second branch, keyed on "this day's `turns` came only from
      daily runs". It doesn't use the existing `gap` flag.
- **Each game has its own streak too,** in its stats only (below). Home keeps the strip it has: your
  own streak and your pairs.
- **The reporting path.** When a run ends, the server reports it like a turn: to the person's own
  streak and to each of their pairs, with the same retry, and never fatal.

### 6. The board

- **Who is on it:** you, plus everyone you have a pair with.
  - On a shared phone, each household person has their own board.
  - The board for date D is the one from your own day.
- **Per game,** each player who played shows:
  - their cat and name, and the result: time, guesses or points;
  - a mark for solved, missed or hinted;
  - nothing at all for someone who hasn't played yet;
  - the order: best first (below, "Ranking");
  - for a run that didn't finish, its percent: "62%".
- **Ranking** (JD, 2026-11-26: "if you fail or quit any puzzle you should get ranked on %
  completed as well. just lower rank than anyone that completed it."). The server works out the
  order and each row's `rank`, and every app shows rows in the server's order, so the 1.2 and 1.3
  apps show this order too, with their own words for the result ("Missed", "Gave up").
  - **Everyone who finished ranks first,** by the game's own measure: the fastest time (Nine
    Lives, Cat Nap), the fewest guesses then time (Sniff), the most points then time (Box Fort).
    Finishing is solving, or for Box Fort, its normal ending: out of room, or the last set placed.
  - **Then everyone who didn't,** together: out of lives, out of guesses, given up, or left open
    when the day turned over at 04:00 (closed). By percent, highest first, then the shorter time.
    The same percent and time share a rank.
  - **Percent, per game** (rounded down, so only a finished run reads 100%):
    | Game | Percent of |
    |---|---|
    | Nine Lives | the open cells the player filled with the right number |
    | Cat Nap | the cats on their right cells, out of the quilt's size |
    | Sniff | the five letters found in their right place, in any guess |
    | Box Fort | the day's sets of pieces placed |
  - **Hints don't count toward percent.** *(Ruling.)* A cell or cat a hint filled doesn't count, so
    a hint never raises a percent; it helps only by getting you to the finish. Wrong numbers and
    wrong cats don't count either.
  - **Sniff counts letters found in any guess,** not the best single guess. *(My call: finding the
    first letter in guess two and the last in guess five is two letters found, and that's how close
    the player came. It shows nothing about the word beyond a number.)*
  - Percent is worked out only at the end. While someone plays, the board's live progress stays
    spoiler-free (cells or cats placed, right or not), so it never tells anyone which are right.
  - A closed run still doesn't count for streaks (§5), and still earns no Dish point for ending.
- **Overall: the Dish.**
  - Per game, 3 points for first, 2 for second and 1 for third among the people on your board,
    plus 1 point for each ended run. Ties share the points.
  - The total ranks the Dish.
  - There's a crown for each game you won.
  - *(My call: it rewards playing all four and winning some, and it reads at a glance on the TV.)*
- **Never shown:** who hasn't played, a "last" label, or anyone outside your pairs.
- **Live:**
  - Boards update the moment a run ends.
  - People playing right now show a small "playing" mark and their progress. Progress gives
    nothing away:
    - Nine Lives and Cat Nap: cells or cats placed;
    - Box Fort: points so far;
    - Sniff: how many guesses are used. No letters.
- **Where results live.**
  - When a run ends, the result goes to the person's own `Player`, and from there to each
    connection's `Player`. So reading a board is one call to your own `Player`.
  - Live updates reach a board's open sockets from there.
  - Results are kept 120 days, like pair days, plus the lifetime stats.
  - *(The builder may choose a different store, with the same reads.)*

### 7. The app

**Home.** The Daily Dish gets a place on Home, and Home is redesigned around it, not added to:
- the streak strip;
- the Dish: four treats, each showing done or not, and your result once done;
- your tables.

The Home builder rebalances the whole screen and shows before and after on every size.

**The Daily Dish screen.**
- The four puzzles as big cards: today's number, your result, and the best on your board.
- The board: overall, then a tab per game.
- A "Show board on TV" button (§8).
- Stats.

**A puzzle screen.**
- Full screen, with the puzzle, the time (the server's start time, counted locally) and the
  controls.
- A "Show on TV" switch, present only while a TV is showing a board you're on (§8).
- When it ends:
  - the result;
  - where you landed on today's board;
  - share;
  - stats;
  - "Next puzzle", for one you haven't played.

**Stats, per game:**
- played, solve rate, current and best streak for that game;
- best time or score;
- a small chart of results (Sniff: guesses 1 to 6; the others: times or points over 30 days);
- the last 30 days as a strip.

**Share.**
- A card image: the game's art, the number, the result, and a grid of marks that gives nothing
  away. Sniff's marks carry no letters. Nine Lives and Cat Nap show only time and hints.
- Plus the text "Sniff 12: 4 of 6" and a link to `play.conleychaos.com/daily`, which offers the app
  and the browser. No emoji.
- Kittens get no share, as today: no links out from an under-13's device.

**Teaching.**
- The first visit to the Dish gets one tip.
- Each puzzle's first run has short coach marks through the tip system (`CoachMark.swift`).
- Each puzzle gets a How to play page. No paragraphs on the puzzle screens.

**Frame rate.**
- Puzzle screens run at 120 Hz where the screen can. Box Fort's drag is the one to watch.
- Rule checks run off the main actor, and so does anything over 1 ms on an iPhone SE: Box Fort's
  "does any piece fit", Cat Nap's mark drags over a 9 by 9 board.
- Network calls and the result card's image render are off the main thread too.

### 8. The TV

**Linking a board.**
- The TV's home (Apple TV and browser) gets a third poster, "Tonight's board", beside the two games.
  It shows the link QR, the same flow as linking a table.
- On a phone, "Show board on TV" scans it, or takes the backup code.
- `POST /v1/screens/link` gains `{ board: true, person }` as an alternative to a room code.
- The TV then shows that person's board.
- **The TV remembers it for 30 days,** so every evening it opens straight to the board *(my
  call)*.
  - It keeps a board token: random, revocable, and naming no one.
  - "Unlink" sits in the TV's menu and beside "Show board on TV" on the phone.
  - A screen still holds no seat and no person.

**What the TV shows.**
- The Dish and each game's board, large and readable from about 3 meters.
- People playing right now, with their progress.
- A small celebration when someone's run ends: their cat leaps, the row slides into place, and a
  sound plays.
- No text entry, as everywhere on the TV.

**Watching a puzzle (JD: the player chooses).**
- The player turns "Show on TV" on from the puzzle screen.
- Every TV showing a board they're on gets a card: "Mom is playing Sniff. Spoilers." with Watch and
  Not now. Not now is the default focus, and the card goes away after 20 seconds.
- **Watch** shows the run live, as the server sees it: Sniff's guesses with letters, the Nine Lives
  grid, Box Fort's rug and current set, the Cat Nap quilt.
  - It comes from the server's own state, so it adds nothing a client could fake.
  - Notes stay on the phone.
- When the run ends, the TV shows the result, then goes back to the board.
- A grandparent's TV across the country gets the same card, and can watch too.
- **Nothing private beyond that choice.** A TV never gets a puzzle unless a player turned on Show on
  TV and someone pressed Watch.

**On Apple TV,** the board and the watch views are SwiftUI and SpriteKit. They share drawing code
with the iPhone's puzzle views, as the tables do.

### 9. Notifications

- **No new push kinds.**
- The daily reminder's rule gains a case. It can fire when you aren't in today and either it's
  your move, or today's Dish isn't played. In the second case the copy is about the Dish:
  "Today's Dish is out. Sniff 12 is waiting."
- The existing caps, quiet hours, backoff and age rules are unchanged:
  - kittens get no server pushes;
  - teens get reminders off by default and nothing from 00:00 to 06:00.
- Backoff now counts days with no turn and no daily run.

### 10. Privacy and kids

- **New data:** daily runs (moves, times, results) and per-game stats. That's Gameplay Content,
  which is already declared. The App Store privacy answers don't change *(builder confirms in
  `docs/privacy/app-store-label.md` and the manifest)*.
- **Who sees what:** results go only to your pairs, and to a TV linked to your board. Say so in the
  privacy policy (`apps/play-api/src/http/privacy.ts`) and the retention policy (120 days for runs).
- **Kittens** play, appear on their pairs' boards under their generated name, and get stats. As
  today:
  - no share links;
  - no server pushes.
- **The parents' notice** gets one line, if it lists what connections see.

### 11. Protocol and compatibility

- **All new routes,** under `/v1/daily/...`, plus additive fields:
  - `board` on screen links;
  - new socket message kinds for the board and watching, which old clients skip.
- **`PROTOCOL_VERSION` stays 1.** Shipped 1.1 and 1.2 apps never call these routes and see no
  change, except that their pair streaks now also count a partner's daily runs. The `StreakView`
  shape is unchanged.
- **A `DAILY` server flag,** as `TV` and `TROPHY` work.
  - Off: every daily route is a 404, and streaks ignore daily runs.
  - **All four at once (JD).** The flag stays off in production until all four games, the Dish
    in the app and on the web, and the TV board have merged and passed the cross-platform check.
    Then one change turns it on: the web player and the TestFlight build show the Dish the same
    day.
  - Until then, every piece is built and tested against local dev servers with `DAILY` on, and
    the simulators. Apps and the web player hide the Dish while the server says it's off.
  - A day-one puzzle number starts at 1 for every game on launch day.
- **The board socket.**
  - Phones and TVs connect to `/v1/daily/board/ws` (phones with `?person=`, TVs with their board
    token).
  - Messages: `board` (a snapshot), `result`, `progress`, `watch` (offer and frames) and
    `watchEnd`.
  - The builder fixes the exact shapes in `docs/daily-protocol.md`, in the style of
    `docs/tv-protocol.md`.

### 12. One set of rules, in two languages

- **TS:** each game's rules live in `apps/play-api/src/daily/<game>/`: the rules, the puzzle maker
  and a solver or grader. The server and the web player use them. The web player already imports
  the server's rules.
- **Swift:** each game's rules live in `PounceKit/Daily/<Game>/`. That's the rules only, no puzzle
  maker. The app and the TV use them.
- **Golden vectors:**
  - TS writes `apps/play-api/fixtures/daily/<game>/*.json`: a puzzle, a list of moves, and after
    each move the expected state, legality and score.
  - Swift tests read the same files by path, as `Fixtures.swift` already does.
  - The vectors cover every rule edge: Box Fort's clears and combos and "nothing fits", Sniff's
    repeated letters, Nine Lives and Cat Nap clashes, touching and finishing.
  - A change to a rule changes the vectors, and both sides fail until both match.
- **Sniff's marks are worked out only on the server,** so they need no Swift copy. Its vectors still
  pin the marking rule for the server tests.

## Testing and the cross-platform bar

These must hold before each piece merges:

- **Server.**
  - Every forged request is refused:
    - a result posted to any route;
    - moves for someone else's run;
    - an illegal move;
    - a move before start or after the end;
    - a second run;
    - a run for tomorrow, including after a time-zone hop;
    - moves faster than the spacing;
    - a seventh Sniff guess;
    - a Box Fort set asked for early.
  - Puzzle makers are deterministic for a seed. Every generated Nine Lives and Cat Nap puzzle has
    exactly one solution (a property test over a year of dates). The weekday grades hold.
  - Streak tests across time zones and DST:
    - daily runs keep own and pair days;
    - mixing a table turn with a daily run;
    - a day with only daily runs needs both people to have played; one person's run alone doesn't
      keep it;
    - days with only table play give exactly today's results (run the existing streak tests
      unchanged);
    - a run closed at 04:00 never counts, and a run that ends after a time-zone hop credits the
      right day.
  - The board's fan-out and live messages, the board link for a TV, and watching.
- **Parity:** every golden vector passes in TS and in Swift.
- **Clients.**
  - Each puzzle played to the end on iPhone (UI test) and in the browser (Playwright).
  - Main-thread hang and frame-budget gates on each puzzle screen, Box Fort's drag included.
- **Mixed, at the end:**
  - The same date on iPhone, browser, Apple TV (simulator) and the browser TV shows the same puzzle
    for each game.
  - A run played on the iPhone and the same moves on the web give the same score.
  - A forged result is refused, and the board is unchanged.
  - The TV's board updates live while a phone plays, and Watch shows the run.
- **Screens:** every changed screen gets before and after shots on iPhone SE, a large iPhone, iPad
  in both orientations and the largest text size, plus the TV at 1080p.

## Order of work

Each piece is its own sub-session and its own PR, with tests, screenshots and frame-rate results.
No two run at once on the same files.

1. **Server core.**
   - The `DAILY` flag, seeds, `DailyPuzzle`, `DailyRun`, start and moves.
   - The game-module interface, with a test-only game.
   - Results, the board and its socket, and the board link for TVs.
   - The streak changes, including the gap-day rule, and the reminder case.
   - `docs/daily-protocol.md`.
2. **Then, side by side,** once 1 has merged:
   - **Each game, one session per game:** its TS rules, puzzle maker and grader, its server module,
     its golden vectors, its Swift rules, its iPhone and iPad screen, and its web screen. Each
     touches its own folders, plus one line in each game list.
   - **The Dish in the app:** the Home redesign, the Dish screen, the board, stats, share and tips.
     It launches whichever games are in the list.
   - **The Dish on the web:** the same, in `apps/play-web`.
3. **The TV,** once the Dish and at least one game have merged: the board poster and link, the live
   board, and watching, on Apple TV and the browser TV page. Each game's watch view is added as
   that game lands.
4. **Launch (all four at once, JD):** the cross-platform check, then one PR that turns `DAILY` on
   in production, plus the release updates. That's a release under `AGENTS.md`, because the web
   player shows it. What's New, the README, and the websites say it's in the browser now, and
   "coming" to the app until the App Store
   version is live (`AGENTS.md`).

## Left to the builder

- The visual design of every new screen, within the UI rules: redesign whole screens, terse copy,
  fit every size, teach with tips, no emoji, the loud and cartoony art style.
- The exact scoring numbers for Box Fort, the time floors, and how the weekday levels map to
  puzzle-maker settings.
- Whether runs live in their own DO or in `Player`, and how board fan-out is stored.
- The exact wire shapes, in `docs/daily-protocol.md`.
- Whether puzzle screens are SpriteKit or SwiftUI on iOS, as long as they hold the frame budget.
- Which permissive word source to start from, named with its license.
