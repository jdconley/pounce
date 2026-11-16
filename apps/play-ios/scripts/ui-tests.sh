#!/bin/bash
# Runs the UI tests on a simulator with the dev server up (started here and stopped on exit,
# unless already running), pounce-e2e built, and the host broker running Mac-side commands
# (pounce-e2e remotes, simctl push) for MixedSeatsTests and PushTests.
# Usage: scripts/ui-tests.sh [extra xcodebuild args, e.g. -only-testing:PounceUITests/SmokeTests]
# DESTINATION overrides the simulator (default: iPhone 17 Pro, iOS 26.2).
# SPEED (default 10) runs the app's animations and the tests' fixed waits that many times faster,
# with silent sound and haptics; SPEED=1 is a normal-speed run. A dev server this script starts
# also runs its bots at SPEED (see lib-dev-server.sh).
# POUNCE_UITEST_TIMEOUT_SCALE (default 1) multiplies every live-test timeout; use 3 on a busy Mac.
# Gates (README "Frame rate and main-thread gates"): every test fails on a Thread Performance
# Checker report (the test plan) and on a gameplay hang over 100 ms or too many slow table frames
# (`GameplayGate`). POUNCE_TPC_IO=1 also turns on the checker's main-thread file IO check (iOS's
# own launch trips it, so every test fails; for reading the log). A failure doesn't stop for a
# sysdiagnose (minutes).
set -euo pipefail
cd "$(dirname "$0")/.."
SPEED="${SPEED:-10}"
source scripts/lib-dev-server.sh
source scripts/lib-host-broker.sh

DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2}"
swift build --package-path PounceKit --product pounce-e2e
E2E_BIN="$(cd PounceKit && pwd)/.build/debug/pounce-e2e"
ensure_dev_server
start_host_broker
trap 'stop_host_broker; stop_dev_server' EXIT

status=0
TEST_RUNNER_POUNCE_BROKER_DIR="$HOST_BROKER_DIR" TEST_RUNNER_POUNCE_API_BASE_URL="$DEV_SERVER_URL" \
  TEST_RUNNER_POUNCE_UITEST_TIMEOUT_SCALE="${POUNCE_UITEST_TIMEOUT_SCALE:-1}" TEST_RUNNER_POUNCE_SPEED="$SPEED" \
  TEST_RUNNER_POUNCE_TPC_IO="${POUNCE_TPC_IO:-0}" \
  xcodebuild test -project Pounce.xcodeproj -scheme Pounce -destination "$DESTINATION" -collect-test-diagnostics never "$@" || status=$?
exit $status
