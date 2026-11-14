#!/bin/bash
# Screenshots of the first-run funnel (FunnelShotTests): a brand-new player, and a fresh install
# opening a friend's invite link while a remote host ("Grandma", pounce-e2e) and a House Cat sit at
# the table.
# Usage: OUT_DIR=/path PREFIX=after DESTINATION=id=<sim> [DEV_SERVER_URL=http://localhost:8797] \
#        [ONLY=testNewPlayer|testInvitedPlayer] scripts/funnel-shots.sh
# Also saves the invite web page's HTML (landing-j.html). Use your own simulator and port.
# Afterwards it checks the first-run funnel's local database (docs/funnel.md): each walk's device
# has the steps it went through. Needs the dev server this script starts (its .wrangler state).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${OUT_DIR:?set OUT_DIR}"
: "${DESTINATION:?set DESTINATION=id=<your simulator>}"
export DEV_SERVER_URL="${DEV_SERVER_URL:-http://localhost:8797}"
mkdir -p "$OUT_DIR"
source scripts/lib-dev-server.sh
swift build --package-path PounceKit --product pounce-e2e -q
ensure_dev_server
# Grandma makes the table and seats a House Cat beside her, as a first table does.
PounceKit/.build/debug/pounce-e2e host --name Grandma --cat 4 --house-cat --timeout 900 --base "$DEV_SERVER_URL" \
  > "$OUT_DIR/host.log" 2>&1 &
HOST_PID=$!
trap 'kill $HOST_PID 2>/dev/null || true; stop_dev_server' EXIT
for _ in $(seq 1 60); do grep -q "^seated as" "$OUT_DIR/host.log" 2>/dev/null && break; sleep 0.5; done
CODE=$(sed -nE 's/^room ([A-Z0-9]+)$/\1/p' "$OUT_DIR/host.log")
echo "room $CODE"
sleep 4
curl -fsS "$DEV_SERVER_URL/j/$CODE" > "$OUT_DIR/landing-j.html"
START_MS=$(($(date +%s) * 1000))
TEST_RUNNER_FUNNEL_SHOT_DIR="$OUT_DIR" TEST_RUNNER_FUNNEL_SHOT_PREFIX="${PREFIX:-shot}" TEST_RUNNER_FUNNEL_CODE="$CODE" \
  scripts/ui-tests.sh -only-testing:"PounceUITests/FunnelShotTests${ONLY:+/$ONLY}"

# The funnel rows the walks left: every step each app device reached, by how it came.
rows=$(cd ../play-api && pnpm exec wrangler d1 execute conleychaos-play-funnel --local --json --command \
  "SELECT d.source, group_concat(m.milestone) AS steps FROM devices d JOIN milestones m ON m.id = d.id
   WHERE d.created_at >= $START_MS AND d.platform = 'ios' GROUP BY d.id")
echo "$rows" | ONLY="${ONLY:-}" node -e '
let input = "";
process.stdin.on("data", (d) => (input += d)).on("end", () => {
  const rows = JSON.parse(input)[0].results;
  const want = {
    testNewPlayer: ["organic", ["device_created", "age_done", "named", "home_seen", "table_created", "seat_taken"]],
    testInvitedPlayer: ["join_link", ["device_created", "link_opened", "age_done", "named", "seat_taken", "joined_table"]],
  };
  let ok = true;
  for (const [test, [source, steps]] of Object.entries(want)) {
    if (process.env.ONLY && process.env.ONLY !== test) continue;
    const found = rows.find((r) => r.source === source && steps.every((s) => r.steps.split(",").includes(s)));
    console.log(`funnel ${test}: ${found ? "ok" : "MISSING"} (${source}: ${steps.join(", ")})`);
    ok &&= Boolean(found);
  }
  if (!ok) {
    console.log(JSON.stringify(rows, null, 1));
    process.exit(1);
  }
});'
