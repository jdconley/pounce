# Pounce (iOS)

Native iPhone and iPad client for the Pounce card game. iOS 26+, Swift 6 (strict concurrency), SwiftUI shell
with a SpriteKit table. Apple frameworks only, no third-party packages.

## Layout

- `project.yml` XcodeGen spec. `Pounce.xcodeproj` is generated and gitignored.
- `Pounce/` app target. `PounceUITests/` UI tests.
- `PounceNotify/` the Notification Service Extension (communication avatars; it also writes each
  push's streak block to the widgets' snapshot). `PounceWidgets/` the widgets (Us: small, medium and
  StandBy; Streak: the lock screen's three families), the Pounce button and WidgetKit push. All three
  share the App Group `group.com.conleychaos.play` (the snapshot, `Widgets/widgets.json`); the app and
  the widgets share the keychain group `<team>.com.conleychaos.play` (the device credential, which the
  widgets read and never mint). The widgets draw the app's own art from the containing bundle.
  `PounceWidgets/LiveTableWidget.swift` is the live table (spec §11.3, daily habit PR 7): a Live
  Activity on the Lock Screen and in the Dynamic Island that play-api starts with push-to-start
  when you leave a table someone else is at, updates on each turn and ends on its own. The app
  (`Pounce/App/LiveTableBridge.swift`) uploads its tokens (never from a kitten's device) and ends a
  table's activity when the table opens; the settings panel's live table toggle turns it off.
- `Pounce/Tiles/` the tile game's table: `TilesScene` (the rug, the stash, the action strip, the loupe)
  with its input, animations and VoiceOver elements, `TilePieceFactory` (the toy tokens, drawn in code
  over the glyph art), `TilesStage` (the SwiftUI shell: curtain, menu, game over) and the demos. Its
  rules, draft model and layout are in PounceKit (`TilesRules`, `TilesDraft`, `TilesLayout`).
- `PounceKit/` local Swift package (game model, networking, `pounce-e2e` CLI) with Swift Testing tests.
- `Config/` xcconfigs. `Debug.xcconfig` points at `http://localhost:8787` and registers the
  `pounce-dev` URL scheme; `Release.xcconfig` points at `https://play.conleychaos.com` and registers no
  custom scheme (a build phase strips the URL type from the built Info.plist).
  Optional gitignored `Config/Local.xcconfig` overrides settings for a real phone.
- `scripts/bootstrap.sh` generates the Xcode project. `scripts/dev-server.sh` runs `wrangler dev` for
  `apps/play-api` on port 8787 (creates the gitignored `apps/play-api/.dev.vars` if missing).

## Build and test

```sh
scripts/bootstrap.sh
swift test --package-path PounceKit
xcodebuild -project Pounce.xcodeproj -scheme Pounce \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build-for-testing
scripts/ui-tests.sh        # the UI suite; the live tests need the dev server, which this script starts
```

If simulator code signing complains about provisioning, add `CODE_SIGNING_ALLOWED=NO` to the
`xcodebuild` command. It was not needed on the author's machine (ad hoc simulator signing).

## Prerequisites

- Xcode 27 (iOS 26 SDK or later; the app's deployment target is iOS 26.0; universal: iPhone in portrait, iPad in every orientation and every multitasking size).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`; `scripts/bootstrap.sh`
  installs it if missing).
- Node 24 and pnpm 10 (run `pnpm install` at the repo root once) for the dev server.
- Optional: `jq` (`scripts/check-assets.sh`), ImageMagick 7 and the Codex CLI (art pipeline),
  Tailscale (phone testing), gitleaks.

## Dev server

```sh
scripts/dev-server.sh
```

Runs `wrangler dev` for `apps/play-api` on `127.0.0.1:8787` (set `DEV_SERVER_IP=0.0.0.0` to listen on
every interface, for the LAN workflow below; `DEV_SERVER_PORT` for another port, and
`DEV_SERVER_SPEED=10` for fast bots, see [Test speed](#test-speed)). The first run writes
`apps/play-api/.dev.vars` with a random `TOKEN_SECRET`. That file is gitignored; never commit it.
Check it with `curl http://localhost:8787/healthz`, which should say `"configured":true`.
Debug builds talk to `http://localhost:8787` by default.

## Run on a simulator

`scripts/bootstrap.sh`, open `Pounce.xcodeproj` (or use `xcodebuild`), and run the `Pounce` scheme
on an iPhone simulator with the dev server up. To point a run at another server set
`POUNCE_API_BASE_URL` in the scheme's environment (or in the launch environment for `simctl`);
that beats everything else.

Base URL precedence, strongest first: the `POUNCE_API_BASE_URL` environment variable at launch,
then the build setting (Debug: `http://localhost:8787`, optionally overridden by the gitignored
`Config/Local.xcconfig`; Release: `https://play.conleychaos.com`).

### Debug-only launch arguments

- `-demo <lobby|lobbyReady|lobbyFirst|lobbyGuest|table|other|replay|nope|celebrate|curtain|handoff|peek|crowded|hit|lay|over>` opens a room fed by
  a fake socket and canned snapshots, so the real screens render with no server. `-slowmo <factor>`
  (at most 1) runs a demo in slow motion. See `Pounce/App/DemoMode.swift` for what each demo shows.
  The bad connection indicator has four: `weak`, `reconnecting`, `pending` (a move the server never
  answers) and `seatLink` (other players' weak and reconnecting phones). Screenshots of each are in
  `Art/screenshots/connection/`.
- The tile game (working title "Tuna Tiles", game id `tiles`; `docs/superpowers/specs/2026-11-11-tile-game-design.md`)
  has its table but nothing in Home starts it yet: `-demo tiles…` is the only way in. `tiles` (mid game,
  my move), `tiles-early` / `tiles-opened` (before and after my opening), `tiles-draft`, `tiles-invalid`,
  `tiles-loupe` (a turn half built: valid, with a broken set, with a set open), `tiles-late` (25 sets and a
  22-piece stash), `tiles-long` (a row of thirteen), `tiles-pass` (the toy box empty), `tiles-other` (watch
  the other seats play), `tiles-curtain` (two seats on this phone), `tiles-over`, and `tiles-play` (a fresh
  game against a House Cat that runs on the device). Every one is fed by `TilesDemoSocket`, which runs the
  game locally (`TilesLocalGame`), so turns can be played. Add `-tiles-easy` for easy mode (a kitten's
  default), `-tiles-tricks`, `-tiles-hint`, `-tiles-recap`, `-tiles-sheet` (every piece at stash and rug
  size, both designs tried) and `-tiles-game-off` (with `tiles-over`: Play again refused with `game_off`).
  See `Pounce/Tiles/TilesDemo.swift`; screenshots are in `Art/screenshots/tiles/`.
- How to play's videos (`HowTo/README.md`): `-demo howto` is Cat Tower's video table (my whole turn,
  taken by `HowToSocket` as the server would, then the other seats), `-demo tiles-last` the tile
  game's last turn (three pieces left, each fits a row), `-show-touches` draws a ring under every
  finger, and `-timecode` (with it) the wall clock in a strip along the top edge, for recordings.
  `HowTo/make.sh` records and cuts both videos.
- `-anim-speed <n>` (or `POUNCE_ANIM_SPEED=<n>` in the environment) runs the whole app n times faster
  and marks the run as a test: sound and haptics go to silent stand-ins. See [Test speed](#test-speed).
- `-show-join` opens the Join screen. `-open-link <url>` handles a link as if it was tapped.
  `-invite-host <name>` makes the name screen's "saved you a seat" peek answer with a made-up host
  (no server).
- A host's first table opens with a House Cat in the first open seat (first-run funnel). Like the
  tips it is off in staged runs; `-house-cat` turns it on there (`FirstRunTests`, `FunnelShotTests`).
- For screenshots: `-demo-home` puts sample tables on Home (`-demo-home calm`: the same tables, none
  waiting on you), `-show-rules` / `-show-people` open
  those sheets over Home, and `-show-scoreboard` opens the scoreboard over a table. `-shelf all`
  shows every game on Home's shelf as playable and `-shelf six` fills the shelf with six games
  (four of them made up), to look at its layouts.
- First-game coaching tips are off under `-uitest-reset` and `-demo` (no bubble over a test's
  taps); add `-tips` to turn them on there (`TutorialTests`), or `-no-tips` to turn them off on
  a phone's own data (`MultiSimTests`). Tips seen are kept per person in `tutorial.json`, next to
  `people.json`; How to play (Home's gear, the table's paw menu) can bring them back.
- UI tips (`Pounce/Shell/Tips.swift`, rules in PounceKit's `Tutorial/UITips.swift`) teach the
  app's own controls: one yellow bubble at a time, pointing at a control marked `.tipTarget(id)`
  and drawn by the screen's `.tipHost(screen)`. They are off in every staged run (the same rule
  as the rating ask: `-demo`, `-uitest-…`, `-anim-speed`, `-show-…`, `-seed-…`, `-stub-…`,
  `-age-band`, …) and under `-no-tips`; `-ui-tips` turns them on there (`UITipsTests`), and
  `-tips-seen ui.home.shelf,ui.home.join` marks some as seen for the owner (screenshots of later
  tips). They share `tutorial.json` with the game's tips ("ui." names) and pace themselves with
  `tip-pacing.json` (app opens, tips per person per day). Settings' Reset tips brings every tip
  back.
- The App Store rating ask (`RatingPrompt` in PounceKit) never runs, and no finished game is counted
  for it, in a run with `-demo`, `-uitest-reset`, `-anim-speed`, `-slowmo`, `-age-band`,
  `-age-range`, or any `-demo-…`, `-show-…`, `-stub-…`, `-seed-…` argument. What it remembers is in
  `rating.json`, next to `people.json`.
- The `pounce-dev://j/<CODE>[?move=<MOVECODE>]` URL scheme is registered in Debug only, for
  `xcrun simctl openurl booted ...` (universal links need the deployed server). Release builds
  never register or accept it.
- Push cannot arrive in Debug builds. Test payload handling with `scripts/push.sh <CODE> [NAME]`
  (an `xcrun simctl push` with a payload shaped like the server's).
- Accounts and age (spec §10.5, §14.1): `-stub-accounts <upgraded|merged|link-merge|cancel|signed-in>`
  swaps Sign in with Apple and the account routes for in-memory fakes (no Apple account, no server).
  `-age-range <kitten|teen|adult|declined|unavailable>` stubs Declared Age Range; any test run
  (`-anim-speed`) without it answers `adult`. Under `-uitest-reset`, `-age-band <band>` starts
  with that band, `-age-range` starts with none (the age screen), and `-uitest-age-service <name>`
  keeps the age record in its own Keychain item. For screenshots: `-seed-people` (an owner and two
  others under `-uitest-reset`), `-show-gear`, `-show-merge` (with `-show-gear`) and
  `-show-household-age` (with `-show-people`).

- Streaks (spec §9, §10): `-demo-streaks` swaps the streak routes for `DemoStreakService`, which plays
  `DemoFixtures.streaks()` in memory (a long pinned streak with a gift, a win-back, a pause and a
  ghosted cat), so Home's badge, the Us screen and the look tray's unlocks draw with no server;
  `-demo-streaks off` is a server with streaks off (every list a 404: no badge, no Us screen).
  `-show-us` opens on the Us screen and `-show-gift` opens its first gift (screenshots). Demo tables
  carry the standard look, so the paw menu's look tray and the game over's Play again show; a demo's
  Play again deals a demo table under `NWCDF`.
- The strip, the trophy room and adding people (trophy room design): with `-demo-streaks` the list also
  carries your own streak (12, a nap yesterday) and `DemoTrophyService` serves the trophy room from
  the demo pairs; `-demo-streaks empty` has nobody connected yet (Home's bouncing Invite). `-show-trophies`
  opens the trophy room and `-show-invite` the invite sheet over Home; a kitten's invite under
  `-demo-streaks` shows the room code `TB4XN`. `TrophyTests` takes the screenshots
  (`TEST_RUNNER_TROPHY_SHOTS_DIR`, `TEST_RUNNER_TROPHY_SHOTS_ORIENTATION=landscape` on an iPad).
- Notifications and Pounce (spec §12): with `-demo-streaks`, `DemoPounceService` plays the pounce
  routes in memory (Kiki's pounce waits on you, Nova's bell rests, a send rings Mia's bell).
  `-show-notify` opens the Us screen's settings panel, `-show-pounce` the Pounce sheet, and
  `-show-pair <i>` picks a pair first (all with `-show-us`); `-show-link` opens the demo Messages
  link's pick sheet (from Leo). `-request-push` asks for notifications at launch, and
  `-demo-communication` posts a pounce from Mia once the app is in the background, drawn exactly as `PounceNotify` draws a push (the
  simulator's `simctl push` skips service extensions; `scripts/push-pounce.apns` is the sample
  payload for a device). `PushShotTests` takes the notification screenshots.
- Widgets (spec §11): `-demo-streaks` (and any `-uitest-reset` or `-demo` run) writes the demo pairs to
  the widgets' snapshot with no server, so the widgets on the simulator's home and lock screen draw
  them and never fetch. `-open-widget-link <pounce-widget://…>` handles a widget tap at launch
  (`WidgetLinkTests`). Every family, state and rendering mode has an Xcode preview in
  `PounceWidgets/Previews.swift`.
- Live table (spec §11.3): `-demo-live-table mine|theirs [seats]` starts a local live table from the
  demo fixture at launch (no server, no push), for the Lock Screen and the Dynamic Island.
  `LiveShotTests` takes the screenshots (`TEST_RUNNER_POUNCE_SHOTS_DIR`); the previews are in
  `PounceWidgets/Previews.swift`. iPad shows the live table on its Lock Screen too (no Dynamic Island).
- App updates (`docs/superpowers/specs/2026-11-12-app-updates-design.md`): `-demo-update <soft|locked|table|required>`
  is one of the update moments with no server (`UpdateDemo`). `soft`: Home with "Update ready".
  `locked`: Home with a table behind a padlock. `table`: a table that answers "this game needs a newer
  app"; add `-update-latest none` for the wording when the App Store has nothing newer. `required`: the
  full "Update Pounce to keep playing" screen. `-update-channel testflight` makes any run a TestFlight
  install (Update becomes "Open TestFlight"; the soft card never shows there), and `-age-band kitten`
  (with `-uitest-reset`) a child's device (no button: "Ask a grown-up to update Pounce."). Under the
  `required` screen's button a quiet "Account" (or "Your data", signed out) opens sign out and delete,
  which the server still answers for a version it refuses; `-stub-accounts signed-in` signs the demo in
  and `-show-update-account` opens that sheet at launch. Use them with
  `-uitest-reset -seed-people -age-band adult`. Screenshots are in `Art/screenshots/app-updates/`. What
  it remembers is in `updates.json`, next to `people.json`.
- Parent consent (daily habit PR 9): `-demo-kitten locked|held|pending|on` is a kitten's own device
  (with `-age-band kitten`; `-kitten-held` keeps the significant change owed) and `-demo-kittens` a
  parent's Kittens panel (with `-stub-accounts signed-in`), both from `DemoKittenService` with no
  server. The demo's Twilio Verify code is `135790`; `-open-kittens <k_…>` opens the panel on that
  kitten as a consent notification's tap does. The notice page loads from the server. `KittenTests` drives them, and saves screenshots
  when the runner sets `TEST_RUNNER_KITTEN_SHOTS_DIR` (`TEST_RUNNER_KITTEN_SHOTS_ORIENTATION=landscape`
  on an iPad).

## Play on your phone

Phones reach the dev server over Tailscale, through one extra `tailscale serve` on one https port
(default 8443; set `POUNCE_TAILNET_PORT` to use another, for example when something else on the Mac
already listens on 8443).

1. Start the dev server: `scripts/dev-server.sh`.
2. Expose it: `scripts/tailnet-serve.sh up` (`status` shows what is served, `down` removes it).
   The script only ever adds or removes the serve on its one port. It never touches any other serve
   (for example the one on `:4343`), and it refuses if the port is already used by something else. A
   process on the Mac that listens on that port itself can answer before the serve does; `up` warns
   if it sees one, and then you should pick another port. Check with
   `curl -s https://<mac>.<tailnet>.ts.net:<port>/healthz`, which should say `"configured":true`.
3. `cp Config/Local.xcconfig.example Config/Local.xcconfig` (gitignored). It sets
   `POUNCE_API_BASE_URL = https://gin-and-tonic.tailc8d3c2.ts.net:8443`. If you chose another port with
   `POUNCE_TAILNET_PORT`, change the port in that URL to match.
4. `scripts/bootstrap.sh`, then run the `Pounce` scheme on the phone from Xcode with automatic signing
   (team `B222J9J7B8`).
5. When done: `scripts/tailnet-serve.sh down` (with the same `POUNCE_TAILNET_PORT`, if you set one).

A LAN alternative with no Tailscale: start the dev server with `DEV_SERVER_IP=0.0.0.0
scripts/dev-server.sh` (it listens on 127.0.0.1 only by default) and set
`POUNCE_API_BASE_URL=http://<mac-ip>:8787` in the scheme's environment. This exposes a
token-minting dev server to the whole LAN, so use it only on a network you trust. iOS may ask for
local network permission.

Share links always use `play.conleychaos.com`, so on the phone join by typing the room code. The QR
code works only once the server is deployed. Debug builds get sandbox APNs tokens and the server
pushes through production APNs, so a debug build never receives a real "your turn" push.

## Tests

```sh
swift test --package-path PounceKit                       # game model, networking, store
xcodebuild -project Pounce.xcodeproj -scheme Pounce \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build-for-testing
scripts/check-assets.sh                                   # manifest, asset catalog, sounds, ArtName.swift agree
```

The UI suite includes tests that play against the live dev server, so run it through
`scripts/ui-tests.sh` (below), not a bare `xcodebuild test`.

### iPad

`IPadTests.swift` runs only on an iPad simulator (a phone skips it). `IPadRotationTests` plays a
turn against a bot and turns the iPad between landscape and portrait mid-turn. It checks that the
hand, its order, the step and the turn survive each turn, and that the table lays out again for the
new shape. The `Landscape*` classes run `ReorderTests`, `HitTests`, `TurnCueTests`, `NamesTests` and
`TableNameTests` again with the iPad on its side. For a whole game on two iPads, run
`SIM_A=<iPad> SIM_B=<iPad> ORIENTATION_A=rotate ORIENTATION_B=landscape scripts/multi-sim.sh`.

### End-to-end

`e2e.sh`, `ui-tests.sh` and `multi-sim.sh` start the dev server themselves when it is not already
running and stop it again on exit (a server that was already up is left alone). They share
`DEV_SERVER_URL` (default `http://localhost:8787`) and `DEV_SERVER_LOG`, and all of them run fast by
default (`SPEED=10`; see [Test speed](#test-speed)). `screenshots.sh` needs no
server (it uses demo modes, plus whatever the device already knows for Home).

| Script | What it does | Environment |
| --- | --- | --- |
| `scripts/e2e.sh [pounce-e2e args]` | Plays a scripted full game against the server with the `pounce-e2e` CLI (default `full --local 2 --bots 2 --timeout 1800`, about 11 minutes at `SPEED=1`). | `DEV_SERVER_URL`, `DEV_SERVER_LOG`, `SPEED` |
| `pounce-e2e scenario stall [--stall 20] --base <url>` | The playtest's slow move: two phones at a table, and one phone's network goes dead (sends, frames and pings held, connects time out) just as it discards. Prints when that phone shows weak and reconnecting, when the other sees its seat weak and lost, and when the move lands, and checks it landed once. Run it from `PounceKit/` with `swift run` against any dev server. | `--stall` seconds (default 20; under 11 shows weak only, with no reconnect) |
| `scripts/ui-tests.sh [xcodebuild args]` | The XCUITest suite on a simulator, with the dev server and a host broker (Mac-side `pounce-e2e` remotes and `simctl push`). Pass `-only-testing:PounceUITests/SmokeTests` to narrow it. | `DESTINATION` (default iPhone 17 Pro, iOS 26.2), `SPEED`, `POUNCE_UITEST_TIMEOUT_SCALE` (default 1; use 3 on a busy Mac) |
| `scripts/multi-sim.sh` | Two simulators: both open the same lobby through a `pounce-dev://` link, then a host game moves seats to the phones and `MultiSimTests` plays them to game over. Screenshots land in `$OUT/shared`. | `SIM_A`, `SIM_B` (UDIDs), `OUT`, `MOVE_AT`, `SPEED`, `SKIP_BUILD=1`, `LOBBY_ONLY=1` (lobby screenshots only), `KEEP_B=1` (leave B booted), `ORIENTATION_A` / `ORIENTATION_B` (iPads: `landscape`, or `rotate` to turn over at every round), `DD` |
| `scripts/phone-game.sh` | A game hosted on a plugged-in iPhone (Developer Mode and UI Automation on) against the live server: `PhoneGameTests` hosts and plays its seat by taps, a `pounce-e2e join` remote on the Mac takes seat 1, House Cats fill the rest, and it runs to game over. Needs no dev server. | `DEVICE` (UDID; default the first connected iPhone), `BASE` (default https://play.conleychaos.com), `BOTS` (default 1), `SPEED` (the phone only; the live server's bots keep their pace), `OUT`, `SKIP_BUILD=1` |
| `IPadScreenshotTests` (UI test) | Screens in portrait and landscape: iPadOS won't let the app rotate itself, so this test turns the simulator. Each `name=launch args` entry lands as `<name>-<orientation>.png`. The iPad set is in `Art/screenshots/ipad/`. | `TEST_RUNNER_POUNCE_SHOTS_DIR` (skipped without it), `TEST_RUNNER_POUNCE_SHOTS` (`table=-demo table;join=-show-join`), `TEST_RUNNER_POUNCE_SHOTS_ORIENTATIONS`, `TEST_RUNNER_POUNCE_SHOTS_WAIT` |
| `ScreenTourTests` (UI test) | A tour of every screen but Home and How to play, for copy and fit reviews: each stop launches a demo (no server), taps its way to one screen and saves `<name>-<orientation>.png`. Set the simulator's text size first (`xcrun simctl ui <device> content_size accessibility-extra-extra-extra-large`). The copy pass's before and after set is in `Art/screenshots/copy-pass/`. | `TEST_RUNNER_TOUR_DIR` (skipped without it), `TEST_RUNNER_TOUR_ONLY` (stop names, comma separated), `TEST_RUNNER_TOUR_ORIENTATIONS` |
| `scripts/screenshots.sh` | The six main screens into `Art/screenshots/*.jpg` from the installed Debug build (build and install first; `multi-sim.sh` does both). | `DEVICE` (UDID), `RAW_DIR`, `CELEBRATE_AT` (seconds into the slow-motion celebrate demo) |

The UI suite should run through `scripts/ui-tests.sh` because the live tests need the dev server.

### Test speed

One knob, `SPEED`, makes a game run many times faster for tests. It defaults to 10 in every test
script; `SPEED=1` is a normal-speed run (for watching a game, or to check nothing depends on the
speed-up).

```sh
scripts/ui-tests.sh                                     # fast (SPEED=10)
SPEED=1 scripts/ui-tests.sh                             # normal speed
SPEED=20 DEV_SERVER_URL=http://localhost:8788 scripts/ui-tests.sh   # faster, with fast bots
```

- The app (Debug only; Release ignores it) takes `-anim-speed <n>` or `POUNCE_ANIM_SPEED`. It runs
  the table scene at that speed (every SpriteKit action, celebration and particle burst), shell
  animations through `Animation.paced` and paced sleeps through `Pace.seconds` / `Pace.duration`
  (`Pounce/Design/Pace.swift`), and UIKit animations (sheets) through the window's layer speed. Any
  `-anim-speed`, even 1, also swaps `Sound.shared` and `Haptics.shared` for silent stand-ins, so tests
  never touch the audio session or the Taptic Engine. New animations and waits should go through
  `.paced` / `Pace` too, or they stay at normal speed under test.
- The UI tests read `POUNCE_SPEED` (the scripts pass `TEST_RUNNER_POUNCE_SPEED=$SPEED`): `Live.app()`,
  `Live.demo(...)` and `Live.arguments()` launch the app at that speed, and fixed waits for an
  animation (`Live.pace`) and poll intervals (`Live.poll`, floored at 0.25 s so polling never starves
  the app's main thread) shrink to match. Timeouts (`Live.t`) don't change: they only cap a wait.
  `HardeningTests.testCurtainNeedsAFullUnbrokenHold` always runs at speed 1, since the hold's timing is
  what it tests.
- The server paces a game too: the House Cat thinks for 1.2 s and the next round is dealt 6 s after
  a round ends. `scripts/dev-server.sh` with `DEV_SERVER_SPEED=<n>` passes `--var DEV_SPEED:<n>` to
  `wrangler dev`, which divides both (capped at 100; `/healthz` reports `"speed"` when it isn't 1).
  Nothing in production sets `DEV_SPEED` (a play-api test checks `wrangler.jsonc`), and no client can.
  A script that starts its own dev server starts it at `SPEED`; one that finds a server already up
  uses it as it is and prints its speed. To get fast bots next to a shared normal-speed server on
  8787, give the script another port with `DEV_SERVER_URL=http://localhost:8788`.

## Games

Home's shelf shows one card per entry in `PounceKit/Sources/PounceKit/Games/GameCatalog.swift`
(id, title, one-line pitch, players, cover art, tint, availability) and nothing else.

- **A new game** is one `GameCatalog.Entry` in `all` plus its cover: a 3:2 painting with the
  subject in the middle (Home shows it whole on an iPad, as a wide banner on a phone and as a
  centred square on a "Coming soon" ticket). Add the prompt under `Art/prompts/ui/`, a manifest
  entry (`"points": [384, 256], "fit": "cover"`), the name in `ArtName.swift`, then copy the raw
  painting to `Art/cut/` and run `Art/tools/build-assets.sh <name>`.
- **Turning the second game on** is one line: `GameCatalog.tiles`' `availability: .comingSoon`
  becomes `.available`. Its card then starts a table by asking the create route for
  `"game": "tiles"`, so the server has to deal that game first; until it does, a tap shows
  Home's "Couldn't start a game" message. `-shelf all` previews the shelf with every game on.
- The two covers were made with the art pipeline below:

  ```sh
  cd Art
  A=../Pounce/Resources/Assets.xcassets
  tools/gen.sh prompts/ui/game-cat-tower.txt raw/game-cat-tower.png "$A/game-tile.imageset/game-tile@3x.png" \
    "$A/Cats.spriteatlas/cat0-celebrate.imageset/cat0-celebrate@3x.png" "$A/AppIcon.appiconset/AppIcon.png"
  tools/gen.sh prompts/ui/game-tiles.txt raw/game-tiles.png "$A/Cats.spriteatlas/cat1-idle.imageset/cat1-idle@3x.png" \
    "$A/Cats.spriteatlas/cat1-celebrate.imageset/cat1-celebrate@3x.png" "$A/Cards.spriteatlas/card-yarn.imageset/card-yarn@3x.png"
  cp raw/game-cat-tower.png raw/game-tiles.png cut/
  tools/build-assets.sh game-cat-tower game-tiles
  ```

  The tile game's cover took two passes: the second had the first as one more reference and
  the tile design spec's four toys (fish, mouse, feather, bell) in its prompt. A new generation
  won't match either cover, so keep the checked-in art unless the game's look changes.

`GameShelfTests` covers the shelf with no server, and saves screenshots when the runner sets
`TEST_RUNNER_SHELF_SHOTS_DIR` (`TEST_RUNNER_SHELF_SHOTS_ORIENTATION=landscape` on an iPad). The
set from this change is in `Art/screenshots/game-picker/`.

Home is a hub: a player bar (the owner's cat, the streak strip, the gear), a column that leads with
your tables while a game is going and with the games otherwise, and a dock with Join (and Practice
before your first table). `HomeShotTests` saves Home in every state (new player, tables, the
sign-in card, the update card, a locked table, a child's device, six games, the biggest text) when
the runner sets `TEST_RUNNER_HOME_SHOTS_DIR`; an iPad takes each in portrait and landscape. Before
and after shots of the redesign are in `Art/screenshots/home-redesign/`.

## Art pipeline

Art is generated, cut out and built into the asset catalog; every name lives in `Art/manifest.json`.

1. `Art/tools/gen.sh <prompt.txt> <out.png> [ref.png...]` generates an image with the Codex CLI, using
   `Art/style-samples/chosen-d-loud-toy.png` as the style reference. Output goes to the gitignored
   `Art/raw/`. Prompts live in `Art/prompts/`; `Art/tools/run.sh` runs a batch.
2. Cutout: `Art/tools/cut.sh <name>...` (Vision, `cutout.swift`), or `cutkey.sh` for subjects Vision
   mis-masks. Results go to the gitignored `Art/cut/`.
3. `Art/tools/build-assets.sh <name>... | --all` writes @2x/@3x art into `Pounce/Resources/Assets.xcassets`
   at the manifest sizes. `Art/tools/placeholders.sh` fills any name without art yet.
   `Art/tools/habit-placeholders.sh` draws the daily habit placeholders (manifest batch `habit`: condos,
   toys, card backs, rugs, the gift box, paw badges, streak icons) from the existing art; they carry
   `_ph` like every placeholder, so real art replaces them by name.
4. `scripts/check-assets.sh` verifies the catalog and sounds against the manifest.

The tile game's art (manifest batch `tiles`, prompts in `Art/prompts/tiles/`) came through the same
pipeline: the four toy glyphs (`tile-fish`, `tile-mouse`, `tile-feather`, `tile-bell`), the toy box open
and closed, and its rug (`rug-play`). The tokens themselves are drawn in code around the glyphs.

The art style is "Loud Toy": saturated violet, hot magenta, electric teal, sunny orange, sky blue,
thick dark outlines. Never beige or muted.

## TestFlight

```sh
scripts/testflight.sh --dry-run    # print the commands, run nothing
scripts/testflight.sh              # bootstrap, archive (Release), export and upload
```

The build number is the current time as `YYYYMMDDHHMM`, passed to `xcodebuild` (project files are not
edited). By default Xcode's signed-in account does the signing and upload. To use an App Store Connect
API key instead, export `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_PATH` (path to the `.p8`, kept
outside the repo). `ExportOptions.plist` selects `app-store-connect`, destination `upload`, team
`B222J9J7B8`, automatic signing. Release builds use `https://play.conleychaos.com` and register no
custom URL scheme.

CI does this for you. `.github/workflows/ios.yml` runs the PounceKit tests and an unsigned Release
build on every pull request (`build` is a required check on `main`), and on each push to `main` that
touches `apps/play-ios` it runs
`scripts/testflight.sh` with an App Store Connect API key (Admin role, so Xcode can manage signing
and distribute builds).
It needs the repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` (the `.p8` file's
contents); until they exist the upload is skipped with a notice.

### Sending a build to testers

A push to `main` that touches `apps/play-ios` uploads a build and sends it to **Family and Friends**
(the external group) as well as the internal testers: every change reaches the family. Later builds
of an approved version usually clear beta app review in minutes. To pick another group or resend a
build, run the workflow by hand: Actions → iOS → Run workflow on `main` (or
`gh workflow run ios.yml --ref main`). Its inputs:

- `distribute` (default on): after the upload, run `scripts/distribute.swift` for that build. Off
  means upload only.
- `group` (default `Family and Friends`): the beta group, looked up by name.
- `build` (default empty): distribute this already-uploaded build number and skip the archive, e.g.
  a build uploaded from a Mac with `scripts/testflight.sh` when CI can't sign
  (`gh workflow run ios.yml --ref main -f build=202611040600`).
- `revoke_ci_certs` (default off): before archiving, revoke every development certificate CI ever
  created (`scripts/certs.swift --revoke-api-created`). Each fresh runner's archive mints one; the
  job now revokes its own when it finishes, but runs before that left them behind until Apple
  refused with "Your account has reached the maximum number of certificates". Certificates a Mac
  made through Xcode are named after its user and are left alone.

`scripts/distribute.swift` talks to the App Store Connect API with the same key (an ES256 JWT signed
with CryptoKit; neither the key nor the token is ever printed). It waits up to 30 minutes for the
build to finish processing, answers export compliance if it is still pending (Info.plist already
sets `ITSAppUsesNonExemptEncryption` to false, so normally it isn't), sets "What to Test" from the
commit subjects since the group's previous build (CI, docs and chore commits are left out; with no
previous build, a short default), adds the build to the group and, for an external group, submits it
for beta app review when App Store Connect says the build is ready for one. Apple reviews the first
build of a version; later builds are usually approved in minutes. The run's summary shows the notes
that went out.

Run it locally with the same three `ASC_*` variables as `testflight.sh`:

```sh
scripts/distribute.swift --dry-run                         # read only: notes and planned changes
scripts/distribute.swift --build 202611020653              # distribute that build to Family and Friends
scripts/distribute.swift --build 202611020653 --group "Family and Friends" --since 2026-11-01
```

`--build` defaults to the newest upload, `--since` overrides the start of the What to Test commit
list, and `--timeout` sets the processing wait in minutes. Without credentials, `--dry-run` prints
the plan and the notes only. External testing also needs the app-level Test Information in App Store
Connect (feedback email, beta app description, review contact); if it's missing, the review
submission fails with Apple's message in the log.

### Prerequisites only JD can do

- Sign in with Apple and Declared Age Range are new entitlements (daily habit PR 2). Automatic
  signing with `-allowProvisioningUpdates` turns both capabilities on for the App ID when the App
  Store Connect key has Admin access (or App Manager with access to Certificates, Identifiers &
  Profiles). If the first archive after this change fails on provisioning, enable them by hand:
  Certificates, Identifiers & Profiles, Identifiers, `com.conleychaos.play`, tick **Sign In with
  Apple** (Configure: **Enable as a primary App ID**) and **Declared Age Range**, Save. Then check
  the archive: `codesign -d --entitlements - <Pounce.app>` lists `com.apple.developer.applesignin`
  and `com.apple.developer.declared-age-range`.

- The widgets (daily habit PR 6) add an App ID, an App Group and two capabilities. Automatic signing
  with `-allowProvisioningUpdates` and an Admin (or App Manager with Certificates, Identifiers &
  Profiles) key normally creates them. If the first archive fails on provisioning, in Certificates,
  Identifiers & Profiles:
  1. Identifiers, +, App Groups: `group.com.conleychaos.play`.
  2. Identifiers, +, App IDs, App: `com.conleychaos.play.widgets` (description "Pounce Widgets"),
     with **App Groups** (assign `group.com.conleychaos.play`) and **Push Notifications**.
  3. `com.conleychaos.play` and `com.conleychaos.play.notify`: tick **App Groups** and assign
     `group.com.conleychaos.play`.
  Keychain sharing (`<team>.com.conleychaos.play`) needs no portal change. Check the archive:
  `codesign -d --entitlements - <Pounce.app/PlugIns/PounceWidgets.appex>` lists
  `com.apple.security.application-groups`, `keychain-access-groups` and `aps-environment`.

- Parent consent (daily habit PR 9) needs no new capability: PermissionKit and `AppTransaction` need
  no entitlement, and Declared Age Range already has one (PR 2). It needs the App Store Server Notifications URL in App Store
  Connect and the four Twilio Verify secrets (root README). Its confirmation push uses a new
  notification category, `CONSENT`, with a Revoke button; no portal change.

- The live table (daily habit PR 7) needs no new App ID, capability or key: Live Activities ride on
  the app's Push Notifications capability (`NSSupportsLiveActivities` in its Info.plist), and the
  server pushes to `com.conleychaos.play.push-type.liveactivity` with the same token-based APNs key.

- Apple Developer: enable Push Notifications and Associated Domains on the App ID
  `com.conleychaos.play`.
- Create an APNs auth key, store the `.p8` in 1Password, and set the deploy secrets
  `PLAY_API_APNS_KEY_P8` and `PLAY_API_APNS_KEY_ID` (the other deploy secrets are in the root README).
- Create the App Store Connect app record for `com.conleychaos.play`, and add TestFlight testers.
- Deploy the server to `play.conleychaos.com` (also needed for the QR code, universal links, and the
  invite bubble art).

`MANUAL-CHECKLIST.md` lists the checks no script can do.
