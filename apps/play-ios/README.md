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
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test
```

If simulator code signing complains about provisioning, add `CODE_SIGNING_ALLOWED=NO` to the
`xcodebuild` command. It was not needed on the author's machine (ad hoc simulator signing).
