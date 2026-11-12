#!/bin/bash
# The How to play videos: records real play in a simulator and cuts one captioned video per game.
#   HowTo/make.sh            # every game in HowTo/beats.json
#   HowTo/make.sh cat-tower  # or: tiles
# Writes Pounce/Resources/HowTo/howto-<game>.mp4 (H.264, 496x1080, 30 fps, no sound) and
# howto-<game>.jpg (the poster: the video's title card), which the app bundles.
#
# How: HowToVideoTests (PounceUITests) plays each game's scripted turns on demo tables, at normal
# speed with `-show-touches` (a ring under every tap and drag) and `-timecode` (the wall clock
# in a strip along the top edge), and logs when each beat starts. `simctl io recordVideo`
# records the whole run. cards.swift draws the title card and captions from beats.json;
# compose.py reads the clock in every frame, lays each segment out in real time, crossfades them
# after the title card and lays each beat's caption over it.
#
# Environment:
#   DEVICE      a simulator UDID (iPhone 17 Pro, iOS 26.x). Default: a new one, deleted at exit.
#   DD          derived data (default build/howto-dd, gitignored).
#   SKIP_BUILD=1    use the build already in $DD.
#   SKIP_RECORD=1   cut again from the recordings in $RAW (after editing captions or timings).
#   RAW         recordings and overlays (default HowTo/raw, gitignored).
# Needs Xcode, XcodeGen, ffmpeg with libx264, python3.
set -euo pipefail
cd "$(dirname "$0")/.."
DD="${DD:-build/howto-dd}"
RAW="${RAW:-HowTo/raw}"
OUT=Pounce/Resources/HowTo
mkdir -p "$RAW" "$OUT"
if [ $# -gt 0 ]; then GAMES=("$@"); else GAMES=(cat-tower tiles); fi

made_device=""
cleanup() {
  [ -n "${recorder:-}" ] && kill -INT "$recorder" 2>/dev/null || true
  if [ -n "$made_device" ]; then
    xcrun simctl shutdown "$made_device" >/dev/null 2>&1 || true
    xcrun simctl delete "$made_device" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

now() { python3 -c 'import time; print(f"{time.time():.3f}")'; }

if [ -z "${SKIP_RECORD:-}" ]; then
  if [ -z "${DEVICE:-}" ]; then
    runtime=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x["identifier"] for x in json.load(sys.stdin)["runtimes"] if x["identifier"].endswith(tuple("iOS-26-%d" % i for i in range(10)))]; print(r[-1])')
    DEVICE=$(xcrun simctl create "howto-make iPhone 17 Pro" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$runtime")
    made_device="$DEVICE"
  fi
  xcrun simctl boot "$DEVICE" 2>/dev/null || true
  xcrun simctl bootstatus "$DEVICE" -b >/dev/null
  xcrun simctl status_bar "$DEVICE" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularBars 4 --dataNetwork wifi >/dev/null
  if [ -z "${SKIP_BUILD:-}" ]; then
    xcodegen generate >/dev/null
    xcodebuild -project Pounce.xcodeproj -scheme Pounce -destination "platform=iOS Simulator,id=$DEVICE" \
      -derivedDataPath "$DD" build-for-testing -quiet
  fi
fi

for game in "${GAMES[@]}"; do
  test=$(python3 -c "import json; print(json.load(open('HowTo/beats.json'))['games']['$game']['test'])")
  if [ -z "${SKIP_RECORD:-}" ]; then
    rm -f "$RAW/$game.log" "$RAW/$game.mov" "$RAW/$game.rec"
    xcrun simctl io "$DEVICE" recordVideo --codec h264 --force "$RAW/$game.mov" 2>"$RAW/$game.rec" &
    recorder=$!
    for _ in $(seq 1 200); do grep -q "Recording started" "$RAW/$game.rec" 2>/dev/null && break; sleep 0.05; done
    now >"$RAW/$game.t0"
    echo "$game: recording ($test)"
    TEST_RUNNER_POUNCE_HOWTO_LOG="$PWD/$RAW/$game.log" TEST_RUNNER_POUNCE_SPEED=1 \
      TEST_RUNNER_POUNCE_DEMO_CAST="${POUNCE_DEMO_CAST:-}" \
      xcodebuild -project Pounce.xcodeproj -scheme Pounce -destination "platform=iOS Simulator,id=$DEVICE" \
      -derivedDataPath "$DD" test-without-building -only-testing:"PounceUITests/HowToVideoTests/$test" -quiet \
      || { echo "$game: the recording test failed"; exit 1; }
    kill -INT "$recorder"
    wait "$recorder" 2>/dev/null || true
    recorder=""
  fi
  swift HowTo/cards.swift "$game" "$RAW/$game-cards" >/dev/null
  python3 -I HowTo/compose.py "$game" "$RAW" "$OUT/howto-$game.mp4"
  # The poster: the title card, as the video shows it.
  ffmpeg -v error -y -ss 1.2 -i "$OUT/howto-$game.mp4" -frames:v 1 -q:v 3 "$OUT/howto-$game.jpg"
  ffprobe -v error -show_entries format=duration,size:stream=codec_name,width,height -of default=nw=1 \
    "$OUT/howto-$game.mp4" | tr '\n' ' '
  echo
done
