#!/bin/bash
# Plays a whole Cat Tower game with a TV watching: `pounce-e2e screen link` is the TV (started in
# the background, its link code read from its output), `pounce-e2e full --screen-code` links it and
# plays 2 local + 2 bots to game over. Passes when the TV linked, saw a playing table and the game
# end, and never failed on anything private (a hand, rack or drawn card). Uses the dev server like
# e2e.sh (DEV_SERVER_URL, SPEED).
# Usage: scripts/e2e-screen.sh [cat-tower]   (Tuna Tiles has no e2e bot yet)
set -euo pipefail
cd "$(dirname "$0")/.."
SPEED="${SPEED:-10}"
source scripts/lib-dev-server.sh

[ "${1:-cat-tower}" = cat-tower ] || { echo "FAIL only cat-tower is supported (no Tuna Tiles bot)" >&2; exit 2; }
swift build --package-path PounceKit --product pounce-e2e
ensure_dev_server

E2E=PounceKit/.build/debug/pounce-e2e
SCREEN_LOG="$(mktemp)"
screen_pid=""
cleanup() {
  [ -z "$screen_pid" ] || kill "$screen_pid" 2>/dev/null || true
  rm -f "$SCREEN_LOG"
}
trap 'cleanup; stop_dev_server' EXIT
trap 'exit 130' INT TERM

"$E2E" screen link --timeout 1800 --base "$DEV_SERVER_URL" >"$SCREEN_LOG" 2>&1 &
screen_pid=$!
code=""
for _ in $(seq 1 60); do
  code=$(sed -nE 's/^link [^ ]+ ([A-Z0-9]{6})$/\1/p' "$SCREEN_LOG" | head -1)
  [ -z "$code" ] || break
  kill -0 "$screen_pid" 2>/dev/null || break
  sleep 0.5
done
[ -n "$code" ] || { cat "$SCREEN_LOG"; echo "FAIL the TV never printed a link" >&2; exit 1; }
echo "TV code $code"

status=0
"$E2E" full --screen-code "$code" --local 2 --bots 2 --timeout 1800 --base "$DEV_SERVER_URL" || status=$?
[ "$status" -eq 0 ] || { echo "FAIL the game exited $status" >&2; exit 1; }
sleep 2 # let the TV hear the last snapshot

echo "--- TV output"
cat "$SCREEN_LOG"
fail() { echo "FAIL $1" >&2; exit 1; }
kill -0 "$screen_pid" 2>/dev/null || fail "the TV stopped (privacy failure or crash)"
! grep -q '^FAIL' "$SCREEN_LOG" || fail "the TV reported a failure"
grep -q '^linked ' "$SCREEN_LOG" || fail "the TV never linked"
grep -q '^snapshot .* playing ' "$SCREEN_LOG" || fail "the TV never saw a playing table"
grep -q '^snapshot .* over ' "$SCREEN_LOG" || fail "the TV never saw game over"
echo "ok: the TV watched a whole game and heard nothing private"
