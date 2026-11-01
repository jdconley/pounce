#!/bin/bash
# Runs the play-api worker locally on :8787 for simulators and (via Tailscale) phones.
# Binds 127.0.0.1 only: simulators use localhost and `tailscale serve` proxies to 127.0.0.1:8787.
# DEV_SERVER_IP=0.0.0.0 opts in to every interface for the LAN workflow (this exposes a
# token-minting dev server to the whole LAN, so only on a network you trust).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
API="$REPO/apps/play-api"
if [ ! -f "$API/.dev.vars" ]; then
  echo "TOKEN_SECRET=$(openssl rand -hex 32)" > "$API/.dev.vars"
  echo "created $API/.dev.vars (gitignored)"
fi
exec pnpm --dir "$API" exec wrangler dev --port 8787 --ip "${DEV_SERVER_IP:-127.0.0.1}"
