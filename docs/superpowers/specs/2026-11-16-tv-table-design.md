# Pounce on the TV

## Why

A family game should have a middle. With a deck of cards on the coffee table, everyone looks at
the same spot, sees the same play land, and groans together. On phones alone, each person looks
down at their own screen.

Pounce on the TV puts the table on the big screen and makes each phone a controller that shows
only that player's own cards. Everyone sits together and looks up at one table. Players can use
their own phones, pass one phone around, or mix the two. The games are the same: Cat Tower and
Tuna Tiles, with the same rules, server and rooms.

There are two ways to show the table:

- **An Apple TV app.** This is the first-class version: Pounce as a real app on the TV, as smooth
  as the iPhone app.
- **A TV page in the browser** at `play.conleychaos.com/play/tv`. It works on anything with a
  browser and a big screen: a laptop on HDMI, a smart TV's browser, a cast tab.

JD's words: "we are gathered together and paying attention to the same central point like a
table game. but we can pass a device or use our own."

## Goals

- **A TV table for both games.** It shows the shared table, everyone's cats, card counts, scores,
  whose turn it is, every play landing, and the round and game celebrations. It is readable from
  the couch.
- **A phone controller.** When a TV is at the table, each phone shows only its player's hand plus
  the controls for a turn. The table itself lives on the TV.
- **Pass and play.** It works unchanged, using today's cover that you hold to reveal.
- **Any mix of players:** iPhone app, browser phones (including Android), and older App Store
  versions, all at one TV table.
- **Smooth on every screen:**
  - Apple TV at the display's top rate (60 Hz on most TVs, more where the TV supports it).
  - Phones keep their 120 Hz.
  - The main-thread rule in `docs/main-thread.md` applies to the new code on every platform.
- **No sign-in on the TV.** Make a table, scan, play.

## Non-goals (for now)

- The Siri Remote or game controllers as player controllers.
- A native Android TV or Google TV app. The browser page covers those TVs.
- AirPlay second screen from a phone, and SharePlay.
- Apple TV Top Shelf, widgets, Live Activities, push, streaks, the trophy room, and accounts on
  the TV.
- Changing either game's rules.

## Anti-goals (a failure even if it works)

- **The TV shows anyone's cards or tiles.** That includes a drawn card or a rack, even for a
  frame. The TV gets the same view the server gives any device that controls no seats, so this
  holds by construction. It must stay that way.
- **A phone needs a TV to play,** or playing with a TV feels slower or laggier than without one.
- **A dropped TV stalls the game.** Phones must always be able to finish without it.
- **Looking back down.** If players still have to read their phones to follow the game, the TV
  has failed. Everything public must be readable on the TV from about 3 meters.

## How it works today (what this builds on)

Recon of `origin/main` at `3829e35`.

- **Devices.** A device is a minted identity (`POST /v1/devices`) with no account needed. Each
  device's view is built from the seats it controls (`controlledSeats`, `api/room/core.ts:890`).
  `viewFor` fills hands and racks only for those seats, and `eventFor` strips drawn cards for
  every other seat.
- **Seatless devices.** A device that controls no seats already connects and gets the full public
  view and every event, with no hands (`core.ts:812-844`). There is no spectator concept beyond
  that.
- **What a seatless device can't do.** `start`, `configure`, `rematch` and `setLook` need a seat
  (`core.ts:1194-1236`). The host has almost no powers: only rename without a seat.
- **Pass and play.** One device claims several seats. The cover is client-only: `PassAndPlay` in
  PounceKit, `Curtain` on the web.
- **iOS code layout.**
  - PounceKit is iOS + macOS and nearly UIKit-free.
  - The tables are SpriteKit scenes in the app target (`Pounce/Table`, `Pounce/Tiles`). Touch input
    (`TableInput.swift`, `TilesInput.swift`) and haptics are separable from the nodes.
  - A few render files reach for `UIScreen`, `UIApplication` and `UIColor`.
- **Web code layout.**
  - The layout functions (`ct-layout.ts`, `tiles-layout.ts`) are pure.
  - `CatTowerTable` already renders with no seat (`mine=[]`), but hand, drag and table live in
    one component.
- **Sounds** fire from event animations on both platforms. The web needs one user gesture to
  unlock audio.

## Approaches considered

1. **An Apple TV app** that draws the table itself, built from the iPhone table code. *Picked*,
   as the first-class version. Every phone is free to be just a controller. The table survives
   any phone leaving. It feels like a console in the living room. The cost is a tvOS port, a
   focus-engine shell and an App Store review.
2. **A phone sends the table to the TV over AirPlay** as a second screen. This is the fastest
   path, but one person's phone draws two screens all night (heat, battery), the TV goes dark
   when that phone sleeps, and browser and Android players can't be the sender. *Not picked*: it
   ties the shared table to one person's phone.
3. **A TV page in the browser.** It's cheap because it falls out of the web player, and it reaches
   any screen. It can't run on Apple TV itself, and smart TV browsers are slow. *Picked as the
   companion* to the Apple TV app. It also comes first, as the test bed for the server and phone
   work.

JD: "Apple TV app plus web. so we could use any device for the shared table easily but have great
first class support with apple tv."

## The design

### 1. A screen is a seatless device that says so

- **Connecting as a screen.** The TV connects to a room as a screen: `role=screen` on the socket
  (query parameter, so browsers can send it). It mints a normal device token. It has no profile,
  no person and no age band.
- **Server rules for a screen:**
  - It never controls a seat. `claim`, `moveSeat`, `claimMove` and `act` from a screen are
    refused.
  - It counts as a member of the room for join-guess rules.
  - It doesn't appear in anyone's table list.
- **`RoomView` gains `screen: boolean`.** It is true while at least one screen is connected. It
  goes false after a 10-second grace (the builder may tune it) so a TV that blinks off Wi-Fi doesn't flip
  every phone's layout.
- **No `PROTOCOL_VERSION` bump: every change is additive.** Shipped iPhone apps and the web player
  require the snapshot's version to equal 1 exactly (`Messages.swift:126`, `RoomStore.swift:374`,
  `play-web/src/store/room.ts:306`), so a bump would lock out every 1.0 and 1.1 app. Swift's
  `Codable` ignores unknown keys, and `RoomSocket` skips message types it doesn't know
  (`RoomSocket.swift:242`). New fields and the relayed `aim` message (which carries no `seq`) are
  therefore safe for old clients, which simply play the full table. A test pins this: an old
  client's decoder reads a snapshot with every new field, and skips an `aim`. *(My call, from the
  code.)*
- **The TV is never the host.** A room a screen creates has no host until the first phone takes a
  seat. That phone becomes the host. Today's host-based safety rules then work unchanged: blocks
  (`game-room.ts:244-262`), kid privacy on the `/j/` page (`safety.ts:70-81`), update asks
  (`game-room.ts:505-520`), and the inviter's name (`game-room.ts:282-290`). Before anyone sits,
  `/j/<code>` shows a neutral page, with no names. *(My call: it keeps every safety rule as it
  is.)*
- **The game starts from a phone.** Start, House Cat seats and Play again stay phone actions,
  because they need a seat and the people holding phones are the ones playing. The TV lobby says
  so: "Press Start on any phone".

### 2. Getting everyone to the TV table

**Nothing is ever typed on the TV.** JD: "i dont want to have to input anything on the tv, only on
the app. we can have some controls there but no code or text entry at all." The TV has a few big
buttons. Every code or name is entered on a phone.

**The TV's home** shows two things:
- **A link QR.** It is big, with a short backup code under it, and the line "Scan with your phone
  to put your table here".
- **Two buttons:** "Cat Tower" and "Tuna Tiles", to start a new table on this TV.

**Linking a phone's table to the TV**, the main path for a table that already exists:

1. **The TV shows its link.** At home, the TV asks the server for a screen link: `POST /v1/screens`
   with its device token.
   - The server returns an unguessable token (at least 128 bits) and a 6-character backup code
     from the room-code alphabet.
   - Both expire after 10 minutes, and the TV renews them before then.
   - The TV holds a socket on its link (`/v1/screens/{token}/ws`) and waits.
2. **The QR opens the phone's app.** The QR encodes `https://play.conleychaos.com/tv/<token>`.
   - Scanned with the iPhone camera, it opens the app through a universal link. `/tv/` is added to
     the app site association.
   - On other phones it opens the web player at `/play/tv-link/<token>`.
   - Inside the app, "Show on TV" in the lobby and table menus opens a scanner. There is a "Type the
     TV's code" fallback for the backup code.
3. **The phone sends its table.** It calls `POST /v1/screens/link` with the token or code and its
   room code.
   - Only a device in that room (seated, or the host) may link it.
   - The server tells the waiting TV which room. The TV connects to it as a screen, and the link
     token is spent.
   - The TV shows the table at once. The phone shows "On the TV" and switches to Cards.
4. **A phone that isn't at a table** gets the phone's game picker when it scans the TV's QR. It makes
   the table, and the TV is linked to it as soon as it exists.

**Making a table on the TV:**

1. Press "Cat Tower" or "Tuna Tiles".
2. The TV creates the room (with no host yet; see above). It shows the room's invite QR
   (`https://play.conleychaos.com/j/<CODE>`) big, with the room code under it for anyone typing it
   into their phone.
3. Phones join and claim seats exactly as today, including adding people for pass and play. Each
   player's cat walks onto the TV as they sit.
4. Anyone seated presses Start on their phone.

**Switching tables or leaving.**
- The TV's menu has two big buttons: "Link another table", which shows the link QR again, and "Leave
  table", which goes back home.
- Linking a new table to a TV that is showing one moves it, after a "Move the TV to this table?"
  confirm on the phone.

**Guessing the backup code.**
- Wrong codes count against the phone, using the same backoff as joining by code (`DEVICE_JOIN_RULE`).
- The worst a guess can do is put a table on a stranger's TV that is sitting on its home screen. The
  short expiry and the backoff make that impractical.

**Camera.** The iPhone scanner needs camera permission, asked only when "Show on TV" is tapped.
Frames never leave the phone and only the QR's text is read. The App Store privacy answers stay
"not collected", and the purpose string says so.

### 3. The phone as a controller

When `screen` is true, every phone (iOS app and web player) switches to the controller layout by
default. JD: "make it every phone by default but there should be a switch on there so people can
toggle to see the whole board easily too."

- **The switch is on the controller screen itself,** always visible and one tap: "Cards" or
  "Table". It is not buried in a menu.
  - "Table" shows today's full table on the phone, with the hand.
  - "Cards" returns to the controller layout.
- **Per phone, kept for that table.** Changing it on one phone changes nothing else. When the TV
  leaves, every phone shows the full table, whatever the switch says. When the TV comes back, a
  phone on "Table" stays on "Table".
- **This covers far-away players.** Grandma in another city taps "Table" once and plays as today.
  Several TVs at one table are fine: the flag only says some screen is there.
- **A first-time tip** points at the switch the first time a phone becomes a controller.

**Cat Tower:**

```
 TV                                  Phone
┌───────────────────────────────┐   ┌──────────────────┐
│  Mom ▸ [3 3 3] [7 8 9 10]     │   │  Your turn       │
│  Ava ▸ (not down yet)         │   │  [Deck] [Discard]│
│  You ▸ [K K K] ◀ glowing      │   │                  │
│     DECK  ▓   DISCARD  [5]    │   │  5 5 7 9 J Q K   │
│  Your turn, Dad               │   │  Lay down  Hit   │
└───────────────────────────────┘   └──────────────────┘
```

- **The hand** is large and sorted the player's way, with today's sort and drag-to-reorder.
- **Draw** is a tap on Deck or the discard card, shown at the top on your turn. The card lands in
  the hand on the phone, and the TV shows it leaving the pile.
- **Lay down.** The player builds their phase groups on the phone in a tray. It works as today's
  lay-down trays do, minus the table around them. Confirm flies them onto the TV.
- **Hit.**
  1. The player picks a card, then a group from a short list on the phone ("Mom's 3s", "Your
     run"). The list uses the same `canHit` the table uses today and lists only legal targets.
  2. While a target is chosen, that group glows on the TV.
  3. Confirm plays it.
- **Discard** is dragging a card to the discard spot or tapping Discard.
- **Off turn,** the phone shows the hand and who's playing. All the action is on the TV.

**Tuna Tiles:**

- Off turn, the phone shows the rack.
- On your turn, the table opens on the phone, because rearranging what's already down needs it.
  Each move shows live on the TV, so the room watches the player work it out.
- Before opening, a turn needs only the rack plus "play these as a set", but showing the table on
  every turn keeps one way to play. Builder's call, with JD's look at it in the screenshots.

**Live pointing** is a new message for both of these:

- It is a client message `aim`: the acting seat's chosen hit target in Cat Tower, or its draft
  table in Tuna Tiles.
- The server relays it to every device in the room. It is not game state and is never stored.
  Rate-limit it to keep within the room budget.
- Only the device controlling the acting seat may send it, on its turn.
- Pieces in a Tuna Tiles draft are public once placed, as at a real table, even if the player
  takes them back. Tiles still on the rack are never sent. *(My call: it matches how the physical
  game works.)*

**Feel:** haptics stay on the phones. A buzz when it's your turn matters more now that eyes are on
the TV.

**Sound:** the TV plays the game sounds. A phone on "Cards" stays quiet for game events and keeps
its own button taps. A phone on "Table" plays game sounds as today, so a far-away player still
hears the game. *(My call: one table, one sound.)*

### 4. The TV table

**Layout.** A wide, seatless layout for each game, made for 16:9 at couch distance:

- Every player's cat around the table with card or tile counts and scores.
- The piles and laid groups for Cat Tower, the board for Tuna Tiles.
- A big "Ava's turn" banner.

**Nothing private, ever.** The hand and rack areas don't exist on the TV.

**Sizing.** Card faces and tile numbers are sized for reading from about 3 meters. On a 1080p
frame, nothing that matters is smaller than about 28 pt.

**Pass and play** shows on the TV as normal turns. The cover lives on the phone.

**Celebrations** play big on the TV: rounds, phases, Pounce moments and game over. Game over shows
the scores and "Play again on any phone".

**Live pointing** shows as a soft glow on the target group, and as draft pieces moving on the Tuna
Tiles board.

**If the TV drops,** phones switch back to the full table after the grace period and the game
goes on. If the TV comes back, it rejoins and the phones switch to controller mode again.

**TV menus** are made for the remote: big focusable buttons, few choices, no text entry
anywhere.

- Home: the link QR, "Cat Tower", "Tuna Tiles".
- The lobby: the invite QR and code, the seats, and "Change game" before start.
- In a game: "Link another table", "Leave table", sound on or off.

### 5. The Apple TV app

- **Target.** A tvOS target in the same Xcode project (`project.yml`), with the same bundle id as
  the iPhone app for universal purchase, so it's the same App Store listing. tvOS 26.
- **PounceKit** adds `.tvOS(.v26)`. Its few iOS-only spots are already behind `#if os(iOS)`
  (Live Activities, the audio session, `AppIdentity`). Tests run for tvOS in CI.
- **The table is shared, not forked:**
  - The SpriteKit nodes and layout code are shared between the iPhone and TV targets.
  - Touch input, haptics and the hand stay iOS-only.
  - The TV gets its own scene setup (a seatless layout) built from the same nodes, animations and
    event handling.
  - The few `UIScreen`, `UIApplication` and `UIColor` uses in render code get a small
    cross-platform seam.
  - Where the code lives (a shared module, or files in both targets) is the builder's call. The
    rule is one copy of the drawing code.
- **The shell** is a small SwiftUI app with focus-engine navigation: home (link QR and game buttons),
  lobby, table, game over. None of the iPhone shell's onboarding (age check, name,
  cat, sign-in) runs on the TV, because the TV has no player.
- **Frame rate.** It asks for the display's top rate, with the same idle behavior as the iPhone
  tables. The main-thread lint covers the tvOS target, and `FrameRateTests` gets a tvOS variant on
  the Apple TV simulator.
- **Storage.** Only the device credential, in the Keychain. Nothing else needs to persist.
- **Shipping.**
  - TestFlight for tvOS, to the same Family and Friends group, like every app change.
  - App Store screenshots and review notes for tvOS. The privacy answers come from the code; the
    TV collects less than the phone.
  - Adding the tvOS platform to the app record in App Store Connect is an account step for JD to
    OK.

### 6. The browser TV page

- **Address.** `play.conleychaos.com/play/tv`, in the same web build and deploy.
- **Skips first run.** No age check, name or cat: a screen has no player. The page's code must not
  create a person.
- **Home** is the same as the Apple TV's: the link QR and the two game buttons, with no text
  entry. It works by arrow keys, Enter and mouse, so a smart TV remote's d-pad works.
- **Audio.** One "Start" press before the table unlocks audio. It's needed anyway for full screen
  (`requestFullscreen`). The page offers full screen and keeps the screen awake with the Wake Lock
  API where available.
- **Table components.** The web player's table is split into a public table and the hand or
  controller parts. The TV page and the phone's full table use the same public table component.
  The phone's controller layout is new, from the same pieces.
- **Where it must run.** It is guaranteed on current desktop Chrome, Safari, Firefox and Edge (a
  laptop on HDMI, or a tab cast to the TV), and on a current Chromium-based TV browser. Older
  smart-TV browsers (Tizen, webOS) are best effort: no legacy bundle. If the page can't load there,
  the page that comes up says to use a laptop or an Apple TV. *(My call: the Apple TV app is the
  first-class path, so the browser page doesn't need a second build for old TVs.)*
- **Performance.** 60 fps on a mid laptop, with the same main-thread gates (`e2e/main-thread.spec.ts`
  gets a TV project at 1920×1080).

## Testing and the cross-platform bar

These must pass before anything merges:

- **Server:**
  - Screen role rules: refused claims and acts.
  - A screen's view never contains a hand or rack, and its events never carry a drawn card or
    tile. This is a property test over random games of both kinds.
  - The `screen` flag and its grace period.
  - `aim` relay rules.
  - The host is the first phone to sit, and the host-based safety rules work at a TV table.
  - An old client still decodes snapshots and skips `aim`.
  - Screen links: by token and by backup code, expiry and renewal, only room members may link,
    wrong-code backoff, and moving a TV between tables.
- **Web e2e:**
  - A TV page plus two browser phones play each game to the end.
  - A pass-and-play phone with a TV.
  - The Cards/Table switch, including that it survives the TV leaving and coming back.
  - The TV dropping and coming back mid-hand.
  - Linking a phone's existing table to a TV on its home screen, by QR link and by backup code.
  - The controller layout on phone sizes.
  - A TV project for the main-thread gates.
- **Mixed:**
  - Apple TV (simulator) as the screen, with an iPhone app player and a browser player at one
    table, for both games.
  - An older iPhone client at a TV table plays the full table without errors.
- **Device:** a real Apple TV if JD has one handy. Otherwise the simulator, plus JD's phone as the
  controller (`scripts/frame-rate.sh` for the phone side).

## Order of work

1. **Server:** the screen role, screen links (`/v1/screens`), the `screen` flag, `aim` relay, the
   first-phone host rule and tests.
2. **Web:** split the public table, the TV page, and the phone controller layout. This proves the
   whole loop in the browser first.
3. **iPhone:** the controller layout, "Show on TV" with the QR scanner and backup code, `/tv/`
   universal links, aim sending, and quieting sounds with a screen
   present.
4. **Apple TV:** PounceKit on tvOS, the shared table code, the tvOS shell, the frame-rate gates,
   TestFlight.

Steps 2 and 3 can run side by side once step 1 has merged.

## Left to the builder

- Exact visual design of the TV layouts and the controller layouts, within the UI rules:
  - redesign whole screens
  - terse copy
  - fit every size
  - teach with tips
  - no emoji
- The `aim` message's exact shape and rate.
- How the shared SpriteKit code is packaged.
- Whether the Tuna Tiles phone shows the table before a player has opened.
- Tips for first-time controller players, such as "Your cards are here. The table is on the TV."
