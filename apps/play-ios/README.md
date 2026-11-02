# Pounce (iOS)

Native iPhone client for the Pounce card game. iOS 26+, Swift 6 (strict concurrency), SwiftUI shell
with a SpriteKit table. Apple frameworks only, no third-party packages.

## Layout

- `project.yml` XcodeGen spec. `Pounce.xcodeproj` is generated and gitignored.
- `Pounce/` app target. `PounceUITests/` UI tests.
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

- Xcode 27 (iOS 26 SDK or later; the app's deployment target is iOS 26.0, iPhone only, portrait only).
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
every interface, for the LAN workflow below). The first run writes
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

- `-demo <lobby|lobbyReady|table|other|replay|nope|celebrate|curtain|handoff|peek>` opens a room fed by
  a fake socket and canned snapshots, so the real screens render with no server. `-slowmo <factor>`
  runs a demo at that speed. See `Pounce/App/DemoMode.swift` for what each demo shows.
- `-show-join` opens the Join screen. `-open-link <url>` handles a link as if it was tapped.
- The `pounce-dev://j/<CODE>[?move=<MOVECODE>]` URL scheme is registered in Debug only, for
  `xcrun simctl openurl booted ...` (universal links need the deployed server). Release builds
  never register or accept it.
- Push cannot arrive in Debug builds. Test payload handling with `scripts/push.sh <CODE> [NAME]`
  (an `xcrun simctl push` with a payload shaped like the server's).

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

### End-to-end

`e2e.sh`, `ui-tests.sh` and `multi-sim.sh` start the dev server themselves when it is not already
running and stop it again on exit (a server that was already up is left alone). They share
`DEV_SERVER_URL` (default `http://localhost:8787`) and `DEV_SERVER_LOG`. `screenshots.sh` needs no
server (it uses demo modes, plus whatever the device already knows for Home).

| Script | What it does | Environment |
| --- | --- | --- |
| `scripts/e2e.sh [pounce-e2e args]` | Plays a scripted full game against the server with the `pounce-e2e` CLI (default `full --local 2 --bots 2 --timeout 1800`, about 11 minutes). | `DEV_SERVER_URL`, `DEV_SERVER_LOG` |
| `scripts/ui-tests.sh [xcodebuild args]` | The XCUITest suite on a simulator, with the dev server and a host broker (Mac-side `pounce-e2e` remotes and `simctl push`). Pass `-only-testing:PounceUITests/SmokeTests` to narrow it. | `DESTINATION` (default iPhone 17 Pro, iOS 26.2), `POUNCE_UITEST_TIMEOUT_SCALE` (default 1; use 3 on a busy Mac) |
| `scripts/multi-sim.sh` | Two simulators: both open the same lobby through a `pounce-dev://` link, then a host game moves seats to the phones and `MultiSimTests` plays them to game over. Screenshots land in `$OUT/shared`. | `SIM_A`, `SIM_B` (UDIDs), `OUT`, `MOVE_AT`, `SKIP_BUILD=1`, `LOBBY_ONLY=1` (lobby screenshots only), `KEEP_B=1` (leave B booted) |
| `scripts/phone-game.sh` | A game hosted on a plugged-in iPhone (Developer Mode and UI Automation on) against the live server: `PhoneGameTests` hosts and plays its seat by taps, a `pounce-e2e join` remote on the Mac takes seat 1, House Cats fill the rest, and it runs to game over. Needs no dev server. | `DEVICE` (UDID; default the first connected iPhone), `BASE` (default https://play.conleychaos.com), `BOTS` (default 1), `OUT`, `SKIP_BUILD=1` |
| `scripts/screenshots.sh` | The six main screens into `Art/screenshots/*.jpg` from the installed Debug build (build and install first; `multi-sim.sh` does both). | `DEVICE` (UDID), `RAW_DIR`, `CELEBRATE_AT` (seconds into the slow-motion celebrate demo) |

The UI suite should run through `scripts/ui-tests.sh` because the live tests need the dev server.

## Art pipeline

Art is generated, cut out and built into the asset catalog; every name lives in `Art/manifest.json`.

1. `Art/tools/gen.sh <prompt.txt> <out.png> [ref.png...]` generates an image with the Codex CLI, using
   `Art/style-samples/chosen-d-loud-toy.png` as the style reference. Output goes to the gitignored
   `Art/raw/`. Prompts live in `Art/prompts/`; `Art/tools/run.sh` runs a batch.
2. Cutout: `Art/tools/cut.sh <name>...` (Vision, `cutout.swift`), or `cutkey.sh` for subjects Vision
   mis-masks. Results go to the gitignored `Art/cut/`.
3. `Art/tools/build-assets.sh <name>... | --all` writes @2x/@3x art into `Pounce/Resources/Assets.xcassets`
   at the manifest sizes. `Art/tools/placeholders.sh` fills any name without art yet.
4. `scripts/check-assets.sh` verifies the catalog and sounds against the manifest.

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
build on every pull request that touches `apps/play-ios`, and on each such push to `main` it runs
`scripts/testflight.sh` with an App Store Connect API key (Admin role, so Xcode can manage signing).
It needs the repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` (the `.p8` file's
contents); until they exist the upload is skipped with a notice. To upload without a code change, run
the workflow from the Actions tab.

### Prerequisites only JD can do

- Apple Developer: enable Push Notifications and Associated Domains on the App ID
  `com.conleychaos.play`.
- Create an APNs auth key, store the `.p8` in 1Password, and set the deploy secrets
  `PLAY_API_APNS_KEY_P8` and `PLAY_API_APNS_KEY_ID` (the other deploy secrets are in the root README).
- Create the App Store Connect app record for `com.conleychaos.play`, and add TestFlight testers.
- Deploy the server to `play.conleychaos.com` (also needed for the QR code, universal links, and the
  invite bubble art).

`MANUAL-CHECKLIST.md` lists the checks no script can do.
