# Purrtrait: design

Date: 2026-11-26 · Owner: JD Conley (Conley Chaos LLC) · Status: draft for JD · Release: web first, then the iPhone app after 1.3 · Lives in `github.com/jdconley/pounce`

Parent specs: `2026-10-31-pounce-cat-tower-design.md` (product principles, architecture), `2026-11-11-tile-game-design.md` (more than one game, the `GAMES` flag), `2026-11-15-web-player-design.md`, `2026-11-16-tv-table-design.md` (screens, links, `aim`), `2026-11-05-parent-consent-design.md` (kittens), `2026-11-25-birdwatch-design.md` (module options, the name check). Where this document says nothing, those apply.

Marks: **(JD)** means JD decided it, in the brief or in answers on 2026-11-26. **(call)** means a call made while writing this, open to override.

## 1. What this is and why

Purrtrait is Pounce's fourth table game and its first party game: one player draws a word on their phone or iPad, the TV is the easel and shows the lines as they are drawn, and everyone else in the room shouts out guesses. The draw-and-guess game is a traditional parlour game. The name, the words, the art and every word of the rules are ours. **(JD)**

JD's words: "people can draw on their device with the central tv screen. this one requires the central 'tv' and the 'table' is like a view of an easel and you see what people are drawing in near real time."

It is made for one room. JD: "pictionary could be iffy with kids so make sure we handle that well. maybe only allow it for same-room play, not internet." **(JD)**

**Success:** a family on the couch plays a full game on the TV, with a mix of the app, browser phones and one shared phone, and the lines appear on the TV as fast as the drawer makes them. A seven-year-old can draw and guess without reading anything but their own word, and a parent never has to think about where the drawings went.

## 2. Goals, non-goals, anti-goals

**Goals**
- Same-room play only, with a TV required: the Apple TV app or the browser TV page (§5). **(JD)**
- Guesses are said out loud. The drawer taps who got it. Nobody types anything. **(JD, from "same room only")**
- Lines show on the TV within about 150 ms of being drawn on the same Wi-Fi, at 60 fps or better on every device (§7).
- Drawings are ephemeral: never written to disk, never kept past the turn, never sent anywhere but that room's TV and the drawer's own device, never shareable or exportable (§8). **(JD)**
- Kids under 13 draw and guess by default (§9). **(JD)**
- It plays on iPhone, iPad, the web player, the Apple TV app and the browser TV page, from the same server and rooms.

**Non-goals (first release)** **(call)**
- Far-away players, invite links, Far away, turn-based play, or internet matchmaking.
- Typed guesses, chat, or any free text.
- House Cats. A bot can't shout a guess or judge one.
- Teams. Everyone plays for themselves.
- Saving, replaying, sharing or exporting a drawing, or a gallery at game over.
- Languages other than English.
- A TV-less mode where a phone is the easel.

**Anti-goals**
- Anything that reads as the commercial draw-and-guess board game: its name, its category names, its board, its timer, its card layout or its rulebook wording. That covers code, comments, tests, docs, UI copy and commit messages. **(JD)**
- A drawing reaching a phone other than the drawer's, a second TV, or anywhere after the turn ends.
- A way to type text that other people see.
- A word a parent would wince at.
- Drawing that lags, stutters or drops frames on the drawer's phone. The drawer's own lines are drawn locally at once and never wait for the server.

## 3. Name

**Purrtrait** **(call, for JD to confirm)**. The code id is `purrtrait` and never changes, even if the display name does.

A search on 2026-11-26 (US records via Trademarkia, `trademarkia.com/search/trademarks?q=purrtrait` and `?q=purrtraits`) returned no marks at all, live or dead, for PURRTRAIT or PURRTRAITS. Names considered and dropped because of live marks:
- DOODLE DEN: a live, pending class 9 application under that exact name (serial 99467743), and the live DOODLE software marks.
- SCRATCH PAD: a live, pending class 41 application (serial 98012262).
- SKETCHY CAT: the live class 41 SKETCHY family (reg. 87431263).
- CAT SCRATCH: the exact marks are dead, but SCRATCH 'N CATCH (class 28, reg. 75617675) is live.

The game is named inside Pounce, not as its own App Store app. Trademarkia's index is a first check, not a clearance opinion. **(as with Birdwatch §3.4)**

## 4. Rules, in our words

How to play is written from this section.

### 4.1 Players and setup

- 2 to 10 players. **(call: 2 works for a couple, with one drawing and one guessing; 10 is a full living room)**
- Every seat is a person in the room. No House Cats. **(call)**
- Everyone plays for themselves. **(call)**
- The lobby has one choice: the timer, 45, 60 or 90 seconds a turn, as three pills. The default is 60. **(call)**

### 4.2 A turn **(call)**

1. **The drawer is shown two words,** one Easy and one Tricky, and picks one. With no pick in 10 seconds, the Easy word is used.
2. **The drawer draws it** on their device. The TV shows the lines as they are drawn, plus the word's group ("Animal", "Food") and the timer. The word itself is never on the TV until the turn ends.
3. **Everyone else shouts guesses.** No letters, numbers or spoken clues from the drawer. That is the rule the tips teach. The app can't enforce it.
4. **The drawer taps who got it.** That guesser and the drawer each score: 1 point for an Easy word, 2 for a Tricky one. One guesser per turn: the first one heard.
5. **The turn ends** when someone gets it, when the timer runs out (no points), or when the drawer gives up (no points). The TV shows the word big for a few seconds, then the next drawer goes.

### 4.3 The game **(call)**

- The drawer goes around the table in seat order. Everyone draws twice, then the game is over.
- The highest score wins. A tie shares the win.
- No word comes up twice in one game.

### 4.4 Leaving

- A drawer who leaves mid-turn ends that turn with no points.
- A seat that leaves is skipped from then on. The game ends early when fewer than 2 people are left.
- The host can remove a player, in the lobby or in a game, from the seat menu on their phone. **(call: a joiner who shouldn't be there, §5.3)**

### 4.5 The words **(call)**

- Our own list, about 500 words, in `apps/play-api/src/purrtrait/words.ts`. Each word has a group and a level, Easy or Tricky.
- Groups: Animals, Food, Home, Outside, Things, Actions, Jobs, Places. The TV shows the group as a hint.
- Every word is something a six-year-old knows by sight: a cat, a pizza, a rainbow, a toothbrush, swimming. Tricky words are harder to draw, not harder to know: a shadow, a whisper, a sandcastle.
- None of these: anything violent, scary, rude, about bodies beyond the obvious (a nose is fine), religious or political, brand names, people's names, or anything a parent would wince at. A second read of the whole list for that is part of review.

## 5. Same room only **(JD)**

### 5.1 What the server enforces

The server can't prove where a device is. So the rules make the TV the only door in, and make joining from elsewhere pointless:

1. **The TV makes the table.** `POST /v1/rooms` with `"game": "purrtrait"` needs `"screen": true`. A phone can't make a Purrtrait table. The phone's shelf shows Purrtrait with "Starts on the TV", and a tip says to pick it on the TV.
2. **One TV only.** The TV that made the table is its only screen, and Play again keeps it. A TV can come back as a new device (the browser TV page's storage cleared, another browser, the Apple TV app reinstalled), so the host's phone may put the table on a new TV with Show on TV: `POST /v1/screens/link` from the host to a Purrtrait room swaps the room's screen for the new one, and the old one is refused from then on. From anyone else it answers 403 `{ "error": "not_allowed" }`. There is never more than one screen. **(call)**
3. **You join from the TV's code, and it changes.** The TV shows a QR and a typed fallback code that change every 30 seconds (§5.2). A device that isn't yet a member of the room is admitted only with the current or the previous near key. The plain room code, an old QR and `/j/<CODE>` links are refused for a Purrtrait table: 403 `{ "error": "not_near" }`, close code 4403 for a browser. A member that already joined reconnects without a key.
4. **No ways in from elsewhere.** At a Purrtrait table: no invite link to share, no Far away, no requests to play, no seat moves by code (`moveSeat` and `claimMove` answer `not_allowed`), and no pushes, live table or Lock Screen activity. `/j/<CODE>` for a Purrtrait room, and `/e/<CODE>` without a live key, show "Scan the code on the TV." with no join button.
5. **Only the TV sees the drawing.** Ink (§6) goes to the room's screen and to the drawer's own device, and nowhere else. A guesser's phone never gets a single point, so there is nothing to see from another room even with a seat.

### 5.2 The near key **(call)**

- The room mints a near key every 30 seconds while a Purrtrait table is in the lobby or in a game: 8 random characters from the room-code alphabet. The current and the previous key are accepted, so a key is good for 30 to 60 seconds.
- Only the screen's snapshot carries it: `room.near: { "key": "...", "expiresIn": ms }`. A phone's snapshot never does.
- The TV's QR encodes `https://play.conleychaos.com/e/<CODE>?near=<KEY>` ("e" for easel), a path of its own, not `/j/`. Until the iPhone app draws Purrtrait, the site association doesn't list `/e/*`, so a phone with the app opens the web player and can play, instead of an app card that says the game isn't there yet. A server flag, `PURRTRAIT_APPLINKS`, adds `/e/*` to the association once that app version is live, as `TV_APPLINKS` did for `/tv/`. The app and the web player pass the key on as `near=<KEY>` on the room socket. **(call)**
- The typed fallback is the room code plus the first 2 characters of the key, as 8 characters: `ABCDEF KQ`. It is accepted only within the same 60 seconds. Phones' "Join with code" takes 6 or 8 characters. **(call: a QR does almost all the joining; the 2 extra characters keep a read-aloud code alive for 30 to 60 seconds only)**
- Wrong or stale keys count against the device on the room-code backoff (`DEVICE_JOIN_RULE`).

### 5.3 What this protects, honestly

- **It stops:** a stranger or relative elsewhere joining from a link, a shared room code, an old screenshot, or a code read out over the phone more than a minute ago. It stops drawings from ever reaching a phone, a second TV or anyone outside the room.
- **It doesn't stop:** someone in the room texting a fresh photo of the QR to a friend, who scans it within the minute. That friend gets a seat, but sees no drawings and can't type anything. On their turn they could draw on the family's TV. The host removes them from the seat menu, and they stay out (§10.2).
- **Rejected: a same-network check.** Comparing the phone's public address with the TV's would lock out a guest on cellular data, misfire on IPv6 and carrier networks, and still prove nothing. **(call)**
- **Rejected: Bluetooth, sound or other local proximity signals.** None works in a browser, and the Apple TV can't offer one to a phone without new permissions and pairing. **(call)**

## 6. Live ink: the wire

Everything here is additive, like `aim`. `PROTOCOL_VERSION` stays 1. Only a Purrtrait room speaks it.

### 6.1 The easel

- The easel is portrait, 3:4, like a real one. Coordinates are integers on a 768 × 1024 grid, origin at the top left. Every device scales the grid to fit. **(call: portrait fits a phone held normally, an iPad portrait exactly, and the middle of a 16:9 TV with the scores beside it)**
- 8 colours, fixed and numbered 0 to 7, black first, plus white as an eraser (colour 8). 3 widths, numbered 0 to 2 (4, 10 and 24 grid units). **(call)**
- Undo takes back the drawer's last stroke. Clear wipes the easel.

### 6.2 Drawer to server: `ink`

```json
{ "t": "ink", "seat": 3, "turn": "<turnKey>", "ops": [
  ["s", 12, 0, 1, 384, 210, 3, -1, 4, 0],
  ["p", 11, 2, 2, 1, 3],
  ["u", 9],
  ["c"]
] }
```

- `["s", id, colour, width, x, y, dx, dy, ...]` starts stroke `id` at `(x, y)`, followed by deltas.
- `["p", id, dx, dy, ...]` adds points to stroke `id`, as deltas from its last point.
- `["u", id]` undoes stroke `id`. `["c"]` clears the easel.
- Stroke ids start at 0 each turn and go up by one. A stroke is finished when a newer one starts, or when the turn ends.
- The exact shape is checked. Anything else is `bad_message`. Every coordinate stays on the grid, every delta between -768 and 768, and the message stays under the server's 8 KB limit.

### 6.3 Sending, simplifying and capping **(call)**

- The drawer's device samples every touch it gets (coalesced touches on iOS, coalesced pointer events on the web), drops points less than 2 grid units from the last one kept, and simplifies each batch (Ramer-Douglas-Peucker, tolerance 1 grid unit).
- It sends a batch every 50 ms while drawing, and at once when a stroke ends. At most 25 messages a second per device are taken. More are dropped, and the device sends its next batch with the points it held back. Nothing is sent while the finger is still.
- **Per turn:** at most 500 strokes and 30,000 points. Past that the server drops the ink and answers `{ "t": "error", "code": "easel_full" }` once. The drawer's device shows "Easel full" and offers Clear.
- **Who may send it:** only the device that controls the drawer's seat, only while that seat is drawing, and only with this turn's `turn`. A well-formed `ink` from anyone else, or for a past turn, is dropped silently, as `aim` is.

### 6.4 Server to the room

- Each `ink` is relayed as it came to the room's screen, and to any other socket of the drawer's own device, with no `seq`. It is not state and never goes in a snapshot.
- **Joining mid-turn.** A screen that connects, or the drawer's device reconnecting, gets the turn's drawing so far right after its snapshot, as one message:
  `{ "t": "inkSync", "turn": "<turnKey>", "ops": [...] }`. Undone strokes and everything before the last clear are left out, so it is always the smallest drawing that looks the same.
- **A new turn.** When the turn changes, clients drop the drawing they show. The room drops the turn's ink from memory at the same moment.
- **Shipped apps** skip both unknown message types. They never meet a Purrtrait table anyway (§10).

### 6.5 Where the ink lives **(call: approach 1)**

- The room keeps the current turn's ink in memory only (`RoomCore`, not `RoomState`), like `aimTimes`. It is never written to Durable Object storage, the alarm, logs or analytics.
- **If the room loses it.** A Durable Object can be evicted from memory mid-turn (after a quiet spell, or a deploy). When a room wakes and finds no ink for a turn that is drawing, it sends the drawer's device `{ "t": "inkResend", "turn": "<turnKey>" }`. The drawer's device answers with one `ink` that starts with `["c"]` and redraws its whole easel. The resend is exempt from the rate limit, once per wake.
- If the drawer's device is gone too, the drawing is gone. The turn goes on with a blank easel.
- A resend bigger than the 8 KB client limit goes as several `ink` messages, the first starting with `["c"]`. **(call)**

## 7. Drawing smoothly, on every device

The main thread does UI only (`docs/main-thread.md`). Drawing at 60 fps or better is a hard requirement: 120 on the drawer's ProMotion phone, 60 on the TV.

- **The drawer's own lines** are drawn locally from touch input on the frame they happen. They never wait for the server.
- **Rendering on every client:** finished strokes are flattened into one bitmap layer. Only the stroke in progress is a live path. That keeps the cost per frame flat however much is on the easel. Lines are smoothed with quadratic curves through the midpoints of the points.
- **Encoding and decoding** of ink, and redrawing a whole `inkSync` into the bitmap, happen off the main thread: the socket layer on iOS and tvOS, a worker on the web. The main thread gets plain point arrays and appends them.
- **iPhone and iPad:** our own canvas, not PencilKit. PencilKit only gives up a stroke once the finger lifts, so it can't stream one as it is drawn, and its ink wouldn't match the web. Apple Pencil works as a finger does. Pressure is ignored. **(call)**
- **Apple TV:** the easel is a SwiftUI view backed by layers, inside the TV shell. Not SpriteKit.
- **Web and the browser TV page:** a 2D `<canvas>` sized to the device's pixel ratio, drawn once per animation frame from the points that came in.
- **Tests:** the iOS frame-rate test and the web `e2e/main-thread.spec.ts` gates get a drawing case. A scripted finger draws for 10 seconds on the drawer's phone, and the TV draws the stream. No frame over budget, no main-thread hang.

## 8. Privacy facts **(JD: drawings are ephemeral)**

### 8.1 What happens to a drawing

- It goes from the drawer's device to the room's server and on to the room's one TV. It is held in the room's memory until the turn ends, so a TV that reconnects can show it. Then it is dropped.
- It is never written to disk, logged, kept in a report, backed up, or sent to any other company.
- No other phone gets it. There is no save, share, export or gallery anywhere. A report about a table (the kid-safety report) carries no drawing.
- Guesses are spoken in the room. Pounce never hears them: no microphone is used.

### 8.2 What changes in the docs (in the server PR)

- **Privacy policy** (`apps/play-api/src/http/privacy.ts`). One line under what we collect: "Drawings in Purrtrait go from the drawer's phone to the table's TV through our server, which keeps them only until the turn ends. They are never saved, shown on another phone, or shared." In the children's section: "A child's drawings show only on the table's TV and are gone when the turn ends."
- **App Store privacy answers** (`docs/privacy/app-store-label.md`). No new box is ticked. Under User Content, the "Other User Content" row (already Yes) adds "drawings in Purrtrait, kept only until the turn ends". Photos or Videos and Audio Data stay No: a drawing isn't a photo, and no microphone is used. Messaging and Chat stays No: nothing is typed. User-Generated Content in the age rating stays Yes, with drawings added to its reason. The manifest gets no new type, and `privacy-label.test.ts` keeps passing.
- **Retention policy** (`docs/privacy/retention-policy.md`): drawings are kept in memory only, until the turn ends.
- **Notice to parents** (`/privacy/kitten-notice`). It lists what is collected under a parent's consent, and consent doesn't change for this game, so its list doesn't change. It adds one sentence: "Children can draw in Purrtrait; drawings show only on the table's TV and are never kept." The consent spec says changes to the notice's substance go back to counsel. This sentence adds no collection, but **JD decides whether counsel reads it before it ships.** Until then the server PR changes the policy and the label, and the notice change waits in its own PR.
- **App Review notes** (`docs/app-review-notes.md`): Purrtrait needs a TV, the Apple TV app or the browser TV page; how a reviewer plays it with one phone and the TV page in a browser; and the drawing facts above.

## 9. Kids under 13 **(JD: kids draw by default)**

- A kitten device draws and guesses like anyone else. No consent is needed to play, as with every table game.
- Why that is safe enough: nothing is typed. A child's drawing goes only to the TV in the room, and is gone when the turn ends. The words are family-friendly by construction (§4.5).
- A kitten device gets Easy words only when it draws. **(call: a younger drawer shouldn't be stuck on "whisper")**
- Kittens still can't type a name or a table name. Names at a Purrtrait table follow today's rules.
- The consent condition that a child's information is never disclosed holds: the only place a drawing appears is the TV of the room the child is in.

## 10. The module and the room

### 10.1 The module

`src/games/purrtrait.ts` exports `purrtrait: GameModule<...>` with id `purrtrait`, `minSeats: 2` and `maxSeats: 10`. It is pure and deterministic, as the other games are. The rules engine lives in `src/purrtrait/`.

- **Options:** `{ timer: 45 | 60 | 90 }`, through `defaultOptions` and `parseOptions`, as Birdwatch's rule set is.
- **Phases:** `choosing` (the drawer picks a word), `drawing`, `reveal` (the word on the TV for a few seconds, through `betweenAction`), and `over`.
- **Actions** (sketch, the builder may refine):

  ```ts
  type PurrAction =
    | { type: "choose"; level: "easy" | "tricky" }
    | { type: "gotIt"; seat: Seat }
    | { type: "giveUp" }
    | { type: "timeUp" }      // the room only
    | { type: "nextTurn" }    // the room, after the reveal
    | { type: "forfeit" };
  ```

- **Hidden information:** only the drawer's seat's view carries the two choices, and only the drawer's device (§10.2) gets the word after the pick. Every other view, the screen's included, carries the group, the timer, the drawer and the scores. The word goes to everyone in the turn's last event, at the reveal.
- **Time.** Modules have no clock, so the room owns the turn timer. Two new optional hooks: `turnLimitMs(s)` says how long the current phase may run (10 seconds to choose, the table's timer to draw), and `timeUpAction` says what the room applies when it runs out. The room sets its alarm for it, as it does for bots. Cat Tower, Tuna Tiles and Birdwatch don't declare them, so nothing changes for them.
- **Pausing.** While the table has no screen connected (after the TV's 10-second grace), the room stops the turn's clock and the view says `paused: true`. Phones show "Waiting for the TV". The clock runs again when the TV is back. A table that stays paused for 30 minutes ends, with the scores as they stand. **(call)**
- **Views carry time** as `remainingMs` at the snapshot plus `paused`. Clients count down locally.
- `botAction` and `fallbackAction` are required by the interface but never used for drawing, since there are no bots. `fallbackAction` is `giveUp` for a drawer, so a stuck turn can always end.
- `progress` is each seat's score and `progressKind` is `"score"`. The live table is off for this game anyway (§5.1).
- `endsTurn` is true when a drawer's turn ends, so streaks count drawing turns as they count other turns. **(call)**

### 10.2 The room

New room behaviour, all keyed on the game, not on any flag a client sends:
- Purrtrait rooms are made only by a screen (§5.1).
- Near keys, the admission check, and refusing screen links, seat moves, invites and pushes (§5.1, §5.2).
- The `ink` relay, `inkSync`, `inkResend` and the in-memory ink (§6).
- The turn clock and its pause (§10.1).
- Start needs 2 seats filled and the TV connected.
- The host removes a seat from the seat menu: a new `remove` message, `{ "t": "remove", "seat": n }`, host only, at a Purrtrait table only. In the lobby the seat opens. In a game the seat is skipped from then on, as if it had left. **(call: other games keep retire and forfeit)**
  - A removed device and its player go on the room's `removed` list and stay out: no seat, no reconnect, not even with a fresh near key. Play again carries the list to the new table. **(call)**
  - The host is the first phone to sit, as at every TV table. At a Purrtrait table, when the host leaves or is removed, the role passes to the next seated person in seat order, so someone can always remove a player. **(call)**
- **The drawer's device.** A seat can be controlled by more than one device: a signed-in parent on a phone and the family iPad, say. The drawing turn belongs to one device: the first one to send `choose`. From then on, only that device gets the word, sends ink, gets `inkSync` on reconnect and is asked for `inkResend`. Every other device gets the guesser's view. Before the pick, every device that controls the seat shows the two words, behind the curtain on a shared phone. That small case is accepted. **(call)**

### 10.3 Rollout

- It follows the Tuna Tiles spec §9 and Birdwatch §8. `GAMES` lists `purrtrait` in dev and tests. The app sends `x-pounce-games: cat-tower,tiles,birdwatch,purrtrait` once it draws the game. An app that can't draw it never meets a Purrtrait table: joining gets a 404 and the table is left out of lists.
- Snapshots carry `gameId: "purrtrait"` and a `purrtrait` view. Events are wrapped as `{ "kind": "purrtrait", "event": … }`.
- The server merges with the flag off in production. It turns on once the web player and the browser TV page draw the game, so the web can play it first, as Birdwatch did. The iPhone app and the Apple TV app follow in the next TestFlight build after 1.3, and the websites change per AGENTS.md: they claim the game only once people can play it.

## 11. The screens

Every screen below is a whole-screen design. Copy is terse. No emoji. Each is checked on iPhone SE, a large iPhone, iPad portrait and landscape, the largest text size, a 1080p TV, and the browser TV page at 1920 × 1080 and 1280 × 720.

### 11.1 The TV

```
┌──────────────────────────────────────────────────────────┐
│  Mom   5        ┌───────────────┐        Ava is drawing  │
│  Dad   4        │               │                        │
│  Ava   3        │               │             0:42       │
│  Leo   2        │    easel      │                        │
│  Mochi 1        │    (3:4)      │           Animal       │
│                 │               │                        │
│                 └───────────────┘                        │
└──────────────────────────────────────────────────────────┘
```

- The easel is in the middle at full height, on a stand or in a frame in the app's loud cartoony style, never beige.
- Left: every player's cat, name and score, the drawer's highlighted. Right: who is drawing, the timer, the word's group.
- When someone gets it: their cat jumps, both scores tick up, and the word shows big across the easel.
- **The lobby** shows the join QR big, with the 8-character code under it and "Scan to join". Cats walk on as people sit. "Press Start on any phone."
- **Game over:** the scores, the winner's cat, and "Play again on any phone".
- **Home:** Purrtrait is a poster beside the other games, "2 to 10 players".

### 11.2 The drawer's phone

```
┌───────────────────────┐
│ PIZZA          0:42   │
│ ┌───────────────────┐ │
│ │                   │ │
│ │      easel        │ │
│ │      (3:4)        │ │
│ │                   │ │
│ └───────────────────┘ │
│ ● ● ● ● ● ● ● ● ○     │
│ ▪ ■ █   Undo  Clear   │
│ [ Got it ]  Give up   │
└───────────────────────┘
```

- First, two big cards: the Easy word and the Tricky word, with their points. Tap one.
- Then the word stays at the top with the timer, the easel fills the middle, and the colours, widths, Undo and Clear sit under it. Got it opens a sheet of everyone's cats and names. Tap the one who got it.
- On a shared phone, the curtain comes down before the words show, and goes back up at the reveal.
- iPhone SE is the hard case. The builder fits it there first, and may move the tools into one row or the sheet.

### 11.3 Everyone else's phone

- "Look at the TV", whose turn it is, and the player's score. On the turn before theirs, "You draw next".
- No drawing, no word, nothing to type.

### 11.4 Teaching

- How to play has a Purrtrait page, with a short video once there is footage.
- Tips, one at a time: on the first word pick ("Pick one to draw"), on the easel ("No letters or numbers"), on Got it ("Tap who said it first"), and on a guesser's phone ("Guess out loud").

## 12. Testing **(call)**

- **Rules:** word picks, scoring for Easy and Tricky, the turn order over two rounds, ties, a drawer leaving, removing a seat, the game ending below 2 players, and no word twice.
- **Time:** the choose and draw timers, time up, pausing without a screen and resuming.
- **Same room:** a Purrtrait room can't be made without `screen`, a join without a near key or with a stale one is refused, a member reconnects without one, a removed device and player stay out (in the rematch too), the host role passes on, the host can swap in a new TV and nobody else can link one, seat moves are refused, the drawing turn belongs to the device that picked the word, `/j/` has no join, no invite or push goes out for the room, and only the screen's snapshot carries `near`.
- **Ink:** the shape check, the caps and `easel_full`, the rate limit, only the drawer's device may send, relay to the screen and the drawer's own sockets and to no other socket (a property test over random rooms), `inkSync` after undo and clear, `inkResend` after a wake, and that nothing about ink is ever in storage (a test that reads every stored key after a game).
- **Hidden word:** no view or event carries the word to anyone but the drawer before the reveal.
- **Fixtures** pin the view and the ink messages for the Swift and web decoders.
- **Smoothness:** the drawing cases in the frame-rate and main-thread gates (§7).
- **Cross-platform, before switching it on:** the browser TV page and the Apple TV app (simulator) as the easel, with an iPhone app, a browser phone and a shared phone at one table, playing a full game. The drawing shows on the TV while being drawn. A TV reload mid-turn comes back with the drawing.

## 13. Order of work

1. **Server:** the module, the words, the turn clock, near keys and admission, the ink relay, `remove`, fixtures, the privacy policy and label lines, and tests. Flag off in production.
2. **Web**, once step 1 has merged: the TV page easel and lobby, the drawer's phone, the guesser's phone, the shelf, tips and How to play. Then the flag goes on in production.
3. **iOS and Apple TV**, alongside step 2: the drawer's canvas on iPhone and iPad, the guesser's phone, the shelf, the Apple TV easel and lobby, tips, How to play, and the frame-rate gates.
4. **The notice to parents** in its own PR, once JD says whether counsel reads it.

## 14. Left to the builder

- The easel's frame, the palette's colours, the cats' reactions and the sounds, in the established loud style.
- Exact layouts on every size, inside §11.
- The words themselves, inside §4.5.
- The tips' wording, kept terse.
- Small tuning of the ink numbers in §6.3, if the tests show a better balance between smoothness and size.
