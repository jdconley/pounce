#!/bin/bash
# Screenshots of the first-run funnel (FunnelShotTests): a brand-new player, and a fresh install
# opening a friend's invite link while a remote host ("Grandma", pounce-e2e) sits at the table.
# Usage: OUT_DIR=/path PREFIX=after DESTINATION=id=<sim> [DEV_SERVER_URL=http://localhost:8797] \
#        [ONLY=testNewPlayer|testInvitedPlayer] scripts/funnel-shots.sh
# Also saves the invite web page's HTML (landing-j.html). Use your own simulator and port.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${OUT_DIR:?set OUT_DIR}"
: "${DESTINATION:?set DESTINATION=id=<your simulator>}"
export DEV_SERVER_URL="${DEV_SERVER_URL:-http://localhost:8797}"
mkdir -p "$OUT_DIR"
source scripts/lib-dev-server.sh
swift build --package-path PounceKit --product pounce-e2e -q
ensure_dev_server
token=$(curl -fsS -X POST "$DEV_SERVER_URL/v1/devices" | sed -E 's/.*"token":"([^"]+)".*/\1/')
CODE=$(curl -fsS -X POST "$DEV_SERVER_URL/v1/rooms" -H "Authorization: Bearer $token" \
  -H 'Content-Type: application/json' -d '{"game":"cat-tower"}' | sed -E 's/.*"code":"([^"]+)".*/\1/')
echo "room $CODE"
PounceKit/.build/debug/pounce-e2e join "$CODE" --name Grandma --cat 4 --timeout 900 --base "$DEV_SERVER_URL" \
  > "$OUT_DIR/host.log" 2>&1 &
HOST_PID=$!
trap 'kill $HOST_PID 2>/dev/null || true; stop_dev_server' EXIT
sleep 4
curl -fsS "$DEV_SERVER_URL/j/$CODE" > "$OUT_DIR/landing-j.html"
TEST_RUNNER_FUNNEL_SHOT_DIR="$OUT_DIR" TEST_RUNNER_FUNNEL_SHOT_PREFIX="${PREFIX:-shot}" TEST_RUNNER_FUNNEL_CODE="$CODE" \
  scripts/ui-tests.sh -only-testing:"PounceUITests/FunnelShotTests${ONLY:+/$ONLY}"
