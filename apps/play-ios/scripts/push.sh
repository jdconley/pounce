#!/bin/bash
# Sends a "your turn" push to the booted simulator, shaped exactly like the server's
# (apps/play-api/src/push/apns.ts). Debug builds never get real pushes (sandbox tokens).
# Usage: scripts/push.sh <CODE> [NAME] [DEVICE]   (DEVICE defaults to "booted")
set -euo pipefail
CODE="${1:?usage: push.sh <CODE> [NAME] [DEVICE]}"
NAME="${2:-Mia}"
DEVICE="${3:-booted}"
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -t pounce-push).apns"
trap 'rm -f "$OUT"' EXIT
sed -e "s/K7QM4/$CODE/g" -e "s/\"Mia\"/\"$NAME\"/" "$DIR/push-sample.apns" > "$OUT"
xcrun simctl push "$DEVICE" com.conleychaos.play "$OUT"
