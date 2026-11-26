# Toy Tumble: the live wire

What the server and clients send while a Toy Tumble round plays. The design is
[specs/2026-11-26-toy-tumble-design.md](superpowers/specs/2026-11-26-toy-tumble-design.md), §6.

The types are in `apps/play-api/src/tumble/wire.ts`. Samples every client must decode or encode
are in `apps/play-api/fixtures/protocol/tumble-*-messages.json`. The engine every client runs is
in `apps/play-api/src/tumble/`, with golden vectors in `apps/play-api/fixtures/tumble/`.

Everything here is additive. `PROTOCOL_VERSION` stays 1. At a table of any other game, a `tumble`
message is answered `{ "t": "error", "code": "bad_message" }`.

## The model

- Each device runs its own box with the shared engine. It sends what happens, as it happens.
- The server runs the same engine for every box, checks each event, and relays it to every other
  device and screen at the table.
- Observers replay what they're sent. Nobody else ever sees a refused event.
- Only the server makes random choices for hits: junk gaps and Paw Swipe shifts. A box's own
  generator (`Box.rng`) decides where its new tricks sit.

## Room state: the snapshot's `tumble` field

A Toy Tumble room's snapshot carries `room.gameId: "tumble"` and `room.tumble`:

```json
{
  "seats": 3, "cats": "easy", "wins": [1, 0, 2], "left": [false, false, false], "away": [false, false, false],
  "status": "playing", "r": 4, "startsAt": 1764200000000,
  "roundSeed": [1, 2, 3, 4], "trickSeeds": [[5, 6, 7, 8], [9, 9, 9, 9], [3, 3, 3, 3]],
  "outs": [], "winner": null, "waitingSince": null
}
```

- `status` is one of:
  - `countdown`: the 3-2-1 runs until `startsAt`;
  - `playing`;
  - `between`: standings for 5 seconds;
  - `over`.
- `roundSeed` and `trickSeeds` are present from `countdown` on.
- Every box starts at `newBox(trickSeeds[seat])`. Toy `n` is `toyAt(roundSeed, n)`.
- The round clock in `l` events counts ms from `startsAt`, by the device's own clock.
- `outs` lists the seats out this round, in order. `winner` is set at round end, `null` for a
  round nobody won.
- `waitingSince` is the server time when a countdown began waiting for a missing device (spec §5.1).
  The status stays `between` while it waits.
- Before the first countdown (a Play again table waiting for its people), `r` is 0, `status` is
  `between`, and the seeds are absent.
- `winner` once `over` is the game's: the third win's seat, or after an early end the seat left
  with the most wins (`null` on a tie).
- These changes go out with a `seq` as usual.

## The room around a round

- **Lobby.** `options` is `{ "cats": "easy" | "quick" }`, set with `setOptions` (host only).
  2 to 6 seats. A device that holds a seat can't `claim` or `claimMove` another: `not_allowed`.
- **Start** is refused with `not_connected` until every person's seat has a connected device.
  It goes straight to the first countdown.
- **Between rounds** the standings show 5 seconds. The next countdown starts once every person
  still playing has a device connected. If one is missing, `waitingSince` is set; 20 seconds
  later the host may send `{ "t": "act", "seat": <theirs>, "action": { "k": "playWithout" } }`
  (`too_soon` before then, `not_allowed` from anyone else or while nothing waits). The missing
  seats become `away` and sit rounds out until their device is back at a countdown.
- **Leave** is `{ "t": "act", "seat": <theirs>, "action": { "k": "leave" } }`: out for the rest of
  the game, wins kept, no House Cat takes it. Fewer than 2 seats left, or no person left, ends
  the game.
- Nothing is ever "to act": snapshots have no turn, and there are no nudges, retires or live
  tables.
- **A server restart** mid-countdown or mid-round loses the round: it counts down again as the
  same `r`, with new seeds and the wins kept.
- **Who gets the game.** An iOS or tvOS app below 1.4 is never given `tumble`, whatever its
  `X-Pounce-Games` lists. The web player always is.

## Client to server: `tumble`

```json
{ "t": "tumble", "r": 2, "ev": [ ["m", 14, 1, 5, 9], ["l", 14, 1, 5, 3, 41250, [7]] ] }
```

`r` is the round. `ev` holds 0 to 64 events, in order:

| Event | Meaning |
| --- | --- |
| `["m", n, rot, x, y]` | toy `n` (the queue index) is at this rotation (0 to 3) and position. Send only the latest in a batch. |
| `["l", n, rot, x, y, ms, landed]` | toy `n` set down here, at `ms` (0 to 600000) on the round clock. `landed` lists up to 16 junk ids that landed after it, oldest first, which is a prefix of the box's waiting junk. |
| `["a", id]` | hit `id` was applied, or junk `id` started its 2-second wait |
| `["u", slot, seat]` | use the trick in `slot` (0 to 5) on `seat` (0 to 5) |

Positions are the bottom-left corner of the toy's own k by k box (`toyCells`). x runs from -3 to
14, and y from -3 to 25.

- **Exact shape.** Anything else is `bad_message`: extra keys, floats, out-of-range numbers, or
  unknown events.
- **Sending:**
  - Send a batch at most every 50 ms while something changes, and at once on `l` or `u`.
  - Send nothing while the toy is still and nothing happens.
  - An empty `ev` asks for a sync of every box. Send one after a gap in `q`, on returning from the
    background, or after a hidden tab.
- **Rate limit.** At most 30 batches a second per device. Over that, the device gets a
  `tumbleSync`.
- **A batch for another round** (`r` not the current one) is dropped silently.
- **Who may send.**
  - Only the device holding a seat, for its own seat. A device holds at most one seat at a Toy
    Tumble table.
  - If the same device has two sockets, only the first to send in a round writes. The other gets
    `{ "t": "error", "code": "not_allowed" }`.
  - A screen's `tumble` is `not_allowed`.

## Server to clients

### `tumble`: one box's checked events

```json
{ "t": "tumble", "r": 2, "s": 1, "q": 88, "ev": [ ["l", 14, 1, 5, 3, 41250, []] ] }
```

- It is sent to every connected device and screen except the box's own device.
- `q` counts up by one per relay of that box. A gap means something was missed, so ask for a sync.
- `m` events are relayed at most every 66 ms per box (the latest wins).

### `tumbleHit`: something hits a box

```json
{ "t": "tumbleHit", "r": 2, "id": 31, "from": 0, "to": 1, "k": "junk", "x": { "rows": 2, "gap": 7 } }
```

| `k` | `x` |
| --- | --- |
| `junk` | `{ rows, gap }`, from a clear (§4.5) |
| `hairball` | `{ gap }` |
| `swipe` | `{ shifts }`: 22 numbers, -2 to 2, one per row from y 0. Positive moves right, wrapping. |
| `swap` | `{ cells, tricks }`: the other box's contents as the server last had them (264 numbers each) |
| `catnip`, `scoop`, `settle`, `nap`, `bath` | none |
| `napped` | none. A trick spent on a napping box, for the animation only. Nothing to apply or ack. |

- It goes to every device and screen.
- **The target's device:**
  - For `junk`, it calls `receiveJunk` and acks with `["a", id]` at once. The 2-second wait starts
    at the ack.
  - For anything else, it calls `applyHit` and acks with `["a", id]` at once.
  - Catnip and Nap last 10 seconds from the ack, on the target's clock.
- **Every other replayer** keeps the hit and applies it to the target's box when the target's
  `["a", id]` comes through in that box's `tumble` relay. So every copy of a box applies hits in
  the order its own device did.
- **Swap** sends one `tumbleHit` per box, each carrying the other box's contents.
- An unacked hit is applied by the server after 3 seconds, and the box's sync goes to everyone.
  A later ack for it is refused with a sync.

### `tumbleSync`: whole boxes

```json
{ "t": "tumbleSync", "r": 2, "boxes": [ { "s": 0, "box": { }, "q": 41, "waitingLeft": [1250], "catnipLeft": 0, "napLeft": 6400, "status": "ok" } ] }
```

`box` is the engine's `Box` exactly. The device snaps that box to it, then carries on from `q`.

It is sent:
- to a device or screen that connects mid-round, or asks for one (an empty `ev`), with every box;
- to a device whose event the server refused, with its own box;
- to everyone, with one box, when the server applied something itself: an unacked hit at 3
  seconds, or junk owed for more than 4 seconds since its ack and not landed by the next set-down
  that cleared nothing.

`status` is `ok`, `lag` (no message from that device for 3 seconds) or `out`.

### `tumbleSeat`: a device is lagging or back

```json
{ "t": "tumbleSeat", "r": 2, "s": 1, "st": "lag" }
```

- After 3 seconds with no message from a seat's device, every client shows "Reconnecting" on its
  box, and its toy hangs still.
- `ok` means it is back.
- After 15 seconds the box is out (the snapshot's `outs`).

## What the server checks (spec §6.5)

On each event:
- `n` is the box's next toy;
- a set-down fits and rests;
- landed junk is the waiting prefix, and nothing cleared;
- an ack names a hit issued to this seat and not yet acked;
- a used trick is held and aimed at a box still in the round;
- set-down times only go forward.

A refused event gets the sender a `tumbleSync` of its own box. It isn't relayed.

The server doesn't check reachability or human speed.
