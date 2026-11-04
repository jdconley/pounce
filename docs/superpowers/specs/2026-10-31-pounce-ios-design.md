# Pounce iOS app (`apps/play-ios`) — Design

Date: 2026-10-31 · Owner: JD Conley (Conley Chaos LLC) · Status: approved (JD, via lead session, 2026-10-31)

Parent spec (the authority on product and rules): `docs/superpowers/specs/2026-10-31-pounce-cat-tower-design.md`. This document designs the iOS client for milestone **M1 — Play together** against the finished server in `apps/play-api`. Where this doc and the parent spec disagree on product, the parent wins; where they disagree on client mechanics, this doc wins.

Marks: **(JD)** = decided by JD; **(call)** = designer call made while writing this, open to override; **(server)** = fixed by the server as built.

## 1. Intent

The first real game is JD in the recliner and their wife on the Lovesac at the end of a long day, each on their own phone. JD sends an invite; she smiles because it was thoughtful; within a minute she is either groaning at a bad draw or gloating because she went out on phase 1. **The app is for her.** (JD)

So the client must make three moments great:
1. **The invite arrives** — a cat-art link card in Messages; one tap lands her at JD's table.
2. **The draw** — a quick, dramatic card flip that makes a good or bad card feel like an event.
3. **Laying down a phase** — a loud, showy celebration everyone sees, the cat leaping up the tower.

Everything else should get out of the way. Common case is two people, two phones, same room; pass-and-play and remote family come second but must work in the same game. (call, from JD's story)

**Success:** JD, their wife and family playing on TestFlight, mixing seat types, and nobody needing words to figure it out.

## 2. Goals, non-goals, anti-goals

**Goals (M1)**
- Full Cat Tower play against `play-api` (protocol 1): create, join by code or link, lobby with human / on-this-phone / bot seats, live play with animation, presence, resume, round and game end.
- Pass-and-play curtain for multiple seats on one phone.
- "Your turn" push; tapping it opens that table.
- Universal links `https://play.conleychaos.com/j/<CODE>`.
- Move a seat to another phone (server supports it).
- Art style D, juicy BTD6-like motion, near-zero CPU at idle.
- VoiceOver, Reduce Motion, color-blind-safe cards.

**Non-goals (M1)** — Sign in with Apple, groups, push invites, Nearby list, nudges, reactions, history/stats, Kitten/Alley Cat, bot-takeover vote (all M2, need server work). iPad layout, landscape, Mac, offline play, localization beyond English VoiceOver strings, iOS CI, analytics. A rematch button that keeps everyone together (needs a server change; see §15). (call, per parent spec milestones)

**Anti-goals** — text-heavy UI; emoji anywhere (all icons are our art) (JD); beige/muted/storybook art (JD rejected); anything resembling the trademarked original's name, card layout, or red/blue/green/yellow scheme; showing any hidden information; a table that burns battery while nothing moves.

## 3. Constraints

- iOS 26+, iPhone, portrait only. Swift 6 (strict concurrency), SwiftUI shell, SpriteKit table. Xcode 27 on JD's Mac. (JD / parent spec)
- Bundle `com.conleychaos.play`, team `B222J9J7B8`, display name "Pounce" (code name; only the display name carries it). (server: AASA already lists `B222J9J7B8.com.conleychaos.play` for `/j/*`)
- **No third-party Swift packages.** Apple frameworks only (SwiftUI, SpriteKit, Core Haptics, AVFoundation, LinkPresentation, CoreImage, Network, Security, UserNotifications). (call — keeps the public repo simple and supply-chain-free)
- The server is authority. The client may pre-validate groups only to drive glow hints.
- Server not yet deployed (needs GitHub secrets). Development runs against `wrangler dev` on `http://localhost:8787`; TestFlight needs the deploy.
- Server contract (from Plan 1 follow-ups): apply every `snapshot` even when its `seq` equals the last seen; `room_closed` is terminal and the socket may stay open; `hands` keys are strings (`"0"`); upload the APNs token every launch; snapshots carry `protocol: 1`.

## 4. Art direction — style D "Loud Toy" (JD)

Reference: `apps/play-ios/Art/style-samples/chosen-d-loud-toy.png` (+ its exact prompt). Mock screens: `apps/play-ios/Art/mockups/m0-table … m5-celebrate.jpg`.

- Bloons TD6 / Supercell energy: glossy 3D-rendered cartoon, chunky rounded shapes, very thick dark outlines, rim light, saturated candy palette — violet, hot magenta, electric teal, sunny orange, sky blue. No beige, cream, pastel. (JD)
- **Cards:** white face, thick glossy violet rim, huge chunky outlined numeral top-left, coat glyph under it, big-eyed cat face center. Coats: orange tabby (stripe glyph), tuxedo (bow-tie glyph), calico (three-patch glyph), gray (paw glyph). Coat is carried by cat pattern + glyph, never color alone. Yarn = glowing magenta yarn ball with sparkles; Cucumber = goofy screaming cucumber. Card back: violet with a big paw. (JD picked D; glyphs per parent spec)
- **Table:** top-down living room at night, round magenta/teal/orange rug with a big paw. (call, from mock m0)
- **Player colors:** avatar rings use our palette only (violet, magenta, teal, orange, sky, lime) — never the red/blue/green/yellow set the first mock drifted toward. (call)
- **Type:** one bundled chunky display font (OFL, e.g. Lilita One) for numerals, names and the room code, always with a thick dark outline. (call)
- **Words on screen:** player names, room code, numerals. Everything else is a picture. (JD)

## 5. Screens and flows

Mobbin research (35 references) is in the Mobbin collection **"Pounce"** (https://mobbin.com/collections/cf6612b6-7558-4559-9a29-44bfb7f15869) and summarized in the session notes; key references are cited inline. Mobbin had almost no real card games, so table/hand/curtain patterns come from the closest analogs.

### 5.1 Map

```
Launch ─┬─ first launch ──► Pick your cat ──► Home
        └─ otherwise ─────────────────────────► Home
Home ──► New game ──► Lobby (host) ──► Table ──► Game over ──► Home
Home ──► Join ──► Lobby (guest) / Table (rejoin)
Universal link /j/CODE ──► (Pick your cat if first launch) ──► Lobby / Table
"Your turn" push ──► Table
Table ⇄ Pass curtain (multi-seat phones) · Table ⇄ Table menu sheet
```

### 5.2 Pick your cat (first launch only)
Mock: none. Refs: Spotify Kids "Pick your character" (big hero over carousel + one check bar), Discord avatar grid.
- Big hero of the selected cat (idle pose, blinking) over a 4×2 grid of the **8 cats** (server `cat` 0–7). (call: roster = orange tabby, tuxedo, calico, gray, black, white fluffy, siamese, tortie)
- One big name field over the cat, **prefilled with a random cat-ish name** and a dice button to reroll (Mobbin had no good guest-name screen; this is the suggested pattern). 1–20 chars (server).
- One big check button. Silently mints the device (`POST /v1/devices`) in the background; if offline, the check button waits with a yarn spinner and retries.
- Creates the phone's **owner person** (UUID generated on device).

### 5.3 Home
Mock: `m1-home.jpg`. Refs: Duolingo Chess hub (one hero tile + two fat CTAs), Hinge "your turn / their turn" ordering, Abode game tiles.
- Hero tile: Cat Tower (tower with a cat on top). Under it two fat pills: **New game** (paw +) and **Join** (keypad).
- **Your tables** row: one card per table this device sits at, from `GET /v1/devices/me/tables` (code, status, yourTurn, updatedAt) merged with a local cache of each room's last snapshot (seat cats, names, phase) so cards can show cats. **Your-turn tables first**, bouncing and glowing orange with the waiting player's cat; others dimmed with the current player's cat in its presence pose. Finished games show a little trophy and drop off after a day. (call)
- Owner's cat sits bottom-left on a cushion: tap → **People on this phone** sheet (Spotify Kids "Who's listening?" pattern): edit owner name/cat, add or edit local people for pass-and-play.
- Small gear: sound, music, haptics toggles. (call)
- Refreshes tables on appear, on foreground, and when a push arrives.

### 5.4 Join
Mock: `m2-join.jpg`. Refs: Kahoot join PIN, Paired code boxes, Duolingo ABC chunky keypad.
- Five chunky letter tiles + a custom 3D keypad containing **only** the room-code alphabet `BCDFGHJKLMNPQRTVWXZ2346789` (server). Auto-submit on the 5th character.
- Bad code (socket upgrade 404) → tiles **shake** and clear, gray cat shakes its head. No error text.
- Valid code → Lobby (guest) if `status == lobby`, Table if the device already holds a seat, otherwise a "table's full / already started" art card (curled-up cat on a full rug) with one home button. (server: claim only works in the lobby. The server would stream public snapshots to a seatless device, but M1 has no spectating — **client choice**, call)
- A QR shown on the host's lobby opens the same universal link via the system camera, so the keypad is the fallback, not the main path. (call)

### 5.5 Lobby (one screen for host and guests)
Mock: `m3-lobby.jpg`. Refs: Flo "waiting for partner" (code huge), Airbuds empty slots, Kahoot QR toggle.
- Top: room code huge + **Share** button + QR toggle.
- Middle: the rug with **six cushions** = the server's six lobby seats (server: seats 0–1 start `open`, 2–5 `closed`). Each cushion shows:
  - a cat (human seat) with a corner badge — this phone / another phone — and presence pose;
  - the House Cat with a gear badge (bot);
  - a pulsing **+** (open: waiting for someone to join);
  - a faint dashed outline (closed).
- **Tap an empty/closed cushion** → a radial bubble of four icons: **Invite** (`configure open` + share sheet), **On this phone** (`configure open` if needed, then pick a local person → `claim`), **Bot** (`configure bot`), **Remove** (`configure closed`).
- Tap your own cat → swap person (leave + claim) or stand up (`leave`).
- **Start** (big orange play pill) is shown to every seated device (server lets any seated device start). Disabled while any seat is `open` or fewer than 2 players; when disabled, the blocking cushions pulse (the wordless reason). (server: `seats_open`, `not_enough_players`)
- **Creating:** `POST /v1/rooms {game:"cat-tower"}` → code → connect → auto-`claim` seat 0 with the owner. (call)
- **Table name:** every room has a name everyone sees (`RoomView.name`): a cat-themed default from the room code ("The Sleepy Sardines") until someone renames it. It sits at the top of the lobby; the host or anyone seated taps it to rename the table (`rename {name}`: trimmed, spaces collapsed, 1-30 code points, no control or bidi characters; refused with `not_seated` or, after the game, `game_over`). The table menu shows it with the same rename, and Home cards, game over, the share text and the your-turn push carry it. The room code stays on the lobby and under the name on Home cards for joining by code.
- **Joining by link/code:** connect → if no seat of mine, auto-claim the **first open seat** with the owner, so the invitee's path is literally one tap. They can swap seats/person after. (call — this is the "she taps and is at your table" moment)

### 5.6 Share / invite
Refs: yope invite card, Apple Games invite bubble, Peerspace share sheet with preview.
- Share sheet item = the link `https://play.conleychaos.com/j/<CODE>` with `LPLinkMetadata` (title "<table name> - Cat Tower", host cat image) so the share-sheet header shows cat art, plus the invite text "Come play Cat Tower at <table name>! Room code <CODE>".
- **The Messages bubble on her phone is built by Messages fetching the page**, so the `/j/` landing page needs Open Graph tags and an image. **Server follow-up in Plan 2:** add `og:title`, `og:description`, `og:image` (a static PNG of the room card art served by the Worker) to the share page. (call — this is the invite moment JD described)

### 5.7 Table (the game)
Mock: `m0-table.jpg`. Refs: Duolingo chess board (opponent top, you bottom, points pop off the move), Stardust fanned deck (lift-on-select), Duolingo ABC room scene, Numo ladder.

Layout, top to bottom (portrait):
1. **Opponents bar:** each other seat's cat in a ring, in turn order starting after you; card-count bubble; presence pose (awake alert / away curled / asleep Zzz); badges for bot, skip-pending (tiny cucumber), and laid-down (tiny check-paw). The current player's ring pulses with a paw marker.
2. **Tower** on the left edge: 10 shelves with number badges, each player's cat head on its current phase. Tap to open the scoreboard (cats + scores + phases, numbers only).
3. **Rug** center: draw pile (card backs, count implied by stack height) and discard pile (top card face up). Around them, a **laid zone**: each player who laid down has their groups shown as small overlapped card rows under a tiny version of their cat. While dragging a card, the laid zone enlarges and valid hit targets glow.
4. **Phase goal pictogram** above your hand: e.g. phase 2 = [3 cards + "same number" glyph] [4 cards + "in a row" glyph]; phase 8 = [7 cards + coat glyph]. Before you lay down, these are also the **lay-down trays** (§5.8).
5. **Your hand** at the bottom: fanned arc, lift-on-select, big readable cards. A small sort toggle (by number / by coat) and free drag-to-reorder.
6. A small paw button top-right → **Table menu** sheet: sound, haptics, move my seat, home.

Turn flow, all by direct manipulation, every action also reachable by tap-tap (select a card, then tap a target) for accessibility:
- **Your turn starts:** hand bounces up, the two piles glow (draw step). Drag from deck or discard to your hand, or tap a pile. Discard glow is off when the top card is a Cucumber (rules).
- **Play step:** the trays glow; legal moves glow; illegal drops snap back with a "nope" wiggle.
- **Discard:** drag a card to the discard pile — this ends the turn. **A Cucumber is aimed by dropping it on an opponent's cat** (only seats not already pending a skip glow). If no seat is targetable it just discards. (server rules)
- **Others' turns:** their actions animate on your table from server events (§7); your hand dims slightly but stays visible (single-seat phone).
- **Reconnecting:** a small unraveling-yarn indicator in the corner; input is disabled until the next snapshot. No text. (call)

### 5.8 Laying down and hitting
- Trays appear in the server's phase order (e.g. phase 2: set tray, then run tray), because `layDown` groups must be sent in that order (server `matchPhase`).
- Drag cards from hand into the goal trays. Each tray validates live with the same rules as the server (group kind/size, at least one natural, no Cucumbers). A valid tray turns gold; when **all** trays are valid a big paw **Lay down** button pops — tap sends `layDown`. Cards in trays return to hand if you leave the play step without laying down. (call: explicit confirm prevents accidental lay-downs)
- Runs auto-sort ascending in their tray. A Yarn in a run sits where the client's placement puts it; dragging the Yarn to another slot changes `runStart`. Without an explicit move, the client sends the lowest valid start (the server's default). (server: `runStart` optional)
- After laying down (this round), drag any card onto any glowing laid group (yours or others') to `hit`.
- Going out (empty hand by discard or by hit) triggers the round-over sequence from server events.

### 5.9 Pass-and-play (multi-seat phones)
Mock: `m4-pass.jpg`. Refs: Amazon Alexa "Hand your phone to Sam", Lapse hold-to-view, Tolan spotlight.
- A phone controlling **one** seat never sees the curtain.
- A phone controlling **two or more** seats: whenever the turn moves to one of its seats and that seat isn't the one currently revealed, the table is covered by the **curtain**: dark violet stage, spotlight on that person's cat, their name once, and a glowing paw button. **Press and hold ~0.6 s** to reveal (hold, not tap, so the previous player can't skip into it by accident). (call)
- While the turn belongs to a remote or bot seat, a multi-seat phone shows the hand area as face-down cards. Tap one of your local cats (shown along the bottom) → curtain for that person → hold to peek; their hand hides again when the turn changes or after they tap away. (call)
- The curtain is a SwiftUI overlay **and** the hand nodes for unrevealed seats are not created at all, so nothing private renders under it.
- When the round starts (new hands for everyone), the curtain shows for whoever moves first if it's a local seat.

### 5.10 Round over and game over
Mock: `m5-celebrate.jpg`. Refs: Greenlight "Challenge Complete", Finch three stars, Duolingo versus intro.
- **Round over** (`roundOver` event): your own leftover cards flip and **points pop** off each player's cat one by one (the server never reveals other seats' leftover cards — `roundOver` carries only `points[]` — and M1 doesn't add that; call); then cats who advanced **leap up a shelf** in sequence (anticipation squat, arc, squash land, star burst, gold shelf badge pops in). The server auto-starts the next round after **6 s** (server), so the sequence fits in ~5 s and then the new deal animates.
- **Game over** (`gameOver`): the winner's cat on the top shelf with a crown, sunburst and confetti; shared wins show both. Buttons: **Home** and **New game** (a fresh lobby; others need the new link — see §15 rematch follow-up).
- **Versus intro** before the first deal: all cats slide in on diagonal color slashes, ~1.2 s. (call)
- **The first deal has no events** (server): `start` sends only a snapshot (round-1 `roundStarted`/`skipped`/`turn` are not broadcast). The client detects the `lobby → playing` transition in snapshots and plays the versus intro + deal from it; an opening-Cucumber skip in round 1 is shown by the skip badge in the snapshot. Later rounds arrive as `roundOver` … `roundStarted` events followed by a snapshot at the same seq.

### 5.11 Move my seat
Server: `moveSeat` returns a one-time 6-character code valid 10 minutes; another device sends `claimMove` over that room's socket.
- Table menu → **Move my seat** → pick which seat (if several) → shows a QR + share button for `https://play.conleychaos.com/j/<CODE>?move=<MOVECODE>`, plus the 6 code tiles.
- The other phone opens the link (camera or share) → connects to the room → sends `claimMove` → the seat is now on that phone; the old phone's view updates via snapshot. (call: reuse the universal link path; the AASA `/j/*` pattern already covers the query)
- `bad_code` → shake; `too_many_attempts` → sad cat, home.

### 5.12 Other states (all art, no text)
- **Room closed** (`room_closed`, terminal): a cat asleep on an empty rug, one home button; the table is removed from Home.
- **Bot stalled** (`bot_stalled`): House Cat with a tangled yarn; table frozen; home button. (rare)
- **Server not configured / unreachable**: cat looking at an unplugged yarn ball; retry button.
- **Push priming** (§10).

## 6. Client architecture

### 6.1 Project layout (call)

```
apps/play-ios/
  project.yml                 XcodeGen spec (source of truth); Pounce.xcodeproj is generated, gitignored
  scripts/bootstrap.sh        brew-installs xcodegen if missing, generates the project
  scripts/testflight.sh       archive + export + upload (local, not CI)
  Pounce/                     app target
    App/                      PounceApp, AppModel, routing, deep links, push delegate
    Shell/                    SwiftUI screens: PickCat, Home, Join, Lobby, PassCurtain, overlays, sheets
    Table/                    SpriteKit: TableScene, nodes, layout, animation director, effects
    Design/                   palette, font, PillButton, pop/wiggle modifiers, Haptics, Sound
    Resources/                Assets.xcassets (+ .spriteatlas folders), fonts, sounds, String Catalog
    Pounce.entitlements, Info.plist
  PounceKit/                  local Swift package: all logic that doesn't need UIKit/SpriteKit
    Sources/PounceKit/
      Protocol/               Codable mirrors of protocol.ts / view.ts / engine events
      Rules/                  card decode, points, groups, phases (mirror of server rules, for hints)
      Net/                    APIClient (HTTP), RoomSocket (WebSocket + reconnect), Transport protocol
      Store/                  RoomStore (reducer), TableModel, animation intents
      Identity/               Keychain device credential, local people, table cache
    Tests/PounceKitTests/     swift test, fast, no simulator
  PounceUITests/              XCUITest smoke test against wrangler dev
  Art/                        style-samples/, mockups/, prompts/, raw/ (gitignored), tools/
```

- **XcodeGen** keeps the project reviewable and agent-editable; the generated `.xcodeproj` is not committed. JD runs `scripts/bootstrap.sh` once (or after pulling). (call)
- `PounceKit` holds every rule and state transition so it's tested with `swift test` in seconds. The app target is thin glue + rendering.
- Swift 6 language mode, strict concurrency. Stores are `@MainActor @Observable`; networking is `async`/`await` with actors.

### 6.2 State flow

```
RoomSocket (actor) ──ServerMessage──► RoomStore (@MainActor)
                                         │ reduces into TableModel (the latest truth)
                                         │ emits TableIntents (animation steps) in order
                                         ▼
           SwiftUI shell observes RoomStore     TableScene consumes TableIntents, then reconciles to TableModel
                                         ▲
User gesture ──► TableScene/Shell ──► RoomStore.send(ClientMessage) ──► RoomSocket
```

- **TableModel** = RoomView + derived data (my seats, revealed seat, glow sets). It is always exactly what the last snapshot + events say.
- **TableIntents** are per-event animation steps ("seat 2 drew from deck", "seat 0 discarded card 17 at seat 3"). The scene plays them in order on one timeline, then calls `reconcile(model)`, which is idempotent and snaps every node to the model. A snapshot with nothing to animate is just a reconcile. This keeps animations pretty and state always correct.

## 7. Networking and reconnect

### 7.1 HTTP (server routes as built)
| Route | Use |
|---|---|
| `POST /v1/devices` → `{deviceId, token}` | First launch (and if the token is ever rejected with 401). Token + deviceId in Keychain (`AfterFirstUnlockThisDeviceOnly`). |
| `PUT /v1/devices/me/push {apnsToken}` | Every launch after APNs registration (contract), and whenever the token changes. |
| `GET /v1/devices/me/tables` → `{tables:[{code,name?,status,yourTurn,updatedAt}]}` | Home. `name` is absent only for tables last reported before tables had names. |
| `POST /v1/rooms {game:"cat-tower", name?}` → `201 {code}` | New game. Without `name` the room gets its default name. |
| `GET /v1/rooms/<CODE>/ws` (WebSocket, `Authorization: Bearer <token>`) | The live room. 404 = no such room. |
| `GET /healthz` | Debug screen only. |

**Local dev:** `wrangler dev` needs `apps/play-api/.dev.vars` with a throwaway `TOKEN_SECRET` (gitignored), or every `POST /v1/devices` returns 503 `not_configured`; Plan 2's dev-setup task adds a `.dev.vars.example` and a script. (call)

Base URL per build configuration: Debug → `http://localhost:8787` (ATS local-networking exception); Release → `https://play.conleychaos.com`. A launch env var overrides it (simulators, UI tests), and an optional gitignored `Local.xcconfig` overrides the Debug build setting so a real phone can use the dev server through Tailscale (`tailscale serve --https=8443` → `https://gin-and-tonic.tailc8d3c2.ts.net:8443`; the existing :4343 serve is left alone). (call; JD: use wrangler and Tailscale for local testing)

### 7.2 One live socket
The app holds **at most one** room socket: the room on screen (lobby or table). Home uses the tables endpoint. (call — simplest; server pushes cover the rest)

### 7.3 Applying server messages (the contract)
- `snapshot`: check `protocol == 1` (otherwise show "update the app" art and stop). **Apply unconditionally**, even if `seq` equals the last seen; set `lastSeq = seq`; reconcile.
- `event`: if `seq == lastSeq + 1` → apply and animate. If `seq <= lastSeq` → ignore (already covered by a snapshot). If `seq > lastSeq + 1` (gap) → drop it and **reconnect** to get a fresh snapshot (the server sends a snapshot on every connect and never replays events). (call)
- `moveCode`: shown by the Move my seat sheet.
- `error room_closed`: **terminal** — stop reconnecting, close the socket client-side, show Room closed, remove from Home and cache. The server also closes sockets and deletes the room, so **a later connect to a known table returns 404**: a 404 for a code in the table cache or `/tables` means "room closed", while a 404 for a typed code means "bad code".
- `error bot_stalled`: show the stalled state; keep the socket.
- Other `error`: the last pending action failed. Errors are not correlated by id, so:
  - **In play**, the client keeps **at most one `act` in flight** and disables game input until the resulting `event` (game) or `error` arrives; an error rolls back the provisional animation (snap back + "nope" wiggle). (call)
  - **In the lobby**, `claim`/`configure`/`start`/`leave` succeed with a snapshot that looks like any other device's change, so there is no in-flight lock: the UI updates from snapshots, and an error simply "nopes" the cushion or button that was tapped most recently. (call)
  - `presence` gets no reply when nothing changed; never wait on it.

### 7.4 Reconnect
- Reconnect on: socket close/error (not after `room_closed`), app foreground, network path becoming satisfied (`NWPathMonitor`), and event gaps.
- Backoff with jitter: 0.25 s, 0.5 s, 1 s, 2 s, 4 s, capped at 8 s; reset after a snapshot arrives. (call)
- Liveness: `sendPing` every 25 s while foregrounded; two missed pongs → reconnect. (call; **verify** in `wrangler dev` and production that the Workers runtime answers WebSocket pings on hibernated DOs — if not, skip pings and rely on send failures + foreground reconnect.)
- Optimism: none for state. The dragged card animates to its target immediately (provisional), then the server's event confirms (no-op) or an error rolls back. Typical round trip is well under the ~200 ms animation, so it feels instant. (call)

### 7.5 Presence and lifecycle
- `scenePhase == .active` → connect (if a room is open) and send `{t:"presence", state:"active"}` after the snapshot.
- `.background` → send `{t:"presence", state:"background"}`, then close the socket normally. The server marks the device away (then asleep after 5 min) and pushes when a turn starts while not awake. (server)
- Presence is per device: all seats on a shared phone share it. (server)
- **Backgrounding mid-turn:** the server only pushes when a turn *starts* while you're away. If the app backgrounds during one of this phone's turns, the client schedules a **local** "your turn" notification for 10 minutes later (same look as the push), cancelled on foreground. Nobody else can act during your turn, so it can't go stale (except a 7-day room close). (call)

## 8. SpriteKit scene structure

- **Host:** a `UIViewRepresentable` wrapping one `SKView` (not `SpriteView`, for direct control of `isPaused`, `preferredFramesPerSecond = 60`, `ignoresSiblingOrder = true`, `shouldCullNonVisibleNodes = true`). The SwiftUI shell draws overlays (curtain, sheets, round-over buttons) above it. (call)
- **One `TableScene`**, fixed design size 390×844 pt scaled `.aspectFill` with safe-area-aware layout computed by a pure `TableLayout` (in PounceKit, unit-tested) for 2–6 seats.
- **Layer nodes** (zPosition bands): `background` (room) → `rug` → `piles` → `laidZone` → `tower` → `opponents` → `trays` → `hand` → `drag` (card being dragged, above all) → `fx` (particles, bursts, score pops).
- **Node types:** `CardNode` (composited face: rim + coat cat art + numeral sprite + glyph; or Yarn/Cucumber/back), `CatNode` (pose sprite + ring + badges; poses swapped by texture, juiced with actions), `TowerNode`, `PileNode`, `GroupRowNode`, `TrayNode`, `HandNode` (arc layout, lift, reorder).
- **Input:** `TableScene` handles touches; hit-testing chooses drag sources and drop targets from `TableModel` glow sets. All moves go through `RoomStore.send`.
- **AnimationDirector:** queues `TableIntent`s, runs each as an `SKAction` group, tracks running actions/emitters, and drives **render-on-demand** (§9.2).

## 9. Animation language (juicy, low CPU)

### 9.1 Verbs (call — timings are starting points, tuned in playtest)
| Verb | Where | Recipe |
|---|---|---|
| **Pop** | anything appearing | scale 0 → 1.15 → 1.0, 0.22 s, ease-out-back |
| **Squash** | landings, taps | 1.0 → (1.15, 0.85) → 1.0, 0.14 s |
| **Nope** | illegal drop / error | snap back along arc + 3 quick ±6° wiggles, soft thud haptic |
| **Glow** | legal targets | pre-rendered glow sprite, alpha pulse 0.6↔1.0, 0.8 s |
| **Draw flip** | your draw from deck | card lifts, 3D-ish flip via x-scale 1→0→1 swapping texture, 0.3 s, sparkle burst on Yarn, groan wobble on Cucumber |
| **Bat** | any discard | card arcs to the pile with spin, a paw sprite swipes in/out, pile squashes |
| **Cucumber terror** | skip hits a seat | cucumber flies to the target cat; cat leaps up with fur-puff particles and "terrified" pose; 4 pt screen shake 0.2 s (skipped under Reduce Motion) |
| **Lay down** | `laidDown` | cards fly from hand/avatar into the laid zone one by one (40 ms stagger), each lands with squash + star particles; the tray badge goes gold |
| **Hit** | `hit` | card arcs onto the group, group bumps |
| **Shelf leap** | phase advance | anticipation squat 0.08 s → arc 0.35 s → squash land → star burst + gold badge pop |
| **Points pop** | round over | "+25"-style numerals pop up and fade off each cat, staggered |
| **Turn handoff** | `turn` | outgoing ring shrinks, incoming ring pops and pulses; your turn also bounces your hand |
| **Reshuffle** | `reshuffled` | discard cards riffle into the deck with a whoosh |
| **Win** | `gameOver` | sunburst, confetti emitter (yarn bits, stars, fur puffs), crown drop, cat celebrate pose |

Haptics (Core Haptics, pre-built patterns): light tick on pickup, medium on drop, crisp success on lay down, heavy thump on cucumber hit, celebration pattern on shelf leap and win. Sound: short punchy SFX per verb (CC0 / licensed or generated), optional light music loop, mute toggle in Home gear and Table menu. (parent spec)

### 9.2 Low CPU rules
- **Render on demand:** `SKView.isPaused = true` whenever the AnimationDirector has nothing running and no touch is active. Unpause on touch-down, on an incoming intent, or for scheduled idle flourishes. Target: ~0 % CPU on an idle table. (parent spec)
- **Idle life without a loop:** a cat blink or tail flick fires as a brief burst every 5–9 s for the first 60 s after the last change, then the table goes fully still. (call)
- Textures only: no `SKShapeNode` at runtime, no `SKEffectNode`/Core Image filters; glows and shadows are pre-rendered sprites. Few, short-lived emitters with capped birth rate; preloaded atlases; card faces composited from shared atlas parts.
- 60 fps cap (no 120 Hz). Verify with Instruments on the oldest supported iPhone (iPhone 11): idle ≈ 0 %, animations hold 60 fps.

## 10. Push notifications

- Payload (server as built): `aps.alert = {title: <name of the person whose turn it is>, body: "Your turn at <table name>"}`, `sound: default`, `thread-id = code`, collapse id = code, top-level `code`. Using the person's name means a shared phone shows *whose* turn it is.
- **Priming (call):** don't ask at first launch. Ask the first time this device is in a started game with a seat on another phone (i.e. a turn could happen while you're away): a cat holds up a mock "your turn" banner; tap the paw → system prompt. Refs: Duolingo "Remind me", Zocdoc mock notification. If declined, a small bell on Home re-offers it once.
- `registerForRemoteNotifications` every launch; upload token every launch (contract) and on change.
- Tap a notification → open that table by `code` (cold start or warm). Foreground: if that table is on screen, suppress the banner (the table already shows it); otherwise show it and refresh Home.
- **Sandbox vs production:** the server sends to production APNs (correct for TestFlight). Debug builds from Xcode get sandbox tokens, so pushes won't arrive in dev builds — test push on TestFlight builds. (server note)

## 11. Universal links

- Entitlement `applinks:play.conleychaos.com`; the server already serves AASA for `/j/*` with this app ID.
- Handle in `onOpenURL` / `onContinueUserActivity`: `/j/<CODE>` → join flow; `/j/<CODE>?move=<MOVECODE>` → move-seat claim. Validate the code against the alphabet/length before connecting.
- First launch from a link: Pick your cat, then continue straight into the join.
- Without the app, the page shows the code and a TestFlight link (server, done).
- **Local testing:** universal links only verify against the real domain, so Debug builds also accept `pounce-dev://j/<CODE>[?move=<M>]` (opened with `xcrun simctl openurl`). Release builds never register that scheme. (call)

## 12. Identity and local data

- **Device:** deviceId + token from the server, Keychain. Never shown.
- **People on this phone:** owner + any local people (UUID, name, cat), JSON in Application Support. The owner is created at Pick your cat. (parent spec identity model)
- **Edits apply to new seats only.** The protocol has no "update person" message, so changing a name or cat affects tables joined afterwards; in a lobby you can re-seat (leave + claim) to pick it up. No server change in M1. (call)
- **Table cache:** last snapshot summary per room code (seats' people/cats, status, my seats, phases, updatedAt) so Home can draw cats; pruned when a room closes or disappears from `/tables`.
- No account, no sign-in in M1.

## 13. Accessibility

- **Every action has a tap path** (select card → tap target) in addition to drag. (call)
- **VoiceOver:** SpriteKit nodes expose accessibility elements with labels ("7, tabby", "Yarn, wild", "Cucumber, skip", "Mia, 6 cards, phase 3, asleep") and custom actions on hand cards ("Discard", "Add to group", "Put in tray 1"). Turn changes and big events post announcements. Labels live in a String Catalog (English); they're spoken, not shown, so they don't break the no-text rule.
- **Reduce Motion:** leaps, arcs and shakes become short fades/slides; no screen shake; confetti reduced.
- **Color-blind:** coats differ by cat pattern + glyph; legal-target glows use brightness and a sparkle, not hue alone.
- Touch targets ≥ 44 pt; Dynamic Type applies to names in the shell; respect system haptics/sound settings.

## 14. Asset pipeline

- **Generation:** Codex CLI image generation (`codex exec` with the `image_generation` feature), always passing the style reference `chosen-d-loud-toy.png` with `-i` and a prompt file from `Art/prompts/`. Prompts are committed; raw outputs go to `Art/raw/` (gitignored). (JD: Codex for art)
- **Cutout:** Codex returns opaque images. A small Swift command-line tool in `Art/tools/cutout` uses Vision's foreground-instance mask to produce transparent PNGs, then trims. Fallback: prompt for a flat chroma background and key it with ImageMagick. (call)
- **Slicing/sizing:** `Art/tools/build-assets.sh` resizes to @2x/@3x, writes into `Resources/Assets.xcassets/*.spriteatlas` (Xcode builds the atlases) and app icon sets.
- **Asset list (M1):** card rim/face base, 4 coat cat faces, 4 coat glyphs, numerals 1–12 (rendered from the display font with outline, not generated), Yarn art, Cucumber art, card back; rug; room background; tower base, shelf, top, number badges; 8 cats × poses (idle, alert/awake, curled/away, asleep, leap, terrified, celebrate) as whole-cat sprites — **not** layered rigs in M1 (call: consistent multi-part rigs are hard to generate; squash/stretch on whole sprites gives the juice); UI icons (plus, keypad, share, QR, play, back, gear, paw menu, sort, bell, check, dice, badges: this phone / other phone / bot / skip / laid); particles (star, fur puff, yarn bit, confetti); app icon; OG share image for the server.
- **Consistency:** each cat's pose set is generated with that cat's approved idle sprite as an extra `-i` reference.
- **Order: placeholders first.** (JD) The game is built end to end on simple placeholder sprites with the final names and sizes, so nothing waits on art. Codex art is produced in parallel and **JD approves it in batches**: (1) the 8 cats (idle first, then poses), (2) cards + table (rug, tower, piles, back), (3) icons, particles, app icon and the OG share image. Approved art replaces placeholders by file name; layouts don't change.

## 15. Server follow-ups this design needs

1. **Open Graph tags + image on `/j/<CODE>`** so the Messages bubble shows the cat art. Small, in Plan 2. (call)
2. **Rematch** (later, M2-ish): let a finished room hand everyone a pointer to a new room. Not in M1.
3. Nudge, reactions, push invites — M2, as the parent spec says.

## 16. Testing

- **PounceKit (`swift test`):** protocol decoding against JSON fixtures emitted by the server's own tests (Plan 2 adds a vitest that writes `apps/play-api/fixtures/protocol/*.json` from real `RoomCore` output, so both sides agree); rules mirror tested against `apps/play-api/fixtures/groups.json`; RoomStore reducer (snapshot-equal-seq, gaps, `room_closed`, one-in-flight errors); reconnect/backoff with a fake transport and clock; TableLayout for 2–6 seats; pass-and-play reveal logic.
- **UI smoke (XCUITest):** against `wrangler dev`: pick cat → new game → add a bot → start → draw → discard.
- **Mixed seats, scripted:** a `pounce-e2e` command-line driver (PounceKit) plays full games against `wrangler dev`, and can join an app-created room as a remote human, dropping and restoring its socket. A UI test pairs the simulator app with that remote driver and a bot, covering presence, reconnect after a dropped socket or backgrounding, the pass-and-play curtain, move-seat and round/game over. A script boots two simulators and joins them through `pounce-dev://` links. Push payloads are tested with `xcrun simctl push` and an `.apns` file. (JD: get as far as possible locally)
- **Manual playtests:** two real phones over Tailscale plus simulators; whatever no script can reach goes in `apps/play-ios/MANUAL-CHECKLIST.md` and the PR description.
- **Performance:** Instruments Time Profiler / Energy on an older iPhone: idle table ≈ 0 % CPU; 60 fps through a lay-down + leap.

## 17. Release

**Finish line: a TestFlight build the family can play.** (JD) The plan includes the small server tweaks this design needs (§15.1 Open Graph tags, §16 protocol fixtures) and pauses at a checkpoint for JD's Apple setup and the server deploy secrets before push, universal links and TestFlight are verified on real devices.

- TestFlight from JD's Mac: `scripts/testflight.sh` (`xcodebuild archive` + `-exportArchive` with automatic signing, upload). iOS CI out of scope. (parent spec)
- **JD prerequisites:** App ID capabilities (Push Notifications, Associated Domains), APNs `.p8` into 1Password and the server deploy secrets, App Store Connect record, TestFlight testers, and the server deployed to `play.conleychaos.com`.

## 18. Left to the builder

Exact pixel layouts within §5/§8, animation timings and easing within §9, sound selection, the random-name list, cat names for VoiceOver, particle tuning, and which glow/sparkle art reads best — all checked against the mocks and in playtests.
