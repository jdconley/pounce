#!/bin/bash
# A game hosted on a plugged-in iPhone (Developer Mode and UI Automation on) against a live server:
# PhoneGameTests.testHostOnPhone runs on the phone, prints its room code, and this script starts a
# `pounce-e2e join` remote on the Mac for seat 1. The phone adds House Cats and plays to game over.
#
# Env: DEVICE (UDID; default the first connected physical iPhone), BASE (default
# https://play.conleychaos.com), BOTS (default 1), OUT (default a temp dir), SKIP_BUILD=1.
set -euo pipefail
cd "$(dirname "$0")/.."

BASE="${BASE:-https://play.conleychaos.com}"
OUT="${OUT:-$(mktemp -d -t pounce-phone)}"
DD=build/dd-device
DEVICE="${DEVICE:-$(xcrun devicectl list devices 2>/dev/null | awk '/connected/ && /iPhone/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) { print $i; exit } }')}"
[ -n "$DEVICE" ] || { echo "no connected iPhone"; exit 1; }
mkdir -p "$OUT"

if [ "${SKIP_BUILD:-0}" != 1 ]; then
  xcodebuild build-for-testing -project Pounce.xcodeproj -scheme Pounce -configuration Debug \
    -destination "id=$DEVICE" -derivedDataPath "$DD" -allowProvisioningUpdates -quiet
  swift build --package-path PounceKit --product pounce-e2e
fi
E2E="$(cd PounceKit && pwd)/.build/debug/pounce-e2e"

pids=()
cleanup() {
  for p in "${pids[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]:-}"; do [ -n "$p" ] && wait "$p" 2>/dev/null || true; done
}
trap cleanup EXIT

TEST_RUNNER_POUNCE_PHONE_GAME=1 TEST_RUNNER_POUNCE_PHONE_BOTS="${BOTS:-1}" \
  TEST_RUNNER_POUNCE_API_BASE_URL="$BASE" \
  xcodebuild test-without-building -project Pounce.xcodeproj -scheme Pounce -derivedDataPath "$DD" \
  -destination "id=$DEVICE" -only-testing:PounceUITests/PhoneGameTests/testHostOnPhone \
  -resultBundlePath "$OUT/phone.xcresult" >"$OUT/phone.log" 2>&1 & pids+=($!); phone_pid=$!
echo "phone test log: $OUT/phone.log"

code=""
for _ in $(seq 1 300); do
  code=$(sed -nE 's/.*\[phone\] room ([A-Z0-9]{5}).*/\1/p' "$OUT/phone.log" | head -1)
  [ -n "$code" ] && break
  kill -0 "$phone_pid" 2>/dev/null || break
  sleep 1
done
[ -n "$code" ] || { echo "the phone never printed a room code"; tail -30 "$OUT/phone.log"; exit 1; }
echo "room $code on the phone; the Mac joins as Remote"
"$E2E" join "$code" --name Remote --cat 4 --timeout 14400 --base "$BASE" >"$OUT/remote.log" 2>&1 & pids+=($!); remote_pid=$!

phone_status=0; remote_status=0
wait "$phone_pid" || phone_status=$?
wait "$remote_pid" || remote_status=$?
echo "phone test exit $phone_status, remote exit $remote_status"
grep -h "\[phone\]" "$OUT/phone.log" || true
tail -3 "$OUT/remote.log" || true
echo "artifacts in $OUT"
[ $phone_status = 0 ] && [ $remote_status = 0 ]
