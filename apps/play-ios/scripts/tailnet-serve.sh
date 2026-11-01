#!/bin/bash
# Exposes the local dev server (127.0.0.1:8787) to your tailnet on https :8443 so a real phone
# can reach it. Usage: scripts/tailnet-serve.sh up|down|status
#
# This script only ever adds or removes the :8443 serve. Other `tailscale serve` entries, in
# particular the one on :4343 that proxies another app, are never touched: no `reset`, no
# changes to any other port. `up` refuses if :8443 already serves something other than the dev
# server, and `down` refuses to remove a :8443 serve that is not the dev server's.
set -euo pipefail

PORT=8443
TARGET=http://127.0.0.1:8787

# serve_block: the lines of `tailscale serve status` that belong to the :8443 listener (its
# header line and the handlers under it), empty if there is none.
serve_block() {
  tailscale serve status | awk -v p=":$PORT" '
    /^https?:\/\// { inblock = (index($1, p) > 0 && $1 ~ (p "$")) }
    inblock { print }'
}

# warn_if_shadowed: a process that listens on :8443 on this Mac (rather than tailscaled) can answer
# tailnet requests before the serve does, so the phone would reach the wrong app.
warn_if_shadowed() {
  local owner
  owner="$(lsof -nP -iTCP:$PORT -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $1 " (pid " $2 ")"}' | sort -u | paste -sd, -)"
  if [ -n "$owner" ]; then
    echo "tailnet-serve: WARNING: $owner listens on :$PORT on this Mac and may answer before the serve does." >&2
    echo "  Check: curl -s https://<this Mac's tailnet name>:$PORT/healthz (expect \"configured\":true)" >&2
  fi
}

cmd="${1:-}"
case "$cmd" in
  up)
    block="$(serve_block)"
    if [ -n "$block" ]; then
      if [ "$(printf '%s\n' "$block" | grep -c 'proxy')" -eq 1 ] && printf '%s\n' "$block" | grep -q "proxy $TARGET\$"; then
        echo "already serving $TARGET on :$PORT"
      else
        echo "tailnet-serve: :$PORT is already used by something else; leaving it alone:" >&2
        printf '%s\n' "$block" >&2
        exit 1
      fi
    else
      tailscale serve --bg --https=$PORT "$TARGET"
    fi
    warn_if_shadowed
    tailscale serve status
    ;;
  down)
    block="$(serve_block)"
    if [ -z "$block" ]; then
      echo "nothing on :$PORT"
    elif printf '%s\n' "$block" | grep -q "proxy $TARGET\$"; then
      tailscale serve --https=$PORT off
    else
      echo "tailnet-serve: :$PORT is not the dev server; not removing it:" >&2
      printf '%s\n' "$block" >&2
      exit 1
    fi
    tailscale serve status
    ;;
  status)
    tailscale serve status
    ;;
  *)
    echo "usage: scripts/tailnet-serve.sh up|down|status" >&2
    exit 64
    ;;
esac
