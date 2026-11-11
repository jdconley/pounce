#!/bin/bash
# Raw captures for the App Store screenshot set: the Debug build's real screens, fed by the
# app's own demo modes (no server), on a simulator of the store's size. Writes
# AppStore/raw/<set>/<n>-<name>.png at the device's native pixels; compose.swift adds the
# caption and background.
#   AppStore/capture.sh iphone <udid>   # iPhone 17 Pro Max: 1320x2868 (the 6.9" set)
#   AppStore/capture.sh ipad <udid>     # iPad Pro 13-inch (M5): 2064x2752 (the 13" set)
# Build and install first:
#   xcodebuild -project Pounce.xcodeproj -scheme Pounce -destination "platform=iOS Simulator,id=<udid>" build
#   xcrun simctl install <udid> <DerivedData>/Build/Products/Debug-iphonesimulator/Pounce.app
# The people on screen come from POUNCE_DEMO_CAST (DemoFixtures.cast): you, your person, then
# the rest of the family. `-anim-speed 1` keeps the simulator silent.
set -euo pipefail
cd "$(dirname "$0")/.."
SET="${1:?iphone or ipad}"
DEVICE="${2:?simulator UDID}"
BUNDLE=com.conleychaos.play
OUT="AppStore/raw/$SET"
CAST="${POUNCE_DEMO_CAST:-Jess,Sam,Grandma,Theo,Ruby,Grandpa}"
mkdir -p "$OUT"

xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl get_app_container "$DEVICE" "$BUNDLE" app >/dev/null
trap 'xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true' EXIT
xcrun simctl status_bar "$DEVICE" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularBars 4 --dataNetwork wifi >/dev/null

# shot <n-name> <seconds> [launch args...]
shot() {
  local name="$1" wait="$2"
  shift 2
  xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
  SIMCTL_CHILD_POUNCE_DEMO_CAST="$CAST" xcrun simctl launch "$DEVICE" "$BUNDLE" \
    -anim-speed 1 -uitest-reset "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$DEVICE" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
  echo "$OUT/$name.png"
}

# `-seed-people` gives the device an owner (and skips the push priming card over a table).
shot 1-table 8 -seed-people -demo table
shot 2-us 7 -seed-people -demo-streaks -show-us
shot 3-family 6 -seed-people -demo lobbyFamily
shot 4-levels 7 -seed-people -demo table -show-scoreboard
# A child's first launch: a cat and a name from the list (the dice), never typed.
shot 5-kids 7 -age-band kitten
shot 6-win 9 -seed-people -demo over
