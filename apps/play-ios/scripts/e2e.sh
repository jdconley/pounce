#!/bin/bash
# Plays a scripted game against the local dev server with pounce-e2e (started here and always
# stopped on exit, unless it was already running). Exits with the driver's status.
# Usage: scripts/e2e.sh [pounce-e2e args]   (default: full --local 2 --bots 2 --timeout 1800)
# SPEED (default 10): a dev server started here runs its bots and round gaps that many times
# faster (see lib-dev-server.sh); SPEED=1 is normal speed.
set -euo pipefail
cd "$(dirname "$0")/.."
SPEED="${SPEED:-10}"
source scripts/lib-dev-server.sh

swift build --package-path PounceKit --product pounce-e2e
ensure_dev_server

[ $# -gt 0 ] || set -- full --local 2 --bots 2 --timeout 1800
status=0
PounceKit/.build/debug/pounce-e2e "$@" --base "$DEV_SERVER_URL" || status=$?
echo "pounce-e2e exited $status"
exit $status
