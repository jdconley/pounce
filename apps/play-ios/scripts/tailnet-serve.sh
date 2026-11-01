#!/bin/bash
# Exposes the local dev server (127.0.0.1:8787) to your tailnet on an https port (default 8443)
# so a real phone can reach it. Usage: scripts/tailnet-serve.sh up|down|status
#
# Env: POUNCE_TAILNET_PORT (default 8443) picks the https port. If something else on this Mac
# already listens on 8443, pick another (for example 8444) and use the same port in the URL in
# Config/Local.xcconfig.
#
# This script only ever adds or removes the serve on that one port. Other `tailscale serve`
# entries, in particular the one on :4343 that proxies another app, are never touched: no
# `reset`, no changes to any other port. `up` refuses if the port already serves something other
# than the dev server, and `down` refuses to remove a serve that is not exactly the dev server's.
set -euo pipefail

PORT="${POUNCE_TAILNET_PORT:-8443}"
case "$PORT" in
  ''|*[!0-9]*) echo "tailnet-serve: POUNCE_TAILNET_PORT must be a port number, got '$PORT'" >&2; exit 64 ;;
esac
case "$PORT" in
  4343) echo "tailnet-serve: refusing :4343, which proxies another app" >&2; exit 64 ;;
esac
TARGET=http://127.0.0.1:8787

# serve_block: the lines of `tailscale serve status` that belong to the :$PORT listener (its
# header line and the handlers under it), empty if there is none.
serve_block() {
  tailscale serve status | awk -v p=":$PORT" '
    /^https?:\/\// { inblock = (index($1, p) > 0 && $1 ~ (p "$")) }
    inblock { print }'
}

# warn_if_shadowed: a process that listens on :$PORT on this Mac (rather than tailscaled) can answer
# tailnet requests before the serve does, so the phone would reach the wrong app.
warn_if_shadowed() {
  local owner
  # lsof exits 1 when nothing listens; with pipefail that must not abort the script.
  owner="$(lsof -nP -iTCP:$PORT -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $1 " (pid " $2 ")"}' | sort -u | paste -sd, - || true)"
  if [ -n "$owner" ]; then
    echo "tailnet-serve: WARNING: $owner listens on :$PORT on this Mac and may answer before the serve does." >&2
    echo "  Check: curl -s https://<this Mac's tailnet name>:$PORT/healthz (expect \"configured\":true)" >&2
  fi
}

# is_dev_server_block <block>: true when the block has exactly one handler and it proxies the dev server.
is_dev_server_block() {
  [ "$(printf '%s\n' "$1" | grep -c 'proxy')" -eq 1 ] && printf '%s\n' "$1" | grep -q "proxy $TARGET\$"
}

cmd="${1:-}"
case "$cmd" in
  up)
    block="$(serve_block)"
    if [ -n "$block" ]; then
      if is_dev_server_block "$block"; then
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
    elif is_dev_server_block "$block"; then
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
    echo "usage: [POUNCE_TAILNET_PORT=8443] scripts/tailnet-serve.sh up|down|status" >&2
    exit 64
    ;;
esac
