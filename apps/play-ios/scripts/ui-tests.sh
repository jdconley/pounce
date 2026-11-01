#!/bin/bash
# Runs the UI tests on a simulator with the dev server up (started here and stopped on exit,
# unless already running), pounce-e2e built, and the host broker running Mac-side commands
# (pounce-e2e remotes, simctl push) for MixedSeatsTests and PushTests.
# Usage: scripts/ui-tests.sh [extra xcodebuild args, e.g. -only-testing:PounceUITests/SmokeTests]
# DESTINATION overrides the simulator (default: iPhone 17 Pro, iOS 26.2).
set -euo pipefail
cd "$(dirname "$0")/.."
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
  xcodebuild test -project Pounce.xcodeproj -scheme Pounce -destination "$DESTINATION" "$@" || status=$?
exit $status
