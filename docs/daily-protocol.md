# The Daily Dish: the wire contract

What the server speaks for daily puzzles, the family board, and a board on the TV. Design:
[specs/2026-11-20-daily-games-design.md](superpowers/specs/2026-11-20-daily-games-design.md).
All of it is additive. `PROTOCOL_VERSION` stays 1, and an app that knows none of it sees no
change, except that its pair streaks also count a partner's daily runs.

Samples of every answer and message are in `apps/play-api/fixtures/daily/protocol/`
(`http.json`, `socket.json`, `client.json`). They are made by the server's own code, pinned by
hash, and checked against the real Worker's answers. Decode them in your tests.

Everything here requires the server flag `DAILY` (`"off"` in `wrangler.jsonc` until all four
games launch together). With it off:
- every `/v1/daily` route is a 404;
- `POST /v1/screens/link` with `"board"` is a 400 `{ "error": "bad_request" }`;
- streaks ignore daily runs, the reminder never mentions the Dish, and the privacy page says
  nothing of it.

Clients ask nothing to learn whether the Dish is on: a 404 from `POST /v1/daily/{game}/start` or
`GET /v1/daily/board` means hide it.

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
- **Numbers and levels.** `number` counts from launch day (`LAUNCH`, 1 on that day, so it is
  negative before launch, as in the samples). `level` is the weekday: Monday 1 to Saturday 6,
  Sunday 7 (level 4, bigger).
- **Games.** `"nine-lives"`, `"box-fort"`, `"sniff"`, `"cat-nap"`. A game the server doesn't list
  is a 404. The server's own test game, `"test"` ("count to 3 + level": a move is
  `{ "k": "step", "n": <the next number> }`, a hint takes one step), exists only on test servers
  with `DAILY_TEST=on`. The hosts are built against it.

## A run

One run per person, game and date. Starting again returns the same run, so another device can
carry on. A run ends solved, missed (Sniff), given up, done (Box Fort), or closed at 04:00.

### `POST /v1/daily/{game}/start`

No body. 200:

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
  "closesAt": 1795521600000
}
```

- `puzzle` is the game's public puzzle (`publicPuzzle`): never a solution, an answer or a future
  set. `state` is the game's public state (`publicState`): what a resuming client draws. Each
  game's doc gives their shapes.
- `seq` counts the moves the server has accepted. `hints` counts hints used. `result` is set once
  the run has ended (below); then show the end screen.
- `run` is unguessable and names no one. Keep it for the calls below.
- 404 `{ "error": "not_found" }`: an unknown or unlisted game. 429 `{ "error": "rate_limited" }`:
  over 30 starts by this device in an hour.

### `POST /v1/daily/runs/{run}/moves`

```json
{ "from": 0, "moves": [ { "k": "step", "n": 1 }, { "k": "step", "n": 2 } ] }
```

- `from` is the `seq` the batch starts at. `moves` are the game's moves, in order. Nothing else in
  the body is read: a posted result, time or outcome is ignored.
- Send a batch at least every second while moves are waiting, and at once for a Sniff guess or Box
  Fort's last piece of a set. At most 100 moves per batch, and a body of at most 8 KB (else a 400).
- The batch is all or nothing: the first move refused refuses it, and nothing changes.

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
  - `timeMs`: from start to the move that ended it, plus 30 seconds a hint.
  - `guesses` (Sniff) and `points` (Box Fort) appear only for those games.
  - `tooFast`: faster than the game's floor. Kept, but left off every board.

200, refused:

```json
{ "ok": false, "error": "illegal", "at": 0, "seq": 2 }
```

| `error` | Meaning | What to do |
|---|---|---|
| `illegal` | Move `at` breaks the rules | Undo from that move; resend the rest from `seq` |
| `too_soon` | Move `at` came closer to the last than the game allows | Wait, then resend from `seq` |
| `bad_message` | Move `at` isn't one of the game's moves, or the batch is over 100 or not a list (`at` 0) | A client bug |
| `stale` | `from` isn't `seq` and isn't a batch the server remembers | Start again to resync |
| `over` | The run has ended, or closed at 04:00 (`at` 0, or the first move past the end) | Start again to see the result |

- **A resend is safe.** A batch sent again from the same `from` (a dropped connection) gets the
  same answer it got the first time, once, and changes nothing. The server remembers the last 8.
- 404 `{ "error": "not_found" }`: no such run, or someone else's (they look the same). 429
  `{ "error": "rate_limited" }`: over 20 calls a second on this run (moves, hints and give-ups).

### `POST /v1/daily/runs/{run}/hint`

No body. 200, an answer as above: `reveals` holds the hint (a cell, a cat), `seq` is unchanged (a
hint isn't a move), `hints` goes up and the result's time grows by 30 seconds. A game with no hints
answers `illegal`. Flush waiting moves first.

### `POST /v1/daily/runs/{run}/giveup`

No body. 200, an answer with the result, `outcome: "gaveUp"`. A run given up before any move
doesn't count toward streaks.

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
  }
}
```

- `date` defaults to the person's day. Any date from 120 days ago to today; anything else is a 400.
- **Who is on it:** the person and everyone they have a streak with (a pair), read now, so someone
  who leaves the pair drops off. Nobody who hasn't played appears.
- **`player`** is `"me"` for the board's owner and the pair id for a connection (the `pair` of
  `GET /v1/me/streaks`). No player id is ever sent.
- **Per game,** rows with a result come first, ranked by the game's own order (best first; for
  Nine Lives, Sniff and Cat Nap unsolved after solved, furthest first; Box Fort by points). `rank`
  is a competition rank: ties share it and the next skips. People playing now follow with
  `rank: null` and their progress. Results marked `tooFast` are left off.
- **The Dish:** per game 3, 2 and 1 points for the first three places (ties share a place's
  points), plus 1 for each ended run (a run closed at 04:00 didn't end). `crowns` lists the games
  won. Sorted by points; equal points share a rank.
- Games are listed in the Dish's order: Sniff, Nine Lives, Cat Nap, Box Fort.

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
| `{ "t": "watch", "player", "game", "state" }` | A frame: the run's public state, first right after the offer, then one per accepted batch | TVs |
| `{ "t": "watchEnd", "player", "game", "result" }` | The watched run ended (`result` null: Show on TV was turned off) | TVs |
| `{ "t": "pong" }` | Answer to a ping | all |
| `{ "t": "error", "error": "not_allowed" }` | The client sent anything but a ping | all |

- `progress` never carries state or letters. Only a TV ever gets `watch`, and only after the
  player turned on Show on TV. A TV keeps the frames it hears after an offer, so pressing Watch
  shows the latest at once.
- The board snapshot's date is the board owner's day. A `result` can be for yesterday (a run
  closed at 04:00); check its `date`.
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
| Spacing between moves | Each game's own (`minMoveGapMs`; Sniff 500 ms); moves in one batch count as 0 ms apart | `too_soon` |
| Faster than a game's floor | Kept, `tooFast: true`, off every board | |

## Streaks and reminders

- A run that ended (not closed) with at least one move counts as playing that day: for your own
  streak, and as your turn in every pair (spec §5). A day whose only plays are daily runs is kept
  only when both people ended one. `StreakView` is unchanged.
- The daily reminder can also fire when no move is waiting but today's Dish is open: "Today's
  Dish is out. Sniff 12 is waiting." It is kind `reminder`, thread `dish`, with no `code` and
  `data: { "dish": "<game>" }`; open the Dish.

## For game builders

A game is a `DailyModule` (`apps/play-api/src/daily/module.ts`): its puzzle maker
(`make(rng, level, { date, key })`, where `rng` is seeded for that game and date and `key` is the
game's cycle key, the same every day, for what runs across days, like Sniff's answer pools), public puzzle
and state, move parser, rules (`apply`), hint, progress, result and ranking, time floors and move
spacing. Add one line to `src/daily/games.ts` (and its title to `DAILY_TITLES`). The referee
(`src/daily/run-core.ts`) does the rest: the clock, batches, resends, hints, closing at 04:00 and
the result. `publicPuzzle` and `publicState` are everything a client ever sees.
