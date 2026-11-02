#!/bin/bash
# Two simulators against the local dev server (started here, stopped on exit unless already up).
#
# 1. Lobby: builds the Debug app, boots both simulators, installs it, gives each an owner if it
#    has none, creates a room through the API as a third device, opens pounce-dev://j/<CODE> on
#    both (DEBUG `-open-link`; `simctl openurl` stops at a system prompt) and screenshots both
#    lobbies.
# 2. Game (unless LOBBY_ONLY=1): a `pounce-e2e full` host game whose seats move to the phones
#    near the end (two to A, pass and play; one to B); MultiSimTests.testMovedSeats runs on both
#    simulators in parallel (two `xcodebuild test-without-building`) and plays them to game over.
#    Each phone's screenshots (arrival, curtain, round over, game over) land in $OUT/shared.
#
# Env: SIM_A / SIM_B (UDIDs; default iPhone 17 Pro and iPhone 17, iOS 26.2), OUT (default a temp
# dir), MOVE_AT (phase index that triggers the moves, default 8), SKIP_BUILD=1, LOBBY_ONLY=1, KEEP_B=1 (leave B booted; otherwise B is shut down at the end),
# POUNCE_UITEST_TIMEOUT_SCALE (default 1; 3 on a busy Mac), LOG_TIMELINE=1 (each phone's table
# timeline from the unified log into $OUT/timeline-A.log and timeline-B.log), SPEED (default 10:
# the phones' animations and the tests' fixed waits run that many times faster, silent sound and
# haptics; a dev server started here runs its bots at SPEED too; SPEED=1 is a normal-speed game).
set -euo pipefail
cd "$(dirname "$0")/.."
SPEED="${SPEED:-10}"
source scripts/lib-dev-server.sh

SIM_A="${SIM_A:-0FEFDAA5-2552-4E51-9281-C1DA13365F42}"
SIM_B="${SIM_B:-36EC3B13-032B-47CD-BB25-0A50E5E4AA03}"
OUT="${OUT:-$(mktemp -d -t pounce-multisim)}"
DD=build/dd
APP="$DD/Build/Products/Debug-iphonesimulator/Pounce.app"
BUNDLE=com.conleychaos.play
mkdir -p "$OUT"
B_WAS_BOOTED=$(xcrun simctl list devices | grep "$SIM_B" | grep -q Booted && echo 1 || echo 0)

pids=()
cleanup() {
  # The pids are the processes themselves (run_role execs xcodebuild), so nothing is orphaned.
  for p in "${pids[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null || true; done
  for p in "${pids[@]:-}"; do [ -n "$p" ] && wait "$p" 2>/dev/null || true; done
  if [ "${KEEP_B:-0}" != 1 ] && [ "$B_WAS_BOOTED" = 0 ]; then xcrun simctl shutdown "$SIM_B" 2>/dev/null || true; fi
  stop_dev_server
}

if [ "${SKIP_BUILD:-0}" != 1 ]; then
  xcodebuild build-for-testing -project Pounce.xcodeproj -scheme Pounce -configuration Debug \
    -destination "id=$SIM_A" -derivedDataPath "$DD" -quiet
  swift build --package-path PounceKit --product pounce-e2e
fi
E2E="$(cd PounceKit && pwd)/.build/debug/pounce-e2e"

trap cleanup EXIT
for sim in "$SIM_A" "$SIM_B"; do
  xcrun simctl boot "$sim" 2>/dev/null || true
  xcrun simctl bootstatus "$sim" -b >/dev/null
  xcrun simctl install "$sim" "$APP"
done
ensure_dev_server
trap cleanup EXIT  # ensure_dev_server set its own EXIT trap; cleanup includes it

# --- 1. both phones into one API-made room ---------------------------------------------------
seed_owner() {  # <sim> <name> <cat>
  local data people
  data="$(xcrun simctl get_app_container "$1" "$BUNDLE" data)"
  people="$data/Library/Application Support/Pounce/people.json"
  if [ ! -f "$people" ]; then
    mkdir -p "$(dirname "$people")"
    printf '{"owner":{"id":"%s","name":"%s","cat":%d},"others":[]}' "$(uuidgen | tr 'A-Z' 'a-z')" "$2" "$3" > "$people"
  fi
}
seed_owner "$SIM_A" Mia 2
seed_owner "$SIM_B" Kiki 5
token=$(curl -fsS -X POST "$DEV_SERVER_URL/v1/devices" | sed -E 's/.*"token":"([^"]+)".*/\1/')
CODE=$(curl -fsS -X POST "$DEV_SERVER_URL/v1/rooms" -H "Authorization: Bearer $token" \
  -H 'Content-Type: application/json' -d '{"game":"cat-tower"}' | sed -E 's/.*"code":"([^"]+)".*/\1/')
echo "room $CODE (made by a third device)"
# The link opens through the DEBUG `-open-link` launch argument: `simctl openurl` works too
# (`xcrun simctl openurl <sim> pounce-dev://j/<CODE>`) but stops at the system's "Open in
# Pounce?" prompt, which a script can't answer.
for sim in "$SIM_A" "$SIM_B"; do
  xcrun simctl terminate "$sim" "$BUNDLE" 2>/dev/null || true
  SIMCTL_CHILD_POUNCE_API_BASE_URL="$DEV_SERVER_URL" xcrun simctl launch "$sim" "$BUNDLE" \
    -anim-speed "$SPEED" -open-link "pounce-dev://j/$CODE" >/dev/null
  sleep 4
done
sleep 15
xcrun simctl io "$SIM_A" screenshot "$OUT/lobby-A.png" >/dev/null 2>&1
xcrun simctl io "$SIM_B" screenshot "$OUT/lobby-B.png" >/dev/null 2>&1
echo "lobby screenshots: $OUT/lobby-A.png $OUT/lobby-B.png"
[ "${LOBBY_ONLY:-0}" = 1 ] && exit 0

# --- 2. a full game: a pounce-e2e host moves seats to both phones near the end -------------
# Host: seats 0–3 on its device plus a bot (seat 4). When a seat reaches phase 9 it moves seats
# 1 and 2 to A (two people on one phone: pass and play) and seat 3 to B, and keeps playing seat
# 0 to game over. Each phone runs MultiSimTests.testMovedSeats for its seats.
for sim in "$SIM_A" "$SIM_B"; do xcrun simctl terminate "$sim" "$BUNDLE" 2>/dev/null || true; done
SHARED="$OUT/shared"
mkdir -p "$SHARED"
rm -f "$SHARED/move.txt"
MOVE_AT="${MOVE_AT:-8}"
run_role() {  # <sim> <seats> <log> <result bundle>
  # exec: the background job's pid is xcodebuild itself, so cleanup can stop it.
  TEST_RUNNER_POUNCE_SHARED_DIR="$SHARED" TEST_RUNNER_POUNCE_MOVE_SEATS="$2" \
    TEST_RUNNER_POUNCE_API_BASE_URL="$DEV_SERVER_URL" \
    TEST_RUNNER_POUNCE_UITEST_TIMEOUT_SCALE="${POUNCE_UITEST_TIMEOUT_SCALE:-1}" \
    TEST_RUNNER_POUNCE_LOG_TIMELINE="${LOG_TIMELINE:-0}" TEST_RUNNER_POUNCE_SPEED="$SPEED" \
    exec xcodebuild test-without-building -project Pounce.xcodeproj -scheme Pounce -derivedDataPath "$DD" \
    -destination "id=$1" -only-testing:PounceUITests/MultiSimTests/testMovedSeats \
    -resultBundlePath "$4" >"$3" 2>&1
}
if [ "${LOG_TIMELINE:-0}" = 1 ]; then
  for role in A B; do
    sim=$SIM_A; [ $role = B ] && sim=$SIM_B
    xcrun simctl spawn "$sim" log stream --level debug --style compact \
      --predicate 'eventMessage CONTAINS "[timeline]" OR eventMessage CONTAINS "multiple times per frame"' \
      >"$OUT/timeline-$role.log" 2>&1 & pids+=($!)
  done
fi
"$E2E" full --local 4 --bots 1 --move-seats 1,2,3 --move-at-phase "$MOVE_AT" --move-file "$SHARED/move.txt" \
  --base "$DEV_SERVER_URL" --timeout 14400 >"$OUT/host-e2e.log" 2>&1 & pids+=($!); host_pid=$!
run_role "$SIM_A" 1,2 "$OUT/simA.log" "$OUT/simA.xcresult" & pids+=($!); a_pid=$!
sleep 5
run_role "$SIM_B" 3 "$OUT/simB.log" "$OUT/simB.xcresult" & pids+=($!); b_pid=$!

host_status=0; a_status=0; b_status=0
wait "$host_pid" || host_status=$?
wait "$a_pid" || a_status=$?
wait "$b_pid" || b_status=$?
echo "e2e host exit $host_status, sim A test exit $a_status, sim B test exit $b_status"
grep -E "^move seat|^rounds=|FAIL" "$OUT/host-e2e.log" || true
grep -h "\[multisim\]" "$OUT/simA.log" "$OUT/simB.log" || true
echo "artifacts in $OUT"
[ $host_status = 0 ] && [ $a_status = 0 ] && [ $b_status = 0 ]
