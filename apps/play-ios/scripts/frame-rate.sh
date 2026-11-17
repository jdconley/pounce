#!/bin/bash
# Frame times on a simulator or a plugged-in iPhone: FrameRateTests plays Cat Tower and Tuna Tiles
# (demo tables that play themselves, no server), and this prints each table's FRAMES line.
#
#   scripts/frame-rate.sh <device id>      # a simulator's UDID, or a connected iPhone's id
#   scripts/frame-rate.sh                  # the first connected iPhone
#   PLATFORM=tvOS scripts/frame-rate.sh <device id>   # the Apple TV: an Apple TV simulator's UDID,
#                                                     # or a paired Apple TV's id (default: the first)
#
# On the Apple TV it runs FrameRateTVTests (the PounceTV scheme): six-seat Cat Tower, four-seat
# Tuna Tiles and the shell (home, a lobby, then its table), each a TV table playing itself
# (`-demo tv-hit`, `tv-tiles`, `tv-shell`), with the same rules as the iPhone's.
#
# On an iPhone with a 120 Hz screen (ProMotion) this is where the 120 Hz numbers come from. The
# phone needs Developer Mode on and to trust this Mac; Xcode signs the app and the test runner
# with the team's automatic signing, as scripts/phone-game.sh does. If signing fails on a stale
# profile (for example one without the App Group), open Pounce.xcodeproj in Xcode once with the
# phone connected so Xcode refreshes it, then run this again. Run it from a normal terminal: a
# sandboxed shell can't reach the phone.
#
# It builds the Debug configuration (the demos and -autoplay are Debug only) with the compiler's
# optimizations on, as a Release build has them, so the numbers are the shipped code's.
#
# Env: SECONDS_PER_TABLE (default 20), OUT (default a temp dir), SKIP_BUILD=1, OPTIMIZE=0 (plain
# Debug, as scripts/ui-tests.sh builds).
set -euo pipefail
cd "$(dirname "$0")/.."

PLATFORM="${PLATFORM:-iOS}"
case "$PLATFORM" in
  iOS) SCHEME=Pounce; TESTS=PounceUITests/FrameRateTests; HARDWARE=iPhone; SIMULATOR="iOS Simulator"; PREFIX=dd-frames ;;
  tvOS) SCHEME=PounceTV; TESTS=PounceTVUITests/FrameRateTVTests; HARDWARE="Apple TV"; SIMULATOR="tvOS Simulator"; PREFIX=dd-frames-tv ;;
  *) echo "PLATFORM is iOS or tvOS, not $PLATFORM"; exit 1 ;;
esac

DEVICE="${1:-${DEVICE:-}}"
if [ -z "$DEVICE" ]; then
  DEVICE="$(xcrun devicectl list devices 2>/dev/null | awk -v hw="$HARDWARE" '/connected/ && index($0, hw) { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) { print $i; exit } }')"
fi
[ -n "$DEVICE" ] || { echo "usage: [PLATFORM=tvOS] scripts/frame-rate.sh <simulator UDID or $HARDWARE id> (no connected $HARDWARE found)"; exit 1; }
OUT="${OUT:-$(mktemp -d -t pounce-frames)}"
mkdir -p "$OUT"

# A simulator's UDID is listed by simctl; anything else is a physical device.
if xcrun simctl list devices | grep -q "$DEVICE"; then
  KIND=simulator
  DESTINATION="platform=$SIMULATOR,id=$DEVICE"
  DD=build/$PREFIX-sim
  SIGN=()
else
  KIND=device
  DESTINATION="id=$DEVICE"
  DD=build/$PREFIX-device
  SIGN=(-allowProvisioningUpdates)
fi

OPT=()
if [ "${OPTIMIZE:-1}" != 0 ]; then
  OPT=(SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule GCC_OPTIMIZATION_LEVEL=s)
  DD="$DD-optimized"
fi

if [ "${SKIP_BUILD:-0}" != 1 ]; then
  scripts/bootstrap.sh >/dev/null
  xcodebuild build-for-testing -project Pounce.xcodeproj -scheme "$SCHEME" -configuration Debug \
    -destination "$DESTINATION" -derivedDataPath "$DD" "${SIGN[@]+"${SIGN[@]}"}" "${OPT[@]+"${OPT[@]}"}" -quiet
fi

status=0
TEST_RUNNER_POUNCE_FRAMES_SECONDS="${SECONDS_PER_TABLE:-20}" TEST_RUNNER_POUNCE_SPEED=1 \
  xcodebuild test-without-building -project Pounce.xcodeproj -scheme "$SCHEME" -derivedDataPath "$DD" \
  -destination "$DESTINATION" -only-testing:"$TESTS" -collect-test-diagnostics never \
  -resultBundlePath "$OUT/frames.xcresult" >"$OUT/frames.log" 2>&1 || status=$?

echo "frame times on the $KIND $DEVICE (log: $OUT/frames.log)"
grep -E '^FRAMES [a-z0-9-]+ screen=' "$OUT/frames.log" | sed -E 's/^FRAMES /  /' || true
echo "each slow or over-budget frame, with the app's share (t= is seconds since the device booted):"
grep -E '^FRAMES [a-z0-9-]+ t=' "$OUT/frames.log" | sed -E 's/^FRAMES /  /' || echo "  none"
grep -E '^FRAMES .*host is busy' "$OUT/frames.log" | sed -E 's/^FRAMES /  /' || true
grep -E 'error: .*FrameRate(TV)?Tests' "$OUT/frames.log" | sed -E 's/.*error: -\[Pounce(TV)?UITests\.FrameRate(TV)?Tests /  failed: /' || true
exit $status
