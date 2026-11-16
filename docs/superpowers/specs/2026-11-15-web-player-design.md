# Pounce on the web

## Goal

Anyone tapping an invite can play, iPhone or not: an Android phone, a laptop, a grandparent's PC.
The web player is Pounce in a browser, at `play.conleychaos.com/play`, installable as an app. It
plays both games with the same rules as iOS, at the same tables as iOS, and it feels like a game:
60 frames a second or better, smooth at 120 Hz, sound, touch, mouse and keyboard.

Native Android comes later and builds on this (last section).

## What it does

The same games and the same ways in as the iOS app:

- Cat Tower and Tuna Tiles; Practice against a House Cat.
- Make a table, join by code or by link (`/j/<code>`, `/p/<token>`), the lobby with its "Add a
  player" choices (Same room QR, Far away link, This phone, House Cat), pass and play on one
  device, rounds, scores, game over and Play again.
- Web and iOS players at the same table: the server can't tell them apart except by the
  `platform` they report.
- First run as on iOS: the age check, a name and a cat, and for a guest "Grandma saved you a seat".
- Tips that teach, one at a time (the same tip texts as iOS where the control is the same).

Left for later, on purpose: accounts and Sign in with Apple, streaks and the trophy room, table
looks, nudges and Pounce requests. The server already answers a web device without them: they
are features of a returning player, and the web player's first job is the first game.

## Never drifting from the game

The rules live once, in TypeScript, in `apps/play-api`. The web player imports them; it never
copies them.

- `@pounce/play-api` exports its pure modules (`package.json` `exports`): the protocol types and
  `PROTOCOL_VERSION`, both games' cards, pieces, groups, phases, sets and solvers, and the views
  and events. The web build compiles them from source, so a changed message, view or rule changes
  the web build in the same commit, and a breaking change fails `pnpm typecheck` or the web tests
  in CI.
- The web player draws Cat Tower's "can I lay this down" and Tuna Tiles' "is this a set" with the
  server's own `buildGroup`, `matchPhase`, `canHit` and `readSet`. (iOS keeps its Swift copies.)
- One deploy: the CI deploy job builds the web player into the Worker's assets and deploys both
  in one `wrangler deploy`, from the same commit. There is never a server without its matching web
  player.
- A contract test runs the web player's own client code (`src/net`) against the real Worker in
  workerd (Miniflare): mint, profile, create a table, open the socket the browser way, claim,
  configure, start, play a move, read the snapshot. It runs in `pnpm test`.

### New deploys and protocol changes

- Every build has an id (the commit), in `/play/version.json` and in the bundle.
- The service worker caches the shell. When a new deploy is out it downloads in the background
  and waits. The page applies it (reloads) only at a safe moment: Home, the lobby, game over, or
  the tab coming back from hidden while not mid-hand. Never mid-hand.
- If the server refuses the client (`426`, a socket closed as "update required", or a snapshot
  whose `protocol` isn't the bundle's), the page reloads at once, because it can't play on
  anyway: the hand is on the server, so the reload lands back in it.
- The server ignores `APP_MINIMUM` for `platform=web` (the web player is always as new as the
  server); the protocol floor still applies.

## Architecture

```
apps/play-web/            Vite + Preact + TypeScript
  src/net/                api.ts (fetch + device token), socket.ts (reconnecting WebSocket, heartbeats, move ids)
  src/store/              room store (snapshot + events -> state), lobby plan, pass and play, identity
  src/ui/                 screens (first run, home, join, lobby, game over), sheets, tips
  src/table/              Cat Tower table, Tuna Tiles table, drag, animation, sound, haptics
  src/sw.ts               service worker (built to /play/sw.js)
  public/                 manifest, icons
  art/                    built from apps/play-ios art (scripts/build-art.mjs), committed as WebP
apps/play-api/public/play/ the build output, served by the Worker's static assets (not committed)
```

### Framework: Preact, with the table drawn in plain DOM

- **Preact** (4 KB) for screens, sheets and the lobby. Signals-free hooks keep it small and
  familiar. React's 45 KB buys nothing here.
- **The table is DOM, not canvas or WebGL.** A table has at most 16 cards in a hand and about 110
  pieces in Tuna Tiles. Each card or piece is one absolutely positioned element whose face is
  pre-composited CSS background layers, moved only by `transform` and faded only by `opacity`, so
  every frame is compositor-only: no layout, no paint. That is 60 fps on a mid-range Android phone
  and holds 120 Hz on a ProMotion Mac. DOM also gives screen-reader labels, focus order, hover and
  keyboard for free, which canvas would make us rebuild. WebGL (PixiJS, about 100 KB) would buy
  particle counts we don't need.
- **Animation** uses the Web Animations API (`element.animate`) on `transform` and `opacity`
  only; it runs on the compositor and survives a busy main thread. Layout reads happen once per
  change (measure, then animate: FLIP), never per frame.
- **Drag** uses pointer events with `setPointerCapture`; the move handler only stores the point,
  and one `requestAnimationFrame` writes one `transform`. The dragged element gets
  `will-change: transform` only while dragged.
- Overlapping groups that fade (a dimmed hand, a stack) fade as one layer (`opacity` on the
  group's container, which becomes one composited layer), per `AGENTS.md`.
- Reduced motion: animations shorten to a fade, nothing flies or bounces.

Bundle budget: the first load (HTML, CSS, JS) under 90 KB compressed; art loads after first
paint and is cached by the service worker. The rules and protocol from `play-api` are about 25 KB
of it.

#### The rendering thread does UI work only

JD's rule for every platform (`docs/main-thread.md`): the thread that draws never waits on IO or
runs long, so every frame lands at 60 Hz and at 120 Hz where the screen has it. On the web:

- **Statically** (`apps/play-web/eslint.main-thread.mjs`, failing `pnpm lint`): no
  `localStorage`, `sessionStorage`, `document.cookie`, `XMLHttpRequest`, `alert`, `confirm`,
  `prompt`, `Atomics.wait` or `importScripts` on the page's thread; no `setTimeout` or
  `setInterval` in screen and table code (animation is CSS, `element.animate()` or
  `requestAnimationFrame`, timed in milliseconds); no hard-coded 60 Hz frame (16.7 ms, 1000 / 60);
  no move search (the solvers, the House Cat) outside `src/workers`.
- **Storage** is one module (`src/lib/kv.ts`): read once, into memory, the first time anything
  asks; written in idle time and when the page hides.
- **The Tuna Tiles hint** runs the House Cat's search in a Web Worker (`src/workers`).
- **At run time** (`e2e/main-thread.spec.ts`, in CI): while both games are played, no task or
  animation frame may pass 50 ms, and the main thread's work per frame (from a DevTools trace) must
  stay at p95 under 8.3 ms (one 120 Hz frame) on a laptop and 16.7 ms on a phone. The phone is a
  fixed speed: the run benchmarks its machine and picks the CPU slowdown that matches a reference
  Mac slowed 4x, so a slower CI runner never means a slower phone.
- **120 Hz** can't be counted in headless Chrome, which draws at 60 Hz whatever the flags. It is
  shown instead by frame work: a frame whose work fits in 8.3 ms is a frame a 120 Hz screen gets.
  Nothing is timed in frames (all in milliseconds), so animations take the same time at any rate.

## Talking to the server

The web player speaks the iOS protocol unchanged. Two things a browser can't do, the Worker now
meets halfway (for browser sockets only; iOS is untouched):

- **Socket auth.** A browser WebSocket can't send `Authorization` or custom headers. The page
  opens `wss://…/v1/rooms/<code>/ws?games=tiles&app=<X-Pounce-App>` with the subprotocols
  `pounce` and `pounce.token.<device token>`. The Worker moves the token to `Authorization` and
  the query to `X-Pounce-Games` and `X-Pounce-App`, and answers with the `pounce` subprotocol.
  The token never appears in a URL or a log.
- **Refusals.** A browser can't read a refused upgrade's status. For a browser socket the Worker
  accepts the upgrade and closes it at once with a code: 4404 (no such table), 4429 (too many
  wrong codes), 4426 (update required), 4401 (bad token).

Every HTTP call sends `X-Pounce-App: platform=web; version=<build version>; build=<n>;
protocol=<PROTOCOL_VERSION>` and `X-Pounce-Games: tiles`. The device token and the people on this
device are kept in `localStorage` (`pounce.device`, `pounce.people`), as iOS keeps them in the
Keychain.

### Reconnecting

The socket follows `RoomSocket.swift`: backoff 250 ms to 8 s, heartbeats (`{"t":"ping"}` every
`room.link.ping` ms), "weak" after a slow round trip and a reconnect when one is lost, and every
`act` carries a move id so a move sent again after a reconnect lands once (`room.link.acks`). The
page also reconnects at once on `online`, on `visibilitychange` back to visible, and on
`pageshow` from the back-forward cache, and sends `presence` active/background with visibility.
Offline, the table dims as one layer and says "Offline"; the shell itself loads offline from the
service worker.

## Screens and layout

The web player is the same family as the iOS app: the same art (`apps/play-ios/Art`, the asset
catalog's cats, cards, pieces, rugs, toys and room), the same violet floor and loud toy-like
buttons, the same words. Layouts are fluid, not a phone frame in the middle of a monitor:

- Phone portrait: as iOS. Phone landscape: opponents and the tower move to the sides.
- Tablet and laptop: the table grows, the hand fans wider, the tower gets its full height.
- Wide monitors: the table is capped and centred on the room art; the room fills the sides.

Every screen is checked at 320 px wide (iPhone SE), a large phone, tablet portrait and landscape,
a laptop, a 2560 px monitor, and at 200% text size.

Laptop: hover lifts a card; keyboard plays the whole game (arrow keys move through the hand, Space
or Enter picks, D draws, Escape cancels, Tab walks every control in order). The keys are taught by
a tip the first time a keyboard is used.

## First run and invites

- The age check (year of birth, as iOS) runs once per device. Under 13: a kitten, whose names come
  from the name generator only, as on iOS. The band goes to the server in the profile upload.
- Name and cat: one screen, a suggested name and cat already chosen.
- A guest from `/play/j/<code>` sees "Grandma saved you a seat" (the invite peek the server
  already does for `/j/`), picks a name and cat, and lands in the seat: the same taps as iOS.
- The invite pages get "Play in your browser" beside the App Store button. On iPhone the app
  stays the big button and the browser is the small link under it; everywhere else the browser
  is the big button and the App Store is the badge under it.

## PWA

- `manifest.webmanifest`: name "Pounce", short name "Pounce", the real app icon (192, 512 and a
  maskable 512), `display: standalone`, theme and background the launch violet, scope and start
  URL `/play/`.
- Service worker: precaches the shell and art on install; network-first for `version.json`,
  cache-first for hashed files. The API and sockets are never cached.
- Install prompt: never on first load. Chrome and Edge get an "Install" pill on Home after the
  first finished game (`beforeinstallprompt`, kept until then). Safari has no prompt event; on
  iPhone the app is the better install anyway, and on Mac Safari the pill opens a one-line tip
  ("File, Add to Dock").

## Sound, touch, notifications

- Sound: the iOS effects (`Pounce/Resources/Sounds`), converted to Opus and AAC, played with Web
  Audio (decoded once, no latency). Starts after the first tap (autoplay rules). A mute toggle in
  Settings, remembered.
- Vibration: `navigator.vibrate` where it exists (Android), the same moments as iOS haptics, with
  the same on/off setting.
- Turn notifications: see "Web Push" below.

## Funnel and privacy

- Web devices are minted like iOS devices with `platform=web`; the funnel's `devices.platform`
  already keeps it. `funnel/queries.sql` gets a `by_platform` split and the main funnel filtered
  per platform.
- The web player reports the same app steps as iOS (`POST /v1/funnel`) after the age check.
- Nothing third party: no analytics, no fonts or scripts from another host, a strict CSP
  (`default-src 'self'`; `connect-src 'self'`). The privacy policy and `docs/privacy/` say what
  the browser keeps (the device token and the people on it, settings, in local storage) and that
  nothing else is collected.

## Web Push

The server's push path (`notify/deliver.ts`) builds one alert per device and sends it by APNs.
Web Push fits the same shape, so the web player gets turn alerts too:

- A device keeps a browser push subscription (`PUT /v1/devices/me/webpush`) beside any APNs
  token, under the same rules: never for a kitten's device without a parent's consent, nothing
  overnight for a teen, gone when consent ends.
- `DeviceIndex.pushAlert` sends the same alert to it (`src/push/webpush.ts`): encrypted for the
  browser alone (RFC 8291, `aes128gcm`, WebCrypto), signed with our VAPID key (RFC 8292). A 404
  or 410 forgets the subscription. Only the big browsers' push services are accepted.
- The service worker shows it and a tap opens the table.
- The web player asks only from Settings (Turn alerts) or from a one-time card on Home once
  there are tables to be alerted about, never on first load. On an iPhone, browsers can only
  receive push once Pounce is added to the Home Screen; there the app is the better choice.
- It needs a VAPID key pair: JD runs `node apps/play-api/scripts/vapid-keys.mjs` once, which makes
  it and stores it with `gh secret set` (the private key is never shown); the next deploy syncs
  it. Until then `GET /v1/push/web` is a 404 and the web player never asks.

## Testing

- Unit tests (Vitest): the socket's reconnect and move ids, the room store, the lobby plan, drag
  hit-testing, layout maths.
- Contract test: the web client's net code against the real Worker in Miniflare (above).
- End to end (Playwright, Chromium and WebKit), in CI against `wrangler dev` with `SPEED` up:
  two browser contexts at one table playing Cat Tower and Tuna Tiles to the end; one web player
  and one `pounce-e2e` client (the iOS protocol client from PounceKit) at one table, on a Mac.
- Performance: Chrome DevTools traces of the deal, a drag, a play and the round-end animation, on
  desktop and with 4x CPU throttling on a mobile viewport; the numbers go in the PR.

## Android later: a Trusted Web Activity or a native app

| | Trusted Web Activity (this PWA in a Play Store shell) | Native Android app |
| --- | --- | --- |
| Reuses | All of this: every screen, the table, sound, the service worker. Adds a Digital Asset Links file and a Bubblewrap project. | The server, the protocol and rules (as TypeScript it can't import: Kotlin needs its own copy, like Swift), the art, the design. |
| Push | Web Push, already built here, shows as an Android notification. | FCM: a new delivery path on the server. |
| Cost | Days: wrap, sign, list on Play. Every web fix ships to Android with no review. | Months: a second full client to build and keep in step, a third copy of the rules. |
| Limits | Chrome must be installed (it is on almost every Android phone). No widgets, no Live Activity equivalent. | Everything: widgets, Android's live notifications. |

Start with the TWA: it is this web player in the Play Store for almost nothing, and the same
family plays it the day it ships. Build a native app only if Android players ask for what only
native does (widgets, a live table on the lock screen).
