#!/bin/bash
# Runs the play-api worker locally on :8787 for simulators and (via Tailscale) phones.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
API="$REPO/apps/play-api"
if [ ! -f "$API/.dev.vars" ]; then
  echo "TOKEN_SECRET=$(openssl rand -hex 32)" > "$API/.dev.vars"
  echo "created $API/.dev.vars (gitignored)"
fi
exec pnpm --dir "$API" exec wrangler dev --port 8787 --ip 0.0.0.0
