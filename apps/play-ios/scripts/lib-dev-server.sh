#!/bin/bash
# Sourced by the test scripts: `ensure_dev_server` makes sure the play-api dev server answers on
# :8787 with a token secret configured. If it was already running it is left alone; if this
# script started it (scripts/dev-server.sh in its own process group), it is killed, the whole
# group, when the calling script exits for any reason.
DEV_SERVER_URL="${DEV_SERVER_URL:-http://localhost:8787}"
DEV_SERVER_PGID=""
DEV_SERVER_LOG="${DEV_SERVER_LOG:-${TMPDIR:-/tmp}/pounce-dev-server.log}"

dev_server_configured() {
  curl -fsS --max-time 2 "$DEV_SERVER_URL/healthz" 2>/dev/null | grep -q '"configured":true'
}

stop_dev_server() {
  if [ -n "$DEV_SERVER_PGID" ]; then
    kill -TERM -- "-$DEV_SERVER_PGID" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 -- "-$DEV_SERVER_PGID" 2>/dev/null || break
      sleep 0.5
    done
    kill -KILL -- "-$DEV_SERVER_PGID" 2>/dev/null || true
    DEV_SERVER_PGID=""
  fi
}

ensure_dev_server() {
  if dev_server_configured; then
    echo "dev server already up at $DEV_SERVER_URL (left running)"
    return 0
  fi
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # set -m: the background job leads its own process group, so wrangler and workerd die with it.
  set -m
  "$here/dev-server.sh" >"$DEV_SERVER_LOG" 2>&1 &
  DEV_SERVER_PGID=$!
  set +m
  trap stop_dev_server EXIT
  trap 'exit 130' INT TERM
  for _ in $(seq 1 60); do
    if dev_server_configured; then
      echo "dev server up at $DEV_SERVER_URL (log $DEV_SERVER_LOG)"
      return 0
    fi
    sleep 0.5
  done
  echo "dev server not configured after 30 s; log: $DEV_SERVER_LOG" >&2
  tail -20 "$DEV_SERVER_LOG" >&2
  return 1
}
