#!/bin/bash
# Screenshots of the six main screens into Art/screenshots/*.jpg (JPEG, 1400 px tall), taken
# with `xcrun simctl io <device> screenshot` from the installed Debug build:
#   home, join   the app's own state on the device (an owner named Mia is seeded if the device
#                has none; Home lists whatever tables the device knows), `-show-join` for Join
#   lobby, table, curtain, celebrate   `-demo` modes (no server needed)
# The full-size PNGs stay in $RAW_DIR. Build and install first (scripts/multi-sim.sh does both).
# Env: DEVICE (simulator UDID, default iPhone 17 Pro 26.2), RAW_DIR, CELEBRATE_AT (seconds into
# `-demo celebrate -slowmo 0.25` for the leap; default 31).
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${DEVICE:-0FEFDAA5-2552-4E51-9281-C1DA13365F42}"
BUNDLE=com.conleychaos.play
OUT=Art/screenshots
RAW_DIR="${RAW_DIR:-$(mktemp -d -t pounce-shots)}"
CELEBRATE_AT="${CELEBRATE_AT:-31}"
mkdir -p "$OUT" "$RAW_DIR"

xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl get_app_container "$DEVICE" "$BUNDLE" app >/dev/null || {
  echo "Pounce isn't installed on $DEVICE (run scripts/multi-sim.sh or an xcodebuild install first)" >&2
  exit 1
}
trap 'xcrun simctl status_bar "$DEVICE" clear >/dev/null 2>&1 || true; xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true' EXIT
xcrun simctl status_bar "$DEVICE" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularBars 4 >/dev/null

# Home and Join need an owner; seed one only if this device has none.
data="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)"
people="$data/Library/Application Support/Pounce/people.json"
if [ ! -f "$people" ]; then
  mkdir -p "$(dirname "$people")"
  printf '{"owner":{"id":"%s","name":"Mia","cat":2},"others":[]}' "$(uuidgen | tr 'A-Z' 'a-z')" > "$people"
  echo "seeded an owner (Mia) in $people"
fi

# shot <name> <seconds> [launch args...]
shot() {
  local name="$1" wait="$2"
  shift 2
  xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$DEVICE" "$BUNDLE" "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$DEVICE" screenshot --type=png "$RAW_DIR/$name.png" >/dev/null 2>&1
  sips -s format jpeg -s formatOptions 82 --resampleHeight 1400 "$RAW_DIR/$name.png" --out "$OUT/$name.jpg" >/dev/null
  echo "$OUT/$name.jpg"
}

shot home 5
shot join 4 -show-join
shot lobby 4 -demo lobby
shot table 6 -demo table
shot curtain 4 -demo curtain
shot celebrate "$CELEBRATE_AT" -demo celebrate -slowmo 0.25
echo "full-size PNGs in $RAW_DIR"
