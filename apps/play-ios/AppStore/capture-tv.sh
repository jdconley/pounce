#!/bin/bash
# Raw captures for the Apple TV App Store screenshots: the Debug PounceTV build on an Apple TV 4K
# simulator at 1080p, so every PNG is 1920x1080 (App Store Connect takes 1920x1080 or 3840x2160).
# Writes AppStore/raw/tv/<name>.png; the PNGs become JPEGs with sips (see README).
#   AppStore/capture-tv.sh <udid>
# Build and install first (an "Apple TV 4K (3rd generation) (at 1080p)" simulator):
#   xcodebuild -project Pounce.xcodeproj -scheme PounceTV -destination "platform=tvOS Simulator,id=<udid>" build
#   xcrun simctl install <udid> <DerivedData>/Build/Products/Debug-appletvsimulator/PounceTV.app
# The two tables come from the Debug build's own preview (a made-up room, no server), with the aim
# glow on the player whose turn it is. Game over is the Debug build's `-demo tv-over`: the whole TV
# back at a four-seat Cat Tower table that just finished (three-digit scores, four levels, four
# cats). The lobby needs a server and phones: `AppStore/tv-live.spec.ts` plays it (see
# README), and writes the same raw folder. Home, Tonight's board and a watched run come from
# `PounceTVUITests/BoardShotTests` (README, "Apple TV screenshots").
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:?Apple TV simulator UDID}"
BUNDLE=com.conleychaos.play
OUT="AppStore/raw/tv"
mkdir -p "$OUT"

xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl get_app_container "$DEVICE" "$BUNDLE" app >/dev/null
trap 'xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true' EXIT

# shot <name> <seconds> [launch args...]
shot() {
  local name="$1" wait="$2"
  shift 2
  xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$DEVICE" "$BUNDLE" -tv.soundOn "<false/>" "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$DEVICE" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
  echo "$OUT/$name.png"
}

# Toy Tumble at four seats, the family's names on the boxes (`-tumble-family`), its cats well into
# the round; then Purrtrait with the demo cat drawn on the easel (Animals).
SIMCTL_CHILD_POUNCE_DEMO_CAST="Jess,Sam,Grandma,Theo,Ruby,Grandpa" shot tumble 24 -demo tv-tumble -seats 4 -tumble-family
SIMCTL_CHILD_POUNCE_DEMO_CAST="Jess,Sam,Grandma,Theo,Ruby,Grandpa" shot purrtrait 9 -tv-preview purrtrait -seats 6
# Birdwatch mid-trick with the store's cast (`TVTablePreview` takes POUNCE_DEMO_CAST): its long name
# doesn't fit beside the sill at four seats.
SIMCTL_CHILD_POUNCE_DEMO_CAST="Jess,Sam,Grandma,Theo,Ruby,Grandpa" shot birdwatch 9 -tv-preview birdwatch -seats 4 -aim
shot cattower 9 -tv-preview cattower -seats 4 -aim
shot tiles 9 -tv-preview tiles -seats 3
shot gameover 9 -demo tv-over -seats 4
