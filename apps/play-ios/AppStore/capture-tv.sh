#!/bin/bash
# Raw captures for the Apple TV App Store screenshots: the Debug PounceTV build on an Apple TV 4K
# simulator at 1080p, so every PNG is 1920x1080 (App Store Connect takes 1920x1080 or 3840x2160).
# Writes AppStore/raw/tv/<name>.png; the PNGs become JPEGs with sips (see README).
#   AppStore/capture-tv.sh <udid>
# Build and install first (an "Apple TV 4K (3rd generation) (at 1080p)" simulator):
#   xcodebuild -project Pounce.xcodeproj -scheme PounceTV -destination "platform=tvOS Simulator,id=<udid>" build
#   xcrun simctl install <udid> <DerivedData>/Build/Products/Debug-appletvsimulator/PounceTV.app
# The two tables come from the Debug build's own preview (a made-up room, no server), with the aim
# glow on the player whose turn it is. Home, the lobby and game over need a server and phones:
# `AppStore/tv-live.spec.ts` plays them (see README), and writes the same raw folder.
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
  xcrun simctl launch "$DEVICE" "$BUNDLE" "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$DEVICE" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
  echo "$OUT/$name.png"
}

shot cattower 9 -tv-preview cattower -seats 4 -aim
shot tiles 9 -tv-preview tiles -seats 3
