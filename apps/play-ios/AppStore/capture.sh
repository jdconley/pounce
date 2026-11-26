#!/bin/bash
# Raw captures for the App Store screenshot set: the Debug build's real screens, fed by the
# app's own demo modes (no server), on a simulator of the store's size. Writes
# AppStore/raw/<set>/<n>-<name>.png at the device's native pixels; compose.swift adds the
# caption and background.
#   AppStore/capture.sh iphone <udid>   # iPhone 17 Pro: 1206x2622 (the required "Dynamic Island, medium display" set)
#   AppStore/capture.sh ipad <udid>     # iPad Pro 13-inch (M5): 2064x2752 (the 13" set)
#   AppStore/capture.sh iphone <udid> 2-bird 3-trump    # only these shots
# Build and install first:
#   xcodebuild -project Pounce.xcodeproj -scheme Pounce -destination "platform=iOS Simulator,id=<udid>" build
#   xcrun simctl install <udid> <DerivedData>/Build/Products/Debug-iphonesimulator/Pounce.app
# The people on screen come from POUNCE_DEMO_CAST (DemoFixtures.cast): you, your person, then
# the rest of the family. `-settings.soundOn <false/>` keeps the simulator silent (`-anim-speed 1`
# plays the real sounds).
set -euo pipefail
cd "$(dirname "$0")/.."
SET="${1:?iphone or ipad}"
DEVICE="${2:?simulator UDID}"
ONLY=("${@:3}")
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
  if [ ${#ONLY[@]} -gt 0 ] && [[ " ${ONLY[*]} " != *" $name "* ]]; then return; fi
  xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
  SIMCTL_CHILD_POUNCE_DEMO_CAST="$CAST" xcrun simctl launch "$DEVICE" "$BUNDLE" \
    -anim-speed 1 -settings.soundOn "<false/>" -uitest-reset "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$DEVICE" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
  echo "$OUT/$name.png"
}

# `-seed-people` gives the device an owner (and skips the push priming card over a table).
shot 1-table 8 -seed-people -demo table
# Birdwatch (1.3): a trick on the sill with cards you can't play dimmed; then naming trump.
shot 2-bird 8 -seed-people -demo bird-play
shot 3-trump 8 -seed-people -demo bird-trump
# The Daily Dish (1.2): today's four puzzles and the family board, everyone done; then Nine Lives
# half filled, played from memory (`-demo-dish` referees it in the app).
shot 4-dish 7 -seed-people -demo-streaks -demo-dish done -show-dish
shot 5-puzzle 7 -seed-people -demo-streaks -demo-dish done -show-daily nine-lives
shot 6-us 7 -seed-people -demo-streaks -show-us
shot 7-family 6 -seed-people -demo lobbyFamily
shot 8-levels 7 -seed-people -demo table -show-scoreboard
# A child's first launch: a cat and a name from the list (the dice), never typed.
shot 9-kids 7 -age-band kitten
shot 10-win 9 -seed-people -demo over
