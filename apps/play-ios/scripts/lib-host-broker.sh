#!/bin/bash
# Sourced by scripts/ui-tests.sh: a tiny broker that runs Mac-side commands for UI tests.
#
# A process spawned from inside the simulator starts, but it lives in the simulator's bootstrap
# namespace and can't reach the Mac's network services, so `pounce-e2e` can't connect from
# there. Instead a test drops a request file into $HOST_BROKER_DIR (the folder is shared: the
# simulator sees the Mac's file system) and this loop runs it here:
#   <id>.req   first line the command (`e2e` or `push`), then one argument per line
#   <id>.pid   written once started;  <id>.log  its output;  <id>.exit  its status when done
#   <id>.kill  the test wants it stopped
# Only `e2e` (the pounce-e2e binary in $E2E_BIN) and `push` (`xcrun simctl push`) are run.
HOST_BROKER_DIR=""
HOST_BROKER_PID=""

start_host_broker() {
  HOST_BROKER_DIR="$(mktemp -d -t pounce-broker)"
  (
    shopt -s nullglob
    while true; do
      for req in "$HOST_BROKER_DIR"/*.req; do
        id="${req%.req}"
        mv "$req" "$id.taken"
        args=()
        while IFS= read -r line || [ -n "$line" ]; do args+=("$line"); done < "$id.taken"
        kind="${args[0]:-}"
        rest=("${args[@]:1}")
        case "$kind" in
          e2e) cmd=("$E2E_BIN" "${rest[@]}") ;;
          push) cmd=(xcrun simctl push "${rest[@]}") ;;
          *) echo "unknown command $kind" > "$id.log"; echo 127 > "$id.exit"; echo 0 > "$id.pid"; continue ;;
        esac
        (
          "${cmd[@]}" > "$id.log" 2>&1 &
          child=$!
          echo "$child" > "$id.pid.tmp" && mv "$id.pid.tmp" "$id.pid"
          status=0
          wait "$child" || status=$?
          echo "$status" > "$id.exit.tmp" && mv "$id.exit.tmp" "$id.exit"
        ) &
      done
      for k in "$HOST_BROKER_DIR"/*.kill; do
        id="${k%.kill}"
        rm -f "$k"
        [ -f "$id.pid" ] && kill "$(cat "$id.pid")" 2>/dev/null || true
      done
      sleep 0.3
    done
  ) &
  HOST_BROKER_PID=$!
  echo "host broker in $HOST_BROKER_DIR"
}

stop_host_broker() {
  [ -n "$HOST_BROKER_DIR" ] || return 0
  for p in "$HOST_BROKER_DIR"/*.pid; do
    [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null || true
  done
  [ -n "$HOST_BROKER_PID" ] && kill "$HOST_BROKER_PID" 2>/dev/null || true
  HOST_BROKER_PID=""
}
