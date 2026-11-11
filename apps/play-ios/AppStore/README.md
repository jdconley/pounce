# App Store product page media

Screenshots and app previews for the App Store, and the scripts that make them. Everything on
screen is the Debug build's real UI in a simulator, fed by the app's demo modes (canned server
messages, no server); nothing is drawn by hand except the caption and the background.

| File | What |
| --- | --- |
| `screenshots/iphone-1.jpg` … `6` | 1206x2622, the required iPhone set (Dynamic Island, medium display; iPhone 17 Pro) |
| `screenshots/ipad-1.jpg` … `6` | 2064x2752, the 13" iPad set |
| `previews/iphone-preview.mp4` | 886x1920, 25.4 s (recorded on an iPhone 17 Pro Max, cut to the size the iPhone slot takes) |
| `previews/ipad-preview.mp4` | 1200x1600, 25.4 s |
| `captions.json`, `captions.md` | The captions and what backs each one |

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
swift AppStore/compose.swift                            # screenshots/*.jpg
AppStore/preview.sh iphone <udid>                       # previews/iphone-preview.mp4
AppStore/preview.sh ipad <udid>
```

`raw/` is gitignored. The people on screen (Jess and Sam, Grandma, Theo, Ruby) come from
`POUNCE_DEMO_CAST`, which renames the demo fixtures' people (`DemoFixtures.cast`, DEBUG only).
The previews' sound is the game's own effects laid on the cut, since `simctl recordVideo`
records no audio.
