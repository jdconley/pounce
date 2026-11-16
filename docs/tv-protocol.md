# Pounce on the TV: the wire contract

What the server speaks for TVs ("screens"), phones at a TV table, and TV links. Design:
[specs/2026-11-16-tv-table-design.md](superpowers/specs/2026-11-16-tv-table-design.md). All of it
is additive. `PROTOCOL_VERSION` stays 1, and an app that knows none of it plays the full table
as before.

Everything here requires the server flag `TV` (`"on"` in `wrangler.jsonc`). With it off:
- every route below is a 404;
- `role=screen` is refused (404);
- `screen` and `aim` are never sent;
- an `aim` from a client is `bad_message`.

## A screen

A screen is a device that connects to a room with `role=screen`. It holds no seat, so it
gets exactly the view and events a device with no seats gets: no hand, no rack, no drawn card
or tile.

- **Connecting.**
  - Apps: `GET /v1/rooms/{code}/ws?role=screen`, with the usual `Authorization` and `X-Pounce-*` headers.
  - Browsers: the same URL plus `games` and `app`, with subprotocols `pounce` and `pounce.token.<device token>`.
  - Once a device has been a screen in a room, it stays one there, with or without the query.
- **Refused:**
  - 409 `{ "error": "seated" }` (close code 4409 for a browser) when the device holds a seat in that room or hosts it.
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
- **Who may send it:**
  - Only the device that controls `seat`, while `seat` is the one to act, mid-round.
  - Anything else (a seat that isn't acting, a group that isn't there, another seat's piece, between rounds) is dropped silently.
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

- 429 `{ "error": "rate_limited" }` beyond 30 per 10 minutes per device, or 120 per 10 minutes per address.
- The token is 128 random bits. The code uses the room-code alphabet.
- Both expire after `expiresIn` ms (10 minutes; less on a fast dev server). The TV asks again at 80% and shows the new link. The old one simply expires.

### `GET /v1/screens/{token}/ws` (the TV's device token)

Only the device that made the link may wait on it; anyone else gets 404. Messages:

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
| 403 `{ "error": "not_seated" }` | The phone is not the host and holds no seat there. Also for a room that doesn't exist |
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
show. The iPhone app adds `/tv/*` to its universal links in stage 3. A shipped 1.1 app opened
by such a link opens and does nothing more.
