# The Daily Dish: the wire contract

What the server speaks for daily puzzles, the family board, and a board on the TV. Design:
[specs/2026-11-20-daily-games-design.md](superpowers/specs/2026-11-20-daily-games-design.md).
All of it is additive. `PROTOCOL_VERSION` stays 1, and an app that knows none of it sees no
change, except that its pair streaks also count a partner's daily runs.

Samples of every answer and message are in `apps/play-api/fixtures/daily/protocol/`
(`http.json`, `socket.json`, `client.json`). They are made by the server's own code, pinned by
hash, and checked against the real Worker's answers. Decode them in your tests.

Everything here requires the server flag `DAILY` (`"on"` in `wrangler.jsonc` since all four
games launched together on Sunday 2026-11-22). With it off:
- every `/v1/daily` route is a 404;
- `POST /v1/screens/link` with `"board"` is a 400 `{ "error": "bad_request" }`;
- streaks ignore daily runs, the reminder never mentions the Dish, and the privacy page says
  nothing of it.

To learn whether the Dish is on, read `GET /v1/daily/board`: a 404 means hide it. Never probe
with `start`, which opens a run and starts its clock.

**Say that the app has the Dish.** An app (or web player) that shows the Dish adds `dish` to its
`X-Pounce-Games` header on every request, beside the table games it can draw:
`X-Pounce-Games: tiles,dish` (browsers: `games=tiles,dish` in a socket's query). The server learns
it on the calls that already tell it the games (`GET /v1/devices/me/tables` and table sockets), and
only such a device is sent the Dish's reminder. An app that doesn't list it keeps its reminders
exactly as before.

## Who and when

- **Identity.** Every route takes the device token as usual and `?person=<person id>`, as the
  `/v1/me` routes do. Without `?person=` it acts for the device's signed-in account.
  - 400 `{ "error": "bad_request" }`: `person` isn't a person id.
  - 403 `{ "error": "not_allowed" }`: the device doesn't speak for that person.
  - 404 `{ "error": "no_player" }`: no person and no account.
- **The day** is the person's own: 04:00 to 04:00 in their time zone. A zone change takes effect
  for daily puzzles only from the next 04:00 of the zone that rules today, so a hop never opens
  tomorrow early and never goes back to yesterday. A person with no zone uses
  `America/Los_Angeles`.
- **The clock is the server's.** `startedAt`, `now` and `closesAt` are epoch milliseconds. Count
  the timer locally from `startedAt`, corrected by `now - Date.now()` at start. There is no pause.
- **Numbers and levels.** `number` counts from launch day (`LAUNCH`, 2026-11-22, 1 on that day;
  the samples' date, 2026-11-23, is 2). A date before launch gets 0 or less, which clients don't show. `level` is the weekday: Monday 1 to Saturday 6,
  Sunday 7 (level 4, bigger).
- **Games.** `"nine-lives"`, `"box-fort"`, `"sniff"`, `"cat-nap"`. A game the server doesn't list
  is a 404. The server's own test game, `"test"` ("count to 3 + level": a move is
  `{ "k": "step", "n": <the next number> }`, a hint takes one step), exists only on test servers
  with `DAILY_TEST=on`. The hosts are built against it.

## A run

One run per person, game and date. Starting again returns the same run, so another device can
carry on. A run ends solved, missed (Sniff), given up, done (Box Fort), or closed at 04:00.

### `POST /v1/daily/{game}/start`

No body, or `{ "rules": "<rules>" }` for a game with more than one set of rules (Nine Lives'
`"lives"`, below). The rules are fixed at the run's first start; a later start's body is ignored,
and so is anything else in it. 200:

```json
{
  "run": "<43 base64url chars>",
  "game": "sniff",
  "date": "2026-11-23",
  "number": 12,
  "level": 1,
  "startedAt": 1795464000000,
  "now": 1795464000000,
  "puzzle": { },
  "state": { },
  "seq": 0,
  "hints": 0,
  "result": null,
  "closesAt": 1795521600000,
  "hintMs": 30000
}
```

- `puzzle` is the game's public puzzle (`publicPuzzle`): never a solution, an answer or a future
  set. `state` is the game's public state (`publicState`): what a resuming client draws. Each
  game's doc gives their shapes.
- `seq` counts the moves the server has accepted. `hints` counts hints used. `result` is set once
  the run has ended (below); then show the end screen.
- `hintMs` is what one hint adds to the run's time: 30 seconds, or 0 under Nine Lives' `"lives"`
  rules. A server before this field always added 30 seconds.
- `activeMs` is the run's active time so far (below, "Active time"). Count on from it while the
  puzzle is on screen. A server before this field had none: count from `startedAt`.
- `run` is unguessable and names no one. Keep it for the calls below.
- 404 `{ "error": "not_found" }`: an unknown or unlisted game. 429 `{ "error": "rate_limited" }`:
  over 30 starts by this device in an hour.

### `POST /v1/daily/runs/{run}/moves`

```json
{ "from": 0, "moves": [ { "k": "step", "n": 1 }, { "k": "step", "n": 2 } ], "activeMs": 18250 }
```

- `from` is the `seq` the batch starts at. `moves` are the game's moves, in order. Nothing else in
  the body is read: a posted result, time or outcome is ignored.
- Send a batch at least every second while moves are waiting, and at once for a Sniff guess or Box
  Fort's last piece of a set. At most 100 moves per batch, and a body of at most 8 KB (else a 400).
- The batch is all or nothing: the first move refused refuses it, and nothing changes.
- A move that ends the run (the solving move, Sniff's sixth guess, Nine Lives' third wrong number)
  ends the batch too: the moves before it and it are taken, any after it are dropped, and `seq`
  counts only the ones taken.

200, accepted:

```json
{ "ok": true, "seq": 2, "reveals": [], "progress": 0.5, "result": null }
```

- `reveals` holds what the server worked out for the moves, in order, for the moves that reveal
  something (Sniff's marks, Box Fort's next set). Moves that reveal nothing add nothing.
- `progress` is 0 to 1, spoiler-free.
- `result` is set when the batch ended the run:

```json
{ "game": "sniff", "date": "2026-11-23", "number": 12, "outcome": "solved", "timeMs": 125000, "hints": 1, "progress": 1, "tooFast": false, "guesses": 4 }
```

  - `outcome`: `"solved"`, `"missed"`, `"gaveUp"`, `"closed"` or `"done"` (Box Fort's ending).
  - `timeMs`: the run's active time when it ended, plus `hintMs` a hint.
  - `progress` (0 to 1) and `percent` (a whole number, rounded down): how far it got by the game's
    fair measure, 1 and 100 once finished. Show `percent` for a run that didn't finish ("62%"). A
    result stored before 2026-11-26 has no `percent`: use `floor(progress * 100)`.
  - `guesses` (Sniff) and `points` (Box Fort) appear only for those games.
  - `tooFast`: faster than the game's floor. Kept, but left off every board.

200, refused:

```json
{ "ok": false, "error": "illegal", "at": 0, "seq": 2 }
```

| `error` | Meaning | What to do |
|---|---|---|
| `illegal` | Move `at` breaks the rules | Undo from that move; resend the rest from `seq` |
| `too_soon` | Move `at` is past the game's move budget (Limits) | Wait, then resend from `seq` |
| `bad_message` | Move `at` isn't one of the game's moves, or the batch is over 100 or not a list (`at` 0) | A client bug |
| `stale` | `from` isn't `seq`, and this isn't a batch the server remembers | Start again to resync |
| `over` | The run has ended, or closed at 04:00 (`at` 0, or the first move past the end) | Start again to see the result |

- **A resend is safe.** The same batch sent again from the same `from` (a dropped connection)
  gets the answer it got the first time, and changes nothing. The server remembers the last 8. A
  different batch from an old `from` (another device that fell behind) answers `stale`.
- 404 `{ "error": "not_found" }`: no such run, or someone else's (they look the same). 429
  `{ "error": "rate_limited" }`: over 20 calls a second on this run (moves, hints and give-ups).

### `POST /v1/daily/runs/{run}/hint`

`{ "hints": <hints used so far>, "activeMs": <active time> }` (an empty body is accepted, but isn't safe to resend). 200, an
answer as above: `reveals` holds the hint (a cell, a cat), `seq` is unchanged (a hint isn't a move),
`hints` goes up and the result's time grows by `hintMs`. A game with no hints, or none left,
answers `illegal`.
Flush waiting moves first.

- **A resent hint is safe** when it carries `hints`: asked again with the same count, it gets the
  same answer and costs nothing more. A count the run never had answers `stale`; 400 for a body
  that isn't `{ "hints": <whole number> }`.

### `POST /v1/daily/runs/{run}/giveup`

`{ "activeMs": <active time> }`, or no body (before active time). 200, an answer with the result,
`outcome: "gaveUp"`. A run given up before any move doesn't count toward streaks.

### `PUT /v1/daily/runs/{run}/tv`

`{ "on": true }` or `{ "on": false }`: Show on TV. 204. Turned on while the run is open, every TV
showing a board this person is on is offered the run (`watchOffer`), then gets its frames
(`watch`). Turned off, those TVs get `watchEnd` with no result. 400 for any other body; 404 for
someone else's run.

## The board

### `GET /v1/daily/board?date=`

200:

```json
{
  "date": "2026-11-23",
  "games": [
    {
      "game": "sniff",
      "number": 12,
      "rows": [
        { "player": "me", "name": "Mom", "cat": 3, "rank": 1, "result": { }, "playing": null },
        { "player": "pr_…", "name": "Kid", "cat": 5, "rank": 2, "result": { }, "playing": null },
        { "player": "pr_…", "name": "Grandpa", "cat": 1, "rank": null, "result": null, "playing": { "progress": 0.5 } }
      ]
    }
  ],
  "dish": {
    "rows": [
      { "player": "me", "name": "Mom", "cat": 3, "rank": 1, "points": 4, "crowns": ["sniff"], "ended": 1 }
    ]
  },
  "tvs": 1
}
```

- `date` defaults to the person's day. Any date from 120 days ago to today; anything else is a 400.
- **Who is on it:** the person and everyone they have a streak with (a pair), read now, so someone
  who leaves the pair drops off. Nobody who hasn't played appears.
- **`player`** is `"me"` for the board's owner and the pair id for a connection (the `pair` of
  `GET /v1/me/streaks`). No player id is ever sent.
- **Per game,** rows with a result come first, best first: every finished run (solved, or Box
  Fort's `done`) by the game's own order (time; Sniff guesses then time; Box Fort points then
  time), then every other run (`missed`, `gaveUp`, `closed`) by `percent`, highest first, then
  time (spec §6, "Ranking"). Show rows in the order sent; never sort them. `rank` is a competition
  rank: ties share it and the next skips. People playing now follow with
  `rank: null` and their progress. Results marked `tooFast` are left off.
- **The Dish:** per game 3, 2 and 1 points for the first three places (ties share a place's
  points), plus 1 for each ended run (a run closed at 04:00 didn't end). `crowns` lists the games
  won. Sorted by points; equal points share a rank. Only rows with at least 1 point are listed,
  so someone whose only run closed at 04:00 below third place isn't on the Dish.
- Games are listed in the Dish's order: Sniff, Nine Lives, Cat Nap, Box Fort.
- **`tvs`** counts the TV board sockets open now that show a board this person is on: their own
  TVs and their connections' (a watch offer reaches all of them). Show the "Show on TV" switch
  only while it is above 0.

### `GET /v1/daily/stats`

200 `{ "games": { "<game>": Stats } }`, for each listed game:

```json
{ "played": 1, "solved": 1, "streak": 1, "best": 1, "bestTimeMs": 125000, "bestPoints": null, "guesses": [0, 0, 0, 1, 0, 0], "last30": [ { "date": "2026-11-23", "result": { } } ], "lastEnded": "2026-11-23" }
```

- `streak` counts consecutive days with an ended run in that game; 0 once a day is missed.
- `guesses[i]` counts Sniff solves in `i + 1` guesses. `last30` lists the days with a result in
  the last 30, oldest first; draw the gaps as empty.

## The board socket

### `GET /v1/daily/board/ws`

- **Phones:** `?person=<person id>` with the device token. Browsers use the subprotocols `pounce`
  and `pounce.token.<device token>` and keep `person` in the query.
- **TVs:** `?board=<board token>` with the TV's own device token (the token works only from the
  TV it was given to). Browsers as above, with `board` in the query.
- 426 without an upgrade. 404 for a board token that is unknown, expired, revoked or another
  device's; the TV forgets it and shows its link poster.

Server to client:

| Message | When | To |
|---|---|---|
| `{ "t": "board", "board": <as GET /v1/daily/board> }` | On connect, and after every result | all |
| `{ "t": "result", "player", "result" }` | A run on this board ended | all |
| `{ "t": "progress", "player", "game", "progress" }` | Someone on the board moved (at most once a second per game) | all |
| `{ "t": "watchOffer", "player", "name", "cat", "game" }` | Someone turned on Show on TV | TVs |
| `{ "t": "watch", "player", "game", "puzzle", "state" }` | A frame: the run's public puzzle (as start gives it) and public state, first right after the offer, then one per accepted batch, the batch (or hint or give up) that ends the run included | TVs |
| `{ "t": "watchEnd", "player", "game", "result" }` | The watched run ended (`result` null: Show on TV was turned off) | TVs |
| `{ "t": "tvs", "count" }` | The number of TVs showing a board this person is on changed (as `tvs` in the snapshot) | phones |
| `{ "t": "pong" }` | Answer to a ping | all |
| `{ "t": "error", "error": "not_allowed" }` | The client sent anything but a ping | all |

- `progress` never carries state or letters. Only a TV ever gets `watch`, and only after the
  player turned on Show on TV. Every frame carries the whole public puzzle (Nine Lives' givens,
  Cat Nap's quilt), exactly what `start` shows the player and nothing more, so a TV can draw from
  any one frame. A TV keeps the frames it hears after an offer, so pressing Watch
  shows the latest at once.
- A watched run that ends by a call (solved, done, out of guesses, gave up) sends one last `watch`
  with the final state, then `watchEnd`, so the picture under the result is the finished puzzle. A
  run closed at 04:00 sends only `watchEnd`: nothing moved since the last frame.
- The board snapshot's date is the board owner's day. A `result` can be for yesterday (a run
  closed at 04:00); check its `date`.
- `tvs` is sent only when the count changes because a TV came or went. A pair formed or left
  changes it without a message; the next snapshot has it.
- A client sends only `{ "t": "ping" }`. Skip message kinds you don't know.
- A TV's socket closes (1000, `"revoked"` or `"expired"`) when its board is unlinked or its token
  expires.

## A board on the TV

The TV shows a link QR and backup code exactly as for a table (`POST /v1/screens`, then
`GET /v1/screens/{token}/ws`; docs/tv-protocol.md).

### `POST /v1/screens/link?person=` (the phone's device token)

```json
{ "token": "<22 base64url chars>", "board": true }
{ "code": "BCDFGH", "board": true }
```

- Exactly one of `token` or `code` (any case), and `"board": true`, in place of `room`.
- 200 `{ "linked": true }`. The TV's waiting socket hears `{ "t": "board", "token": "<board
  token>" }`; a TV that connects later hears it at once. The TV keeps the token for 30 days and
  opens `GET /v1/daily/board/ws?board=` every evening.
- A board can replace whatever the TV shows. 404 for no live link (or a spent one); a wrong code
  backs off with 429 `{ "error": "too_many_attempts", "retryAfter" }` as for a table; 403 and 404
  for the person as above.

### `DELETE /v1/daily/board/tv?person=`

Unlink: every TV showing this person's board forgets it, and their sockets close. 204.

## Limits

| What | Limit | Answer |
|---|---|---|
| Starts | 30 per device per hour | 429 `rate_limited` |
| Calls on one run | 20 per second | 429 `rate_limited` |
| Moves per batch | 100 | `bad_message` |
| Move body | 8 KB | 400 |
| Moves over time | For a game with a spacing (`minMoveGapMs` > 0): `seq + n <= floor((now - startedAt) / minMoveGapMs) + 10` for a batch of `n`, so one move per spacing since the start plus a burst of 10 (`MOVE_BURST`) for batching and jitter. Hints don't count | `too_soon`, `at` the first move past the budget, `seq` unchanged |
| Faster than a game's floor | Kept, `tooFast: true`, off every board | |

## Streaks and reminders

- A run that ended (not closed) with at least one move counts as playing that day: for your own
  streak, and as your turn in every pair (spec §5). A day whose only plays are daily runs is kept
  only when both people ended one. `StreakView` is unchanged.
- The daily reminder can also fire when no move is waiting but today's Dish is open: "Today's
  Dish is out. Sniff 12 is waiting." It is kind `reminder`, thread `dish`, with no `code` and
  `data: { "dish": "<game>" }`; open the Dish. It goes only to devices whose app lists `dish` in
  `X-Pounce-Games`, and a player with none of those is never sent it.

## Signing in

- **An upgrade** (a guest's first sign-in) keeps everything in place: the run, results and stats.
- **A merge** (a guest signs in to an account that already exists) brings the guest's Dish to the
  account: results, stats, connections' results and TV board tokens (the TV now shows the
  account's board; its socket closes once and reconnects).
- **One run per game and date.** When both had started today's puzzle, the run started first
  stays, with its moves and result; the other run and its result go (its id answers 404), and its
  stats come off. `start` on any of the account's devices then returns the run that stayed.

## Active time

Spec §3, "The clock" (JD, 2026-11-26).

- Count the time the puzzle is on screen with the app in front: pause in the background, on a
  locked screen, on Home or a menu, under a sheet, and (web) in a hidden tab. Show that time, plus
  `hintMs` a hint, as the run's clock.
- Send it as `activeMs` with every moves batch, hint and give-up: the total so far, in whole
  milliseconds, carrying on from start's `activeMs`.
- The server trusts it, and keeps it sane: a value that isn't a whole number of 0 or more is
  ignored, one below the run's last is ignored, and one past the time since the start is cut to
  it. The result's `timeMs` is the active time at the end.
- An app that sends none (1.3 and before) gets an estimate: each gap between its calls on the
  run, counted up to 5 minutes (`IDLE_CAP_MS`).
- A run open at 04:00 closes at its active time then.

## Nine Lives

- **Puzzle:** `{ "givens": [81 digits, 0 for an open cell] }`, cells in reading order.
- **Moves:** `{ "k": "set", "i": 0..80, "d": 1..9 }` and `{ "k": "clear", "i": 0..80 }`. A given or a
  hinted cell is `illegal`.
- **Hint reveal:** `{ "i": <cell>, "d": <digit> }`. That cell is locked from then on.

### The first rules (no `rules` at start: every app before 2026-11-26)

- **State:** `{ "cells": [81], "hinted": [cells a hint filled, ascending] }`.
- Any digit may go in any open cell, and be changed or cleared. The run ends solved when every cell
  holds its answer. Unlimited hints, 30 seconds each (`hintMs` 30000).

### The `"lives"` rules (`{ "rules": "lives" }` at start)

Send `{ "rules": "lives" }` on EVERY Nine Lives start, a resume too. A start without it on an open
lives run is an app that can't show lives: the run goes back to the first rules for good (hints
used so far stay free), and its state then has no `rules`. Draw from the state start returns.

Spec: [Nine Lives: lives and hints](superpowers/specs/2026-11-20-daily-games-design.md#nine-lives-lives-and-hints).

- **State:**

```json
{ "cells": [81], "hinted": [], "rules": "lives", "lives": 3, "hintsLeft": 3, "wrong": [ { "i": 4, "d": 7 } ] }
```

  - `lives` (3 to 0) and `hintsLeft` (3 to 0) are what is left. `wrong` is every wrong number
    entered, in order: at most three. `cells` never holds a wrong number.
  - `"solution": [81]` is added once the run ended out of lives, and only then.
- **A set** goes only in an open cell: not a given, not hinted, not already holding its answer
  (`illegal`). Its answer's digit stays and locks; a wrong one costs a life and changes no cell.
- **`clear` is `illegal`.** The server holds no wrong numbers to clear; erasing one shown on the
  phone is the phone's.
- **Reveals,** in a moves answer, one per wrong set: `{ "k": "wrong", "i", "d", "lives": <left> }`.
  The set that leaves 0 ends the run `missed`, and its reveal also carries `"solution": [81]`. A
  right set reveals nothing.
- **Hints:** three, `hintMs` 0, never a life. A fourth answers `illegal`.
- **Watch frames** carry this state, so a TV shows lives, hints left and the wrong numbers.

## For game builders

A game is a `DailyModule` (`apps/play-api/src/daily/module.ts`): its puzzle maker
(`make(rng, level, { date, key })`, where `rng` is seeded for that game and date and `key` is the
game's cycle key, the same every day, for what runs across days, like Sniff's answer pools), public puzzle
and state, move parser, rules (`apply`), hint, progress, result and ranking, time floors and move
spacing. Add one line to `src/daily/games.ts` (and its title to `DAILY_TITLES`). The referee
(`src/daily/run-core.ts`) does the rest: the clock, batches, resends, hints, closing at 04:00 and
the result. `publicPuzzle` and `publicState` are everything a client ever sees.
