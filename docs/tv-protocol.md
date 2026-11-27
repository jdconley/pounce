# Pounce on the TV: the wire contract

What the server speaks for TVs ("screens"), phones at a TV table, and TV links. Design:
[specs/2026-11-16-tv-table-design.md](superpowers/specs/2026-11-16-tv-table-design.md). All of it
is additive. `PROTOCOL_VERSION` stays 1, and an app that knows none of it plays the full table
as before.

Everything here requires the server flag `TV` (`"on"` in `wrangler.jsonc`). With it off:
- every `/v1/screens` route and `/tv/{token}` is a 404;
- `POST /v1/rooms` with `"screen": true` is a 400 `{ "error": "bad_request" }`;
- `role=screen` is refused (404);
- `screen` and `aim` are never sent;
- an `aim` from a client is `bad_message`.

## A screen

A screen is a device the room lists as one: it made the table (`"screen": true`), a phone
linked it (TV links, below), or it followed Play again from a table that listed it. It connects
with `role=screen`. It holds no seat, so it gets exactly the view and events a device with no
seats gets: no hand, no rack, no drawn card or tile.

- **Connecting.**
  - Apps: `GET /v1/rooms/{code}/ws?role=screen`, with the usual `Authorization` and `X-Pounce-*` headers.
  - Browsers: the same URL plus `games` and `app`, with subprotocols `pounce` and `pounce.token.<device token>`.
  - A listed device is a screen there for good, with or without the query.
  - Asking for `role=screen` never lists a device. Knowing a room's code is not enough.
- **Refused:**
  - 409 `{ "error": "seated" }` (close code 4409 for a browser) when the device holds a seat in that room or hosts it.
  - 403 `{ "error": "not_screen" }` (close code 4403 for a browser) when the room doesn't list the device as a screen. A TV that hears it, or 404, forgets the room it kept and goes home.
  - Use a device of its own for the TV. The web TV page keeps its credential under `pounce.tv.device`.
- **What a screen may send.** Only `ping`, `presence` and `link`. Every other message is answered `{ "t": "error", "code": "not_allowed" }`.
- **Membership.**
  - A screen counts as a member of the room for joining by code. Reconnecting never costs a guess.
  - It appears in no one's table list.
- **Making a table.**
  - `POST /v1/rooms` with `{ "game": "cat-tower" | "tiles", "screen": true }` (no `name`) returns 201 `{ "code" }`.
  - The caller is the room's screen. The room has no host until the first phone takes a seat, and that phone becomes the host.
  - Start, House Cat seats and Play again stay phone actions.
- **Play again.** The new table knows the old table's screens. A TV that follows `{ "t": "rematch", "code" }` to it is a screen there.

## `screen` in the snapshot

`room.screen: true` is present while at least one screen is connected, and for 10 seconds
after the last one goes. Otherwise the key is absent.

- A screen that comes back within the 10 seconds changes nothing for the phones.
- The flag says only that some screen is there; several TVs are fine.
- Phones use it to switch to the controller layout. A shipped app ignores the key.

## `aim`: live pointing

Client to server:

```json
{ "t": "aim", "seat": 0, "aim": { "target": { "seat": 2, "group": 1 } } }
{ "t": "aim", "seat": 1, "aim": { "table": [[12, 13, 14], [40, 41, 42, 43]] } }
{ "t": "aim", "seat": 0 }
```

The last form clears it.

- **Cat Tower:** `target` is a laid group, `laid[seat][group]`.
- **Tuna Tiles:** `table` is the player's draft of the whole table. Every piece must be on the table or in the sender's own rack.
- **The exact shape.** Anything else is answered `{ "t": "error", "code": "bad_message" }`, not dropped:
  - The message is exactly `t`, `seat` (an integer, 0 or more) and, unless it clears, `aim`.
  - Cat Tower: `aim` is exactly `{ "target": { "seat", "group" } }`, both integers 0 or more, no other keys.
  - Tuna Tiles: `aim` is exactly `{ "table" }`: at most 60 sets (an empty table is fine). Each set holds 1 to 13 piece ids (integers 0 to 105). No id appears twice in the whole table. No other keys.
  - Clients drop empty sets before sending, and never send a draft over these limits.
- **Who may send it:**
  - Only the device that controls `seat`, while `seat` is the one to act, mid-round.
  - A well-formed aim that doesn't fit the table (a seat that isn't acting, a group that isn't there, another seat's piece, between rounds) is dropped silently.
  - A screen's `aim` is `not_allowed`.
- **Rate limit.**
  - At most 10 per device per rolling second; extras are dropped.
  - A clear over the limit still goes, once, when the last thing relayed for that seat was an aim.
  - Clients send at most one every 120 ms, with the latest one trailing.

Server to every other connected device, with no `seq`:

```json
{ "t": "aim", "seat": 0, "aim": { "target": { "seat": 2, "group": 1 } } }
```

- It is not state. It is never stored and never replayed to a device that connects later.
- Clients drop the aims they show whenever a snapshot changes the turn or the status. They also drop an aim when they get a clear.
- Shipped apps skip the unknown message type.

## TV links

How a phone puts its table on a TV with nothing typed on the TV.

### `POST /v1/screens` (the TV's device token)

Body `{}`, or `{ "showing": "<ROOM CODE>" }` from a TV that is showing that table ("Link another table").

- 201:

  ```json
  { "token": "<22 base64url chars>", "code": "<6 chars>", "url": "https://play.conleychaos.com/tv/<token>", "expiresIn": 600000 }
  ```

- 400 `{ "error": "bad_request" }` for any other body, or a `showing` that isn't a room code.
- 429 `{ "error": "rate_limited" }` beyond 30 per 10 minutes per device, or 120 per 10 minutes per address.
- 503 `{ "error": "no_link_code" }` when no free backup code was found. Ask again.
- The token is 128 random bits. The code uses the room-code alphabet.
- Both expire after `expiresIn` ms (10 minutes; less on a fast dev server). The TV asks again at 80% and shows the new link. The old one simply expires.

### `GET /v1/screens/{token}/ws` (the TV's device token)

Only the device that made the link may wait on it; anyone else gets 404 (close code 4404 for a
browser), as does a link that has expired. A request that isn't a socket upgrade gets 426
`{ "error": "upgrade_required" }`. Messages:

- `{ "t": "linked", "room": "<ROOM CODE>" }`. The link is spent. The TV is already listed as a screen there, so it opens `/v1/rooms/{room}/ws?role=screen`.
  - A socket that connects after the link happened hears this at once, until the link expires.
  - On `linked`, a TV closes this socket and any screen socket it had on another table.
- `{ "t": "expired" }`. The server then closes the socket (1000). A TV that was linked ignores it.
- `{ "t": "ping" }` is answered `{ "t": "pong" }`.

### `POST /v1/screens/link` (the phone's device token)

Body: exactly one of `"token"` or `"code"` (any case), plus `"room"`, and `"move": true` when
the phone has confirmed "Move the TV to this table?".

| Answer | When |
|---|---|
| 200 `{ "linked": true }` | Linked, or the TV already shows this table |
| 403 `{ "error": "not_seated" }` | The phone is not the host and holds no seat there, or is itself a screen there. Also for a room that doesn't exist, or that went while linking |
| 404 `{ "error": "not_found" }` | No live link with that token or code, or it is spent |
| 409 `{ "error": "showing" }` | The TV shows another table and `move` wasn't sent |
| 409 `{ "error": "seated" }` | The TV's device holds a seat at this table |
| 429 `{ "error": "too_many_attempts", "retryAfter": n }` | Too many wrong codes (`retry-after` header too) |
| 400 `{ "error": "bad_request" }` | Malformed |

- Wrong codes count against the phone (the room-code backoff, `DEVICE_JOIN_RULE`) and its address. Their counters are separate from joining by code.
- Tokens can't be guessed, so they aren't counted.
- A TV takes a link only while it shows one: on its home screen, or after "Link another table" is chosen on the TV. A guessed code, with the backoff, can at worst put a table on such a TV.

### `GET /tv/{token}`

A 302 to `/play/tv-link/{token}`, where a phone without the app picks or makes the table to
show.

- **Universal links.** Only while `TV` and `TV_APPLINKS` are both on does the site association
  list `/tv/*` after `/j/*` (and `/p/*`), so iOS opens these links in the app. `TV_APPLINKS` is
  `"off"` in `wrangler.jsonc` until the 1.2 app is live on the App Store: until then every `/tv/`
  link opens the web page above, which works with or without the app. With `TV` off the path is a
  404 and the association never lists it. The app's own ways in don't depend on the association:
  the Show on TV scanner and typed code, and the dev scheme `pounce-dev://tv/<token>`.
- **A shipped 1.1 app** (before stage 3) opened by such a link simply opens. It doesn't know the
  path, so it does nothing more. That is why `TV_APPLINKS` waits.
- **This app** (stage 3 on) takes the token:
  - At a table (lobby or game) where it is seated or hosts, it links that table at once, asking
    "Move the TV to this table?" on a 409 `showing`.
  - Anywhere else it opens Home ("Your tables" and the games) with "Pick a table for the TV.",
    and links the table picked from Home's list or made from its games (within the link's 10
    minutes), as soon as the room exists. Reaching a table any other way (a push, Play again, an
    invite link), or tapping the cue, drops the waiting link.
  - Before the age check or pick-a-cat, the link waits for them, as a `/j/` link does.
- **Show on TV** in the app scans the TV's QR. It accepts only
  `https://play.conleychaos.com/tv/<22 base64url chars>` and keeps looking past any other code,
  or takes the 6-character backup code typed on the phone. Only the QR's text is read; camera
  frames never leave the phone.

## Purrtrait: same room and live ink

Purrtrait (`"game": "purrtrait"`) is the draw-and-guess game for one room: the TV shows the easel
and the scores, the drawer draws on their phone, and everyone else guesses out loud. It needs
`TV` on and `purrtrait` in `GAMES`, and an app whose `X-Pounce-Games` lists it. Design:
[specs/2026-11-26-purrtrait-design.md](superpowers/specs/2026-11-26-purrtrait-design.md). Wire
samples, generated from real rooms: `apps/play-api/fixtures/protocol/purrtrait-server-messages.json`
and `purrtrait-client-messages.json`. Only a Purrtrait room speaks any of this. Its view is
`room.purrtrait`, its options `room.options: { "timer": 45 | 60 | 90 }`.

### The table and its one TV

- **Only a TV makes it.** `POST /v1/rooms` with `{ "game": "purrtrait", "screen": true }` returns
  201 `{ "code" }`. Without `"screen": true` it is a 400 `{ "error": "bad_request" }`. The first
  phone to sit is the host.
- **One TV.** The TV that made the table is its only screen, and Play again keeps it.
  `POST /v1/screens/link` to a Purrtrait table:
  - From the host: the new TV replaces the old one. The old TV's sockets close with 4403, reason
    `not_screen`, and it is refused from then on.
  - From anyone else seated: 403 `{ "error": "not_allowed" }`. From a stranger: 403 `not_seated`.
- **Start** needs 2 seats filled and the TV showing (connected, or within its 10-second grace).
  Otherwise `not_enough_players` or `no_screen`. Open seats don't hold it up.
- **The turn clock** runs only while the TV is showing. Without it, after the grace, the view
  says `paused: true` and `remainingMs` stops. 30 minutes paused ends the game.
- **Refused at a Purrtrait table:** `moveSeat`, `claimMove`, `nudge`, `retire` and `configure`
  to `bot` are `not_allowed`. No pushes, live table, invite link or request to play (409
  `not_shared`) for it.

### Near keys: joining from the TV's code

- **The key.** While the table is in its lobby or a game and its TV is connected, the room mints
  a near key every 30 seconds: 8 characters from the room-code alphabet. The current and the
  previous key are taken, each for at most 60 seconds from its mint.
- **Only the TV's snapshot has it:**

  ```json
  "near": { "key": "KQXMT7RB", "code": "BCDFGKQX", "expiresIn": 21400 }
  ```

  `code` is the typed fallback: the 5-character room code plus the key's first 3 characters.
  `expiresIn` is ms until the next key, which comes in a new snapshot. A phone's snapshot never
  has `near`, and an over table has none.
- **The TV's QR** is `https://play.conleychaos.com/e/<CODE>?near=<KEY>`.
- **The socket.** `GET /v1/rooms/{code}/ws?near=<KEY>`, or `near=<8-character typed code>`, in
  any case. A member reconnects with no key: a seat's device, the host, the TV, a device that
  has been at the table, and Play again's followers.
- **Refused:** 403 `{ "error": "not_near" }` (close 4403 for a browser) for a device that isn't a
  member and brings no key, a stale key, the plain room code or a wrong code.
  - Each is a wrong room-code guess against the device (`DEVICE_JOIN_RULE`, 5 an hour free) and
    its address (`IP_JOIN_RULE`, 20 an hour free; an IPv6 address counts by its /64). Past that
    both back off, and a locked-out device or address gets 429 `too_many_attempts` with
    `retryAfter`, even with the right key.
  - 30 wrong guesses at one table within one key's 30 seconds close the typed code until the next
    key. The QR's whole key still works.
  - An app that can't draw Purrtrait is told what any game it can't draw tells it (426 naming the
    game for an app that sends `X-Pounce-App`, else 404), uncounted.
- **`/e/<CODE>?near=<KEY>`.** With a live key: 302 to `/play/e/<CODE>?near=<KEY>`, the web
  player's join page. Without one, or with a stale or wrong one: a page that says "Scan the code
  on the TV." with no button (a wrong key counts against the address). `/j/<CODE>` for a
  Purrtrait table shows the same page. While Purrtrait tables can't be dealt, `/e/` is a 404.
- **`PURRTRAIT_APPLINKS`** (`"off"` by default). With it `"on"`, and Purrtrait dealt, the site
  association lists `/e/*` after `/j/*` and `/p/*`, so iOS opens the TV's QR in the app. Leave
  it off until an App Store version draws Purrtrait: until then the QR opens the web player,
  which can play.

### Live ink

The drawer's strokes, on a portrait 768 × 1024 grid (x 0-767, y 0-1023). Colours 0-7, 8 is the
eraser; widths 0-2.

Client to server, from the device that owns the drawing turn only:

```json
{ "t": "ink", "seat": 3, "turn": "2:5", "ops": [["s", 12, 0, 1, 384, 210, 3, -1, 4, 0], ["p", 12, 2, 2, 1, 3], ["u", 11], ["c"]] }
{ "t": "ink", "seat": 3, "turn": "2:5", "ops": [["s", 40, 0, 1, 384, 210, 3, -1]], "last": true }
```

- **Ops.** `["s", id, colour, width, x, y, dx, dy, ...]` starts stroke `id` at (x, y), then
  deltas. `["p", id, dx, dy, ...]` adds points to it. `["u", id]` undoes it. `["c"]` clears the
  easel.
- **Checked exactly**, else `bad_message`: every delta -768 to 768, every point stays on the
  grid, `p` and `u` name a stroke on the easel, and the message is under 8 KB. Stroke ids start
  at 0 each turn, and each new stroke's id is exactly the next one (a clear doesn't reset them).
- **`turn`** is the view's `turn` (`"<round>:<turn index>"`).
- **Who may send it.** The device that picked the word owns the turn (when the clock picked, the
  first device on the drawer's seat to send ink, `gotIt` or `giveUp`). Anyone else's well-formed
  ink, ink for another seat, or for a past turn is dropped silently. The TV's is `not_allowed`.
- **Rate.** 25 messages a second per device; more are dropped. Send the held-back points in the
  next batch.
- **Caps.** At most 500 strokes and 30 000 points since the last clear. A batch that would go
  past either is refused whole, even when it also holds a `["c"]`, with `easel_full` once a turn;
  after that, full batches are dropped silently. Send `["c"]` on its own, then draw again.

Server to client, with no `seq`, never in a snapshot and never stored:

```json
{ "t": "ink", "seat": 3, "turn": "2:5", "ops": [...] }
{ "t": "inkSync", "turn": "2:5", "ops": [...] }
{ "t": "inkResend", "turn": "2:5" }
```

- **`ink`** goes, as it came, to the TV and to the drawer's own device's other sockets. Never to
  another phone, and never with `last`.
- **`inkSync`** comes right after the snapshot of a TV, or of the drawer's device, that connects
  while the drawer is drawing: the drawing so far, compacted (no clears, no undone strokes, each
  stroke's points folded into its `s`). **It replaces:** drop what is on the easel for that turn
  and draw its `ops`, which may be `[]`. It reaches every socket of the drawer's device, so a
  socket that already shows the drawing gets it again, harmlessly.
- **`inkResend`.** The room keeps the drawing in memory only. A room that wakes from storage
  mid-drawing has lost it, and asks the drawer's device for it (at once when it is connected,
  else when it connects, each time while the drawing is still lost). Answer from the one socket
  that is drawing, with the whole easel:
  - The first message starts with `["c"]` and carries your own stroke ids, which only have to go
    up. The final message carries `"last": true`, including when the reply is a single message.
  - From its first message to the one marked `last`, the reply is exempt from the rate limit,
    once, for up to 5 seconds.
  - Until it arrives, the room drops ink that doesn't start with `["c"]`, and a TV that connects
    gets no `inkSync`.
- **A new turn** (a new `turn` in a snapshot): clients drop the drawing. The room drops it from
  memory at the same moment.
- Shipped apps skip the three unknown message types. They never reach a Purrtrait table anyway.

### Removing a player

```json
{ "t": "remove", "seat": 4 }
```

- From the host only; anyone else, or any other game's table, gets `not_allowed`. `bad_seat` for
  the host's own seat, or a seat with nobody in it.
- In the lobby the seat opens. In a game the seat is out, as if its person left: a drawer
  mid-turn misses the turn (`missed`, reason `left`), and the game ends if fewer than 2 are left.
- The seat's devices and its player go on the room's removed list, which Play again copies. A
  device that still holds another seat stays; only the removed person is refused.
- **A removed device gets only a close:** its sockets close at once with 4403, reason `removed`,
  with no error, snapshot or event first. After that its socket upgrade is 403
  `{ "error": "removed" }` (4403 for a browser), with or without a key, and never counted as a
  guess. The removed player on another device is refused the same way, and a `claim` as them
  answers `removed`.
- When the host's seat leaves, the host role passes to the next seat still in.
