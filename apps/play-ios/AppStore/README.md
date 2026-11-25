# App Store product page media

Screenshots and app previews for the App Store, and the scripts that make them. Everything on
screen is the Debug build's real UI in a simulator, fed by the app's demo modes (canned server
messages, no server); nothing is drawn by hand except the caption and the background.

| File | What |
| --- | --- |
| `screenshots/iphone-1.jpg` … `8` | 1206x2622, the required iPhone set (Dynamic Island, medium display; iPhone 17 Pro) |
| `screenshots/ipad-1.jpg` … `8` | 2064x2752, the 13" iPad set |
| `screenshots/tv-1.jpg` … `7` | 1920x1080, the Apple TV set (home, Tonight's board, lobby, Cat Tower, Tuna Tiles, game over, a watched Sniff run) |
| `previews/iphone-preview.mp4` | 886x1920, 25.4 s (recorded on an iPhone 17 Pro Max, cut to the size the iPhone slot takes) |
| `previews/ipad-preview.mp4` | 1200x1600, 25.4 s |
| `captions.json`, `captions.md` | The captions and what backs each one |
| `creative/header.png` | 3840x1646 (21:9), the product page header |
| `creative/search.jpg` | 3840x2560 (3:2), the search results image |

Specs followed: Apple's "Screenshot specifications" and "App preview specifications" pages in App
Store Connect Help, as read on 2026-11-11 (JPEG without alpha; previews H.264 High 4.0, 30 fps,
stereo AAC 256 kbps, 15 to 30 seconds).

## Make them again

```sh
scripts/bootstrap.sh
xcodebuild -project Pounce.xcodeproj -scheme Pounce -destination "platform=iOS Simulator,id=<udid>" build
xcrun simctl install <udid> <DerivedData>/Build/Products/Debug-iphonesimulator/Pounce.app
AppStore/capture.sh iphone <iPhone 17 Pro udid>   # raw/iphone/*.png
AppStore/capture.sh ipad <iPad Pro 13-inch (M5) udid>   # raw/ipad/*.png
AppStore/capture.sh iphone <udid> 2-dish 3-puzzle       # only those shots
swift AppStore/compose.swift                            # screenshots/*.jpg (keeps a shot with no raw capture)
AppStore/preview.sh iphone <udid>                       # previews/iphone-preview.mp4
AppStore/preview.sh ipad <udid>
```

The Daily Dish shots (2 and 3) use `-demo-dish done` (the Dish from memory) and
`-show-daily nine-lives`, which plays Nine Lives half filled against an in-app referee
(`NineLivesDemoServer`), with no server.

`raw/` is gitignored. The people on screen (Jess and Sam, Grandma, Theo, Ruby) come from
`POUNCE_DEMO_CAST`, which renames the demo fixtures' people (`DemoFixtures.cast`, DEBUG only).
The previews' sound is the game's own effects laid on the cut, since `simctl recordVideo`
records no audio.

## Header and search results images

These two are Apple's "creative assets" (iOS 27 and later): key art, not screenshots. Each is the
hero group on a procedural sunburst with the name and tagline in the app's type, composed by
`creative.swift`. Sizes are from "Creative assets specifications" in App Store Connect Help, as
read on 2026-11-11.

```sh
swift AppStore/creative.swift            # creative/header.png, creative/search.jpg
swift AppStore/creative.swift --guides   # the same with each layout's safe box drawn
```

The search results image is shown whole on every device. The header is not: App Store Connect's
Device Preview showed an iPhone trimming the sides and putting its back and share buttons over the
top corners, and an iPad or an unfolded iPhone Duo in landscape keeping only the middle band. The
header layout keeps the name, tagline and cats inside the part all of them show. After changing it,
upload it and check Device Preview on each device and orientation.

The hero group (`Art/store/store-hero.png`) was generated once with the art pipeline and is
checked in, because a new generation would not match it:

```sh
cd Art
A=../Pounce/Resources/Assets.xcassets
tools/gen.sh prompts/store/store-hero.txt raw/store-hero.png \
  "$A/AppIcon.appiconset/AppIcon.png" \
  "$A/Cats.spriteatlas/cat0-celebrate.imageset/cat0-celebrate@3x.png" \
  "$A/Cats.spriteatlas/cat1-idle.imageset/cat1-idle@3x.png" \
  "$A/Cats.spriteatlas/cat2-idle.imageset/cat2-idle@3x.png" \
  "$A/Cats.spriteatlas/cat3-idle.imageset/cat3-idle@3x.png"
tools/cut.sh store-hero                  # cut/store-hero.png
```

The cutout kept two small patches of the gray background enclosed by the cats (between the
tabby's tail and the tuxedo's ear). They were flood-filled to transparent with ImageMagick before
the file went to `Art/store/`.

## Apple TV icon and Top Shelf

The Apple TV app's brand assets (`PounceTV/Resources/TVAssets.xcassets`, "App Icon & Top Shelf
Image") are composed by `tv-brand.swift` from the app's own art: the living room from `home-bg`
under the sunburst, the cats, and the name in the app's type. The icon is three layers for the
parallax: the room (back, blurred), three cats cheering (middle), and the name with stars (front).
The Top Shelf images keep their art in the middle 1920 points, which both the plain and the wide
image show.

```sh
swift AppStore/tv-brand.swift                      # rewrites the brand assets
swift AppStore/tv-brand.swift --preview /tmp/tv    # also writes each icon flattened, to look at
```

## Apple TV screenshots

The Apple TV shots (`screenshots/tv-N.jpg`, 1920x1080, from an "Apple TV 4K (3rd generation)
(at 1080p)" simulator; App Store Connect also takes 3840x2160) are the Debug PounceTV build's real
screens, with no caption or background. The two tables come from the build's own preview, and game
over from its `-demo tv-over` (the whole TV back at a four-seat Cat Tower game that just ended:
three-digit scores, four levels, four cats, nobody left), all with no server. The lobby needs a TV
that is linked to a table, so a dev server and browser phones play it.

```sh
xcodebuild -project Pounce.xcodeproj -scheme PounceTV -destination "platform=tvOS Simulator,id=<udid>" build
xcrun simctl install <udid> <DerivedData>/Build/Products/Debug-appletvsimulator/PounceTV.app
AppStore/capture-tv.sh <udid>        # raw/tv/cattower.png, tiles.png, gameover.png (tv-4, tv-5, tv-6)
# raw/tv/lobby.png (tv-3): AppStore/tv-live.spec.ts, against your own dev server
# (its header says how); never port 4343.
sips -s format jpeg -s formatOptions 92 AppStore/raw/tv/<name>.png --out AppStore/screenshots/tv-<n>.jpg
```

Home, Tonight's board and the watched Sniff run (tv-1, tv-2, tv-7) come from the Debug build's
`-demo tv-board` (an evening of the Daily Dish on a fake board socket), played by
`PounceTVUITests/BoardShotTests`, which presses Watch on the remote:

```sh
TEST_RUNNER_TV_SHOTS_DIR=<dir> TEST_RUNNER_POUNCE_DEMO_CAST="Jess,Sam,Ruby,Theo,Grandma,Grandpa" \
  xcodebuild -project Pounce.xcodeproj -scheme PounceTV -destination "platform=tvOS Simulator,id=<udid>" \
  test -only-testing:PounceTVUITests/BoardShotTests
# <dir>/appletv-home.png, appletv-board.png, appletv-watch.png
```

The cast's fourth name takes the hint badge, so keep it short. In 1.2, tv-3 to tv-6 are the 1.1
shots (lobby, Cat Tower, Tuna Tiles, game over) under new numbers.

Look at each shot before converting it: the seats' scores behind game over must all show. Delete
the simulator afterwards.
